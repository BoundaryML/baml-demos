import { authkitProxy } from '@workos-inc/authkit-nextjs';
import { NextResponse, type NextRequest, type NextFetchEvent } from 'next/server';
import { authConfiguration } from '@/lib/server/auth-config';

const sessionProxy = authkitProxy();
export default function proxy(request: NextRequest, event: NextFetchEvent) {
  const config = authConfiguration();
  if (!config.configured) return NextResponse.next();
  return sessionProxy(request, event);
}

// AuthKit maintains sessions here without requiring visitors to sign in.
export const config = { matcher: ['/login/:path*', '/auth/:path*'] };
