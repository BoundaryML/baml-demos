import 'server-only';

export function authConfiguration() {
  const missing = ['WORKOS_API_KEY', 'WORKOS_CLIENT_ID', 'WORKOS_COOKIE_PASSWORD', 'NEXT_PUBLIC_WORKOS_REDIRECT_URI'].filter((name) => !process.env[name]?.trim());
  if (process.env.WORKOS_COOKIE_PASSWORD && process.env.WORKOS_COOKIE_PASSWORD.length < 32) missing.push('WORKOS_COOKIE_PASSWORD (at least 32 characters)');
  let redirectUri: URL | undefined;
  try {
    redirectUri = new URL(process.env.NEXT_PUBLIC_WORKOS_REDIRECT_URI || '');
    if (!['http:', 'https:'].includes(redirectUri.protocol) || redirectUri.pathname !== '/auth/callback' || redirectUri.search || redirectUri.hash || redirectUri.username || redirectUri.password) throw new Error('Invalid callback');
  } catch {
    if (!missing.includes('NEXT_PUBLIC_WORKOS_REDIRECT_URI')) missing.push('NEXT_PUBLIC_WORKOS_REDIRECT_URI (must end in /auth/callback)');
  }
  return { configured: missing.length === 0, missing, redirectUri: redirectUri?.href, origin: redirectUri?.origin };
}
