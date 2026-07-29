import crypto from 'crypto';
import { redisClient } from '../../config/database';

export interface RealtimeTicketPayload {
  id: string;
  name: string;
  email: string;
  company_id: string;
  roles: string[];
  permissions: string[];
  token_version?: number;
}

const TICKET_TTL_SECONDS = 60;
const keyFor = (ticket: string) =>
  `realtime:ticket:${crypto.createHash('sha256').update(ticket).digest('hex')}`;

export async function issueRealtimeTicket(
  user: RealtimeTicketPayload,
): Promise<{ ticket: string; expires_in_seconds: number }> {
  if (!redisClient?.isReady) {
    throw new Error('realtime_ticket_store_unavailable');
  }
  const ticket = crypto.randomBytes(32).toString('base64url');
  await redisClient.set(keyFor(ticket), JSON.stringify(user), {
    EX: TICKET_TTL_SECONDS,
    NX: true,
  });
  return { ticket, expires_in_seconds: TICKET_TTL_SECONDS };
}

export async function consumeRealtimeTicket(
  ticket: string,
): Promise<RealtimeTicketPayload | null> {
  if (!redisClient?.isReady || !ticket) return null;
  const serialized = await redisClient.getDel(keyFor(ticket));
  if (!serialized) return null;
  try {
    return JSON.parse(serialized) as RealtimeTicketPayload;
  } catch (_) {
    return null;
  }
}
