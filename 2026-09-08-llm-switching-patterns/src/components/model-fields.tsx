'use client';
import { useId } from 'react';
import { modelPresets, type AssetFunction, type ModelConfig, type Provider } from '@/lib/demos';
import styles from '@/app/page.module.css';
export function ModelFields({ functionName, value, onChange, disabled = false }: { functionName: AssetFunction; value: ModelConfig; onChange: (value: ModelConfig) => void; disabled?: boolean }) {
  const id = useId();
  return <div className={styles.modelFields}>
    <label htmlFor={`${id}-provider`}>Provider</label><label htmlFor={`${id}-model`}>Model ID</label>
    <select id={`${id}-provider`} value={value.provider} disabled={disabled} onChange={(event) => { const provider = event.target.value as Provider; onChange({ provider, model: modelPresets[functionName][provider][0] }); }}><option value="google">Google Gemini</option><option value="openai">OpenAI</option></select>
    <div><input id={`${id}-model`} list={`${id}-models`} value={value.model} disabled={disabled} onChange={(event) => onChange({ ...value, model: event.target.value })} maxLength={150} /><datalist id={`${id}-models`}>{modelPresets[functionName][value.provider].map((model) => <option key={model} value={model} />)}</datalist></div>
  </div>;
}
