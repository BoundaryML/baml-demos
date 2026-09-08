import 'server-only';
import { mkdir, readFile, rename, unlink, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { assetFunctions, DEFAULT_MODELS, MAX_PROGRAM, type AssetFunction, type Context, type LlmChoiceKey, type ModelConfig } from '@/lib/demos';
import { DemoError } from './errors';
export type Store = 'models' | 'programs';
export type Scope = 'organization' | 'user';
export function validateContext(organizationId: unknown, userId?: unknown): Context {
  if (typeof organizationId !== 'string' || !/^org_[a-zA-Z0-9]+$/.test(organizationId)) throw new DemoError('Choose a WorkOS organization.');
  if (userId !== undefined && userId !== '' && (typeof userId !== 'string' || !/^user_[a-zA-Z0-9]+$/.test(userId))) throw new DemoError('Choose a valid WorkOS user ID.');
  return { organizationId, ...(userId ? { userId: userId as string } : {}) };
}
export function validateFunction(value: unknown): AssetFunction {
  if (!assetFunctions.includes(value as AssetFunction)) throw new DemoError('Choose GenerateLogo or GenerateAnnouncementCopy.');
  return value as AssetFunction;
}
export function choiceKey(context: Context, functionName: AssetFunction): LlmChoiceKey {
  return { org: context.organizationId, user: context.userId ?? '', function_name: functionName };
}
export function validateModel(value: unknown, functionName: AssetFunction): ModelConfig {
  if (!value || typeof value !== 'object') throw new DemoError('Provide a provider and model ID.');
  const { provider, model } = value as Record<string, unknown>;
  if (provider !== 'openai' && provider !== 'google') throw new DemoError('Provider must be openai or google (Gemini).');
  if (typeof model !== 'string' || !/^[a-zA-Z0-9][a-zA-Z0-9._:/-]{0,149}$/.test(model)) throw new DemoError('Enter a valid model ID (up to 150 characters).');
  const isImageModel = provider === 'openai' ? /^(gpt-image-|chatgpt-image-)/.test(model) : /image/.test(model);
  if ((functionName === 'GenerateLogo') !== isImageModel) throw new DemoError(functionName === 'GenerateLogo' ? 'GenerateLogo needs an image-generation model. Use Gemini Flash Image or GPT Image.' : 'GenerateAnnouncementCopy needs a text model, such as GPT-5.2, Terra, Luna, or Gemini Flash.');
  return { provider, model };
}
export function validateProgram(value: unknown): string {
  if (typeof value !== 'string' || !value.trim() || value.length > MAX_PROGRAM) throw new DemoError(`Enter a complete BAML function between 1 and ${MAX_PROGRAM} characters.`);
  return value;
}
export function overrideKey(context: Context, scope: Scope, functionName: AssetFunction) {
  if (scope === 'user' && !context.userId) throw new DemoError('Choose a user for a user override.');
  return `${functionName}/${context.organizationId}${scope === 'user' ? `-${context.userId}` : ''}.llm-override`;
}
const storeDirectory = (store: Store) => join(process.env.DEMO_DATA_DIR || join(process.cwd(), '.demo-data'), store);
function missing(error: unknown) { return (error as NodeJS.ErrnoException)?.code === 'ENOENT'; }
export const db = {
  async get(store: Store, key: string): Promise<string | null> {
    try { return await readFile(join(storeDirectory(store), key), 'utf8'); }
    catch (error) { if (missing(error)) return null; throw error; }
  },
  async set(store: Store, key: string, value: string) {
    const destination = join(storeDirectory(store), key);
    const directory = dirname(destination);
    await mkdir(directory, { recursive: true });
    const temporary = join(directory, `.${randomUUID()}.tmp`);
    try {
      await writeFile(temporary, value, { mode: 0o600 });
      await rename(temporary, destination);
    } finally { await unlink(temporary).catch((error) => { if (!missing(error)) throw error; }); }
  },
  async delete(store: Store, key: string) {
    try { await unlink(join(storeDirectory(store), key)); }
    catch (error) { if (!missing(error)) throw error; }
  },
};
export async function readOverrides(store: Store, context: Context, functionName: AssetFunction) {
  const organizationKey = overrideKey(context, 'organization', functionName);
  const userKey = context.userId ? overrideKey(context, 'user', functionName) : null;
  const [organization, user] = await Promise.all([db.get(store, organizationKey), userKey ? db.get(store, userKey) : null]);
  return { organizationKey, userKey, organization, user };
}
export async function resolveOverride(store: Store, context: Context, functionName: AssetFunction) {
  const entries = await readOverrides(store, context, functionName);
  const trace: string[] = [];
  if (entries.userKey) trace.push(`User override: ${entries.user !== null ? 'found · wins' : 'not set'}`);
  trace.push(`Organization override: ${entries.organization !== null ? (entries.user !== null ? 'found · shadowed' : 'found · wins') : 'not set'}`);
  const value = entries.user ?? entries.organization;
  const key = entries.user !== null ? entries.userKey : entries.organization !== null ? entries.organizationKey : null;
  const fallback = DEFAULT_MODELS[functionName];
  if (value === null) trace.push(`No override → ${fallback.provider}/${fallback.model}`);
  return { value, source: key ?? 'Application default', trace };
}
