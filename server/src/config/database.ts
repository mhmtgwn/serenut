import dotenv from 'dotenv';
import path from 'path';
import { AsyncLocalStorage } from 'async_hooks';

const nodeEnv = process.env.NODE_ENV || 'development';
const envFile = nodeEnv === 'test' ? '.env.test' : '.env';
dotenv.config({ path: path.resolve(process.cwd(), envFile) });

import { Pool, PoolClient } from 'pg';
import { createClient } from 'redis';
import { incrementSlowQueries } from '../utils/telemetry';

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

// AsyncLocalStorage for request-scoped database RLS contexts
export const tenantLocalStorage = new AsyncLocalStorage<{ companyId: string; bypassRls?: boolean }>();

async function setClientContext(client: PoolClient) {
  const store = tenantLocalStorage.getStore();
  if (store) {
    const companyId = store.companyId || '';
    const bypassRls = store.bypassRls ? 'true' : 'false';
    await client.query(`SELECT set_config('app.current_company_id', $1, true), set_config('app.bypass_rls', $2, true)`, [companyId, bypassRls]);
  } else {
    // Default fallback context
    await client.query(`SELECT set_config('app.current_company_id', '', true), set_config('app.bypass_rls', 'false', true)`);
  }
}

async function resetClientContext(client: PoolClient) {
  try {
    await client.query('RESET app.current_company_id; RESET app.bypass_rls;');
  } catch (err) {
    // Ignore silent reset errors if connection died
  }
}

// ── SLOW QUERY DETECTOR WRAPPER ──────────────────────────────────────────────
const originalQuery = (pgPool as any).query.bind(pgPool);
(pgPool as any).query = async function (this: any, ...args: any[]) {
  const start = Date.now();
  try {
    const result = await originalQuery.apply(this, args);
    const duration = Date.now() - start;
    if (duration > 200) {
      incrementSlowQueries();
    }
    if (duration > 1000) {
      console.warn(`\u26a0\ufe0f SLOW QUERY ALERT (${duration}ms):`, args[0]);
      if (process.env.SENTRY_DSN) {
        const Sentry = require('@sentry/node');
        Sentry.captureMessage(`Slow DB Query: ${duration}ms`, {
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
      if (duration > 200) {
        incrementSlowQueries();
      }
      if (duration > 1000) {
        console.warn(`\u26a0\ufe0f SLOW QUERY ALERT (${duration}ms):`, queryArgs[0]);
        if (process.env.SENTRY_DSN) {
          const Sentry = require('@sentry/node');
          Sentry.captureMessage(`Slow DB Query: ${duration}ms`, {
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
    args[0] = async function (err: any, client: any, done: any) {
      if (client) {
        wrapClientQuery(client);
        try {
          await setClientContext(client);
        } catch (setupErr) {
          return originalCallback(setupErr, client, done);
        }
        const originalDone = done;
        done = async function(releaseErr?: any) {
          await resetClientContext(client);
          originalDone(releaseErr);
        };
      }
      originalCallback(err, client, done);
    };
    return originalConnect.apply(this, args);
  }

  const promise = originalConnect.apply(this, args);
  if (promise && typeof promise.then === 'function') {
    return promise.then(async (client: any) => {
      wrapClientQuery(client);
      await setClientContext(client);
      
      const originalRelease = client.release;
      client.release = async function(this: any, releaseArg?: any) {
        await resetClientContext(client);
        return originalRelease.call(this, releaseArg);
      };
      
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
  redisClient = createClient({
    url: redisUrl,
    socket: nodeEnv === 'test' ? { reconnectStrategy: false } : undefined
  });
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
