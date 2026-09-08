'use client';
import { useEffect, useState } from 'react';
import { CANDIDATE_MODELS, programExamples, MAX_PROGRAM, type AssetFunction, type Context, type ModelConfig } from '@/lib/demos';
import { api, postBody } from '@/lib/http';
import { ModelFields } from './model-fields';
import styles from '@/app/page.module.css';

type Entries = { organizationKey: string; userKey: string | null; organization: string | null; user: string | null };
export function OverrideEditor({ store, functionName, context, onSaved, disabled }: { functionName: AssetFunction; store: 'models' | 'programs'; context: Context; onSaved: () => void; disabled: boolean }) {
  const examples = programExamples(functionName);
  const [scope, setScope] = useState<'organization' | 'user'>('organization');
  const [entries, setEntries] = useState<Entries | null>(null);
  const [model, setModel] = useState<ModelConfig>(CANDIDATE_MODELS[functionName]);
  const [program, setProgram] = useState<string>(programExamples(functionName).simple);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [revision, setRevision] = useState(0);
  const { organizationId, userId } = context;

  useEffect(() => {
    const controller = new AbortController();
    const query = new URLSearchParams({ store, functionName, organizationId, ...(userId ? { userId } : {}) });
    api<Entries>(`/api/overrides?${query}`, { signal: controller.signal }).then((data) => {
      setEntries(data);
      const current = scope === 'user' ? data.user : data.organization;
      if (store === 'programs') setProgram(current ?? programExamples(functionName).simple);
      else if (current) {
        try { setModel(JSON.parse(current)); } catch { setError('The existing file is invalid JSON. Save a replacement or remove it.'); }
      } else setModel(CANDIDATE_MODELS[functionName]);
      setLoading(false);
    }).catch((error) => { if (!controller.signal.aborted) { setError(error.message); setLoading(false); } });
    return () => controller.abort();
  }, [store, functionName, organizationId, userId, scope, revision]);

  async function save(remove: boolean) {
    setBusy(true); setError(null); setNotice(null);
    try {
      const result = await api<{ key: string; clientId?: string }>('/api/overrides', {
        ...postBody({ store, functionName, ...context, scope, value: store === 'programs' ? program : model }),
        method: remove ? 'DELETE' : 'PUT',
      });
      setNotice(remove ? 'Override removed. The next matching level takes over.' : store === 'programs' ? `Saved. Reflection verified ChooseLlm() → ai.Client → ${result.clientId}.` : 'Saved. The next request will read this override.');
      setRevision((revision) => revision + 1);
      onSaved();
    } catch (error) { setError(error instanceof Error ? error.message : 'Could not save the override.'); }
    finally { setBusy(false); }
  }
  const locked = busy || disabled || loading;
  const filename = scope === 'user' ? entries?.userKey : entries?.organizationKey;
  return <div className={styles.overrideEditor}>
    <div className={styles.controlLabel}>WRITE AN OVERRIDE</div>
    <div className={styles.segmented} aria-label="Override scope">
      <button type="button" disabled={locked} aria-pressed={scope === 'organization'} onClick={() => { setScope('organization'); setLoading(true); setNotice(null); setError(null); }}>Organization</button>
      <button type="button" disabled={locked || !userId} aria-pressed={scope === 'user'} onClick={() => { setScope('user'); setLoading(true); setNotice(null); setError(null); }}>This user</button>
    </div>
    <p className={styles.filePath}>{store}/{filename || 'Choose a context'}</p>
    {store === 'models' ? <ModelFields functionName={functionName} value={model} onChange={setModel} disabled={locked} /> : <>
      <div className={styles.presets}><span>Try a program</span>{(['simple', 'retry', 'fallback'] as const).map((name) => <button type="button" key={name} disabled={locked} onClick={() => setProgram(examples[name])}>{name}</button>)}</div>
      <label>Complete BAML function<textarea className={styles.codeEditor} value={program} onChange={(event) => setProgram(event.target.value)} rows={9} maxLength={MAX_PROGRAM} spellCheck={false} disabled={locked} /></label>
      <p className={styles.hint}>Store the entire <code>function ChooseLlm() → ai.Client</code>, including its signature and body. Reflection checks the function contract and invokes it on every run.</p>
    </>}
    <div className={styles.actions}><button type="button" className={styles.secondaryButton} disabled={locked} onClick={() => save(false)}>{busy ? 'Working…' : store === 'programs' ? 'Validate & save' : 'Save override'}</button><button type="button" className={styles.textButton} disabled={locked || !(scope === 'user' ? entries?.user : entries?.organization)} onClick={() => save(true)}>Remove override</button></div>
    {error && <p className={styles.error} role="alert">{error}</p>}
    {notice && <p className={styles.notice} role="status">{notice}</p>}
    <details className={styles.savedFiles}><summary>Inspect saved files</summary><div><strong>Organization</strong><pre>{entries?.organization ?? 'No override'}</pre>{userId && <><strong>User</strong><pre>{entries?.user ?? 'No override'}</pre></>}</div></details>
  </div>;
}
