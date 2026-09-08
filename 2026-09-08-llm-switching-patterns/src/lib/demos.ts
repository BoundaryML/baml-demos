export const assetFunctions = ['GenerateLogo', 'GenerateAnnouncementCopy'] as const;
export type AssetFunction = typeof assetFunctions[number];
export const providers = ['openai', 'google'] as const;
export type Provider = typeof providers[number];
export type ModelConfig = { provider: Provider; model: string };
export type ModelChoices = Record<AssetFunction, ModelConfig>;
export const DEFAULT_MODELS: ModelChoices = {
  GenerateLogo: { provider: 'google', model: 'gemini-3.1-flash-image' },
  GenerateAnnouncementCopy: { provider: 'openai', model: 'gpt-5.2' },
};
export const CANDIDATE_MODELS: ModelChoices = {
  GenerateLogo: { provider: 'openai', model: 'gpt-image-2' },
  GenerateAnnouncementCopy: { provider: 'openai', model: 'gpt-5.6-terra' },
};
export const modelPresets: Record<AssetFunction, Record<Provider, string[]>> = {
  GenerateLogo: { google: ['gemini-3.1-flash-image', 'gemini-3-pro-image'], openai: ['gpt-image-2', 'gpt-image-1.5'] },
  GenerateAnnouncementCopy: { openai: ['gpt-5.2', 'gpt-5.3-chat-latest', 'gpt-5.6-terra', 'gpt-5.6-luna'], google: ['gemini-3.8-flash', 'gemini-3.1-pro-preview', 'gemini-3.1-flash-lite'] },
};
export const DEFAULT_FLAGS: Record<AssetFunction, string> = { GenerateLogo: 'launch-logo-upgrade', GenerateAnnouncementCopy: 'launch-copy-upgrade' };
export const demos = [
  { id: 'direct', namespace: 'demo1', number: '01', title: 'Pass the clients', subtitle: 'Two calls. One workflow.', description: 'Pick an image model for the logo and a text model for the announcement. GenerateAssets starts both LLM functions in parallel.', changes: 'The next launch brief', code: "// baml_src/ns_demo1/main.baml\nfunction GenerateAssets(\n    brief: root.LaunchBrief,\n    logo_client: ai.Client = root.shared.DefaultLogo,\n    copy_client: ai.Client = root.shared.DefaultCopy,\n) -> root.LaunchAssets {\n    //# Generate the visual and written assets in parallel\n    let logo = spawn { GenerateLogo(brief, client = logo_client) };\n    let copy = spawn { GenerateAnnouncementCopy(brief, client = copy_client) };\n    root.shared.AssembleAssets(await logo, await copy)\n}" },
  { id: 'environment', namespace: 'demo2', number: '02', title: 'Environment variables', subtitle: 'Deployment defaults', description: 'The same parallel workflow, with one provider/model pair per function read from the server environment.', changes: 'Environment reload / restart', code: '// baml_src/ns_demo2/main.baml\nfunction GenerateAssets(brief: root.LaunchBrief) -> root.LaunchAssets {\n  let logo = spawn { GenerateLogo(brief) };\n  let copy = spawn { GenerateAnnouncementCopy(brief) };\n  root.shared.AssembleAssets(await logo, await copy)\n}\n// Each LLM uses EnvironmentClient(function_name).' },
  { id: 'overrides', namespace: 'demo3', number: '03', title: 'Choose by context', subtitle: 'Org × user × function', description: 'Each LLM function receives UserContext and attaches its own function name before calling ChooseLlm. A logo override affects the logo; announcement copy has its own lookup.', changes: 'The next database read', code: '// baml_src/ns_demo3/main.baml\nclass UserContext { org: string, user: string }\n\nfunction GenerateLogo(\n  brief: root.LaunchBrief,\n  user_context: root.demo3.UserContext,\n) -> image {\n  client: ChooseLlm(llm_choice_key = root.LlmChoiceKey {\n    org: user_context.org,\n    user: user_context.user,\n    function_name: "GenerateLogo",\n  })\n  // ... logo prompt ...\n}' },
  { id: 'programs', namespace: 'demo4', number: '04', title: 'Store a BAML function', subtitle: 'Executable configuration', description: 'Store an entire ChooseLlm() function in the override file. Reflection compiles it, verifies its function contract, and invokes it to obtain the client.', changes: 'The next function load', code: '// baml_src/ns_demo4/main.baml\nlet package = reflect.Package.compile({\n  "override.baml": stored_source,\n});\nlet choose = package.get_function<\n  () -> ai.Client throws unknown\n>("ChooseLlm") ?? throw baml.errors.InvalidArgument { message: "Expected ChooseLlm() → ai.Client" };\nlet client = choose();' },
  { id: 'flags', namespace: 'demo5', number: '05', title: 'Flip it in WorkOS', subtitle: 'Live rollout per asset', description: 'Use a separate WorkOS feature flag for each asset function. Roll out a new logo model or copy model independently, while GenerateAssets stays unchanged.', changes: 'Within the 5-second sync interval', code: '// WorkOS evaluates flags before calling demo5.GenerateAssets.\nlogo = flags.isEnabled("launch-logo-upgrade", context)\n  ? candidateLogo : baselineLogo;\ncopy = flags.isEnabled("launch-copy-upgrade", context)\n  ? candidateCopy : baselineCopy;\ndemo5.GenerateAssets(brief, logo, copy);' },
] as const;
export type DemoId = typeof demos[number]['id'];
export type LaunchBrief = { product_name: string; description: string; audience: string; tone: string };
export type Context = { organizationId: string; userId?: string };
export type LlmChoiceKey = { org: string; user: string; function_name: AssetFunction };
export type DemoRequest = { demo: DemoId; brief?: LaunchBrief; choices?: ModelChoices; organizationId?: string; userId?: string; flags?: Record<AssetFunction, string> };
export type FlagState = { slug: string; exists: boolean; enabled: boolean; targetingEnabled: boolean; lastSyncedAt: string | null; stale: boolean; error?: string; pollingIntervalMs: number };
export type FunctionResolution = { functionName: AssetFunction; clientId: string; provider?: string; model?: string; source: string; trace: string[]; key?: LlmChoiceKey; program?: string; flag?: FlagState; validated?: boolean };
export type Resolution = { demo: DemoId; functions: Record<AssetFunction, FunctionResolution> };
export type AnnouncementCopy = { headline: string; tagline: string; body: string; call_to_action: string };
export type LaunchAssets = { logo: { base64: string; mime_type: string }; announcement: AnnouncementCopy };
export type RunResult = { resolution: Resolution; output: LaunchAssets; durationMs: number; productName: string };
export type Identity = { id: string; name: string };
export type ContextData = { organizations: Identity[]; users: Identity[]; error?: string };
export const SAMPLE_BRIEF: LaunchBrief = {
  product_name: 'Orbit',
  description: 'A collaborative product-launch workspace that brings the timeline, decisions, and launch checklist together. Teams can see what is ready, what is blocked, and who owns the next step.',
  audience: 'Small product and marketing teams launching their next big idea.',
  tone: 'Confident, warm, and clear. Optimistic without hype.',
};
export const MAX_INPUT = 12000;
export const MAX_PROGRAM = 16000;
export function programExamples(functionName: AssetFunction) {
  const constructor = functionName === 'GenerateLogo'
    ? 'google.GeminiClient.new(\n        model = "gemini-3.1-flash-image",\n        api_key = env.GEMINI_API_KEY,\n        response_modalities = ["IMAGE"],\n    )'
    : 'openai.ResponsesClient.new(\n        model = "gpt-5.6-luna",\n        api_key = env.OPENAI_API_KEY,\n        request_timeout_ms = 120000,\n    )';
  const alternate = functionName === 'GenerateLogo'
    ? 'openai.ImageClient.new(model = "gpt-image-2", api_key = env.OPENAI_API_KEY, quality = "low", size = "1024x1024")'
    : 'openai.ResponsesClient.new(model = "gpt-5.2", api_key = env.OPENAI_API_KEY, request_timeout_ms = 120000)';
  return {
    simple: `function ChooseLlm() -> ai.Client {\n    ${constructor}\n}`,
    retry: `function ChooseLlm() -> ai.Client {\n    let primary = ${constructor};\n    ai.clients.Retry.new(inner = primary, max_attempts = 2)\n}`,
    fallback: `function ChooseLlm() -> ai.Client {\n    let primary = ${constructor};\n    let backup = ${alternate};\n    ai.clients.Fallback { members: [primary, backup] }\n}`,
  };
}
