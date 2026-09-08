import { test, expect, type APIRequestContext, type Page } from '@playwright/test';
import { WorkOS } from '@workos-inc/node';
import { DEFAULT_MODELS, SAMPLE_BRIEF, demos, programExamples } from '../src/lib/demos';

const identities = { organizations: [{ id: 'org_e2ebrowser', name: 'Demo organization' }], users: [{ id: 'user_ada', name: 'Ada Demo' }, { id: 'user_lin', name: 'Lin Demo' }] };
async function mockContext(page: Page) { await page.route('**/api/context*', (route) => route.fulfill({ json: identities })); }
async function resolve(request: APIRequestContext, data: object) {
  const response = await request.post('/api/demos/resolve', { data });
  expect(response.status(), await response.text()).toBe(200);
  return response.json();
}
const copyId = (result: Awaited<ReturnType<typeof resolve>>) => result.functions.GenerateAnnouncementCopy.clientId;

test('all five demos need no login and each direct client switches independently', async ({ page, request }) => {
  await mockContext(page); await page.goto('/');
  await expect(page).toHaveURL('/demo1');
  await expect(page.getByRole('navigation', { name: 'Switching demos' }).getByRole('link')).toHaveCount(5);
  await expect(page.getByTestId('resolved-GenerateLogo')).toHaveText('google/gemini-3.1-flash-image');
  const copy = page.getByRole('group', { name: 'GenerateAnnouncementCopy()' });
  await copy.getByLabel('Model ID', { exact: true }).fill('gpt-5.6-luna');
  await expect(page.getByTestId('resolved-GenerateAnnouncementCopy')).toHaveText('openai/gpt-5.6-luna');
  await expect(page.getByTestId('resolved-GenerateLogo')).toHaveText('google/gemini-3.1-flash-image');
  const result = await resolve(request, { demo: 'direct', choices: { ...DEFAULT_MODELS, GenerateAnnouncementCopy: { provider: 'google', model: 'gemini-3.8-flash' } } });
  expect(copyId(result)).toBe('google/gemini-3.8-flash');
});

test('environment selection is read per function by the native BAML runtime', async ({ page, request }) => {
  const result = await resolve(request, { demo: 'environment', choices: DEFAULT_MODELS });
  expect(copyId(result)).toBe('openai/gpt-5.6-luna');
  expect(result.functions.GenerateLogo.clientId).toBe('google/gemini-3.1-flash-image');
  await mockContext(page); await page.goto('/');
  await page.getByRole('link', { name: /02 Environment variables/ }).click();
  await expect(page.getByTestId('resolved-GenerateAnnouncementCopy')).toHaveText('openai/gpt-5.6-luna');
});

test('filesystem lookup uses org, user and function with isolated model and program stores', async ({ request }) => {
  const context = { organizationId: `org_precedence${Date.now()}`, userId: 'user_ada' };
  const base = { demo: 'overrides', ...context };
  const body = { store: 'models', functionName: 'GenerateAnnouncementCopy', ...context };
  const write = (scope: string, model: string) => request.put('/api/overrides', { data: { ...body, scope, value: { provider: 'openai', model } } });
  try {
    expect(copyId(await resolve(request, base))).toBe('openai/gpt-5.2');
    expect((await write('organization', 'gpt-5.6-terra')).status()).toBe(200);
    expect(copyId(await resolve(request, base))).toBe('openai/gpt-5.6-terra');
    expect((await write('user', 'gpt-5.6-luna')).status()).toBe(200);
    const user = await resolve(request, base);
    expect(copyId(user)).toBe('openai/gpt-5.6-luna');
    expect(user.functions.GenerateAnnouncementCopy.key).toEqual({ org: context.organizationId, user: context.userId, function_name: 'GenerateAnnouncementCopy' });
    expect(user.functions.GenerateAnnouncementCopy.source).toBe(`GenerateAnnouncementCopy/${context.organizationId}-${context.userId}.llm-override`);
    expect(user.functions.GenerateLogo.clientId).toBe('google/gemini-3.1-flash-image');
    expect(copyId(await resolve(request, { ...base, userId: 'user_lin' }))).toBe('openai/gpt-5.6-terra');
    expect(copyId(await resolve(request, { ...base, demo: 'programs' }))).toBe('openai/gpt-5.2');
    await request.delete('/api/overrides', { data: { ...body, scope: 'user' } });
    expect(copyId(await resolve(request, base))).toBe('openai/gpt-5.6-terra');
  } finally { for (const scope of ['user', 'organization']) await request.delete('/api/overrides', { data: { ...body, scope } }); }
});

test('reflection verifies complete function contracts and preserves valid files after rejected edits', async ({ request }) => {
  const context = { organizationId: `org_reflect${Date.now()}` };
  for (const functionName of ['GenerateLogo', 'GenerateAnnouncementCopy'] as const) {
    const body = { store: 'programs', functionName, scope: 'organization', ...context };
    const examples = programExamples(functionName);
    try {
      for (const value of Object.values(examples)) {
        const save = await request.put('/api/overrides', { data: { ...body, value } });
        expect(save.status(), await save.text()).toBe(200);
        const decision = (await resolve(request, { demo: 'programs', ...context })).functions[functionName];
        expect(decision.validated).toBe(true);
        expect(decision.clientId).toBe(functionName === 'GenerateLogo' ? 'google/gemini-3.1-flash-image' : 'openai/gpt-5.6-luna');
      }
      for (const value of ['42', 'openai.ResponsesClient.new(model = "gpt-5.2")', 'function ChooseLlm() -> string { "wrong type" }', 'function AnotherName() -> ai.Client { openai.ResponsesClient.new(model = "gpt-5.2") }', 'function ChooseLlm(required: string) -> ai.Client { openai.ResponsesClient.new(model = required) }']) {
        const rejected = await request.put('/api/overrides', { data: { ...body, value } });
        expect(rejected.status(), await rejected.text()).toBe(422);
      }
      expect((await resolve(request, { demo: 'programs', ...context })).functions[functionName].program).toBe(examples.fallback);
    } finally { await request.delete('/api/overrides', { data: body }); }
  }
});

test('malformed inputs, wrong modalities and unsafe paths are rejected', async ({ request }) => {
  for (const data of [null, { demo: 'constructor' }, { demo: 'direct', choices: { GenerateLogo: { provider: 'openai', model: 'gpt-5.2' } } }, { demo: 'direct', choices: { GenerateAnnouncementCopy: { provider: 'google', model: 'gemini-3.1-flash-image' } } }, { demo: 'overrides', organizationId: '../outside' }, { demo: 'programs', organizationId: 'org_good', userId: '../../escape' }]) {
    expect((await request.post('/api/demos/resolve', { data })).status()).toBe(400);
  }
  expect((await request.put('/api/overrides', { data: { store: 'models', organizationId: 'org_good', functionName: '../outside', scope: 'organization', value: {} } })).status()).toBe(400);
  for (const brief of [undefined, { ...SAMPLE_BRIEF, product_name: ' ' }, { ...SAMPLE_BRIEF, description: 'x'.repeat(12001) }]) {
    expect((await request.post('/api/demos/run', { data: { demo: 'direct', brief } })).status()).toBe(400);
  }
});

test('missing image key is actionable and blank briefs cannot run', async ({ page }) => {
  await mockContext(page); await page.goto('/');
  await expect(page.getByRole('button', { name: 'Generate launch assets' })).toBeEnabled();
  await page.getByRole('button', { name: 'Generate launch assets' }).click();
  await expect(page.getByRole('region', { name: 'Launch assets' }).getByRole('alert')).toContainText('GEMINI_API_KEY');
  await page.getByLabel('Product name', { exact: true }).fill('   ');
  await expect(page.getByRole('button', { name: 'Generate launch assets' })).toBeDisabled();
});

test('run sends the launch brief and both clients and renders downloadable assets', async ({ page }, testInfo) => {
  await mockContext(page);
  let finish!: () => void;
  const pending = new Promise<void>((resolve) => { finish = resolve; });
  await page.route('**/api/demos/run', async (route) => {
    expect(route.request().postDataJSON()).toMatchObject({ demo: 'direct', choices: DEFAULT_MODELS, brief: { ...SAMPLE_BRIEF, product_name: 'Test launch' } });
    await pending;
    const functions = Object.fromEntries(Object.entries(DEFAULT_MODELS).map(([functionName, config]) => [functionName, { functionName, ...config, clientId: `${config.provider}/${config.model}`, source: 'Client argument', trace: ['Two parallel calls'] }]));
    await route.fulfill({ json: { productName: 'Test launch', resolution: { demo: 'direct', functions }, output: { logo: { mime_type: 'image/png', base64: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=' }, announcement: { headline: 'Your next launch starts here.', tagline: 'Build together.', body: 'Meet your new launch workspace.', call_to_action: 'Explore the product' } }, durationMs: 1250 } });
  });
  await page.goto('/'); await page.getByLabel('Product name', { exact: true }).fill('Test launch');
  await expect(page.getByRole('button', { name: 'Generate launch assets' })).toBeEnabled();
  await page.getByRole('button', { name: 'Generate launch assets' }).click();
  await expect(page.getByRole('button', { name: 'Generating launch assets…' })).toBeDisabled();
  finish();
  await expect(page.getByRole('img', { name: 'Generated logo for Test launch' })).toBeVisible();
  await expect(page.getByTestId('announcement-copy')).toContainText('Your next launch starts here.');
  await expect(page.getByRole('link', { name: /Download logo/ })).toHaveAttribute('download', 'test-launch-logo.png');
  await expect(page.getByRole('link', { name: /Download announcement/ })).toHaveAttribute('download', 'test-launch-announcement.txt');
  await expect(page.getByRole('region', { name: 'Recent launches' })).toContainText('Test launch');
  await page.screenshot({ path: testInfo.outputPath('launch-studio.png'), fullPage: true });
});

test('browser edits organization and user routes for a single function through the filesystem API', async ({ page, request }) => {
  await mockContext(page);
  const body = { store: 'models', functionName: 'GenerateAnnouncementCopy', organizationId: 'org_e2ebrowser', userId: 'user_ada' };
  const cleanup = async () => { for (const scope of ['organization', 'user']) await request.delete('/api/overrides', { data: { ...body, scope } }); };
  await cleanup();
  try {
    await page.goto('/'); await page.getByRole('link', { name: /03 Choose by context/ }).click();
    await page.getByLabel('Function to override').selectOption('GenerateAnnouncementCopy');
    await expect(page.getByRole('button', { name: 'Save override' })).toBeEnabled();
    await page.getByRole('button', { name: 'Save override' }).click();
    await expect(page.getByTestId('resolved-GenerateAnnouncementCopy')).toHaveText('openai/gpt-5.6-terra');
    await page.getByRole('combobox', { name: 'User', exact: true }).selectOption('user_ada');
    await page.getByRole('button', { name: 'This user', exact: true }).click();
    await page.getByLabel('Model ID', { exact: true }).fill('gpt-5.6-luna');
    await page.getByRole('button', { name: 'Save override' }).click();
    await expect(page.getByTestId('resolved-GenerateAnnouncementCopy')).toHaveText('openai/gpt-5.6-luna');
    await expect(page.getByTestId('resolved-GenerateLogo')).toHaveText('google/gemini-3.1-flash-image');
    await page.getByRole('combobox', { name: 'User', exact: true }).selectOption('user_lin');
    await expect(page.getByTestId('resolved-GenerateAnnouncementCopy')).toHaveText('openai/gpt-5.6-terra');
  } finally { await cleanup(); }
});

test('WorkOS live sync independently targets each asset by organization OR user', async () => {
  const initial = (slug: string) => ({ slug, enabled: false, default_value: false, targets: { users: [] as { id: string; enabled: boolean }[], organizations: [] as { id: string; enabled: boolean }[] } });
  let copy = initial('launch-copy-upgrade');
  const logo = initial('launch-logo-upgrade');
  const workos = new WorkOS('test-key', { fetchFn: async () => Response.json({ 'launch-copy-upgrade': copy, 'launch-logo-upgrade': logo }) });
  const client = workos.featureFlags.createRuntimeClient({ pollingIntervalMs: 5000 });
  try {
    await client.waitUntilReady({ timeoutMs: 3000 });
    expect(client.isEnabled(copy.slug, { organizationId: 'org_pilot' })).toBe(false);
    copy = { ...copy, enabled: true, targets: { organizations: [{ id: 'org_pilot', enabled: true }], users: [{ id: 'user_ada', enabled: true }] } };
    await expect.poll(() => client.isEnabled(copy.slug, { organizationId: 'org_pilot', userId: 'user_lin' }), { timeout: 8000 }).toBe(true);
    expect(client.isEnabled(copy.slug, { organizationId: 'org_other', userId: 'user_ada' })).toBe(true);
    expect(client.isEnabled(copy.slug, { organizationId: 'org_other', userId: 'user_lin' })).toBe(false);
    expect(client.isEnabled(logo.slug, { organizationId: 'org_pilot', userId: 'user_ada' })).toBe(false);
    copy = { ...copy, enabled: false };
    await expect.poll(() => client.isEnabled(copy.slug, { organizationId: 'org_pilot' }), { timeout: 8000 }).toBe(false);
  } finally { client.close(); }
});

test('mobile layout fits and complete function editor remains usable', async ({ page }, testInfo) => {
  await mockContext(page); await page.setViewportSize({ width: 390, height: 844 }); await page.goto('/');
  await page.getByRole('link', { name: /04 Store a BAML function/ }).click();
  await expect(page.getByRole('heading', { name: 'Store a BAML function' })).toBeVisible();
  await expect(page.getByLabel('Complete BAML function')).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page.screenshot({ path: testInfo.outputPath('mobile.png'), fullPage: true });
});


test('each tab exposes its own namespaced BAML workflow', async ({ page }) => {
  await mockContext(page); await page.goto('/');
  for (const demo of demos) {
    await page.getByRole('navigation', { name: 'Switching demos' }).getByRole('link').filter({ hasText: demo.title }).click();
    await expect(page).toHaveURL(`/${demo.namespace}`);
    await expect(page.getByRole('region', { name: 'Launch brief' }).getByText(`${demo.namespace}.GenerateAssets()`, { exact: true })).toBeVisible();
  }
});

for (const demo of demos) {
  test(`${demo.namespace} opens directly and survives a reload`, async ({ page }) => {
    await mockContext(page);
    await page.goto(`/${demo.namespace}`);
    await expect(page.getByRole('heading', { name: demo.title, exact: true })).toBeVisible();
    const activeLink = page.getByRole('navigation', { name: 'Switching demos' }).locator('a[aria-current="page"]');
    await expect(activeLink).toHaveAttribute('href', `/${demo.namespace}`);
    await page.reload();
    await expect(page.getByRole('region', { name: 'Launch brief' }).getByText(`${demo.namespace}.GenerateAssets()`, { exact: true })).toBeVisible();
    await expect(activeLink).toHaveAttribute('href', `/${demo.namespace}`);
  });
}

test('demo navigation follows browser history and unknown demos return 404', async ({ page, request }) => {
  await mockContext(page);
  await page.goto('/demo1');
  await page.getByRole('link', { name: /02 Environment variables/ }).click();
  await expect(page).toHaveURL('/demo2');
  await page.goBack();
  await expect(page).toHaveURL('/demo1');
  await expect(page.getByRole('heading', { name: 'Pass the clients', exact: true })).toBeVisible();
  await page.goForward();
  await expect(page).toHaveURL('/demo2');
  await expect(page.getByRole('heading', { name: 'Environment variables', exact: true })).toBeVisible();
  expect((await request.get('/demo6')).status()).toBe(404);
});
