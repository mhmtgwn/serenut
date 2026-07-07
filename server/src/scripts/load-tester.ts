import dotenv from 'dotenv';
dotenv.config();

import http from 'http';
import express from 'express';
import { initRealtimeWebSocket } from '../modules/realtime/realtime.ws';
import { RealtimeBroadcastService } from '../modules/realtime/broadcast.service';
import WebSocket from 'ws';

const jwt = require('jsonwebtoken');

async function runLoadTest() {
  console.log('⚡ STARTING REALTIME WEBSOCKET & REST LOAD TEST SIMULATOR...');
  console.log('================================================================');

  const app = express();
  const server = http.createServer(app);
  
  // Init realtime ws
  initRealtimeWebSocket(server);
  
  const port = 4002; // Use distinct port for load tester
  
  server.listen(port, async () => {
    console.log(`📡 Load Test Server running on port ${port}`);

    const jwtSecret = process.env.JWT_SECRET || 'test_jwt_secret_must_be_32_characters_minimum';
    const companyId = 'serenut_cloud';
    
    // Generate valid JWT token
    const token = jwt.sign({
      jti: 'load-test-jti',
      id: 'user-load-tester',
      name: 'Load Tester Agent',
      email: 'load@tester.com',
      company_id: companyId,
      roles: ['owner'],
      permissions: ['sales:view', 'orders:view']
    }, jwtSecret, {
      expiresIn: '1h',
      issuer: 'serenut.com',
      audience: 'serenut-pos'
    });

    const clientCount = 50; // Simulate 50 concurrent WebSocket cashier Terminals
    const clients: WebSocket[] = [];
    let connectedClients = 0;
    let eventsReceived = 0;
    const latencies: number[] = [];

    console.log(`🔌 Spawning ${clientCount} concurrent WebSocket client connections...`);

    // Connect clients
    const connectPromises = Array.from({ length: clientCount }).map((_, index) => {
      return new Promise<void>((resolve, reject) => {
        const wsUrl = `ws://localhost:${port}/api/v1/realtime/live?token=${token}`;
        const ws = new WebSocket(wsUrl);

        ws.on('open', () => {
          connectedClients++;
          // Subscribe to topic
          ws.send(JSON.stringify({
            action: 'subscribe',
            topic: `tenant/${companyId}/orders`,
            correlationId: `corr-load-${index}`
          }));
        });

        ws.on('message', (data) => {
          const frame = JSON.parse(data.toString());
          
          if (frame.status === 'subscribed') {
            resolve();
          }

          if (frame.type === 'OrderCreated') {
            eventsReceived++;
            // Calculate delivery latency
            const sentTime = new Date(frame.timestamp).getTime();
            const now = Date.now();
            latencies.push(now - sentTime);
          }
        });

        ws.on('error', (err) => {
          console.error(`WebSocket client ${index} error:`, err.message);
          reject(err);
        });

        clients.push(ws);
      });
    });

    try {
      await Promise.all(connectPromises);
      console.log(`✅ All ${clientCount} WebSocket clients successfully connected and subscribed!`);

      // Begin broadcasting load
      const broadcastIterations = 100; // Broadcast 100 events
      const intervalMs = 20; // 50 broadcasts per second (3000 events/minute)
      
      console.log(`🔊 Broadcasting ${broadcastIterations} OrderCreated events at ${1000/intervalMs} events/sec...`);
      
      let count = 0;
      const startTime = Date.now();

      const runBroadcast = async () => {
        if (count >= broadcastIterations) {
          // Completed sending, wait for events to propagate
          setTimeout(() => {
            const duration = Date.now() - startTime;
            const avgLatency = latencies.reduce((a, b) => a + b, 0) / latencies.length;
            const maxLatency = Math.max(...latencies);
            const totalExpectedEvents = clientCount * broadcastIterations;

            console.log('================================================================');
            console.log('🏁 LOAD TEST RUN COMPLETE. PERFORMANCE RESULTS:');
            console.log(`👥 Connected Clients:    ${connectedClients}`);
            console.log(`📤 Events Broadcasted:   ${broadcastIterations}`);
            console.log(`📥 Events Expected:      ${totalExpectedEvents}`);
            console.log(`📥 Events Received:      ${eventsReceived} (${((eventsReceived/totalExpectedEvents)*100).toFixed(1)}% delivery success)`);
            console.log(`⏱️  Total Test Duration:   ${(duration/1000).toFixed(2)} seconds`);
            console.log(`⚡ Avg Event Latency:    ${avgLatency.toFixed(2)} ms`);
            console.log(`⚡ Max Event Latency:    ${maxLatency.toFixed(2)} ms`);
            console.log('================================================================');

            // Cleanup
            clients.forEach(c => c.close());
            server.close(() => {
              process.exit(eventsReceived === totalExpectedEvents ? 0 : 1);
            });
          }, 1500);
          return;
        }

        count++;
        await RealtimeBroadcastService.publishEvent(companyId, 'OrderCreated', {
          orderId: `sale-load-id-${count}`,
          totalAmount: 99.99,
          clientIndex: count
        }, `corr-load-trigger-${count}`);

        setTimeout(runBroadcast, intervalMs);
      };

      runBroadcast();

    } catch (err: any) {
      console.error('❌ Load test initialization failed:', err.message);
      process.exit(1);
    }
  });
}

runLoadTest();
