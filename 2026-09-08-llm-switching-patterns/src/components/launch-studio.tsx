'use client';
import { useEffect, useMemo, useState } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { assetFunctions, demos, DEFAULT_MODELS, CANDIDATE_MODELS, DEFAULT_FLAGS, SAMPLE_BRIEF, MAX_INPUT, type AssetFunction, type ContextData, type DemoId, type DemoRequest, type LaunchBrief, type ModelChoices, type Resolution, type RunResult } from '@/lib/demos';
import { api, postBody } from '@/lib/http';
import { ModelFields } from '@/components/model-fields';
import { OverrideEditor } from '@/components/override-editor';
import styles from '@/app/page.module.css';

type RecentRun = { product: string; headline: string; demo: DemoId; durationMs: number };
export default function LaunchStudio({ selected }: { selected: DemoId }) {
  const [choices, setChoices] = useState<ModelChoices>(DEFAULT_MODELS);
  const [brief, setBrief] = useState<LaunchBrief>(SAMPLE_BRIEF);
  const [organizationId, setOrganizationId] = useState('');
  const [userId, setUserId] = useState('');
  const [editingFunction, setEditingFunction] = useState<AssetFunction>('GenerateLogo');
  const [identities, setIdentities] = useState<ContextData>({ organizations: [], users: [] });
  const [contextError, setContextError] = useState<string | null>(null);
  const [loadingContext, setLoadingContext] = useState(true);
  const [contextRevision, setContextRevision] = useState(0);
  const [flags, setFlags] = useState(DEFAULT_FLAGS);
  const [resolution, setResolution] = useState<Resolution | null>(null);
  const [resolveError, setResolveError] = useState<string | null>(null);
  const [runError, setRunError] = useState<string | null>(null);
  const [result, setResult] = useState<RunResult | null>(null);
  const [history, setHistory] = useState<RecentRun[]>([]);
  const [running, setRunning] = useState(false);
  const [revision, setRevision] = useState(0);
  const demo = demos.find((item) => item.id === selected)!;
  const needsContext = ['overrides', 'programs', 'flags'].includes(selected);
  const request = useMemo<DemoRequest>(() => ({ demo: selected, choices, organizationId, ...(userId ? { userId } : {}), flags }), [selected, choices, organizationId, userId, flags]);

  useEffect(() => {
    const controller = new AbortController();
    api<ContextData>(`/api/context${organizationId ? `?organizationId=${encodeURIComponent(organizationId)}` : ''}`, { signal: controller.signal }).then((data) => {
      setIdentities(data);
      if (!organizationId && data.organizations[0]) setOrganizationId(data.organizations[0].id);
      setContextError(null); setLoadingContext(false);
    }).catch((error) => { if (!controller.signal.aborted) { setContextError(error.message); setLoadingContext(false); } });
    return () => controller.abort();
  }, [organizationId, contextRevision]);

  useEffect(() => {
    if (needsContext && !organizationId) return;
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout>;
    async function refresh() {
      try {
        const data = await api<Resolution>('/api/demos/resolve', { ...postBody(request), signal: controller.signal });
        if (!controller.signal.aborted) { setResolution(data); setResolveError(null); }
      } catch (error) { if (!controller.signal.aborted) { setResolution(null); setResolveError(error instanceof Error ? error.message : 'Could not resolve the clients.'); } }
      finally { if (selected === 'flags' && !controller.signal.aborted) timer = setTimeout(refresh, 2500); }
    }
    timer = setTimeout(refresh, 200);
    return () => { controller.abort(); clearTimeout(timer); };
  }, [request, needsContext, organizationId, selected, revision]);

  function refreshResolution() { setResolution(null); setRevision((value) => value + 1); }
  async function run() {
    if (running) return;
    setRunning(true); setRunError(null); setResult(null);
    try {
      const data = await api<RunResult>('/api/demos/run', postBody({ ...request, brief }));
      setResult(data); setResolution(data.resolution);
      setHistory((previous) => [{ product: data.productName, headline: data.output.announcement.headline, demo: selected, durationMs: data.durationMs }, ...previous].slice(0, 4));
    } catch (error) { setRunError(error instanceof Error ? error.message : 'The workflow failed.'); }
    finally { setRunning(false); }
  }
  const ready = !!resolution && !resolveError && Object.values(brief).every((value) => value.trim()) && (!needsContext || !!organizationId);
  const logoUrl = result ? `data:${result.output.logo.mime_type};base64,${result.output.logo.base64}` : '';
  const copy = result?.output.announcement;
  const copyText = copy ? `${copy.headline}\n\n${copy.tagline}\n\n${copy.body}\n\n${copy.call_to_action}` : '';
  const filename = (result?.productName || 'launch').toLowerCase().replace(/[^a-z0-9]+/g, '-') || 'launch';

  return <div className={styles.shell}>
    <header className={styles.header}><Link className={styles.brand} href="/"><span className={styles.logo}>b.</span>Launch studio<span className={styles.divider}>/</span><span className={styles.project}>LLM switching patterns</span></Link><div className={styles.headerBadges}><Link href="/login" className={styles.accountLink}>Log in / switch account</Link><span className={styles.noLogin}>No sign-in required</span><span className={styles.nightly}><i />BAML nightly</span></div></header>
    <main className={styles.main}>
      <div className={styles.intro}><div><p className={styles.eyebrow}>ONE PRODUCT LAUNCH · FIVE SWITCHING PATTERNS</p><h1>Make your next launch<br className={styles.mobileBreak} /> look and sound the part.</h1><p>One brief becomes a logo and announcement copy. Two LLM functions, running in parallel.</p></div><div className={styles.introMark} aria-hidden="true">↗ <span>+</span> Aa</div></div>
      <nav className={styles.demoNav} aria-label="Switching demos">{demos.map((item) => <Link key={item.id} href={`/${item.namespace}`} scroll={false} aria-current={selected === item.id ? 'page' : undefined} aria-disabled={running || undefined} onNavigate={(event) => { if (running) event.preventDefault(); }}><span className={styles.demoNumber}>{item.number}</span><strong>{item.title}</strong><small>{item.subtitle}</small></Link>)}</nav>
      <section className={styles.demoHeading}><div><p className={styles.eyebrow}>PATTERN {demo.number}</p><h2>{demo.title}</h2><p>{demo.description}</p></div><div className={styles.changeBadge}><span>TAKES EFFECT</span><strong>{demo.changes}</strong></div></section>
      <div className={styles.workspace}>
        <section className={styles.configuration} aria-label="Model configuration"><div className={styles.panelHeader}><span>01 / CHOOSE THE MODELS</span><span>{selected === 'flags' ? 'WorkOS' : 'Per function'}</span></div><div className={styles.panelBody}>
          {needsContext && <div className={styles.contextBlock}><div className={styles.controlLabel}>PREPARE A LAUNCH FOR</div><p className={styles.hint}>Choose a WorkOS organization and optional user. No app login is needed.</p><label htmlFor="org">Organization</label><select id="org" value={organizationId} disabled={running || loadingContext} onChange={(event) => { setOrganizationId(event.target.value); setUserId(''); setLoadingContext(true); setResolution(null); }}><option value="">{loadingContext ? 'Loading…' : 'Choose an organization'}</option>{identities.organizations.map((org) => <option key={org.id} value={org.id}>{org.name}</option>)}</select><label htmlFor="user">User</label><select id="user" value={userId} disabled={running || loadingContext || !organizationId} onChange={(event) => { setUserId(event.target.value); setResolution(null); }}><option value="">Organization only</option>{identities.users.map((user) => <option key={user.id} value={user.id}>{user.name}</option>)}</select>{contextError && <p className={styles.error} role="alert">{contextError}</p>}<button type="button" className={styles.textButton} disabled={running || loadingContext} onClick={() => { setLoadingContext(true); setContextRevision((value) => value + 1); }}>Reload identities</button></div>}
          {selected === 'direct' && assetFunctions.map((name) => <fieldset className={styles.functionConfig} key={name}><legend>{name}()</legend><span className={styles.assetType}>{name === 'GenerateLogo' ? 'IMAGE GENERATION' : 'ANNOUNCEMENT COPY'}</span><ModelFields functionName={name} value={choices[name]} disabled={running} onChange={(value) => { setChoices((previous) => ({ ...previous, [name]: value })); setResolution(null); }} /></fieldset>)}
          {selected === 'direct' && <p className={styles.hint}>Image models create the logo. GPT‑5.2, GPT‑5.3 Chat, Terra, Luna, and Gemini text models write the announcement.</p>}
          {selected === 'environment' && <div className={styles.environment}>{assetFunctions.map((name) => { const route = resolution?.functions[name]; const prefix = name === 'GenerateLogo' ? 'LOGO' : 'COPY'; return <div key={name} className={styles.functionConfig}><div className={styles.controlLabel}>{name}()</div><div className={styles.envRow}><code>{prefix}_LLM_PROVIDER</code><strong>{route?.provider ?? '…'}</strong></div><div className={styles.envRow}><code>{prefix}_LLM_MODEL</code><strong>{route?.model ?? '…'}</strong></div></div>; })}<p className={styles.hint}>Edit these values in <code>.env.llm_settings</code> and restart the server. Credentials can stay in <code>.env.local</code>. Each function reads its own environment variables.</p><button className={styles.secondaryButton} type="button" disabled={running} onClick={refreshResolution}>Read environment again</button></div>}
          {(selected === 'overrides' || selected === 'programs') && organizationId && <><label htmlFor="function-name">Function to override</label><select id="function-name" value={editingFunction} disabled={running} onChange={(event) => setEditingFunction(event.target.value as AssetFunction)}>{assetFunctions.map((name) => <option key={name} value={name}>{name}</option>)}</select><OverrideEditor key={`${selected}-${organizationId}-${userId}-${editingFunction}`} store={selected === 'programs' ? 'programs' : 'models'} functionName={editingFunction} context={{ organizationId, ...(userId ? { userId } : {}) }} onSaved={refreshResolution} disabled={running} /></>}
          {selected === 'flags' && <div className={styles.flagPanel}>{assetFunctions.map((name) => { const state = resolution?.functions[name].flag; return <div className={styles.functionConfig} key={name}><label>{name} flag<input value={flags[name]} onChange={(event) => { setFlags((previous) => ({ ...previous, [name]: event.target.value })); setResolution(null); }} disabled={running} maxLength={100} /></label><div className={styles.flagMappings}><div><span>OFF · BASELINE</span><strong>{DEFAULT_MODELS[name].model}</strong></div><div><span>ON · CANDIDATE</span><strong>{CANDIDATE_MODELS[name].model}</strong></div></div>{state && <p className={state.exists && !state.stale ? styles.notice : styles.warning}>{!state.exists ? `Create “${state.slug}” in WorkOS. Baseline is used until then.` : state.stale ? 'Sync is stale; using the last known state.' : `${state.enabled ? 'On' : 'Off'} for this context · synced ${state.lastSyncedAt ? new Date(state.lastSyncedAt).toLocaleTimeString() : 'just now'}`}</p>}</div>; })}<a className={styles.dashboardLink} href="https://dashboard.workos.com" target="_blank" rel="noreferrer">Open WorkOS dashboard <span>↗</span></a><p className={styles.hint}>Target an organization or user and toggle either flag. Decisions sync every 5 seconds. Generate again to use the new route.</p></div>}
          <details className={styles.sourceDetails}><summary>See the BAML pattern <span>↗</span></summary><pre>{demo.code}</pre></details>
        </div></section>
        <section className={styles.execution} aria-label="Launch brief"><div className={styles.panelHeader}><span>02 / YOUR LAUNCH</span><code>{demo.namespace}.GenerateAssets()</code></div><div className={styles.panelBody}>
          <label>Product name<input value={brief.product_name} onChange={(event) => setBrief({ ...brief, product_name: event.target.value })} maxLength={100} disabled={running} /></label>
          <label>What are you launching?<textarea value={brief.description} onChange={(event) => setBrief({ ...brief, description: event.target.value })} rows={4} maxLength={MAX_INPUT} disabled={running} /></label>
          <label>Audience<textarea value={brief.audience} onChange={(event) => setBrief({ ...brief, audience: event.target.value })} rows={2} maxLength={1000} disabled={running} /></label>
          <label>Brand voice<input value={brief.tone} onChange={(event) => setBrief({ ...brief, tone: event.target.value })} maxLength={500} disabled={running} /></label>
          <button type="button" className={styles.textButton} disabled={running} onClick={() => setBrief(SAMPLE_BRIEF)}>Use example brief</button>
          <div className={styles.parallelFlow}><div className={styles.controlLabel}>TWO PARALLEL LLM CALLS</div>{assetFunctions.map((name) => { const route = resolution?.functions[name]; return <div className={styles.routeCard} key={name}><span className={styles.controlLabel}>{name}()</span><strong data-testid={`resolved-${name}`}>{route?.clientId ?? (resolveError ? 'Could not resolve' : needsContext && !organizationId ? 'Choose a context' : 'Resolving…')}</strong><span className={styles.routeSource}>{route?.source ?? 'Resolved again when you generate.'}</span>{route?.validated && <span className={styles.verified}>✓ Complete function → ai.Client verified</span>}{route?.key && <details className={styles.keyDetails}><summary>LlmChoiceKey</summary><pre>{JSON.stringify(route.key, null, 2)}</pre></details>}{route && <details className={styles.keyDetails}><summary>Why this model?</summary><ul>{route.trace.map((line, index) => <li key={index}>{line}</li>)}</ul></details>}</div>; })}</div>
          {resolveError && <p className={styles.error} role="alert">{resolveError}</p>}
          <button className={styles.runButton} type="button" disabled={running || !ready} onClick={run}><span>{running ? 'Generating launch assets…' : 'Generate launch assets'}</span><span aria-hidden="true">{running ? '◌' : '→'}</span></button><p className={styles.hint}>Makes two real model calls in parallel. Image generation can take a minute or more.</p>
        </div></section>
        <section className={styles.output} aria-label="Launch assets" aria-busy={running}><div className={styles.panelHeader}><span>03 / YOUR ASSETS</span><span>{running ? 'Generating' : result ? `${(result.durationMs / 1000).toFixed(1)}s · Ready` : runError ? 'Failed' : 'Ready when you are'}</span></div><div className={styles.panelBody} aria-live="polite">
          {runError ? <div className={styles.error} role="alert"><strong>Couldn’t generate the assets</strong><p>{runError}</p></div> : result && copy ? <><div className={styles.resultMeta}><span>{result.productName} · LAUNCH KIT</span></div><div className={styles.logoPreview}><Image src={logoUrl} width={1024} height={1024} unoptimized alt={`Generated logo for ${result.productName}`} /></div><a className={styles.downloadLink} href={logoUrl} download={`${filename}-logo.${result.output.logo.mime_type === 'image/jpeg' ? 'jpg' : result.output.logo.mime_type.split('/')[1]}`}>Download logo ↓</a><div className={styles.copyPreview} data-testid="announcement-copy"><span className={styles.controlLabel}>ANNOUNCEMENT COPY</span><h3>{copy.headline}</h3><p className={styles.tagline}>{copy.tagline}</p><p>{copy.body}</p><strong>{copy.call_to_action}</strong></div><a className={styles.downloadLink} href={`data:text/plain;charset=utf-8,${encodeURIComponent(copyText)}`} download={`${filename}-announcement.txt`}>Download announcement ↓</a><details className={styles.jsonOutput}><summary>Typed workflow output</summary><pre data-testid="function-output">{JSON.stringify({ ...result.output, logo: { mime_type: result.output.logo.mime_type, base64: `[${result.output.logo.base64.length.toLocaleString()} characters · use Download logo]` } }, null, 2)}</pre></details></> : <div className={styles.empty}><span aria-hidden="true">{running ? '◌' : '↗'}</span><h3>{running ? 'Your launch kit is taking shape.' : 'A logo. The right words.'}</h3><p>{running ? 'The logo and announcement functions run independently. Both assets will appear when the workflow finishes.' : 'Tell us what you’re launching. GenerateAssets will create the visual and written assets together.'}</p><div className={styles.assetPlaceholders}><span>◈ Logo</span><span>Aa Announcement</span></div></div>}
        </div></section>
      </div>
      {history.length > 0 && <section className={styles.history} aria-label="Recent launches"><div className={styles.controlLabel}>RECENT LAUNCHES <span>THIS SESSION</span></div>{history.map((run, index) => <div key={index}><span>{demos.find((demo) => demo.id === run.demo)?.number}</span><code>{run.product}</code><p>{run.headline}</p><strong>{(run.durationMs / 1000).toFixed(1)}s</strong></div>)}</section>}
      <footer className={styles.footer}><span><i className={styles.liveDot} /> BAML · OpenAI · Gemini · WorkOS</span><span>The model can change. Your launch workflow stays the same.</span></footer>
    </main>
  </div>;
}
