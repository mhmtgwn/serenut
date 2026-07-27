import { WebSocketServer, WebSocket } from 'ws';
import { Server } from 'http';
import url from 'url';
import { redisClient } from '../../../config/database';
import { logger } from '../../../config/logger';

export interface SignalInvalidationTicket {
  type: 'REVISION_INVALIDATED';
  tenant_id: string;
  domain: string;
  head_revision: number;
  timestamp: number;
}

export class SignalBroadcaster {
  private static wss: WebSocketServer;
  private static tenantSockets: Map<string, Set<WebSocket>> = new Map();

  public static init(server?: Server) {
    if (!this.wss) {
      this.wss = new WebSocketServer({ noServer: true });

      this.wss.on('connection', (ws: WebSocket, request: any, tenantId: string) => {
        logger.info(`SyncV2 WS: Client connected for tenant ${tenantId}`);

        if (!this.tenantSockets.has(tenantId)) {
          this.tenantSockets.set(tenantId, new Set());
        }
        this.tenantSockets.get(tenantId)!.add(ws);

        // Setup Active Ping/Pong Heartbeat
        (ws as any).isAlive = true;
        ws.on('pong', () => {
          (ws as any).isAlive = true;
        });

        ws.on('close', () => {
          this.tenantSockets.get(tenantId)?.delete(ws);
          logger.info(`SyncV2 WS: Client disconnected for tenant ${tenantId}`);
        });

        ws.on('error', (err) => {
          logger.error(`SyncV2 WS: Socket error for tenant ${tenantId}: ${err.message}`);
          this.tenantSockets.get(tenantId)?.delete(ws);
        });
      });
    }

    if (server) {
      server.on('upgrade', (request, socket, head) => {
        const pathname = url.parse(request.url || '').pathname;
        if (pathname === '/api/v2/sync/live' || pathname === '/sync/live') {
          this.handleUpgrade(request, socket, head);
        }
      });
    }
  }

  public static handleUpgrade(request: any, socket: any, head: any) {
    this.init();
    const query = url.parse(request.url || '', true).query;
    const tenantId = (query.tenant_id || query.tenantId) as string;

    if (!tenantId) {
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
      socket.destroy();
      return;
    }

    this.wss.handleUpgrade(request, socket, head, (ws) => {
      this.wss.emit('connection', ws, request, tenantId);
    });
  }
        logger.error(`SyncV2 WS Socket error: ${err.message}`);
        this.tenantSockets.get(tenantId)?.delete(ws);
      });
    });

    // 30s Heartbeat Sweeper to terminate dead connections
    setInterval(() => {
      this.wss.clients.forEach((ws: WebSocket) => {
        if ((ws as any).isAlive === false) {
          return ws.terminate();
        }
        (ws as any).isAlive = false;
        ws.ping();
      });
    }, 30000);

    logger.info('SyncV2 SignalBroadcaster initialized on WSS endpoint /api/v2/sync/live');
  }

  /**
   * Publishes invalidation ticket to Redis Pub/Sub channel 'sync_v2_invalidations'
   */
  public static async publishInvalidation(tenantId: string, domain: string, headRevision: number) {
    const ticket: SignalInvalidationTicket = {
      type: 'REVISION_INVALIDATED',
      tenant_id: tenantId,
      domain,
      head_revision: headRevision,
      timestamp: Date.now(),
    };

    const message = JSON.stringify(ticket);

    // 1. Broadcast locally to active WebSocket clients on this node
    this.broadcastLocal(tenantId, message);

    // 2. Publish to Redis Pub/Sub for multi-VPS fanout
    try {
      if (redisClient && redisClient.isOpen) {
        await redisClient.publish('sync_v2_invalidations', message);
      }
    } catch (err: any) {
      logger.warn(`SyncV2 Redis PubSub publish error: ${err.message}`);
    }
  }

  private static broadcastLocal(tenantId: string, message: string) {
    const sockets = this.tenantSockets.get(tenantId);
    if (!sockets || sockets.size === 0) return;

    for (const ws of sockets) {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(message);
      }
    }
  }
}
