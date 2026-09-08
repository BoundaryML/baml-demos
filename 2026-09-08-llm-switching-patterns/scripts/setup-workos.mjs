import './load-env.mjs';
import { WorkOS } from '@workos-inc/node';
if (!process.env.WORKOS_API_KEY) throw new Error('Set WORKOS_API_KEY in .env.local.');
const workos = new WorkOS(process.env.WORKOS_API_KEY);
const organizations = await workos.organizations.listOrganizations({ limit: 100 });
const organization = organizations.data[0] ?? await workos.organizations.createOrganization({ name: 'LLM switching demo' });
for (const name of ['Ada', 'Lin']) {
  const email = `llm-switching-demo-${name.toLowerCase()}@example.com`;
  const existing = await workos.userManagement.listUsers({ email });
  const user = existing.data[0] ?? await workos.userManagement.createUser({ email, firstName: name, lastName: 'Demo', metadata: { demo: 'llm-switching-patterns' } });
  const memberships = await workos.userManagement.listOrganizationMemberships({ userId: user.id, organizationId: organization.id });
  if (!memberships.data.length) await workos.userManagement.createOrganizationMembership({ userId: user.id, organizationId: organization.id });
  console.log(`${name}: ${user.id} in ${organization.id}`);
}
console.log('Demo identities are ready. No invitations or emails were sent.');
