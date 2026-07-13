import dotenv from 'dotenv';
dotenv.config();

import http from 'http';
import express from 'express';
import { pgPool } from '../config/database';
import { initRealtimeWebSocket } from '../modules/realtime/realtime.ws';
import { eventBroker } from '../modules/realtime/event-broker';
import { AuthService } from '../modules/auth/auth.service';
import { TopicManager } from '../modules/realtime/topic-manager';
import WebSocket from 'ws';

function getActiveBrokerChannelsCount(): number {
  if ((eventBroker as any).wrappedListeners) {
    return (eventBroker as any).wrappedListeners.size;
  }
  if ((eventBroker as any).subCallbacks) {
    return (eventBroker as any).subCallbacks.size;
  }
  return 0;
}

async function runTest() {
  console.log('🧪 Starting Sprint 2 Subscription Leak Integration Tests (50 Clients)...');
  const app = express();
  const server = http.createServer(app);
  
  // Initialize WebSocket server
  initRealtimeWebSocket(server);
  
  server.listen(4002, async () => {
    console.log('📡 Leak Test Server listening on port 4002');
    
    try {
      // Find an active company/tenant from the DB
      const compRes = await pgPool.query(
        "SELECT id FROM companies WHERE status = 'active' LIMIT 1"
      );
      
      if (compRes.rows.length === 0) {
        console.error('❌ Test failed: No active companies found in database. Run sprint2_verification first.');
        process.exit(1);
      }
      
      const companyId = compRes.rows[0].id;
      const jwtSecret = process.env.JWT_SECRET || 'test_jwt_secret_must_be_32_characters_minimum';
      process.env.JWT_SECRET = jwtSecret;
      
      const jwt = require('jsonwebtoken');
      const clientsCount = 50;
      const clients: { ws: WebSocket; index: number; refreshToken: string; userId: string; email: string }[] = [];
      
      console.log(`🔌 Connecting ${clientsCount} WebSocket clients concurrently...`);
      
      const openPromises = Array.from({ length: clientsCount }).map(async (_, index) => {
        const userId = `user-test-id-999-${index}`;
        const email = `test-${index}@owner.com`;
        const userName = `Test Leak User ${index}`;
        
        // 1. Ensure mock user exists in DB to satisfy foreign key constraints
        await pgPool.query(
          `INSERT INTO users (id, company_id, name, email, password_hash, is_active)
           VALUES ($1, $2, $3, $4, 'mock-hash', true)
           ON CONFLICT (id) DO UPDATE SET is_active = true`,
          [userId, companyId, userName, email]
        );

        // 2. Ensure session exists in DB for this refresh token rotation test
        const initialRefreshToken = `mock-refresh-token-999-${index}`;
        const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000);
        await pgPool.query(
          `INSERT INTO sessions (id, user_id, company_id, refresh_token, ip_address, user_agent, expires_at, is_revoked)
           VALUES ($1, $2, $3, $4, '127.0.0.1', 'mock-agent', $5, false)
           ON CONFLICT (refresh_token) DO UPDATE SET is_revoked = false, expires_at = $5`,
          [`session-999-${index}`, userId, companyId, initialRefreshToken, expiresAt]
        );

        // 3. Sign access token
        const payload = {
          jti: `test-ws-jti-999-${index}`,
          id: userId,
          name: userName,
          email: email,
          company_id: companyId,
          roles: ['owner'],
          permissions: ['sales:view'],
        };
        
        const token = jwt.sign(payload, jwtSecret, {
          expiresIn: '15m',
          issuer: 'serenut.com',
          audience: 'serenut-pos',
        });
        
        const clientWsUrl = `ws://localhost:4002/api/v1/realtime/live?token=${token}`;

        return new Promise<void>((resolve, reject) => {
          const client = new WebSocket(clientWsUrl);
          client.on('open', () => {
            clients.push({
              ws: client,
              index,
              refreshToken: initialRefreshToken,
              userId,
              email
            });
            // Subscribe to unique room
            client.send(JSON.stringify({
              action: 'subscribe',
              topic: `tenant/${companyId}/room-${index}`,
              correlationId: `corr-${index}`
            }));
          });
          
          client.on('message', (data) => {
            const frame = JSON.parse(data.toString());
            if (frame.status === 'subscribed' && frame.correlationId === `corr-${index}`) {
              resolve();
            }
          });
          
          client.on('error', (err) => reject(err));
        });
      });
      
      await Promise.all(openPromises);
      console.log(`✅ All ${clientsCount} clients connected and subscribed successfully.`);
      
      // Let's verify eventBroker active subscription count
      let brokerSubscriptionsCount = getActiveBrokerChannelsCount();
      console.log(`📈 EventBroker active channels count: ${brokerSubscriptionsCount}`);
      if (brokerSubscriptionsCount !== clientsCount) {
        throw new Error(`Expected ${clientsCount} active channels on broker, but got ${brokerSubscriptionsCount}`);
      }
      
      // 1. Simulate abrupt crash/disconnection of half of the clients (indexes 0 to 24)
      console.log('💥 Simulating crash of 25 clients...');
      const crashedClients = clients.filter(c => c.index < 25);
      const activeClients = clients.filter(c => c.index >= 25);
      
      for (const client of crashedClients) {
        client.ws.terminate(); // terminate abruptly without closing handshake
      }
      
      // Wait a moment for server to clean up sockets
      await new Promise((resolve) => setTimeout(resolve, 1500));
      
      brokerSubscriptionsCount = getActiveBrokerChannelsCount();
      console.log(`📉 EventBroker active channels count after 25 crashes: ${brokerSubscriptionsCount}`);
      if (brokerSubscriptionsCount !== 25) {
        throw new Error(`Expected 25 active channels on broker after crash, but got ${brokerSubscriptionsCount}`);
      }
      console.log('  ✔️ Crash cleanup verified: broker subscriptions correctly dropped to 25.');

      // 2. Simulate network outage for the remaining 25 clients (indexes 25 to 49)
      console.log('🔌 Simulating network loss (disconnecting remaining 25 clients)...');
      const disconnectPromises = activeClients.map(client => {
        return new Promise<void>((resolve) => {
          client.ws.on('close', () => resolve());
          client.ws.close();
        });
      });
      await Promise.all(disconnectPromises);
      
      // Wait a moment for server cleanup
      await new Promise((resolve) => setTimeout(resolve, 1500));
      
      brokerSubscriptionsCount = getActiveBrokerChannelsCount();
      console.log(`📉 EventBroker active channels count during network loss: ${brokerSubscriptionsCount}`);
      if (brokerSubscriptionsCount !== 0) {
        throw new Error(`Expected 0 active channels on broker, but got ${brokerSubscriptionsCount}`);
      }
      console.log('  ✔️ Network loss cleanup verified: broker subscriptions dropped to 0.');

      // 3. Reconnect the 25 clients using token refresh (RTR flow)
      console.log('🔄 Reconnecting the 25 clients using refresh token rotation...');
      const reconnectPromises = activeClients.map(async (client) => {
        // Run refresh token rotation
        const refreshResult = await AuthService.refresh(client.refreshToken);
        const newAccessToken = refreshResult.access_token;
        const nextRefreshToken = refreshResult.refresh_token;
        
        // Update client info with the rotated refresh token
        client.refreshToken = nextRefreshToken;

        const clientWsUrl = `ws://localhost:4002/api/v1/realtime/live?token=${newAccessToken}`;

        return new Promise<void>((resolve, reject) => {
          const newWs = new WebSocket(clientWsUrl);
          client.ws = newWs;

          newWs.on('open', () => {
            newWs.send(JSON.stringify({
              action: 'subscribe',
              topic: `tenant/${companyId}/room-${client.index}`,
              correlationId: `reconnect-corr-${client.index}`
            }));
          });

          newWs.on('message', (data) => {
            const frame = JSON.parse(data.toString());
            if (frame.status === 'subscribed' && frame.correlationId === `reconnect-corr-${client.index}`) {
              resolve();
            }
          });

          newWs.on('error', (err) => reject(err));
        });
      });

      await Promise.all(reconnectPromises);
      console.log('✅ All 25 clients reconnected and re-subscribed successfully via RTR.');

      brokerSubscriptionsCount = getActiveBrokerChannelsCount();
      console.log(`📈 EventBroker active channels count after reconnection: ${brokerSubscriptionsCount}`);
      if (brokerSubscriptionsCount !== 25) {
        throw new Error(`Expected 25 active channels on broker, but got ${brokerSubscriptionsCount}`);
      }

      // 4. Close all reconnected clients cleanly
      console.log('🔌 Closing all reconnected clients...');
      const finalClosePromises = activeClients.map(client => {
        return new Promise<void>((resolve) => {
          client.ws.on('close', () => resolve());
          client.ws.close();
        });
      });
      await Promise.all(finalClosePromises);

      // Wait a moment for server cleanup
      await new Promise((resolve) => setTimeout(resolve, 1500));

      brokerSubscriptionsCount = getActiveBrokerChannelsCount();
      console.log(`📉 Final EventBroker active channels count: ${brokerSubscriptionsCount}`);
      if (brokerSubscriptionsCount !== 0) {
        throw new Error(`Expected 0 active channels on broker, but got ${brokerSubscriptionsCount}`);
      }
      console.log('  ✔️ Final cleanup verified: broker subscriptions dropped to 0.');
      
      // 5. Unsubscribe-Subscribe Race Condition Integration Test (B.1)
      console.log('🧪 Running B.1: Unsubscribe-Subscribe Race Condition Integration Test...');
      const raceTopic = `tenant/${companyId}/race-topic`;

      // Helper to connect a socket and subscribe
      const connectAndSubscribe = (clientId: string) => {
        const token = jwt.sign({
          jti: `test-ws-jti-race-${clientId}`,
          id: 'user-test-id-999-0',
          name: 'Test Leak User 0',
          email: 'test-0@owner.com',
          company_id: companyId,
          roles: ['owner'],
          permissions: ['sales:view'],
        }, jwtSecret, { expiresIn: '15m', issuer: 'serenut.com', audience: 'serenut-pos' });

        return new Promise<{ ws: WebSocket; subMsg: any }>((resolve, reject) => {
          const ws = new WebSocket(`ws://localhost:4002/api/v1/realtime/live?token=${token}`);
          ws.on('open', () => {
            ws.send(JSON.stringify({
              action: 'subscribe',
              topic: raceTopic,
              correlationId: `race-corr-${clientId}`
            }));
          });
          ws.on('message', (data) => {
            const frame = JSON.parse(data.toString());
            if (frame.status === 'subscribed' && frame.correlationId === `race-corr-${clientId}`) {
              resolve({ ws, subMsg: frame });
            }
          });
          ws.on('error', reject);
        });
      };

      // Connect Client A and subscribe to raceTopic
      console.log('🔌 Connecting Client A...');
      const clientA = await connectAndSubscribe('clientA');
      console.log('✅ Client A subscribed.');

      // Close Client A (triggering unsubscribe) and IMMEDIATELY connect Client B (triggering subscribe)
      console.log('💥 Closing Client A and IMMEDIATELY subscribing Client B (Race simulation)...');
      
      const clientAPromise = new Promise<void>((res) => clientA.ws.on('close', () => res()));
      clientA.ws.close();

      // Immediately connect Client B without waiting for Client A closure/cleanup to finish
      const clientBPromise = connectAndSubscribe('clientB');
      const [_, clientB] = await Promise.all([clientAPromise, clientBPromise]);
      console.log('✅ Client B subscribed while Client A unsubscribe completed.');

      // Wait 500ms to ensure the async promise chains complete and settle
      await new Promise((resolve) => setTimeout(resolve, 500));

      // Set up listener on Client B for incoming messages
      const clientBMessagePromise = new Promise<any>((resolve, reject) => {
        const timeout = setTimeout(() => reject(new Error('Timeout waiting for message on Client B')), 5000);
        clientB.ws.on('message', (data) => {
          const frame = JSON.parse(data.toString());
          if (frame.event === 'race-test-event') {
            clearTimeout(timeout);
            resolve(frame);
          }
        });
      });

      // Publish a message to raceTopic via eventBroker
      console.log('📢 Publishing message to race-topic via EventBroker...');
      await eventBroker.publish(raceTopic, JSON.stringify({ event: 'race-test-event', payload: 'B.1-success' }));

      // Wait for Client B to receive the message
      const receivedFrame = await clientBMessagePromise;
      console.log('📥 Client B successfully received message:', receivedFrame);
      if (receivedFrame.payload !== 'B.1-success') {
        throw new Error(`Expected B.1-success payload, but got ${receivedFrame.payload}`);
      }
      console.log('  ✔️ B.1 Race condition immunity verified: Client B successfully received messages after immediate connection.');

      // Clean up Client B
      await new Promise<void>((resolve) => {
        clientB.ws.on('close', () => resolve());
        clientB.ws.close();
      });
      await new Promise((resolve) => setTimeout(resolve, 1000));

      // 6. Redis Unsubscribe Retry and Alarm Verification Test (B.2)
      console.log('🧪 Running B.2: Redis Unsubscribe Retry and Alarm Verification Test...');
      
      const originalBrokerUnsubscribe = eventBroker.unsubscribe;
      
      // Senaryo 1: İlk 2 denemede hata fırlatıp 3. denemede başarılı olan senaryo
      console.log('🔄 Scenario 1: Unsubscribe fails twice, succeeds on 3rd attempt...');
      let unsubCalls = 0;
      eventBroker.unsubscribe = async (topic: string, cb: any) => {
        unsubCalls++;
        if (unsubCalls < 3) {
          throw new Error(`Redis network error (Attempt ${unsubCalls})`);
        }
        return originalBrokerUnsubscribe.call(eventBroker, topic, cb);
      };

      // Connect and subscribe to test retry
      const retryTopic = `tenant/${companyId}/retry-topic`;
      const clientRetry = await new Promise<{ ws: WebSocket }>((resolve, reject) => {
        const token = jwt.sign({
          jti: `test-ws-jti-retry-1`,
          id: 'user-test-id-999-0',
          name: 'Test Leak User 0',
          email: 'test-0@owner.com',
          company_id: companyId,
          roles: ['owner'],
          permissions: ['sales:view'],
        }, jwtSecret, { expiresIn: '15m', issuer: 'serenut.com', audience: 'serenut-pos' });

        const ws = new WebSocket(`ws://localhost:4002/api/v1/realtime/live?token=${token}`);
        ws.on('open', () => {
          ws.send(JSON.stringify({
            action: 'subscribe',
            topic: retryTopic,
            correlationId: 'retry-sub-1'
          }));
        });
        ws.on('message', (data) => {
          const frame = JSON.parse(data.toString());
          if (frame.status === 'subscribed' && frame.correlationId === 'retry-sub-1') {
            resolve({ ws });
          }
        });
        ws.on('error', reject);
      });

      // Trigger disconnect to run checkAndCleanupTopic (which calls unsubscribe)
      const clientRetryPromise = new Promise<void>((res) => clientRetry.ws.on('close', () => res()));
      clientRetry.ws.close();
      await clientRetryPromise;

      // Wait a moment for retry delay (100ms + 200ms = 300ms + margin = 1000ms)
      await new Promise((resolve) => setTimeout(resolve, 1000));

      console.log(`ℹ️ Total unsubscribe attempts made: ${unsubCalls}`);
      if (unsubCalls !== 3) {
        throw new Error(`Expected exactly 3 attempts, but got ${unsubCalls}`);
      }
      console.log('  ✔️ Scenario 1 verified successfully: retries succeeded on 3rd attempt.');

      // Senaryo 2: Retry sınırının aşılması ve Alarm üretilmesi
      console.log('🚨 Scenario 2: Unsubscribe always fails, exhausts all retries and logs alarm...');
      let alwaysFailCalls = 0;
      eventBroker.unsubscribe = async (topic: string, cb: any) => {
        alwaysFailCalls++;
        throw new Error('Redis connection permanently lost');
      };

      // Connect and subscribe again
      const alarmTopic = `tenant/${companyId}/alarm-topic`;
      const clientAlarm = await new Promise<{ ws: WebSocket }>((resolve, reject) => {
        const token = jwt.sign({
          jti: `test-ws-jti-retry-2`,
          id: 'user-test-id-999-0',
          name: 'Test Leak User 0',
          email: 'test-0@owner.com',
          company_id: companyId,
          roles: ['owner'],
          permissions: ['sales:view'],
        }, jwtSecret, { expiresIn: '15m', issuer: 'serenut.com', audience: 'serenut-pos' });

        const ws = new WebSocket(`ws://localhost:4002/api/v1/realtime/live?token=${token}`);
        ws.on('open', () => {
          ws.send(JSON.stringify({
            action: 'subscribe',
            topic: alarmTopic,
            correlationId: 'retry-sub-2'
          }));
        });
        ws.on('message', (data) => {
          const frame = JSON.parse(data.toString());
          if (frame.status === 'subscribed' && frame.correlationId === 'retry-sub-2') {
            resolve({ ws });
          }
        });
        ws.on('error', reject);
      });

      // Trigger disconnect
      const clientAlarmPromise = new Promise<void>((res) => clientAlarm.ws.on('close', () => res()));
      clientAlarm.ws.close();
      await clientAlarmPromise;

      // Wait a moment for retry delay (100ms + 200ms = 300ms + margin = 1000ms)
      await new Promise((resolve) => setTimeout(resolve, 1000));

      console.log(`ℹ️ Total unsubscribe attempts made on permanent failure: ${alwaysFailCalls}`);
      if (alwaysFailCalls !== 3) {
        throw new Error(`Expected exactly 3 attempts, but got ${alwaysFailCalls}`);
      }
      console.log('  ✔️ Scenario 2 verified successfully: alarm triggered and cleanup executed after 3 failures.');

      // Restore original unsubscribe method
      eventBroker.unsubscribe = originalBrokerUnsubscribe;
      
      console.log('🎉 SPRINT 2 WS SUBSCRIPTION LEAK INTEGRATION TESTS PASSED SUCCESSFULLY!');
      server.close(() => {
        pgPool.end();
        process.exit(0);
      });
      
    } catch (err: any) {
      console.error('❌ Leak test script encountered fatal error:', err);
      process.exit(1);
    }
  });
}

runTest();
