import { getSignInUrl } from '@workos-inc/authkit-nextjs';
import { NextResponse } from 'next/server';
import { authConfiguration } from '@/lib/server/auth-config';

export async function GET(request: Request) {
  const config = authConfiguration();
  if (!config.configured) return NextResponse.redirect(new URL('/login?error=configuration', request.url));
  if (request.headers.get('host') !== new URL(config.origin!).host) return NextResponse.redirect(new URL('/auth/sign-in', config.origin));
  const url = await getSignInUrl({ redirectUri: config.redirectUri, returnTo: '/login', maxAge: 0 });
  return NextResponse.redirect(url, { headers: { 'Cache-Control': 'no-store' } });
}
