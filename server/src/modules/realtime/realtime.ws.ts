import { WebSocketServer, WebSocket } from 'ws';
import { Server } from 'http';
import url from 'url';
import { AuthService } from '../auth/auth.service';
import { pgPool } from '../../config/database';
import { logger } from '../../config/logger';
import { ConnectionRegistry, ConnectionMetadata } from './connection-registry';
import { TopicManager } from './topic-manager';
import { writeAuditLog } from '../analytics/telemetry.controller';
import { eventBroker } from './event-broker';

let wss: WebSocketServer;

// Telemetry counters
let authErrors = 0;
let tenantRejections = 0;
let reconnectCount = 0;
let heartbeatTimeouts = 0;

export function initRealtimeWebSocket(server: Server) {
  wss = new WebSocketServer({ noServer: true });

  // Bind topic manager to broadcast events locally
  (TopicManager as any).broadcastLocal = function (topic: string, message: string) {
    const sockets = TopicManager.getSubscribers(topic);
    if (!sockets || sockets.size === 0) return;
    for (const socket of sockets) {
      if (socket.readyState === WebSocket.OPEN) {
        socket.send(message);
      }
    }
  };

  // Bind broker subscribe hook in TopicManager
  const originalSubscribe = TopicManager.subscribe;
  const activeBrokerSubscriptions = new Set<string>();
  
  TopicManager.subscribe = async function (ws: WebSocket, topic: string, correlationId?: string): Promise<boolean> {
    const success = await originalSubscribe.call(TopicManager, ws, topic, correlationId);
    if (success && !activeBrokerSubscriptions.has(topic)) {
      activeBrokerSubscriptions.add(topic);
      eventBroker.subscribe(topic, (t, message) => {
        (TopicManager as any).broadcastLocal(t, message);
      }).catch((err) => {
        logger.error(`Broker subscription failed for topic ${topic}: ${err.message}`);
        activeBrokerSubscriptions.delete(topic);
      });
    }
    return success;
  };

  server.on('upgrade', async (request, socket, head) => {
    const pathname = url.parse(request.url || '').pathname;

    if (pathname === '/api/v1/realtime/live') {
      const query = url.parse(request.url || '', true).query;
      const token = query.token as string;
      const clientReconnects = parseInt((query.reconnectCount as string) || '0', 10);

      if (!token) {
        logger.warn('WS Upgrade failed: Missing token');
        authErrors++;
        socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
        socket.destroy();
        return;
      }

      try {
        const isBlacklisted = await AuthService.isTokenBlacklisted(token);
        if (isBlacklisted) {
          logger.warn('WS Upgrade failed: Token blacklisted');
          authErrors++;
          socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
          socket.destroy();
          return;
        }

        const user = AuthService.verifyAccessToken(token);

        // Tenant Validation: Check active company in DB
        const companyRes = await pgPool.query(
          'SELECT status FROM companies WHERE id = $1',
          [user.company_id]
        );

        if (companyRes.rows.length === 0 || companyRes.rows[0].status !== 'active') {
          logger.warn(`WS Upgrade failed: Company suspended or invalid company_id=${user.company_id}`);
          tenantRejections++;
          socket.write('HTTP/1.1 403 Forbidden\r\n\r\n');
          socket.destroy();
          return;
        }

        // Complete upgrade handshake
        wss.handleUpgrade(request, socket, head, (ws) => {
          wss.emit('connection', ws, request, user, clientReconnects);
        });
      } catch (err: any) {
        logger.warn(`WS Upgrade authentication error: ${err.message}`);
        authErrors++;
        socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
        socket.destroy();
      }
    }
  });

  wss.on('connection', async (ws: WebSocket, request: any, user: any, clientReconnects: number) => {
    const ipAddress = request.socket.remoteAddress || 'unknown';
    const userAgent = request.headers['user-agent'] || 'unknown';

    const meta: ConnectionMetadata = {
      userId: user.id,
      userName: user.name,
      companyId: user.company_id,
      ipAddress,
      userAgent,
      connectedAt: new Date(),
      reconnectCount: clientReconnects,
    };

    if (clientReconnects > 0) {
      reconnectCount += clientReconnects;
    }

    ConnectionRegistry.register(ws, meta);
    logger.info(`WS Client connected: user_id=${user.id}, company_id=${user.company_id}, reconnects=${clientReconnects}`);

    // Audit connection open (non-blocking)
    writeAuditLog(
      user.company_id,
      user.id,
      user.name,
      'WEBSOCKET_CONNECTION_OPEN',
      'WebSocketConnection',
      user.id,
      null,
      { ipAddress, userAgent, clientReconnects },
      ipAddress,
      userAgent
    ).catch((err) => logger.error(`Audit log error on connection open: ${err.message}`));

    // Heartbeat ping/pong setup (30-second interval, 10-second tolerance)
    let isAlive = true;
    ws.on('pong', () => {
      isAlive = true;
    });

    const heartbeatInterval = setInterval(() => {
      if (!isAlive) {
        logger.info(`WS Heartbeat timeout: user_id=${user.id}`);
        heartbeatTimeouts++;
        ws.terminate();
        return;
      }
      isAlive = false;
      ws.ping();
    }, 30000);

    ws.on('message', async (data: string) => {
      try {
        const rawMessage = data.toString();
        const frame = JSON.parse(rawMessage);
        const { action, topic, correlationId } = frame;

        if (action === 'subscribe') {
          if (!topic) {
            ws.send(JSON.stringify({ status: 'error', message: 'Topic is required', correlationId }));
            return;
          }
          const success = await TopicManager.subscribe(ws, topic, correlationId);
          if (success) {
            ws.send(JSON.stringify({ status: 'subscribed', topic, correlationId }));
          } else {
            ws.send(JSON.stringify({ status: 'error', message: 'Unauthorized topic subscription', topic, correlationId }));
          }
        } else if (action === 'unsubscribe') {
          if (!topic) {
            ws.send(JSON.stringify({ status: 'error', message: 'Topic is required', correlationId }));
            return;
          }
          TopicManager.unsubscribe(ws, topic);
          ws.send(JSON.stringify({ status: 'unsubscribed', topic, correlationId }));
        } else if (action === 'ping') {
          ws.send(JSON.stringify({ action: 'pong', correlationId }));
        } else {
          ws.send(JSON.stringify({ status: 'error', message: `Unknown action: ${action}`, correlationId }));
        }
      } catch (err: any) {
        ws.send(JSON.stringify({ status: 'error', message: 'Malformed JSON payload' }));
      }
    });

    ws.on('close', async () => {
      logger.info(`WS Client disconnected: user_id=${user.id}`);
      clearInterval(heartbeatInterval);
      TopicManager.unsubscribeAll(ws);
      ConnectionRegistry.unregister(ws);

      // Audit connection close (non-blocking)
      writeAuditLog(
        user.company_id,
        user.id,
        user.name,
        'WEBSOCKET_CONNECTION_CLOSE',
        'WebSocketConnection',
        user.id,
        null,
        null,
        ipAddress,
        userAgent
      ).catch((err) => logger.error(`Audit log error on connection close: ${err.message}`));
    });

    ws.on('error', (err) => {
      logger.error(`WS Error for user ${user.id}:`, err);
    });
  });
}

// Telemetry helper functions
export function getAuthErrorsCount(): number {
  return authErrors;
}

export function getTenantRejectionsCount(): number {
  return tenantRejections;
}

export function getReconnectCount(): number {
  return reconnectCount;
}

export function getHeartbeatTimeoutsCount(): number {
  return heartbeatTimeouts;
}
