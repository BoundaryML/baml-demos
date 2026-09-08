'use server';
import { signOut } from '@workos-inc/authkit-nextjs';
import { redirect } from 'next/navigation';
import { authConfiguration } from '@/lib/server/auth-config';

export async function switchAccount() {
  const config = authConfiguration();
  if (!config.configured) redirect('/login');
  // End the WorkOS session as well as the local session before starting again.
  await signOut({ returnTo: `${config.origin}/auth/sign-in` });
}

export async function logOut() {
  const config = authConfiguration();
  if (!config.configured) redirect('/login');
  await signOut({ returnTo: `${config.origin}/login` });
}
