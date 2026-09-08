import { test, expect } from '@playwright/test';

test('guests can access login and demos, and sign-in creates a PKCE flow', async ({ page, request }) => {
  await page.goto('/login');
  await expect(page.getByRole('heading', { name: 'Welcome to the studio.' })).toBeVisible();
  await expect(page.getByRole('link', { name: /Continue as a guest/ })).toHaveAttribute('href', '/');
  const alternateHost = await request.get('http://localhost:3100/login', { maxRedirects: 0 });
  expect(alternateHost.status()).toBe(307);
  expect(alternateHost.headers().location).toBe('http://127.0.0.1:3100/login');
  const response = await request.get('/auth/sign-in', { maxRedirects: 0 });
  expect(response.status()).toBe(307);
  const target = new URL(response.headers().location);
  expect(target.origin).toBe('http://127.0.0.1:3199');
  expect(target.searchParams.get('redirect_uri')).toBe('http://127.0.0.1:3100/auth/callback');
  expect(target.searchParams.get('max_age')).toBe('0');
  expect(target.searchParams.get('code_challenge_method')).toBe('S256');
  expect(target.searchParams.get('code_challenge')).toBeTruthy();
  expect(target.searchParams.get('state')).toBeTruthy();
  const cookie = response.headers()['set-cookie'];
  expect(cookie).toContain('HttpOnly'); expect(cookie).toContain('SameSite=lax');
  expect((await request.get('/')).status()).toBe(200);
});

test('real AuthKit callback stores a session, switch account ends it, and sign-out clears it', async ({ page, request }, testInfo) => {
  await page.goto('/login');
  await page.getByRole('link', { name: 'Sign in with WorkOS' }).click();
  await expect(page.getByRole('heading', { name: 'Test WorkOS sign-in' })).toBeVisible();
  await page.getByRole('link', { name: 'Continue as Alice' }).click();
  await expect(page.getByRole('heading', { name: 'Alice Demo' })).toBeVisible();
  await expect(page.getByRole('region', { name: 'Your account' })).toContainText('alice@example.com');
  await page.screenshot({ path: testInfo.outputPath('signed-in.png'), fullPage: true });
  const originalSession = (await page.context().cookies()).find((cookie) => cookie.name === 'wos-session');
  expect(originalSession?.httpOnly).toBe(true);
  expect(originalSession?.sameSite).toBe('Lax');
  await page.getByRole('button', { name: 'Switch account' }).click();
  await expect(page.getByRole('heading', { name: 'Test WorkOS sign-in' })).toBeVisible();
  expect((await page.context().cookies()).some((cookie) => cookie.name === 'wos-session')).toBe(false);
  expect((await (await request.get('http://127.0.0.1:3199/test/revoked')).json()).sessions.some((id: string) => id.startsWith('session_alice_'))).toBe(true);
  await page.getByRole('link', { name: 'Continue as Bob' }).click();
  await expect(page.getByRole('heading', { name: 'Bob Demo' })).toBeVisible();
  await expect(page.getByRole('region', { name: 'Your account' })).not.toContainText('alice@example.com');
  await page.reload();
  await expect(page.getByRole('heading', { name: 'Bob Demo' })).toBeVisible();
  await page.getByRole('button', { name: 'Sign out', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Welcome to the studio.' })).toBeVisible();
  expect((await page.context().cookies()).some((cookie) => cookie.name === 'wos-session')).toBe(false);
});

test('callback rejects missing or mismatched state and never exposes auth credentials', async ({ page, request }) => {
  for (const path of ['/auth/callback', '/auth/callback?code=fake&state=forged']) {
    const result = await request.get(path, { maxRedirects: 0 });
    expect(result.status()).toBe(307);
    expect(result.headers().location).toBe('http://127.0.0.1:3100/login?error=callback');
    expect(result.headers()['cache-control']).toContain('no-store');
    expect(result.headers()['set-cookie'] ?? '').not.toContain('wos-session=');
  }
  const signedOut = await request.get('/login', { headers: { 'x-workos-middleware': 'true', 'x-workos-session': 'forged-session', 'x-url': 'https://attacker.example' } });
  expect(signedOut.status()).toBe(200);
  expect(await signedOut.text()).toContain('Welcome to the studio.');
  expect(signedOut.headers()['x-workos-session']).toBeUndefined();
  await page.goto('/login?error=callback');
  await expect(page.getByRole('region', { name: 'Your account' }).getByRole('alert')).toContainText('Start a new sign-in');
});

test('login page fits on mobile', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/login');
  await expect(page.getByRole('link', { name: 'Sign in with WorkOS' })).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page.screenshot({ path: testInfo.outputPath('login-mobile.png'), fullPage: true });
});
