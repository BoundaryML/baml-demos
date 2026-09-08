import { db, overrideKey, readOverrides, validateContext, validateFunction, validateModel, validateProgram, type Store, type Scope } from '@/lib/server/database';
import { inspectProgram } from '@/lib/server/runner';
import { DemoError, errorResponse, jsonBody } from '@/lib/server/errors';
export const runtime = 'nodejs';
function storeOf(value: unknown): Store {
  if (value !== 'models' && value !== 'programs') throw new DemoError('Choose the model or program store.');
  return value;
}
function scopeOf(value: unknown): Scope {
  if (value !== 'organization' && value !== 'user') throw new DemoError('Choose organization or user scope.');
  return value;
}
export async function GET(request: Request) {
  try {
    const params = new URL(request.url).searchParams;
    const context = validateContext(params.get('organizationId'), params.get('userId') || undefined);
    return Response.json(await readOverrides(storeOf(params.get('store')), context, validateFunction(params.get('functionName'))), { headers: { 'Cache-Control': 'no-store' } });
  } catch (error) { return errorResponse(error); }
}
export async function PUT(request: Request) {
  try {
    const body = await jsonBody(request);
    const store = storeOf(body.store);
    const context = validateContext(body.organizationId, body.userId);
    const functionName = validateFunction(body.functionName);
    const key = overrideKey(context, scopeOf(body.scope), functionName);
    let value: string;
    let clientId: string | undefined;
    if (store === 'models') value = JSON.stringify(validateModel(body.value, functionName), null, 2) + '\n';
    else { value = validateProgram(body.value); clientId = await inspectProgram(value, functionName); }
    await db.set(store, key, value);
    return Response.json({ key, clientId, saved: true });
  } catch (error) { return errorResponse(error); }
}
export async function DELETE(request: Request) {
  try {
    const body = await jsonBody(request);
    const store = storeOf(body.store);
    const context = validateContext(body.organizationId, body.userId);
    const functionName = validateFunction(body.functionName);
    const key = overrideKey(context, scopeOf(body.scope), functionName);
    await db.delete(store, key);
    return Response.json({ key, deleted: true });
  } catch (error) { return errorResponse(error); }
}
