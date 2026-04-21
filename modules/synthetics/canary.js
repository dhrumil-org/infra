/**
 * VocuOne API Canary
 *
 * Steps:
 *   1. GET /health  — unauthenticated liveness check
 *   2. POST /auth/login — authenticate with LOGIN_EMAIL + LOGIN_PASSWORD
 *   3. GET /api/ping (or any protected endpoint) — authenticated check
 *
 * Environment variables (set in Terraform):
 *   BASE_URL       — e.g. https://api.stage.vocuone.ai
 *   LOGIN_EMAIL    — canary test account email
 *   LOGIN_PASSWORD — canary test account password
 */

const synthetics = require('Synthetics');
const log = require('SyntheticsLogger');
const https = require('https');

// ─── Helpers ────────────────────────────────────────────────────────────────

function parseUrl(raw) {
  const url = new URL(raw.endsWith('/') ? raw.slice(0, -1) : raw);
  return {
    hostname: url.hostname,
    port: url.port || 443,
    protocol: url.protocol,
  };
}

function httpRequest(options, body) {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => resolve({ statusCode: res.statusCode, body: data, headers: res.headers }));
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

// ─── Canary Steps ────────────────────────────────────────────────────────────

const baseUrl  = (process.env.BASE_URL || '').replace(/\/$/, '');
const email    = process.env.LOGIN_EMAIL    || '';
const password = process.env.LOGIN_PASSWORD || '';

const stepConfig = {
  includeResponseHeaders: true,
  includeResponseBody:    true,
  includeRequestHeaders:  false,
  includeRequestBody:     false,
  restrictedHeaders:      ['Authorization', 'Cookie'],
};

// Step 1: Health check
async function healthCheck() {
  const { hostname, port } = parseUrl(baseUrl);

  const options = {
    hostname,
    port,
    method: 'GET',
    path:   '/health',
    headers: { 'User-Agent': 'CloudWatch-Synthetics-Canary' },
  };

  await synthetics.executeHttpStep('Health Check', options, async (res) => {
    return new Promise((resolve, reject) => {
      let body = '';
      res.on('data', (c) => { body += c; });
      res.on('end', () => {
        log.info(`Health: HTTP ${res.statusCode} — ${body.slice(0, 200)}`);
        if (res.statusCode !== 200) {
          reject(new Error(`Health check failed: HTTP ${res.statusCode}`));
        } else {
          resolve();
        }
      });
    });
  }, stepConfig);
}

// Step 2 + 3: Authenticated flow (skipped if no credentials)
async function authenticatedCheck() {
  if (!email || !password) {
    log.info('No LOGIN_EMAIL/LOGIN_PASSWORD set — skipping auth check');
    return;
  }

  const { hostname, port } = parseUrl(baseUrl);
  const loginBody = JSON.stringify({ email, password });

  // POST /auth/login
  let authToken = '';
  const loginOptions = {
    hostname,
    port,
    method: 'POST',
    path:   '/auth/login',
    headers: {
      'Content-Type':   'application/json',
      'Content-Length': Buffer.byteLength(loginBody),
      'User-Agent':     'CloudWatch-Synthetics-Canary',
    },
  };

  await synthetics.executeHttpStep('Login', loginOptions, async (res) => {
    return new Promise((resolve, reject) => {
      let body = '';
      res.on('data', (c) => { body += c; });
      res.on('end', () => {
        log.info(`Login: HTTP ${res.statusCode}`);
        if (res.statusCode !== 200) {
          reject(new Error(`Login failed: HTTP ${res.statusCode}`));
          return;
        }
        try {
          const json = JSON.parse(body);
          authToken = json.token || json.accessToken || json.access_token || '';
          // Also check Set-Cookie header
          const setCookie = res.headers['set-cookie'];
          if (setCookie) {
            authToken = setCookie.join('; ');
          }
        } catch (e) {
          log.warn('Could not parse login response: ' + e.message);
        }
        resolve();
      });
    });
  }, stepConfig);

  if (!authToken) {
    log.warn('No auth token extracted from login response — skipping protected endpoint check');
    return;
  }

  // GET protected endpoint
  const protectedOptions = {
    hostname,
    port,
    method: 'GET',
    path:   '/api/health',
    headers: {
      'Authorization': `Bearer ${authToken}`,
      'User-Agent':    'CloudWatch-Synthetics-Canary',
    },
  };

  await synthetics.executeHttpStep('Authenticated Check', protectedOptions, async (res) => {
    return new Promise((resolve, reject) => {
      res.on('data', () => {});
      res.on('end', () => {
        log.info(`Protected endpoint: HTTP ${res.statusCode}`);
        if (res.statusCode >= 500) {
          reject(new Error(`Protected endpoint returned HTTP ${res.statusCode}`));
        } else {
          resolve();
        }
      });
    });
  }, stepConfig);
}

// ─── Entry Point ─────────────────────────────────────────────────────────────

exports.handler = async () => {
  await healthCheck();
  await authenticatedCheck();
};
