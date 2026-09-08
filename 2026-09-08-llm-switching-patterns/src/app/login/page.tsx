import type { Metadata } from 'next';
import Link from 'next/link';
import { headers } from 'next/headers';
import { redirect } from 'next/navigation';
import { withAuth } from '@workos-inc/authkit-nextjs';
import { AuthKitProvider } from '@workos-inc/authkit-nextjs/components';
import { authConfiguration } from '@/lib/server/auth-config';
import { logOut, switchAccount } from './actions';
import styles from './page.module.css';

export const metadata: Metadata = { title: 'Your account · Launch studio' };
export default async function LoginPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const config = authConfiguration();
  const { error } = await searchParams;
  // Canonicalize in the page, since Next proxy normalizes loopback redirect URLs.
  if (config.configured && (await headers()).get('host') !== new URL(config.origin!).host) {
    redirect(`${config.origin}/login${error === 'callback' ? '?error=callback' : ''}`);
  }
  const auth = config.configured ? await withAuth() : { user: null };
  const { user } = auth;
  const name = user ? [user.firstName, user.lastName].filter(Boolean).join(' ') || user.email : '';
  // Only public identity/session metadata is passed into the client provider.
  const initialAuth = user ? { user, sessionId: auth.sessionId!, organizationId: auth.organizationId } : { user: null };
  const content = <div className={styles.shell}>
    <header className={styles.header}><Link href="/" className={styles.brand}><span>b.</span>Launch studio</Link><Link href="/">Back to demos ↗</Link></header>
    <main className={styles.main}>
      <p className={styles.eyebrow}>YOUR LAUNCH STUDIO ACCOUNT</p>
      <h1>{user ? 'Make yourself at home.' : 'Welcome to the studio.'}</h1>
      <p className={styles.intro}>{user ? 'Manage your sign-in or continue with a different account.' : 'Sign in with WorkOS to connect your account. All five demos are also available as a guest.'}</p>
      <section className={styles.card} aria-label="Your account">
        {error === 'callback' && <p className={styles.error} role="alert">We couldn’t complete sign-in. The link may have expired or been canceled. Start a new sign-in to try again.</p>}
        {!config.configured ? <><h2>Finish configuring WorkOS</h2><p>Add these settings to <code>.env.local</code> and restart the server.</p><ul>{config.missing.map((name) => <li key={name}><code>{name}</code></li>)}</ul></> : user ? <>
          <span className={styles.status}>● Signed in with WorkOS</span>
          <div className={styles.identity}><span className={styles.avatar} aria-hidden="true">{name.slice(0, 1).toUpperCase()}</span><div><h2>{name}</h2><p>{user.email}</p></div></div>
          <dl><dt>User ID</dt><dd>{user.id}</dd>{auth.organizationId && <><dt>Organization ID</dt><dd>{auth.organizationId}</dd></>}</dl>
          <Link className={styles.primary} href="/">Continue to demos <span>→</span></Link>
          <form action={switchAccount}><button className={styles.secondary} type="submit">Switch account</button></form>
          <form action={logOut}><button className={styles.textButton} type="submit">Sign out</button></form>
          <p className={styles.note}>Switching accounts signs out this WorkOS session, then opens a fresh sign-in so you can use another email address.</p>
        </> : <>
          <span className={styles.status}>WORKOS AUTHKIT</span><h2>Your account, your next launch.</h2><p>Use your email or a sign-in method available through WorkOS.</p>
          {/* OAuth starts with a full navigation to set cookies and follow the external redirect. */}
          {/* eslint-disable-next-line @next/next/no-html-link-for-pages */}
          <a className={styles.primary} href="/auth/sign-in">Sign in with WorkOS <span>→</span></a>
          <p className={styles.note}>Want to use a different account? You can switch accounts here after signing in.</p>
        </>}
      </section>
      {!user && <Link href="/" className={styles.guest}>Continue as a guest →</Link>}
    </main>
  </div>;
  return config.configured ? <AuthKitProvider initialAuth={initialAuth}>{content}</AuthKitProvider> : content;
}
