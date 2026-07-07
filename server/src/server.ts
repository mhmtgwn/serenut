import dotenv from 'dotenv';
dotenv.config();

import express, { Request, Response, NextFunction } from 'express';
import cors from 'cors';
import * as Sentry from '@sentry/node';

import path from 'path';
import http from 'http';
import helmet from 'helmet';
import swaggerUi from 'swagger-ui-express';
import swaggerJSDoc from 'swagger-jsdoc';
import { pgPool, redisClient } from './config/database';
import { runMigrations } from './migrations';
import { logger } from './config/logger';
import { generalApiLimiter, authLimiter, licenseLimiter } from './middleware/rate-limit.middleware';
import { idempotencyMiddleware } from './middleware/idempotency';

// Import Routers
import authRouter from './modules/auth/auth.controller';
import licenseRouter from './modules/license/license.controller';
import updateRouter from './modules/update/update.controller';
import syncRouter from './modules/sync/sync.controller';
import analyticsRouter from './modules/analytics/analytics.controller';
import biRouter from './modules/analytics/bi.controller';
import userRouter from './modules/user/user.controller';
import tenantRouter from './modules/tenant/tenant.controller';
import adminRouter from './modules/admin/admin.controller';
import portalRouter from './modules/portal/portal.controller';
import releaseRouter from './modules/release/release.controller';
import { initAnalyticsWebSocket, getActiveWebSocketCount } from './modules/analytics/analytics.ws';
import { initRealtimeWebSocket, getAuthErrorsCount, getReconnectCount, getHeartbeatTimeoutsCount, getTenantRejectionsCount } from './modules/realtime/realtime.ws';
import { ConnectionRegistry } from './modules/realtime/connection-registry';
import { RealtimeBroadcastService } from './modules/realtime/broadcast.service';
import billingRouter from './modules/billing/billing.controller';
import notificationRouter from './modules/notification/notification.controller';
import telemetryRouter from './modules/analytics/telemetry.controller';

// BullMQ Workers
import { startNotificationWorker } from './workers/notification.worker';
import { startBillingScheduler } from './workers/billing.scheduler';

const app = express();

// Initialize Sentry before anything else
if (process.env.SENTRY_DSN) {
  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    environment: process.env.NODE_ENV || 'development',
    tracesSampleRate: 0.1,
  });
  logger.info('🎨 Sentry/GlitchTip monitoring initialized successfully.');
} else {
  logger.warn('⚠️ Sentry DSN not provided. Crash reporting is disabled.');
}

const server = http.createServer(app);
const port = process.env.PORT || 3000;
const SCHEMA_VERSION = 1;

// ── STARTUP VALIDATION ────────────────────────────────────────────────────────
// JWT_SECRET validation is handled in auth.service.ts (fails at import time).
if (!process.env.DATABASE_URL) {
  logger.error('FATAL: DATABASE_URL environment variable is not set. Server cannot start.');
  process.exit(1);
}

// ── CORS HARDENING ────────────────────────────────────────────────────────────
// Üretimde yalnızca bilinen domain'lere izin ver.
const allowedOrigins = (process.env.ALLOWED_ORIGINS || 'http://localhost:3000,http://localhost:5000,http://127.0.0.1:3000,http://127.0.0.1:5000')
  .split(',')
  .map((o) => o.trim());

app.use(
  cors({
    origin: (origin, callback) => {
      // API istemcileri (Flutter desktop) origin göndermeyebilir — izin ver
      if (!origin) return callback(null, true);
      const isLocal = origin.startsWith('http://localhost:') || origin.startsWith('http://127.0.0.1:');
      const isSerenutDomain = /^https?:\/\/(?:[a-zA-Z0-9-]+\.)*serenut\.(?:com|com\.tr|az|de|net|org)(?::\d+)?$/.test(origin);
      if (allowedOrigins.includes(origin) || isLocal || isSerenutDomain || process.env.NODE_ENV !== 'production') {
        callback(null, true);
      } else {
        logger.warn(`CORS blocked request from: ${origin}`);
        callback(new Error('CORS policy: Origin not allowed'));
      }
    },
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'x-schema-version', 'Idempotency-Key'],
  })
);

// Trust Nginx proxy (X-Forwarded-For için gerekli — rate limiter doğru IP'yi okusun)
app.set('trust proxy', 1);

app.use(helmet({
  contentSecurityPolicy: {
    directives: { defaultSrc: ["'self'"], scriptSrc: ["'self'"] }
  },
  hsts: { maxAge: 31536000, includeSubDomains: true, preload: true },
  referrerPolicy: { policy: 'no-referrer' },
  noSniff: true,
  xssFilter: true,
}));
app.disable('x-powered-by');

// ── BODY PARSER ───────────────────────────────────────────────────────────────
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use(idempotencyMiddleware);

// ── GENEL RATE LİMİTER (tüm API'ye uygulanır) ────────────────────────────────
app.use('/api/', generalApiLimiter);

// ── HTTP REQUEST LOGGER ───────────────────────────────────────────────────────
app.use((req: Request, res: Response, next: NextFunction) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    logger.info(`${req.method} ${req.originalUrl} ${res.statusCode} - ${duration}ms`, {
      method: req.method,
      url: req.originalUrl,
      statusCode: res.statusCode,
      durationMs: duration,
      ip: req.ip,
    });
  });
  next();
});

// ── SWAGGER/OPENAPI ───────────────────────────────────────────────────────────
const swaggerOptions = {
  definition: {
    openapi: '3.0.0',
    info: {
      title: 'Serenut Cloud SaaS Platform API',
      version: '1.0.0',
      description: 'Enterprise API documentation for Serenut POS SaaS cloud orchestrator.',
    },
    components: {
      securitySchemes: {
        BearerAuth: {
          type: 'http',
          scheme: 'bearer',
          bearerFormat: 'JWT',
        },
      },
    },
  },
  apis: [path.join(__dirname, './modules/**/*.ts'), path.join(__dirname, './modules/**/*.js')],
};

const swaggerSpec = swaggerJSDoc(swaggerOptions);
app.use('/api-docs', swaggerUi.serve, swaggerUi.setup(swaggerSpec));

// ── SCHEMA DRIFT MIDDLEWARE ───────────────────────────────────────────────────
function enforceSchemaHandshake(req: Request, res: Response, next: NextFunction) {
  if (
    req.path === '/health' ||
    req.path.startsWith('/api/v1/updates') ||
    req.path.startsWith('/api/v1/releases/check') ||
    req.path.startsWith('/api-docs')
  ) {
    return next();
  }

  const clientSchemaVersionStr = req.headers['x-schema-version'];
  if (clientSchemaVersionStr) {
    const clientSchemaVersion = parseInt(clientSchemaVersionStr as string, 10);
    if (clientSchemaVersion !== SCHEMA_VERSION) {
      logger.warn(`Schema drift: client=${clientSchemaVersion} server=${SCHEMA_VERSION}`);
      return res.status(426).json({
        error: 'schema_version_mismatch',
        message: 'Veri şeması uyuşmazlığı tespit edildi. Lütfen istemci yazılımını güncelleyin.',
      });
    }
  }
  next();
}

app.use(enforceSchemaHandshake);

// ── STATIC WEB INTERFACES ────────────────────────────────────────────────────
app.use('/admin', express.static(path.join(process.cwd(), 'public/admin')));
app.use('/portal', express.static(path.join(process.cwd(), 'public/portal')));
app.use('/', express.static(path.join(process.cwd(), 'public/website')));

// ── ROUTERS — Auth & License (özel rate limitler) ────────────────────────────
app.use('/api/v1/auth', authLimiter, authRouter);
app.use('/api/v1/licenses', licenseLimiter, licenseRouter);

// ── ROUTERS — Genel ───────────────────────────────────────────────────────────
app.use('/api/v1/updates', updateRouter);
app.use('/api/v1/releases', releaseRouter);
app.use('/api/v1/sync', syncRouter);
app.use('/api/v1/telemetry', telemetryRouter);
app.use('/api/v1/analytics', biRouter);
app.use('/api/v1/billing', billingRouter);
app.use('/api/v1/notifications', notificationRouter);
app.use('/api/v1/users', userRouter);
app.use('/api/v1/admin', adminRouter);
app.use('/api/v1/portal', portalRouter);
app.use('/api/v1', tenantRouter);

// ── SYSTEM HEALTH CHECK ───────────────────────────────────────────────────────
app.get('/health', async (req: Request, res: Response) => {
  // Check maintenance mode in Redis or global
  let isMaintenance = false;
  try {
    if (redisClient && redisClient.isOpen) {
      const maintenanceVal = await redisClient.get('admin:maintenance_mode');
      isMaintenance = maintenanceVal === 'true';
    }
  } catch (_) {}
  if (!isMaintenance && (global as any).maintenanceMode) {
    isMaintenance = true;
  }

  if (isMaintenance) {
    return res.status(503).json({
      status: 'maintenance',
      timestamp: new Date().toISOString(),
      version: process.env.npm_package_version || '1.0.0',
      message: 'System is undergoing scheduled maintenance'
    });
  }

  const healthStatus: any = {
    status: 'healthy',
    timestamp: new Date().toISOString(),
    version: process.env.npm_package_version || '1.0.0',
    services: {
      express: 'up',
      database: 'down',
      redis: 'down',
    },
  };

  let isHealthy = true;

  try {
    const dbCheck = await pgPool.query('SELECT 1');
    if (dbCheck.rows.length > 0) {
      healthStatus.services.database = 'up';
    }
  } catch (err) {
    isHealthy = false;
    healthStatus.services.database = 'down';
    healthStatus.error = 'database_connection_failed';
  }

  if (redisClient && redisClient.isOpen) {
    healthStatus.services.redis = 'up';
  } else {
    healthStatus.services.redis = 'degraded'; // Redis optional
  }

  if (!isHealthy) {
    healthStatus.status = 'unhealthy';
    return res.status(503).json(healthStatus);
  }

  return res.json(healthStatus);
});

// ── PROMETHEUS METRICS EXPORTER ──────────────────────────────────────────────
app.get('/metrics', async (req: Request, res: Response) => {
  const activeWs = getActiveWebSocketCount ? getActiveWebSocketCount() : 0;
  const memory = process.memoryUsage();
  const uptime = process.uptime();
  const dbPool = pgPool;
  
  const realtimeActiveWs = ConnectionRegistry.getActiveConnectionsCount();
  const sentEvents = RealtimeBroadcastService.getSentEventsCount();
  const failedEvents = RealtimeBroadcastService.getFailedEventsCount();
  const authErrors = getAuthErrorsCount();
  const reconnects = getReconnectCount();
  const heartbeatTimeouts = getHeartbeatTimeoutsCount();
  const tenantRejections = getTenantRejectionsCount();
  const avgDuration = ConnectionRegistry.getAverageConnectionDurationMs() / 1000;

  const payload = [
    `# HELP serenut_node_uptime_seconds Process uptime in seconds`,
    `# TYPE serenut_node_uptime_seconds gauge`,
    `serenut_node_uptime_seconds ${uptime}`,
    
    `# HELP serenut_node_memory_rss_bytes Process Resident Set Size in bytes`,
    `# TYPE serenut_node_memory_rss_bytes gauge`,
    `serenut_node_memory_rss_bytes ${memory.rss}`,
    
    `# HELP serenut_node_memory_heap_used_bytes Process Heap Used in bytes`,
    `# TYPE serenut_node_memory_heap_used_bytes gauge`,
    `serenut_node_memory_heap_used_bytes ${memory.heapUsed}`,
    
    `# HELP serenut_active_websockets_count Active WebSocket client count`,
    `# TYPE serenut_active_websockets_count gauge`,
    `serenut_active_websockets_count ${activeWs}`,
    
    `# HELP serenut_db_pool_total_connections Total DB connections`,
    `# TYPE serenut_db_pool_total_connections gauge`,
    `serenut_db_pool_total_connections ${dbPool.totalCount || 0}`,
    
    `# HELP serenut_db_pool_idle_connections Idle DB connections`,
    `# TYPE serenut_db_pool_idle_connections gauge`,
    `serenut_db_pool_idle_connections ${dbPool.idleCount || 0}`,

    `# HELP serenut_realtime_active_connections Active Realtime WebSocket connections`,
    `# TYPE serenut_realtime_active_connections gauge`,
    `serenut_realtime_active_connections ${realtimeActiveWs}`,

    `# HELP serenut_realtime_sent_events_total Total real-time events sent`,
    `# TYPE serenut_realtime_sent_events_total counter`,
    `serenut_realtime_sent_events_total ${sentEvents}`,

    `# HELP serenut_realtime_failed_events_total Total real-time events failed`,
    `# TYPE serenut_realtime_failed_events_total counter`,
    `serenut_realtime_failed_events_total ${failedEvents}`,

    `# HELP serenut_realtime_auth_errors_total Total real-time upgrade auth errors`,
    `# TYPE serenut_realtime_auth_errors_total counter`,
    `serenut_realtime_auth_errors_total ${authErrors}`,

    `# HELP serenut_realtime_reconnects_total Total real-time client reconnect count`,
    `# TYPE serenut_realtime_reconnects_total counter`,
    `serenut_realtime_reconnects_total ${reconnects}`,

    `# HELP serenut_realtime_heartbeat_timeouts_total Total real-time heartbeat timeout count`,
    `# TYPE serenut_realtime_heartbeat_timeouts_total counter`,
    `serenut_realtime_heartbeat_timeouts_total ${heartbeatTimeouts}`,

    `# HELP serenut_realtime_tenant_rejections_total Total real-time tenant validation rejections`,
    `# TYPE serenut_realtime_tenant_rejections_total counter`,
    `serenut_realtime_tenant_rejections_total ${tenantRejections}`,

    `# HELP serenut_realtime_avg_connection_duration_seconds Average connection duration in seconds`,
    `# TYPE serenut_realtime_avg_connection_duration_seconds gauge`,
    `serenut_realtime_avg_connection_duration_seconds ${avgDuration}`
  ].join('\n') + '\n';
  
  res.set('Content-Type', 'text/plain; version=0.0.4; charset=utf-8');
  return res.send(payload);
});

// ── 404 HANDLER ───────────────────────────────────────────────────────────────
app.use((req: Request, res: Response) => {
  res.status(404).json({
    error: 'not_found',
    message: `Route not found: ${req.method} ${req.originalUrl}`,
  });
});

// Sentry error handler must be registered before any other error middleware
if (process.env.SENTRY_DSN) {
  Sentry.setupExpressErrorHandler(app);
}

// ── GLOBAL ERROR HANDLER ─────────────────────────────────────────────────────
app.use((err: any, req: Request, res: Response, _next: NextFunction) => {
  logger.error('Unhandled error:', { error: err.message, stack: err.stack, url: req.originalUrl });

  // CORS hataları özel mesaj
  if (err.message && err.message.startsWith('CORS')) {
    return res.status(403).json({ error: 'cors_error', message: err.message });
  }

  res.status(err.status || 500).json({
    error: 'server_error',
    message: process.env.NODE_ENV === 'production' ? 'Beklenmedik bir hata oluştu.' : err.message,
  });
});

// ── CACHE WARMUP Stratejisi ──────────────────────────────────────────────────
async function warmupCache() {
  try {
    if (redisClient && redisClient.isOpen) {
      const plansRes = await pgPool.query('SELECT * FROM plans');
      if (plansRes.rows.length > 0) {
        await redisClient.setEx('plans:list', 300, JSON.stringify(plansRes.rows));
        logger.info('🔥 Cache warmed up: plans:list key populated.');
      }
    }
  } catch (err: any) {
    logger.error(`Failed to warm up cache on startup: ${err.message}`);
  }
}

// ── BOOTSTRAP ─────────────────────────────────────────────────────────────────
async function bootstrap() {
  try {
    await runMigrations(pgPool);
    initAnalyticsWebSocket(server);
    initRealtimeWebSocket(server);

    // BullMQ Workers
    startNotificationWorker();
    startBillingScheduler();

    // Caching warmup
    await warmupCache();

    server.listen(port, () => {
      logger.info(`✅ Serenut Cloud API running on port ${port} [${process.env.NODE_ENV || 'development'}]`);
      logger.info(`📚 API Docs: http://localhost:${port}/api-docs`);
    });

    // Graceful shutdown
    process.on('SIGTERM', async () => {
      logger.info('SIGTERM received — shutting down gracefully...');
      server.close(async () => {
        await pgPool.end();
        logger.info('Server closed. Bye!');
        process.exit(0);
      });
    });
  } catch (err) {
    logger.error('Failed to bootstrap Serenut Cloud Server:', err);
    process.exit(1);
  }
}

bootstrap();
