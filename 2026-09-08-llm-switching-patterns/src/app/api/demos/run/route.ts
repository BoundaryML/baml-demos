import { parseRequest, runDemo } from '@/lib/server/runner';
import { errorResponse, jsonBody } from '@/lib/server/errors';
export const runtime = 'nodejs';
export async function POST(request: Request) {
  try { return Response.json(await runDemo(parseRequest(await jsonBody(request)))); }
  catch (error) { return errorResponse(error); }
}
