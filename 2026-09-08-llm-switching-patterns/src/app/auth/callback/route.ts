import { handleAuth } from '@workos-inc/authkit-nextjs';
import { NextResponse, type NextRequest } from 'next/server';
import { authConfiguration } from '@/lib/server/auth-config';

export async function GET(request: NextRequest) {
  const config = authConfiguration();
  if (!config.configured) return NextResponse.redirect(new URL('/login?error=configuration', request.url));
  return handleAuth({
    baseURL: config.origin,
    returnPathname: '/login',
    onError: () => NextResponse.redirect(new URL('/login?error=callback', config.origin)),
  })(request);
}
