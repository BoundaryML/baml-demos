export class DemoError extends Error {
  constructor(message: string, public status = 400) { super(message); }
}
export function errorResponse(error: unknown) {
  if (error instanceof DemoError) return Response.json({ error: error.message }, { status: error.status });
  // Raw SDK/provider errors can contain headers or credentials.
  return Response.json({ error: 'The call failed. Check the provider key, model access, quota, and connection, then try again.' }, { status: 502 });
}
export async function jsonBody(request: Request): Promise<Record<string, unknown>> {
  const text = await request.text();
  if (text.length > 40000) throw new DemoError('Request is too large.', 413);
  let body: unknown;
  try { body = JSON.parse(text); } catch { throw new DemoError('Send valid JSON.'); }
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new DemoError('Send a JSON object.');
  return body as Record<string, unknown>;
}
