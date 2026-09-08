import 'server-only';
import { WorkOS, type FeatureFlagsRuntimeClient } from '@workos-inc/node';
import type { Context, ContextData, FlagState } from '@/lib/demos';
import { DemoError } from './errors';

// Survives Next.js hot reload: one polling client for the server process.
const shared = globalThis as typeof globalThis & { llmWorkos?: WorkOS; llmFlags?: FeatureFlagsRuntimeClient; llmFlagError?: string };
export function getWorkOS() {
  if (!process.env.WORKOS_API_KEY) throw new DemoError('Set WORKOS_API_KEY in .env.local to load WorkOS identities and flags.', 503);
  return shared.llmWorkos ??= new WorkOS(process.env.WORKOS_API_KEY, { clientId: process.env.WORKOS_CLIENT_ID, apiHostname: process.env.WORKOS_API_HOSTNAME, port: process.env.WORKOS_API_PORT ? Number(process.env.WORKOS_API_PORT) : undefined, https: process.env.WORKOS_API_HTTPS !== 'false' });
}
export async function listContext(organizationId?: string): Promise<ContextData> {
  const workos = getWorkOS();
  const organizations = await (await workos.organizations.listOrganizations({ limit: 100 })).autoPagination();
  const selected = organizationId || organizations[0]?.id;
  const users = selected ? await (await workos.userManagement.listUsers({ organizationId: selected, limit: 100 })).autoPagination() : [];
  return {
    organizations: organizations.map((org) => ({ id: org.id, name: org.name })),
    users: users.map((user) => ({ id: user.id, name: [user.firstName, user.lastName].filter(Boolean).join(' ') || user.id })),
  };
}
export function getFlags() {
  if (!shared.llmFlags) {
    shared.llmFlags = getWorkOS().featureFlags.createRuntimeClient({ pollingIntervalMs: 5000, requestTimeoutMs: 5000 });
    shared.llmFlags.on('error', () => { shared.llmFlagError = 'WorkOS sync failed; the last known flag state is being used.'; });
    shared.llmFlags.on('failed', () => { shared.llmFlagError = 'WorkOS rejected the API key. Fix it and restart the server.'; });
    const close = () => shared.llmFlags?.close();
    process.once('SIGTERM', close);
    process.once('SIGINT', close);
  }
  return shared.llmFlags;
}
export async function evaluateFlag(slug: string, context: Context): Promise<FlagState> {
  const client = getFlags();
  try { await client.waitUntilReady({ timeoutMs: 5500 }); }
  catch { throw new DemoError('WorkOS feature flags have not synced. Check WORKOS_API_KEY and the connection, then retry.', 503); }
  const stats = client.getStats();
  const entry = client.getFlag(slug);
  const stale = stats.cacheAge === null || stats.cacheAge > 15000;
  return {
    slug, exists: entry !== undefined,
    enabled: client.isEnabled(slug, context, false),
    targetingEnabled: entry?.enabled ?? false,
    lastSyncedAt: stats.lastSuccessfulPollAt?.toISOString() ?? null,
    stale,
    ...(stale && shared.llmFlagError ? { error: shared.llmFlagError } : {}),
    pollingIntervalMs: 5000,
  };
}
