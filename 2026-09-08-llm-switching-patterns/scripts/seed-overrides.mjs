import './load-env.mjs';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { WorkOS } from '@workos-inc/node';
if (!process.env.WORKOS_API_KEY) throw new Error('Set WORKOS_API_KEY first.');
const workos = new WorkOS(process.env.WORKOS_API_KEY);
const organizations = await workos.organizations.listOrganizations({ limit: 100 });
const org = organizations.data[0];
if (!org) throw new Error('Run pnpm workos:setup first.');
const users = await workos.userManagement.listUsers({ organizationId: org.id, limit: 100 });
const ada = users.data.find((user) => user.metadata?.demo === 'llm-switching-patterns' && user.firstName === 'Ada');
const root = process.env.DEMO_DATA_DIR || join(process.cwd(), '.demo-data');
const rows = [];
for (const [person, key] of [['organization', org.id], ...(ada ? [['Ada', `${org.id}-${ada.id}`]] : [])]) {
  const copyModel = person === 'Ada' ? 'gpt-5.6-luna' : 'gpt-5.6-terra';
  rows.push(['models', 'GenerateLogo', `${key}.llm-override`, JSON.stringify({ provider: 'google', model: 'gemini-3.1-flash-image' }, null, 2)]);
  rows.push(['models', 'GenerateAnnouncementCopy', `${key}.llm-override`, JSON.stringify({ provider: 'openai', model: copyModel }, null, 2)]);
  rows.push(['programs', 'GenerateLogo', `${key}.llm-override`, 'function ChooseLlm() -> ai.Client {\n    google.GeminiClient.new(\n        model = "gemini-3.1-flash-image",\n        api_key = env.GEMINI_API_KEY,\n        response_modalities = ["IMAGE"],\n    )\n}\n']);
  rows.push(['programs', 'GenerateAnnouncementCopy', `${key}.llm-override`, `function ChooseLlm() -> ai.Client {\n    let primary = openai.ResponsesClient.new(\n        model = "${copyModel}",\n        api_key = env.OPENAI_API_KEY,\n        request_timeout_ms = 120000,\n    );\n    ai.clients.Retry.new(inner = primary, max_attempts = 2)\n}\n`]);
}
for (const [store, functionName, key, value] of rows) {
  await mkdir(join(root, store, functionName), { recursive: true });
  try { await writeFile(join(root, store, functionName, key), value, { flag: 'wx', mode: 0o600 }); console.log(`Created ${store}/${functionName}/${key}`); }
  catch (error) { if (error.code !== 'EEXIST') throw error; console.log(`Kept ${store}/${functionName}/${key}`); }
}
