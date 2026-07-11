/* load-test.js — High concurrent load testing benchmark script for Serenut OS */

const autocannon = require('autocannon');

const targetUrl = process.env.TARGET_URL || 'http://localhost:3000';

console.log(`🚀 Initializing high-concurrency load test on ${targetUrl}...`);

const instance = autocannon({
  url: targetUrl,
  connections: 250, // 250 concurrent users simulated
  pipelining: 5,
  duration: 15,     // Test for 15 seconds
  title: 'Serenut OS POS Sync & Telemetry Benchmark',
  requests: [
    {
      method: 'GET',
      path: '/health'
    },
    {
      method: 'GET',
      path: '/metrics'
    },
    {
      method: 'POST',
      path: '/api/v1/auth/login',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'demo@serenut.com', password: 'wrongpassword' }) // rate-limited route verification
    }
  ]
}, (err, result) => {
  if (err) {
    console.error('Error running load test:', err);
    return;
  }
  console.log('🏁 Load test completed! Summary Results:');
  console.log(`- Total Requests Sent: ${result.requests.sent}`);
  console.log(`- Avg Request Latency: ${result.latency.average} ms`);
  console.log(`- Request Throughput (Req/Sec): ${result.requests.average}`);
  console.log(`- Data Transferred: ${(result.throughput.average / 1024 / 1024).toFixed(2)} MB/sec`);
  console.log(`- 2xx Responses: ${result['2xx']}`);
  console.log(`- 4xx Responses (Blocked/Limited): ${result['4xx']}`);
  console.log(`- 5xx Responses (Internal Failures): ${result['5xx']}`);
});

autocannon.track(instance, { renderProgressBar: true });
