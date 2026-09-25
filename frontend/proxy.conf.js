/**
 * Angular dev-server proxy configuration.
 *
 * Reads `API_TARGET` from the environment. Falls back to the local
 * API on https://localhost:50943 (the one started from Visual Studio).
 *
 * Usage (via npm scripts in package.json):
 *   npm run dev        -> local API from IDE
 *   npm run dev:k8s    -> API in kind cluster via ingress
 *   npm run dev:port   -> custom target (set API_TARGET manually)
 *
 * Common targets:
 *   Local IDE:      https://localhost:50943
 *   K8s (kind):     http://api.flights.local
 *   Remote env:     https://api.staging.example.com
 */

const DEFAULT_TARGET = 'https://localhost:50943';
const target = process.env.API_TARGET || DEFAULT_TARGET;

// Strip trailing slash to keep path rewriting consistent.
const cleanTarget = target.replace(/\/+$/, '');

console.log(`[proxy] Forwarding /api/* -> ${cleanTarget}/*`);

module.exports = {
  '/api': {
    target: cleanTarget,
    secure: false,          // allow self-signed certs (local IDE, dev)
    changeOrigin: true,     // rewrite Host header (needed by ingress)
    logLevel: 'info',
    pathRewrite: { '^/api': '' },
    // Do not verify TLS certificate for local targets - dev only.
    // In production traffic is terminated by a real ingress with valid certs.
    onProxyReq: (proxyReq, req, res) => {
      // Optional: add a header for tracing which proxy sent the request.
      proxyReq.setHeader('X-Forwarded-By', 'angular-dev-proxy');
    }
  }
};