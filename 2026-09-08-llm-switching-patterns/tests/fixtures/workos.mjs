// Local OAuth transport for integration tests. Never used by the application in normal development.
import { createServer } from 'node:http';
import { generateKeyPairSync, randomUUID, createHash, sign } from 'node:crypto';
const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const jwk = { ...publicKey.export({ format: 'jwk' }), kid: 'test-key', alg: 'RS256', use: 'sig' };
const codes = new Map();
const revoked = new Set();
const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
function token(user, sessionId) {
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${encode({ alg: 'RS256', kid: jwk.kid })}.${encode({ sub: user.id, sid: sessionId, org_id: 'org_authfixture', iss: 'http://127.0.0.1:3199/', iat: now, exp: now + 3600 })}`;
  return `${unsigned}.${sign('RSA-SHA256', Buffer.from(unsigned), privateKey).toString('base64url')}`;
}
function json(response, body, status = 200) { response.writeHead(status, { 'Content-Type': 'application/json' }); response.end(JSON.stringify(body)); }
const server = createServer(async (request, response) => {
  const url = new URL(request.url, 'http://127.0.0.1:3199');
  if (url.pathname === '/health') return json(response, { ok: true });
  if (url.pathname === '/sso/jwks/client_authfixture') return json(response, { keys: [jwk] });
  if (url.pathname === '/user_management/authorize') {
    const callback = url.searchParams.get('redirect_uri');
    if (callback !== 'http://127.0.0.1:3100/auth/callback' || url.searchParams.get('code_challenge_method') !== 'S256') return json(response, { error: 'Invalid test OAuth request' }, 400);
    const links = ['Alice', 'Bob'].map((name) => {
      const code = randomUUID();
      codes.set(code, { name, challenge: url.searchParams.get('code_challenge') });
      const target = new URL(callback); target.searchParams.set('state', url.searchParams.get('state')); target.searchParams.set('code', code);
      return `<p><a href="${target.toString().replaceAll('&', '&amp;')}">Continue as ${name}</a></p>`;
    });
    response.writeHead(200, { 'Content-Type': 'text/html' });
    return response.end(`<!doctype html><html><body><h1>Test WorkOS sign-in</h1>${links.join('')}</body></html>`);
  }
  if (url.pathname === '/user_management/authenticate') {
    let text = ''; for await (const chunk of request) text += chunk;
    const body = JSON.parse(text);
    const flow = codes.get(body.code); codes.delete(body.code);
    if (!flow || flow.challenge !== createHash('sha256').update(body.code_verifier ?? '').digest('base64url')) return json(response, { error: 'invalid_grant' }, 400);
    const user = { object: 'user', id: `user_${flow.name.toLowerCase()}`, email: `${flow.name.toLowerCase()}@example.com`, email_verified: true, first_name: flow.name, last_name: 'Demo', profile_picture_url: null, created_at: new Date().toISOString(), updated_at: new Date().toISOString(), external_id: null, metadata: {} };
    const sessionId = `session_${flow.name.toLowerCase()}_${randomUUID()}`;
    return json(response, { user, organization_id: 'org_authfixture', access_token: token(user, sessionId), refresh_token: `refresh_${sessionId}`, authentication_method: 'Password' });
  }
  if (url.pathname === '/user_management/sessions/logout') {
    const session = url.searchParams.get('session_id');
    const target = url.searchParams.get('return_to');
    if (!session || !['http://127.0.0.1:3100/login', 'http://127.0.0.1:3100/auth/sign-in'].includes(target)) return json(response, { error: 'Invalid logout request' }, 400);
    revoked.add(session);
    response.writeHead(302, { Location: target }); return response.end();
  }
  if (url.pathname === '/test/revoked') return json(response, { sessions: [...revoked] });
  if (url.pathname.includes('feature_flags') || url.pathname.includes('feature-flags')) return json(response, {});
  return json(response, { error: 'Unimplemented test endpoint', path: url.pathname }, 404);
});
server.listen(3199, '127.0.0.1');
process.on('SIGTERM', () => server.close());
