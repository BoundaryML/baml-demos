import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",
  fullyParallel: true,
  use: { baseURL: "http://127.0.0.1:3100", trace: "retain-on-failure" },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: [{ command: "node tests/fixtures/workos.mjs", url: "http://127.0.0.1:3199/health", reuseExistingServer: false }, {
    command: "pnpm dev --hostname 127.0.0.1 --port 3100",
    url: "http://127.0.0.1:3100",
    reuseExistingServer: false,
    env: {
      OPENAI_API_KEY: "", GEMINI_API_KEY: "", WORKOS_API_KEY: "test-key",
      WORKOS_CLIENT_ID: "client_authfixture",
      WORKOS_COOKIE_PASSWORD: "test-only-cookie-password-with-at-least-32-characters",
      NEXT_PUBLIC_WORKOS_REDIRECT_URI: "http://127.0.0.1:3100/auth/callback",
      WORKOS_API_HOSTNAME: "127.0.0.1", WORKOS_API_PORT: "3199", WORKOS_API_HTTPS: "false",
      LOGO_LLM_PROVIDER: "google", LOGO_LLM_MODEL: "gemini-3.1-flash-image",
      COPY_LLM_PROVIDER: "openai", COPY_LLM_MODEL: "gpt-5.6-luna",
      DEMO_DATA_DIR: "/tmp/llm-switching-patterns-e2e-data",
      NEXT_DIST_DIR: ".next-e2e",
    },
    timeout: 120000,
  }],
});
