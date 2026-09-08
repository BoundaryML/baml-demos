# Launch studio: five ways to switch LLMs

There are five demos in this app for techniques to switch LLMs:

1. Simple plumbing: use either shorthand clients like `client: "openai/gpt-5.2"` or reference statically defined clients e.g. `client: root.shared.DefaultLogo`
2. Use environment variables: define client constructors that read from envvars, then switch LLM by changing the envvar and restarting the app
3. Switch on caller context: in the `GenerateLogo` LLM function, use `client: ChooseLlm(org_id, user_id, "GenerateLogo")`, so that in `ChooseLlm`, you can define your own dynamic switching logic based on org ID, user ID, and function name. Choose model based on org and user characteristics, e.g. switch on free vs premium users, or free org plans vs $20/mo org plans or $200/mo org plans.
4. Code mode: instead of defining your own switching heuristics, ask an LLM to generate a `ChooseLlm()` implementation on the fly (or provide your own), and then run it yourself.
5. Feature flags: use feature flags to control LLM selection, which allows you to change LLM selection by simply updating a feature flag, instead of by having to do another application release.

## Summary

A pnpm + Next.js app for preparing marketing assets for a product launch. Each demo owns a namespaced `GenerateAssets` entry point: `GenerateLogo` and `GenerateAnnouncementCopy` run in parallel, producing an actual image and structured announcement copy. The UI previews each selected client and lets you generate, view, and download both assets. No app login is required; the WorkOS organization/user picker supplies a simulated request identity.

```sh
cd 2026-09-08-llm-switching-patterns
baml toolchain use nightly
pnpm install --frozen-lockfile
cp .env.example .env.local
cp .env.llm_settings.example .env.llm_settings
# Fill in .env.local as described below, then:
pnpm dev
```

Open [http://localhost:3000/demo1](http://localhost:3000/demo1). Each demo has its own URL: `/demo1`, `/demo2`, `/demo3`, `/demo4`, and `/demo5`. The demo navigation updates the URL, and `/` redirects to `/demo1`. Set `OPENAI_API_KEY` and `GEMINI_API_KEY` for generation, plus `WORKOS_API_KEY` and `WORKOS_CLIENT_ID` for the identity and feature flag demos. Preserve existing credentials when updating environment settings. Each **Generate launch assets** click makes two real model calls. Selecting a demo or previewing a model route does not generate assets; the supplied BAML override functions only construct clients.

## Environment files

Use Node.js 22.9 or newer, pnpm 11.1.3, and the BAML CLI. The project pins its BAML toolchain and bridge package together; `baml toolchain use nightly` selects the nightly channel while `baml.toml` records the version used by this demo. The committed pnpm lockfile reproduces the tested dependencies. The workspace configuration includes this single app and exempts only the pinned BAML nightly packages from pnpm's release-age delay.

Copy the two example files once on a fresh checkout. The real `.env.local` and `.env.llm_settings` files are ignored by version control; never commit credentials. Do not overwrite existing env files when updating the app.

Put credentials and optional sign-in configuration in `.env.local`:


| Variable                          | Value / purpose                                                                                                                                |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `OPENAI_API_KEY`                  | Your OpenAI API key. Required for the default announcement model and any selected OpenAI model.                                                |
| `GEMINI_API_KEY`                  | Your Gemini API key. Required for the default logo model and any selected Google model.                                                        |
| `WORKOS_API_KEY`                  | A WorkOS API key for the environment containing your demo organizations, users, and feature flags; used by demos 3–5 and optional sign-in.     |
| `WORKOS_CLIENT_ID`                | The WorkOS client ID from the same environment.                                                                                                |
| `WORKOS_COOKIE_PASSWORD`          | A random secret of at least 32 characters for optional sign-in session encryption. Generate one with `openssl rand -hex 32` and paste it here. |
| `NEXT_PUBLIC_WORKOS_REDIRECT_URI` | `http://localhost:3000/auth/callback` locally; register this exact URI in WorkOS. This URL is public, not a secret.                            |


Demos 1 and 2 can generate assets with just the provider keys. All five demos are public; WorkOS API credentials let the server load routing identities for demos 3–5 without requiring an app login. `WORKOS_COOKIE_PASSWORD` and the callback URI are needed only for `/login`.

Put model selections and flag names in `.env.llm_settings`:

```dotenv
LOGO_LLM_PROVIDER=google
LOGO_LLM_MODEL=gemini-3.1-flash-image
COPY_LLM_PROVIDER=openai
COPY_LLM_MODEL=gpt-5.2
WORKOS_LOGO_FLAG=launch-logo-upgrade
WORKOS_COPY_FLAG=launch-copy-upgrade
```

The provider/model pairs control demo 2. Valid providers are `openai` and `google`; choose an image-capable model for the logo and a text model for announcement copy. The flag names configure demo 5; create matching boolean flags in the same WorkOS environment. Optional `DEMO_DATA_DIR` changes the filesystem database location from `.demo-data` relative to the app directory. Run `pnpm workos:setup` to prepare demo users and an organization, then `pnpm demo:seed` to create sample override files; both commands preserve existing records and overrides.

`pnpm dev`, `pnpm build`, `pnpm start`, `pnpm workos:setup`, and `pnpm demo:seed` load both `.env.local` and `.env.llm_settings` from the project root. Keep credentials in `.env.local` and model-selection settings in `.env.llm_settings`. Both files are optional and ignored by version control. For duplicate keys, the order is **shell / deployment environment → .env.llm_settings → .env.local**. Restart the server after changing either file; the loaded values are inherited by the native BAML runtime as well as Next.js. These commands require Node.js 22.9 or newer.

## Optional WorkOS sign-in

Open [http://localhost:3000/login](http://localhost:3000/login), or use **Log in / switch account** in the app header. Sign in through WorkOS AuthKit, then return to `/login` to see the active name, email, user ID, and organization ID when present. **Switch account** ends the current WorkOS session, clears the app session, and starts a fresh sign-in for another account. **Sign out** returns to the guest login page. All five demos remain public; their organization/user picker continues to supply the simulated routing context independently of your sign-in.

Set `WORKOS_COOKIE_PASSWORD` to a random secret of at least 32 characters and `NEXT_PUBLIC_WORKOS_REDIRECT_URI=http://localhost:3000/auth/callback`, in addition to the WorkOS API key and client ID. Keep the password stable between server restarts so existing sessions remain readable.

Configure these URLs in your WorkOS application's **Redirects** tab:


| Setting                                       | URL                                   |
| --------------------------------------------- | ------------------------------------- |
| Allowed callback / redirect URI               | `http://localhost:3000/auth/callback` |
| Initiate login URL                            | `http://localhost:3000/auth/sign-in`  |
| Allowed sign-out URI                          | `http://localhost:3000/login`         |
| Additional allowed sign-out URI for switching | `http://localhost:3000/auth/sign-in`  |


Register all four URLs in your own WorkOS environment before testing sign-in, logout, and account switching. On another deployment, replace the origin in all four settings and use HTTPS. Auth routes redirect to the configured hostname so the sign-in request and callback share the PKCE cookie.

The integration uses `@workos-inc/authkit-nextjs`: `src/proxy.ts` maintains optional sessions for `/login` and `/auth/*`; `/auth/sign-in` creates a PKCE flow with `maxAge: 0`; `/auth/callback` validates state, exchanges the code, and saves an encrypted HTTP-only session. Account switching and sign-out are POST server actions. Tokens stay on the server. The `/login` page uses `AuthKitProvider` for session handling in the browser. Invalid or canceled callbacks return a retry message without exposing credentials.

References: [WorkOS Next.js integration](https://workos.com/docs/authkit/nextjs), [WorkOS sessions and sign-out URLs](https://workos.com/docs/authkit/sessions).

## BAML source layout

BAML's `ns_` directory convention defines namespaces. Each demo owns its workflow, both LLM functions, and its selection logic. No demo calls another demo's workflow.


| Entry point            | Source                                                     |
| ---------------------- | ---------------------------------------------------------- |
| `demo1.GenerateAssets` | [baml_src/ns_demo1/main.baml](baml_src/ns_demo1/main.baml) |
| `demo2.GenerateAssets` | [baml_src/ns_demo2/main.baml](baml_src/ns_demo2/main.baml) |
| `demo3.GenerateAssets` | [baml_src/ns_demo3/main.baml](baml_src/ns_demo3/main.baml) |
| `demo4.GenerateAssets` | [baml_src/ns_demo4/main.baml](baml_src/ns_demo4/main.baml) |
| `demo5.GenerateAssets` | [baml_src/ns_demo5/main.baml](baml_src/ns_demo5/main.baml) |


Common data contracts live in [baml_src/types.baml](baml_src/types.baml). `ns_shared` contains client construction, asset serialization, and filesystem utilities. The generated TypeScript SDK exports `demo1` through `demo5`; the server dispatches to the selected namespace. Demo 1's `GenerateAssetsWithModels` bridges UI provider/model strings to `demo1.GenerateAssets`'s client parameters. Stored demo 4 override files still declare a standalone `ChooseLlm()` function: reflection compiles them as separate packages.

## Models

The default logo model is `google/gemini-3.1-flash-image`; the default copy model is `openai/gpt-5.2`. The copy selector also offers `gpt-5.3-chat-latest`, `gpt-5.6-terra`, `gpt-5.6-luna`, and Gemini text models. Terra and Luna are available under those exact 5.6 IDs. Image generation has its own models: Gemini Flash Image / Pro Image and OpenAI `gpt-image-2` / `gpt-image-1.5`. A text-only model cannot be used for `GenerateLogo`.

## The five demos


| Demo                     | How the client is selected                                                | When a change takes effect                        |
| ------------------------ | ------------------------------------------------------------------------- | ------------------------------------------------- |
| 1. Pass the clients      | Default client parameters or explicit `client=` arguments                 | Next workflow invocation                          |
| 2. Environment variables | A separate provider/model pair for each function                          | After reloading the server environment            |
| 3. Choose by context     | `ChooseLlm` reads a local database using organization, user, and function | Next filesystem read                              |
| 4. Store a BAML function | Reflection loads and invokes a complete stored `ChooseLlm()` function     | Next function load                                |
| 5. Flip it in WorkOS     | One live feature flag per asset selects baseline or candidate             | After the runtime sync, normally within 5 seconds |


## Demo 1: two parallel calls

```baml
function GenerateAssets(
    brief: root.LaunchBrief,
    logo_client: ai.Client = root.shared.DefaultLogo,
    copy_client: ai.Client = root.shared.DefaultCopy,
) -> root.LaunchAssets {
    let logo = spawn { GenerateLogo(brief, client = logo_client) };
    let copy = spawn { GenerateAnnouncementCopy(brief, client = copy_client) };
    root.shared.AssembleAssets(await logo, await copy)
}
```

`demo1.GenerateAssets(brief)` uses defaults. Passing either client overrides that function for one invocation. `demo1.GenerateAssetsWithModels` is the UI bridge: it accepts provider/model pairs, constructs the clients, and invokes this workflow. The logo is an image; the copy contains `headline`, `tagline`, `body`, and `call_to_action`.

## Demo 2: environment variables

```dotenv
LOGO_LLM_PROVIDER=google
LOGO_LLM_MODEL=gemini-3.1-flash-image
COPY_LLM_PROVIDER=openai
COPY_LLM_MODEL=gpt-5.2
```

`demo2.EnvironmentModel` reads these variables inside BAML. Missing values use the defaults above. `demo2.GenerateAssets` starts its own two LLM functions in parallel; each uses `EnvironmentClient` to construct its client. After editing `.env.llm_settings` (or `.env.local`), restart the server and click **Read environment again**. Production processes must restart or redeploy with the changed environment. Old `LLM_PROVIDER` / `LLM_MODEL` variables from the summary demo are no longer used.

## Demo 3: organization × user × function

`demo3.GenerateAssets` accepts a `root.demo3.UserContext` containing only `org` and `user`, and passes that same context to both LLM functions in parallel. Each LLM function constructs its own lookup key internally, so callers never supply `function_name`.

```baml
class UserContext {
    org: string,
    user: string,
}

// Inside demo3.GenerateLogo(brief, user_context):
client: ChooseLlm(llm_choice_key = root.LlmChoiceKey {
    org: user_context.org,
    user: user_context.user,
    function_name: "GenerateLogo",
})
```

`demo3.GenerateAnnouncementCopy` uses the same context with its own fixed `"GenerateAnnouncementCopy"` name. The workflow call is `demo3.GenerateAssets(brief, user_context)`.

`demo3.ChooseLlm` reads the filesystem database inside BAML. Resolution order is **user → organization → application default**, independently for each function. The UI writes JSON such as `{"provider":"openai","model":"gpt-5.6-luna"}`. Deleting a user override reveals the organization choice; deleting both restores the function's default. An invalid present file returns an error.

```text
.demo-data/
  models/
    GenerateLogo/
      {orgid}.llm-override
      {orgid}-{userid}.llm-override
    GenerateAnnouncementCopy/
      {orgid}.llm-override
      {orgid}-{userid}.llm-override
  programs/
    GenerateLogo/
      {orgid}.llm-override
      {orgid}-{userid}.llm-override
    GenerateAnnouncementCopy/
      {orgid}.llm-override
      {orgid}-{userid}.llm-override
```

`src/lib/server/database.ts` models writes and route previews; BAML's `shared.ReadOverride` performs the lookup used during generation. `DEMO_DATA_DIR` overrides the root directory. Writes are atomic. Function and identity validation prevents path traversal. Model and program stores are independent. Existing flat files from the earlier summary demo are preserved but are no longer read.

## Demo 4: store the entire BAML function

Each program override file contains a **complete BAML function**, including its name, signature, and body. The contract is `ChooseLlm() -> ai.Client`, with no required arguments. For example, an announcement override file contains:

```baml
function ChooseLlm() -> ai.Client {
    let primary = openai.ResponsesClient.new(
        model = "gpt-5.6-luna",
        api_key = env.OPENAI_API_KEY,
        request_timeout_ms = 120000,
    );
    ai.clients.Retry.new(inner = primary, max_attempts = 2)
}
```

A logo override can contain:

```baml
function ChooseLlm() -> ai.Client {
    google.GeminiClient.new(
        model = "gemini-3.1-flash-image",
        api_key = env.GEMINI_API_KEY,
        response_modalities = ["IMAGE"],
    )
}
```

The loader compiles the stored source with `reflect.Package.compile`, looks up `ChooseLlm` with the typed contract `() -> ai.Client throws unknown`, and invokes it to obtain the client. Bare constructor expressions, missing functions, required arguments, and wrong return types are rejected. Validation runs before saving, preserving the previous file after invalid edits. `demo4.GenerateAssets` starts its own LLM functions in parallel. Each function calls `demo4.ChooseLlm`, which reads and compiles its override file to obtain the client. The editor includes complete simple, retry, and fallback examples for each asset.

This local configuration editor executes trusted server-side BAML; reflection verifies the return contract, not a security sandbox. In production, restrict editing to trusted administrators and derive identity from authenticated requests. The displayed `Client.id()` reports the configured client; for fallback clients it reports the first member, not telemetry proving which member ultimately answered. Route previews and generation are separate reads, so edits between them apply on the next read.

## WorkOS identities and sample overrides

```sh
pnpm workos:setup
pnpm demo:seed
```

Setup reuses the first organization, or creates a demo organization, and ensures Ada and Lin have memberships. It sends no invitations or emails. Seeding creates only missing files: organization copy uses Terra, Ada copy uses Luna, and Lin inherits the organization. Logo overrides use Gemini Flash Image. Program files contain full functions and demonstrate the same hierarchy with retry wrappers. Existing files and credentials are preserved.

## Demo 5: flip WorkOS flags live

1. Open [WorkOS Feature Flags](https://dashboard.workos.com) in the environment matching `WORKOS_API_KEY`.
2. Create flags with slugs `launch-logo-upgrade` and `launch-copy-upgrade`.
3. Target the desired organization or user.
4. In the app, select **Flip it in WorkOS** and the matching identity.
5. Toggle either flag in the dashboard, watch its route update, and generate the assets again.


| Flag                  | Off: baseline                   | On: candidate          |
| --------------------- | ------------------------------- | ---------------------- |
| `launch-logo-upgrade` | `google/gemini-3.1-flash-image` | `openai/gpt-image-2`   |
| `launch-copy-upgrade` | `openai/gpt-5.2`                | `openai/gpt-5.6-terra` |


The server runtime syncs every 5 seconds; the UI polls the evaluated route every 2.5 seconds. Each generation evaluates both flags again and passes the two model choices to `demo5.GenerateAssets`, which runs its own logo and announcement functions in parallel. No application code change is needed to flip between these configured routes. The flags are boolean; adding a third route requires extending the mapping. Customize the slugs in the UI or with `WORKOS_LOGO_FLAG` / `WORKOS_COPY_FLAG`.

WorkOS targeting is organization **OR** user, unlike the filesystem precedence rule. Missing flags visibly select the baseline. Initial sync failures report an error; subsequent failures retain the last known state with a stale indicator. An already-running generation keeps the clients selected when it started. The app does not create flags automatically; create them in the WorkOS dashboard.

References: [WorkOS Node runtime client](https://workos.com/docs/feature-flags/node-runtime-client), [WorkOS flag API](https://workos.com/docs/reference/feature-flags/flag).

## Development and verification

```sh
pnpm baml:check
pnpm lint
pnpm typecheck
pnpm exec playwright install chromium
pnpm test:e2e
pnpm build
```

The tests use a separate server on port 3100, an isolated filesystem database under `/tmp`, blank LLM provider keys, test WorkOS credentials, and mocked browser identities. A local WorkOS transport on port 3199 issues signed test tokens and checks PKCE; it exercises the real AuthKit callback, encrypted session persistence, account switching, sign-out, callback rejection, and mobile login UI. They verify real BAML environment reads, complete-function reflection, per-function/user/org precedence, input validation, downloadable output and loading/error UI, mobile layout, and WorkOS runtime polling using a mocked transport. They do not make paid calls or flip real WorkOS flags. Real generation can be checked separately through the local app.

BAML and `@boundaryml/baml-bridge` are pinned to `0.18.1-nightly.20260906.a`; upgrade them together. `pnpm dev` and `pnpm build` regenerate `src/baml_sdk`. Run `pnpm baml:generate` after BAML edits during development. Next.js uses Webpack with a `.js` → `.ts` extension alias for generated SDK imports. The nightly generator currently emits type-only `_typemap.ts` warnings; native runtime execution remains supported.

Key files: `baml_src/ns_demo1` through `baml_src/ns_demo5` contain the individual demos; `baml_src/ns_shared` contains shared utilities; `src/lib/server/runner.ts` coordinates API execution; `src/lib/server/workos.ts` owns identity reads and flag synchronization; `src/components/launch-studio.tsx` implements the UI; `src/app/[demo]/page.tsx` selects the demo from the URL. Credentials stay on the server.