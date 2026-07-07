import { WebSocket } from 'ws';

export interface ConnectionMetadata {
  userId: string;
  userName: string;
  companyId: string;
  ipAddress: string;
  userAgent: string;
  connectedAt: Date;
  reconnectCount: number;
}

export class ConnectionRegistry {
  private static connections = new Map<WebSocket, ConnectionMetadata>();
  private static tenantConnections = new Map<string, Set<WebSocket>>();

  public static register(ws: WebSocket, meta: ConnectionMetadata) {
    this.connections.set(ws, meta);
    if (!this.tenantConnections.has(meta.companyId)) {
      this.tenantConnections.set(meta.companyId, new Set());
    }
    this.tenantConnections.get(meta.companyId)!.add(ws);
  }

  public static unregister(ws: WebSocket): ConnectionMetadata | undefined {
    const meta = this.connections.get(ws);
    if (meta) {
      this.connections.delete(ws);
      const tenantSocks = this.tenantConnections.get(meta.companyId);
      if (tenantSocks) {
        tenantSocks.delete(ws);
        if (tenantSocks.size === 0) {
          this.tenantConnections.delete(meta.companyId);
        }
      }
    }
    return meta;
  }

  public static getMetadata(ws: WebSocket): ConnectionMetadata | undefined {
    return this.connections.get(ws);
  }

  public static getTenantSockets(companyId: string): Set<WebSocket> {
    return this.tenantConnections.get(companyId) || new Set();
  }

  public static getAllConnections(): Map<WebSocket, ConnectionMetadata> {
    return this.connections;
  }

  public static getActiveConnectionsCount(): number {
    return this.connections.size;
  }

  public static getTenantConnectionsCount(companyId: string): number {
    return this.getTenantSockets(companyId).size;
  }

  public static getAverageConnectionDurationMs(): number {
    if (this.connections.size === 0) return 0;
    const now = Date.now();
    let totalDuration = 0;
    for (const meta of this.connections.values()) {
      totalDuration += (now - meta.connectedAt.getTime());
    }
    return totalDuration / this.connections.size;
  }
}
