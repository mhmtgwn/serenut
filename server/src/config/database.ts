import { Pool } from 'pg';
import { createClient } from 'redis';

if (!process.env.DATABASE_URL) {
  console.error('FATAL: DATABASE_URL environment variable is not set. Server cannot start.');
  process.exit(1);
}
const dbUrl = process.env.DATABASE_URL;

export const pgPool = new Pool({
  connectionString: dbUrl,
  max: 50,
  min: 5,
  idleTimeoutMillis: 10000,
  connectionTimeoutMillis: 5000,
  statement_timeout: 30000,
});

// ── SLOW QUERY DETECTOR WRAPPER ──────────────────────────────────────────────
const originalQuery = (pgPool as any).query.bind(pgPool);
(pgPool as any).query = async function (this: any, ...args: any[]) {
  const start = Date.now();
  try {
    const result = await originalQuery.apply(this, args);
    const duration = Date.now() - start;
    if (duration > 1000) {
      console.warn(`⚠️ SLOW QUERY ALERT (${duration}ms):`, args[0]);
      if (process.env.SENTRY_DSN) {
        const Sentry = require('@sentry/node');
        Sentry.captureMessage(`Slow DB Query: ${duration}ms`, {
          level: 'warning',
          extra: { query: args[0], durationMs: duration }
        });
      }
    }
    return result;
  } catch (err) {
    throw err;
  }
};

function wrapClientQuery(client: any) {
  if (!client || client.query.__wrapped) return;
  const originalClientQuery = client.query.bind(client);
  client.query = async function (this: any, ...queryArgs: any[]) {
    const start = Date.now();
    try {
      const result = await originalClientQuery.apply(this, queryArgs);
      const duration = Date.now() - start;
      if (duration > 1000) {
        console.warn(`⚠️ SLOW QUERY ALERT (${duration}ms):`, queryArgs[0]);
        if (process.env.SENTRY_DSN) {
          const Sentry = require('@sentry/node');
          Sentry.captureMessage(`Slow DB Query: ${duration}ms`, {
            level: 'warning',
            extra: { query: queryArgs[0], durationMs: duration }
          });
        }
      }
      return result;
    } catch (err) {
      throw err;
    }
  };
  client.query.__wrapped = true;
}

const originalConnect = (pgPool as any).connect.bind(pgPool);
(pgPool as any).connect = function (this: any, ...args: any[]) {
  if (typeof args[0] === 'function') {
    const originalCallback = args[0];
    args[0] = function (err: any, client: any, done: any) {
      wrapClientQuery(client);
      originalCallback(err, client, done);
    };
    return originalConnect.apply(this, args);
  }

  const promise = originalConnect.apply(this, args);
  if (promise && typeof promise.then === 'function') {
    return promise.then((client: any) => {
      wrapClientQuery(client);
      return client;
    });
  }
  return promise;
};

pgPool.on('error', (err) => {
  console.error('🐘 Unexpected error on idle PostgreSQL client:', err);
});

// Redis Client Setup
const redisUrl = process.env.REDIS_URL;
let redisClient: any = null;

if (redisUrl) {
  redisClient = createClient({ url: redisUrl });
  redisClient.on('error', (err: any) => console.error('🔴 Redis Client Error:', err));
  redisClient.connect()
    .then(() => console.log('🔴 Connected to Redis successfully!'))
    .catch((err: any) => {
      console.error('🔴 Redis connection failed, falling back to memory cache:', err);
      redisClient = null;
    });
} else {
  console.log('ℹ️ Redis URL not provided, running in memory-cache fallback mode.');
}

export { redisClient };
