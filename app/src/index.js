const express = require('express');
const os = require('os');
const app = express();

const PORT = process.env.PORT || 3000;
const APP_VERSION = process.env.APP_VERSION || 'v1.0.0';
const ENVIRONMENT = process.env.ENVIRONMENT || 'local';
const DB_PASSWORD = process.env.DB_PASSWORD || 'not-set';

app.use(express.json());

let isReady = true;
let requestCount = 0;

app.get('/', (req, res) => {
  requestCount++;
  res.json({
    message: 'Production-grade DevOps Training App - v2 - v2',
    version: APP_VERSION,
    environment: ENVIRONMENT,
    hostname: os.hostname(),
    timestamp: new Date().toISOString(),
    secret_loaded: DB_PASSWORD !== 'not-set',
  });
});

app.get('/healthz', (req, res) => {
  res.status(200).json({ status: 'alive', uptime: Math.floor(process.uptime()) });
});

app.get('/readyz', (req, res) => {
  if (!isReady) return res.status(503).json({ status: 'draining' });
  res.status(200).json({ status: 'ready' });
});

app.get('/startupz', (req, res) => {
  res.status(200).json({ status: 'started' });
});

app.get('/metrics', (req, res) => {
  res.set('Content-Type', 'text/plain');
  res.send([
    `# HELP http_requests_total Total HTTP requests`,
    `# TYPE http_requests_total counter`,
    `http_requests_total{app="${APP_VERSION}",env="${ENVIRONMENT}"} ${requestCount}`,
    `# HELP process_uptime_seconds Process uptime`,
    `# TYPE process_uptime_seconds gauge`,
    `process_uptime_seconds ${Math.floor(process.uptime())}`,
  ].join('\n'));
});

const server = app.listen(PORT, () => {
  console.log(JSON.stringify({ level: 'info', msg: 'Server started', port: PORT, version: APP_VERSION, env: ENVIRONMENT }));
});

const DRAIN_TIMEOUT = parseInt(process.env.DRAIN_TIMEOUT_MS || '5000');

process.on('SIGTERM', () => {
  console.log(JSON.stringify({ level: 'info', msg: 'SIGTERM received, draining...' }));
  isReady = false;
  setTimeout(() => {
    server.close(() => {
      console.log(JSON.stringify({ level: 'info', msg: 'Server closed, exiting' }));
      process.exit(0);
    });
  }, DRAIN_TIMEOUT);
});
