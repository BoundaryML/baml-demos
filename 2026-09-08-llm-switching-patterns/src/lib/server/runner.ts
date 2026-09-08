import 'server-only';
import { demo1, demo2, demo3, demo4, demo5 } from '@/baml_sdk';
import { assetFunctions, demos, DEFAULT_MODELS, CANDIDATE_MODELS, DEFAULT_FLAGS, MAX_INPUT, type AssetFunction, type DemoRequest, type FunctionResolution, type LaunchBrief, type ModelChoices, type Resolution } from '@/lib/demos';
import { DemoError } from './errors';
import { choiceKey, resolveOverride, validateContext, validateModel, validateProgram } from './database';
import { evaluateFlag } from './workos';

export function parseRequest(body: Record<string, unknown>): DemoRequest {
  if (!demos.some((demo) => demo.id === body.demo)) throw new DemoError('Choose one of the five demos.');
  for (const key of ['organizationId', 'userId']) if (body[key] !== undefined && typeof body[key] !== 'string') throw new DemoError(`${key} must be a string.`);
  if (body.choices !== undefined && (!body.choices || typeof body.choices !== 'object' || Array.isArray(body.choices))) throw new DemoError('Provide a model choice for each function.');
  if (body.flags !== undefined && (!body.flags || typeof body.flags !== 'object' || Array.isArray(body.flags))) throw new DemoError('Provide a flag slug for each function.');
  return body as DemoRequest;
}
export function validateBrief(brief: unknown): LaunchBrief {
  if (!brief || typeof brief !== 'object') throw new DemoError('Enter a product launch brief.');
  const result = {} as LaunchBrief;
  const limits = { product_name: 100, description: MAX_INPUT, audience: 1000, tone: 500 };
  for (const field of Object.keys(limits) as (keyof LaunchBrief)[]) {
    const value = (brief as Record<string, unknown>)[field];
    if (typeof value !== 'string' || !value.trim() || value.length > limits[field]) throw new DemoError(`Enter ${field.replaceAll('_', ' ')} (1–${limits[field]} characters).`);
    result[field] = value.trim();
  }
  return result;
}
export async function inspectProgram(source: string, functionName: AssetFunction) {
  let clientId: string;
  try { clientId = await demo4.InspectProgram_async(validateProgram(source)); }
  catch { throw new DemoError('Reflection rejected this program. Store a complete function ChooseLlm() -> ai.Client { ... }, with no required arguments. A bare expression, missing function, or wrong return type is not accepted. The saved file is preserved.', 422); }
  const slash = clientId.indexOf('/');
  // Constructors and the provided reliability wrappers expose provider/model IDs.
  // Validate output modality as well as the reflected ai.Client contract.
  if (slash > 0) validateModel({ provider: clientId.slice(0, slash), model: clientId.slice(slash + 1) }, functionName);
  return clientId;
}
function modelResolution(functionName: AssetFunction, config: unknown, source: string, trace: string[]): FunctionResolution {
  const validated = validateModel(config, functionName);
  return { functionName, ...validated, clientId: `${validated.provider}/${validated.model}`, source, trace };
}
async function resolveFunction(request: DemoRequest, functionName: AssetFunction): Promise<FunctionResolution> {
  if (request.demo === 'direct') return modelResolution(functionName, request.choices?.[functionName] ?? DEFAULT_MODELS[functionName], 'GenerateAssets · client argument', [`${functionName}(brief, client = selected)`, 'Both LLM calls start before either is awaited.']);
  if (request.demo === 'environment') {
    const config = await demo2.EnvironmentModel_async(functionName);
    const prefix = functionName === 'GenerateLogo' ? 'LOGO' : 'COPY';
    return modelResolution(functionName, config, 'Server environment', [`${prefix}_LLM_PROVIDER = ${config.provider}`, `${prefix}_LLM_MODEL = ${config.model}`]);
  }
  const context = validateContext(request.organizationId, request.userId);
  const key = choiceKey(context, functionName);
  if (request.demo === 'flags') {
    const variable = functionName === 'GenerateLogo' ? 'WORKOS_LOGO_FLAG' : 'WORKOS_COPY_FLAG';
    const slug = request.flags?.[functionName] ?? process.env[variable] ?? DEFAULT_FLAGS[functionName];
    if (typeof slug !== 'string' || !/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,99}$/.test(slug)) throw new DemoError('Enter a valid WorkOS feature flag slug.');
    const flag = await evaluateFlag(slug, context);
    const config = flag.enabled ? CANDIDATE_MODELS[functionName] : DEFAULT_MODELS[functionName];
    return { ...modelResolution(functionName, config, `WorkOS · ${slug} = ${flag.enabled}`, [flag.exists ? 'Organization OR user targeting, evaluated for this function’s flag.' : `Create “${slug}” in WorkOS. Baseline is used until then.`, flag.enabled ? 'On → candidate model' : 'Off → baseline model', flag.stale ? 'Sync stale; using last known state.' : 'Synced every 5 seconds.']), key, flag };
  }
  const store = request.demo === 'programs' ? 'programs' : 'models';
  const override = await resolveOverride(store, context, functionName);
  if (store === 'models') {
    let config;
    try { config = await demo3.DatabaseModel_async(key); }
    catch { throw new DemoError(`Invalid stored model for ${functionName}. Fix or clear its override file.`, 422); }
    return { ...modelResolution(functionName, config, override.source, ['ChooseLlm(llm_choice_key)', ...override.trace]), key };
  }
  if (override.value === null) return { ...modelResolution(functionName, DEFAULT_MODELS[functionName], override.source, override.trace), key };
  const clientId = await inspectProgram(override.value, functionName);
  return { functionName, clientId, source: override.source, trace: [...override.trace, 'Complete ChooseLlm function compiled.', '() → ai.Client contract verified; function invoked.'], key, program: override.value, validated: true };
}
export async function resolveDemo(request: DemoRequest): Promise<Resolution> {
  const decisions = await Promise.all(assetFunctions.map((name) => resolveFunction(request, name)));
  return { demo: request.demo, functions: { GenerateLogo: decisions[0], GenerateAnnouncementCopy: decisions[1] } };
}
export async function runDemo(request: DemoRequest) {
  const brief = validateBrief(request.brief);
  const start = performance.now();
  const resolution = await resolveDemo(request);
  for (const decision of Object.values(resolution.functions)) {
    const provider = decision.provider ?? decision.clientId.split('/')[0];
    const key = provider === 'google' ? 'GEMINI_API_KEY' : provider === 'openai' ? 'OPENAI_API_KEY' : undefined;
    if (key && !process.env[key]?.trim()) throw new DemoError(`Set ${key} in .env.local and restart the server.`, 503);
  }
  const choices = Object.fromEntries(assetFunctions.map((name) => [name, { provider: resolution.functions[name].provider!, model: resolution.functions[name].model! }])) as ModelChoices;
  const output = request.demo === 'environment' ? await demo2.GenerateAssets_async(brief)
    : request.demo === 'overrides' ? await demo3.GenerateAssets_async(brief, { org: request.organizationId!, user: request.userId ?? '' })
    : request.demo === 'programs' ? await demo4.GenerateAssets_async(brief, request.organizationId!, request.userId ?? '')
    : request.demo === 'flags' ? await demo5.GenerateAssets_async(brief, choices.GenerateLogo, choices.GenerateAnnouncementCopy)
    : await demo1.GenerateAssetsWithModels_async(brief, choices.GenerateLogo, choices.GenerateAnnouncementCopy);
  if (!['image/png', 'image/jpeg', 'image/webp'].includes(output.logo.mime_type) || !output.logo.base64) throw new DemoError('The logo model did not return a supported image. Try a different image model.', 502);
  return { resolution, output, durationMs: Math.round(performance.now() - start), productName: brief.product_name };
}
