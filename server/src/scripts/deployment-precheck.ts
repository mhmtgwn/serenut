import { Client } from 'pg';
import { createClient } from 'redis';
import os from 'os';
import fs from 'fs';
import path from 'path';
import dotenv from 'dotenv';
dotenv.config();

async function runPrecheck() {
  console.log('🚀 RUNNING PRE-DEPLOYMENT PRODUCTION-READINESS AUTO-CHECKS...');
  console.log('===============================================================');

  let failed = false;

  // 1. Secret Management Verification
  const requiredVars = ['DATABASE_URL', 'JWT_SECRET', 'NODE_ENV'];
  const missingVars = requiredVars.filter(v => !process.env[v]);
  
  if (missingVars.length > 0) {
    console.error(`❌ [FAIL] Missing required environment variables: ${missingVars.join(', ')}`);
    failed = true;
  } else {
    console.log('✅ [PASS] Secret Management: All required environment variables are set.');
    // Check JWT key complexity
    const secret = process.env.JWT_SECRET!;
    if (secret === 'REPLACE_WITH_OPENSSL_RAND_HEX_64_OUTPUT' || secret.length < 32) {
      console.warn('⚠️ [WARN] JWT_SECRET is weak or uses placeholder value.');
    }
  }

  // 2. Database Connectivity & Migration Version Check
  if (process.env.DATABASE_URL) {
    const client = new Client({ connectionString: process.env.DATABASE_URL });
    try {
      await client.connect();
      console.log('✅ [PASS] Database Connection: Successfully connected to PostgreSQL.');
      
      const migRes = await client.query('SELECT MAX(version) as current_version FROM schema_migrations');
      const maxVersion = migRes.rows[0].current_version || 0;
      
      // Dynamically scan the db directory for the highest expected migration version
      const dbDir = path.join(__dirname, '../../db');
      let expectedVersion = 1;
      if (fs.existsSync(dbDir)) {
        const files = fs.readdirSync(dbDir);
        for (const file of files) {
          const match = file.match(/^schema_v(\d+)\.sql$/);
          if (match) {
            const ver = parseInt(match[1], 10);
            if (ver > expectedVersion) {
              expectedVersion = ver;
            }
          }
        }
      } else {
        expectedVersion = 32;
      }

      if (maxVersion < expectedVersion) {
        console.error(`❌ [FAIL] Migrations Check: Database schema version (${maxVersion}) is behind expected version (${expectedVersion}). Please run migrations.`);
        failed = true;
      } else {
        console.log(`✅ [PASS] Migrations Check: Database is fully migrated to version ${maxVersion}.`);
      }
      await client.end();
    } catch (err: any) {
      console.error('❌ [FAIL] Database Connection: Failed to connect to PostgreSQL:', err.message);
      failed = true;
    }
  }

  // 3. Redis Connectivity Check
  const redisUrl = process.env.REDIS_URL;
  if (redisUrl) {
    const redisClient = createClient({ url: redisUrl });
    try {
      await redisClient.connect();
      console.log('✅ [PASS] Redis Connection: Successfully connected to Redis.');
      await redisClient.quit();
    } catch (err: any) {
      if (process.env.NODE_ENV === 'production') {
        console.error('❌ [FAIL] Redis Connection: Redis is required in production but connection failed:', err.message);
        failed = true;
      } else {
        console.warn('⚠️ [WARN] Redis Connection failed (running in local memory-fallback mode).');
      }
    }
  } else {
    if (process.env.NODE_ENV === 'production') {
      console.error('❌ [FAIL] Redis Configuration: REDIS_URL must be configured in production for horizontally scalable WebSockets.');
      failed = true;
    } else {
      console.log('ℹ️ Redis Connection: REDIS_URL not configured. Local event broker fallback is active.');
    }
  }

  // 4. System Resource Allocation Check
  const totalMemBytes = os.totalmem();
  const freeMemBytes = os.freemem();
  const freeMemPct = (freeMemBytes / totalMemBytes) * 100;
  console.log(`ℹ️ System Resources: Total Memory: ${(totalMemBytes / 1024 / 1024 / 1024).toFixed(2)} GB, Free: ${(freeMemBytes / 1024 / 1024 / 1024).toFixed(2)} GB (${freeMemPct.toFixed(1)}%)`);
  
  if (freeMemBytes < 100 * 1024 * 1024) { // Less than 100MB free RAM
    console.error('❌ [FAIL] System Resources: Insufficient free memory (< 100MB). Deployment blocked.');
    failed = true;
  } else {
    console.log('✅ [PASS] System Resources: Memory footprint is within safe operating parameters.');
  }

  console.log('===============================================================');
  if (failed) {
    console.error('❌ PRE-DEPLOYMENT CHECKS FAILED. Deployment blocked to prevent environment downtime.');
    process.exit(1);
  } else {
    console.log('🎉 ALL PRE-DEPLOYMENT CHECKS PASSED. Environment is healthy and ready for deploy!');
    process.exit(0);
  }
}

runPrecheck().catch((err) => {
  console.error('Fatal error during pre-deployment checks:', err);
  process.exit(1);
});
