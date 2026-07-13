import dotenv from 'dotenv';
import path from 'path';

const nodeEnv = process.env.NODE_ENV || 'development';
const envFile = nodeEnv === 'test' ? '.env.test' : '.env';
dotenv.config({ path: path.resolve(process.cwd(), envFile) });

// Environment Validation
const isProduction = process.env.NODE_ENV === 'production';
const requiredEnv = ['DATABASE_URL', 'REDIS_URL', 'JWT_SECRET', 'RSA_PRIVATE_KEY'];
const missingEnv = requiredEnv.filter(key => !process.env[key]);

if (missingEnv.length > 0) {
  console.error(`🚨 FATAL STARTUP ERROR: Missing required environment variables: ${missingEnv.join(', ')}`);
  if (isProduction) {
    process.exit(1);
  }
}

// Operational warning for optional API keys
const optionalEnv = ['SMS_API_KEY', 'SMTP_API_KEY'];
optionalEnv.forEach(key => {
  if (!process.env[key]) {
    console.warn(`⚠️ Warning: Optional operational key ${key} is not set. Related dispatch services will fail.`);
  }
});


import express, { Request, Response, NextFunction } from 'express';
import cors from 'cors';
import * as Sentry from '@sentry/node';

import http from 'http';
import helmet from 'helmet';
import swaggerUi from 'swagger-ui-express';
import swaggerJSDoc from 'swagger-jsdoc';
import { pgPool, redisClient } from './config/database';
import { runMigrations } from './migrations';
import { logger } from './config/logger';
import { getJwtFailuresCount, getLicenseSuccessCount, getLicenseFailuresCount, getSlowQueriesCount } from './utils/telemetry';
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
import supportRouter from './modules/support/support.controller';
import branchRouter from './modules/branch/branch.controller';
import orderRouter from './modules/order/order.controller';
import remoteConfigRouter from './modules/remote-config/remote-config.controller';
import logsRouter from './modules/logs/logs.controller';
import healthRouter from './modules/health/health.controller';

// BullMQ Workers
import { startNotificationWorker, stopNotificationWorker } from './workers/notification.worker';
import { startBillingScheduler, stopBillingScheduler } from './workers/billing.scheduler';

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
      // API istemcileri (Flutter desktop vb.) origin göndermeyebilir.
      if (!origin) return callback(null, true);
      const isLocal = origin.startsWith('http://localhost:') || origin.startsWith('http://127.0.0.1:');
      const isSerenutDomain = /^https?:\/\/(?:[a-zA-Z0-9-]+\.)*serenut\.(?:com|com\.tr|az|de|net|org)(?::\d+)?$/.test(origin);
      if (allowedOrigins.includes(origin) || isLocal || isSerenutDomain) {
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

// Trust proxy: yalnızca bilinen proxy/loopback IP'lerini güven.
app.set('trust proxy', 'loopback');

app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'", "'unsafe-inline'"], // unsafe-eval kaldırıldı
      styleSrc: ["'self'", "'unsafe-inline'", "https://fonts.googleapis.com"],
      fontSrc: ["'self'", "https://fonts.gstatic.com", "data:"],
      imgSrc: ["'self'", "data:", "https:"],
      connectSrc: ["'self'", "https://api.serenut.com"] // Geniş bağlantı kısıtlandı
    }
  },
  hsts: { maxAge: 31536000, includeSubDomains: true, preload: true },
  referrerPolicy: { policy: 'no-referrer' },
  noSniff: true,
  xssFilter: true,
}));
app.disable('x-powered-by');

// ── BODY PARSER ───────────────────────────────────────────────────────────────
app.use(express.json({
  limit: '10mb',
  verify: (req: any, res, buf) => {
    req.rawBody = buf;
  }
}));
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

// ── REDIRECTS (301 KALICI YÖNLENDİRME) ─────────────────────────────────────────
app.get(['/pricing', '/pricing.html'], (req, res) => {
  res.redirect(301, '/plans.html');
});
app.get(['/marketing/pricing', '/marketing/pricing.html'], (req, res) => {
  res.redirect(301, '/marketing/plans.html');
});
app.get(['/features', '/features.html'], (req, res) => {
  res.redirect(301, '/platform.html');
});
app.get(['/marketing/features', '/marketing/features.html'], (req, res) => {
  res.redirect(301, '/marketing/platform.html');
});
app.get(['/login', '/login.html'], (req, res) => {
  res.redirect(301, '/portal/');
});
app.get(['/marketing/login', '/marketing/login.html'], (req, res) => {
  res.redirect(301, '/portal/');
});

// ── STATIC WEB INTERFACES ────────────────────────────────────────────────────
app.use('/admin', express.static(path.join(process.cwd(), 'public/admin')));
app.use('/portal', express.static(path.join(process.cwd(), 'public/portal')));
app.use('/', express.static(path.join(process.cwd(), 'public/website')));
app.use('/marketing', express.static(path.join(process.cwd(), '../web/marketing')));

// ── ROUTERS — Auth & License (özel rate limitler) ────────────────────────────
app.use('/api/v1/auth', authLimiter, authRouter);
app.use('/api/auth', authLimiter, authRouter);
app.use('/api/v1/licenses', licenseLimiter, licenseRouter);
app.use('/api/licenses', licenseLimiter, licenseRouter);

// ── ROUTERS — Genel ───────────────────────────────────────────────────────────
app.use('/api/v1/updates', updateRouter);
app.use('/api/v1/releases', releaseRouter);
app.use('/api/v1/sync', syncRouter);
app.use('/api/v1/telemetry', telemetryRouter);
app.use('/api/v1/analytics', biRouter);
app.use('/api/v1/billing', billingRouter);
app.use('/api/v1/notifications', notificationRouter);
app.use('/api/v1/remote-config', remoteConfigRouter);
app.use('/api/v1/logs', logsRouter);
app.use('/api/v1/health', healthRouter);
app.use('/api/v1/users', userRouter);
app.use('/api/v1/admin', adminRouter);
app.use('/api/v1/portal', portalRouter);
app.use('/api/v1/support', supportRouter);
app.use('/api/v1/branches', branchRouter);
app.use('/api/v1/orders', orderRouter);
app.use('/api/v1/sales', orderRouter);
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
    uptime: process.uptime(),
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

// ── LIVENESS AND READINESS PROBES ─────────────────────────────────────────────
app.get('/live', (req: Request, res: Response) => {
  return res.json({ status: 'alive', timestamp: new Date().toISOString() });
});

app.get('/ready', async (req: Request, res: Response) => {
  try {
    await pgPool.query('SELECT 1');
    if (redisClient && redisClient.isOpen) {
      return res.json({ status: 'ready', timestamp: new Date().toISOString() });
    }
    return res.status(503).json({ status: 'degraded', reason: 'redis_not_connected' });
  } catch (err: any) {
    return res.status(503).json({ status: 'not_ready', reason: 'database_not_connected' });
  }
});


// ── SYSTEM VERSION CHECK ─────────────────────────────────────────────────────
const versionHandler = (req: Request, res: Response) => {
  return res.json({
    version: '1.0.0',
    build: 'RC1',
    commit: process.env.GIT_COMMIT || '8f828a2a8b9487c6e00a94f6e1f0e22ea1f8f3c7',
    date: '2026-07-09'
  });
};
app.get('/version', versionHandler);
app.get('/api/v1/version', versionHandler);


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
  if (req.accepts('html')) {
    return res.status(404).sendFile(path.join(process.cwd(), 'public/website/404.html'));
  }
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

    // Auto-seed/sanitize Windows and Android release metadata on startup
    try {
      await pgPool.query(`
        UPDATE app_versions 
        SET status = 'inactive' 
        WHERE (platform = 'windows' AND id <> 'win-v1-stable')
           OR (platform = 'android' AND id <> 'android-v1-stable');
      `);

      await pgPool.query(`
        INSERT INTO app_versions (
          id, version_code, platform, download_url, sha256_hash, 
          file_path, status, channel, is_mandatory, rollout_percentage, 
          file_size_bytes, release_notes, created_at
        ) VALUES (
          'win-v1-stable', '1.0.0', 'windows', '/api/v1/updates/download/windows/latest', 
          '94DACCA2B0C5605F960C6DE74D8B23A8B44D59AEAB79DC9A3C91EA3A19859B9D', 
          'public/website/downloads/SerenutOSSetup.exe', 
          'active', 'stable', true, 100, 14009885, 'RC1 Release Build — Inno Setup Installer', NOW()
        ) ON CONFLICT (id) DO UPDATE SET 
          file_path = EXCLUDED.file_path, 
          version_code = EXCLUDED.version_code,
          sha256_hash = EXCLUDED.sha256_hash,
          file_size_bytes = EXCLUDED.file_size_bytes,
          status = 'active',
          created_at = NOW();
      `);

      await pgPool.query(`
        INSERT INTO app_versions (
          id, version_code, platform, download_url, sha256_hash, 
          file_path, status, channel, is_mandatory, rollout_percentage, 
          file_size_bytes, release_notes, created_at
        ) VALUES (
          'android-v1-stable', '1.0.0', 'android', '/api/v1/updates/download/android/latest', 
          '36DA4BD533E1973B9A3A1ECFC1A59EE8F1D9B54F629857ADE78FBAC99D172C9B', 
          'public/website/downloads/serenut.apk', 
          'active', 'stable', true, 100, 142629988, 'RC1 Release Build — Android Application Package', NOW()
        ) ON CONFLICT (id) DO UPDATE SET 
          file_path = EXCLUDED.file_path, 
          version_code = EXCLUDED.version_code,
          sha256_hash = EXCLUDED.sha256_hash,
          file_size_bytes = EXCLUDED.file_size_bytes,
          status = 'active',
          created_at = NOW();
      `);
      logger.info('✅ Production Windows and Android release metadata auto-seeded successfully.');
    } catch (seedErr: any) {
      logger.error(`Failed to auto-seed release metadata on startup: ${seedErr.message}`);
    }

    server.listen(port, () => {
      logger.info(`✅ Serenut Cloud API running on port ${port} [${process.env.NODE_ENV || 'development'}]`);
      logger.info(`📚 API Docs: http://localhost:${port}/api-docs`);
    });

    // Graceful shutdown
    const gracefulShutdown = async (signal: string) => {
      logger.info(`🚨 ${signal} received — starting graceful shutdown process...`);
      server.close(async () => {
        try {
          logger.info('⏳ Stopping BullMQ Workers...');
          await Promise.all([
            stopNotificationWorker(),
            stopBillingScheduler()
          ]);
          logger.info('⏳ Stopping Redis Client...');
          if (redisClient && redisClient.isOpen) {
            await redisClient.quit();
          }
          logger.info('⏳ Ending PostgreSQL Connection Pool...');
          await pgPool.end();
          logger.info('✅ All connections gracefully closed. Goodbye!');
          process.exit(0);
        } catch (shutdownErr: any) {
          logger.error(`❌ Error during graceful shutdown: ${shutdownErr.message}`);
          process.exit(1);
        }
      });
    };

    process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
    process.on('SIGINT', () => gracefulShutdown('SIGINT'));
  } catch (err) {
    logger.error('Failed to bootstrap Serenut Cloud Server:', err);
    process.exit(1);
  }
}

bootstrap();
