import dotenv from 'dotenv';
dotenv.config();

import http from 'http';
import express from 'express';
import { pgPool } from '../config/database';
import { AuthService } from '../modules/auth/auth.service';
import { initRealtimeWebSocket } from '../modules/realtime/realtime.ws';
import { RealtimeBroadcastService } from '../modules/realtime/broadcast.service';
import WebSocket from 'ws';

async function runTest() {
  console.log('🧪 Starting Realtime WebSocket Integration Tests...');
  const app = express();
  const server = http.createServer(app);
  
  // Initialize WebSocket server
  initRealtimeWebSocket(server);
  
  // Listen on dynamic port
  server.listen(4001, async () => {
    console.log('📡 Test Server listening on port 4001');
    
    try {
      // Find an active user and tenant from the DB
      const userRes = await pgPool.query(
        "SELECT u.email, c.id as company_id FROM users u JOIN companies c ON u.company_id = c.id WHERE c.status = 'active' LIMIT 1"
      );
      
      if (userRes.rows.length === 0) {
        console.error('❌ Test failed: No active users/companies found in database. Please seed the database first.');
        process.exit(1);
      }
      
      const testEmail = userRes.rows[0].email;
      const companyId = userRes.rows[0].company_id;
      
      console.log(`👤 Using test user: ${testEmail}, tenant company: ${companyId}`);
      
      const jwtSecret = process.env.JWT_SECRET || 'test_jwt_secret_must_be_32_characters_minimum';
      process.env.JWT_SECRET = jwtSecret;
      
      const jwt = require('jsonwebtoken');
      const payload = {
        jti: 'test-ws-jti-123',
        id: 'user-test-id',
        name: 'Test Realtime User',
        email: testEmail,
        company_id: companyId,
        roles: ['owner'],
        permissions: ['sales:view', 'orders:view'],
      };
      
      const token = jwt.sign(payload, jwtSecret, {
        expiresIn: '15m',
        issuer: 'serenut.com',
        audience: 'serenut-pos',
      });
      
      // Connect to WS endpoint
      const wsUrl = `ws://localhost:4001/api/v1/realtime/live?token=${token}`;
      console.log(`🔌 Connecting WebSocket client to ${wsUrl}...`);
      const client = new WebSocket(wsUrl);
      
      let verifiedSub = false;
      let verifiedIsolation = false;

      client.on('open', () => {
        console.log('✅ WebSocket client connection established.');
        
        // 1. Subscribe to local company topic (Authorized)
        console.log('📤 Subscribing to authorized topic: tenant/company/orders...');
        client.send(JSON.stringify({
          action: 'subscribe',
          topic: `tenant/${companyId}/orders`,
          correlationId: 'corr-sub-auth'
        }));
        
        // 2. Subscribe to another company topic (Unauthorized)
        console.log('📤 Attempting subscription to unauthorized topic...');
        client.send(JSON.stringify({
          action: 'subscribe',
          topic: `tenant/other-company/orders`,
          correlationId: 'corr-sub-unauth'
        }));
      });
      
      client.on('message', async (data) => {
        const frame = JSON.parse(data.toString());
        console.log('📥 Received frame:', frame);
        
        if (frame.correlationId === 'corr-sub-auth') {
          if (frame.status === 'subscribed') {
            console.log('✅ Authorized subscription acknowledged by server.');
            verifiedSub = true;
            
            // Broadcast dummy event
            console.log('🔊 Triggering OrderCreated event...');
            await RealtimeBroadcastService.publishEvent(companyId, 'OrderCreated', {
              orderId: 'sale-test-uuid-99999',
              totalAmount: 240.00,
              paymentMethod: 'cash'
            }, 'corr-trigger-event');
          } else {
            console.error('❌ Authorized subscription failed.');
            process.exit(1);
          }
        }
        
        if (frame.correlationId === 'corr-sub-unauth') {
          if (frame.status === 'error' && frame.message.includes('Unauthorized')) {
            console.log('✅ Tenant Isolation verified: subscription rejected.');
            verifiedIsolation = true;
          } else {
            console.error('❌ Tenant Isolation violation: subscription accepted.');
            process.exit(1);
          }
        }
        
        if (frame.type === 'OrderCreated' && frame.correlationId === 'corr-trigger-event') {
          console.log('✅ Event payload successfully received on WS client.');
          console.log('✅ Event correlationId matched.');
          console.log('✅ Event payload data:', frame.payload);
          
          if (verifiedSub && verifiedIsolation) {
            console.log('🎉 ALL INTEGRATION TESTS PASSED SUCCESSFULLY!');
            client.close();
            server.close(() => {
              pgPool.end();
              process.exit(0);
            });
          }
        }
      });
      
      client.on('error', (err) => {
        console.error('❌ WebSocket Client error:', err);
        process.exit(1);
      });
      
    } catch (err: any) {
      console.error('❌ Integration test script encountered fatal error:', err);
      process.exit(1);
    }
  });
}

runTest();
