export async function api<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, { cache: 'no-store', ...init });
  const contentType = response.headers.get('content-type') || '';
  if (!contentType.includes('application/json')) throw new Error('The server did not return JSON. Check that the app is running and try again.');
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || 'The request failed.');
  return data as T;
}
export function postBody(value: unknown): RequestInit {
  return { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(value) };
}
