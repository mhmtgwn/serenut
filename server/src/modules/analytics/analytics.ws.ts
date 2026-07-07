import { WebSocketServer, WebSocket } from 'ws';
import { Server } from 'http';
import url from 'url';
import { AuthService } from '../auth/auth.service';
import { logger } from '../../config/logger';

// Store active connections by company_id
const companyClients = new Map<string, Set<WebSocket>>();

export function initAnalyticsWebSocket(server: Server) {
  const wss = new WebSocketServer({ noServer: true });

  // Handle upgrade handshakes manually to enforce authentication
  server.on('upgrade', (request, socket, head) => {
    const pathname = url.parse(request.url || '').pathname;

    if (pathname === '/api/v1/analytics/live') {
      const query = url.parse(request.url || '', true).query;
      const token = query.token as string;

      if (!token) {
        logger.warn('WS Connection rejected: Missing token');
        socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
        socket.destroy();
        return;
      }

      // Check blacklist asynchronously
      AuthService.isTokenBlacklisted(token).then((isBlacklisted) => {
        if (isBlacklisted) {
          logger.warn('WS Connection rejected: Blacklisted token');
          socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
          socket.destroy();
          return;
        }

        const user = AuthService.verifyAccessToken(token);
        wss.handleUpgrade(request, socket, head, (ws) => {
          wss.emit('connection', ws, request, user);
        });
      }).catch((err) => {
        logger.warn('WS Connection rejected: Invalid token check error');
        socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
        socket.destroy();
      });
    } else {
      // Do not destroy socket if pathname doesn't match, other parts might use it (e.g. general updates)
    }
  });

  wss.on('connection', (ws: WebSocket, request: any, user: any) => {
    const companyId = user.company_id;
    logger.info(`WS Client connected: company_id=${companyId}, user_id=${user.id}`);

    if (!companyClients.has(companyId)) {
      companyClients.set(companyId, new Set());
    }
    companyClients.get(companyId)!.add(ws);

    // Keepalive ping/pong
    let isAlive = true;
    ws.on('pong', () => { isAlive = true; });

    const interval = setInterval(() => {
      if (!isAlive) {
        logger.info(`WS Client timed out: user_id=${user.id}`);
        return ws.terminate();
      }
      isAlive = false;
      ws.ping();
    }, 30000);

    ws.on('close', () => {
      logger.info(`WS Client disconnected: user_id=${user.id}`);
      clearInterval(interval);
      const clients = companyClients.get(companyId);
      if (clients) {
        clients.delete(ws);
        if (clients.size === 0) {
          companyClients.delete(companyId);
        }
      }
    });

    ws.on('error', (err) => {
      logger.error(`WS Error for user ${user.id}:`, err);
    });
  });
}

/**
 * Broadcasts an event to all connected WebSocket clients of a specific company.
 * Used by Sync Engine on successful sale synchronization.
 */
export function broadcastToCompany(companyId: string, event: string, payload: any) {
  const clients = companyClients.get(companyId);
  if (!clients || clients.size === 0) return;

  const message = JSON.stringify({ event, data: payload, timestamp: new Date().toISOString() });
  logger.info(`WS Broadcasting to company ${companyId}: event=${event}`);

  for (const client of clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(message);
    }
  }
}

export function getActiveWebSocketCount(): number {
  let count = 0;
  for (const clients of companyClients.values()) {
    count += clients.size;
  }
  return count;
}
