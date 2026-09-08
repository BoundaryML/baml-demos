import { listContext } from '@/lib/server/workos';
import { errorResponse } from '@/lib/server/errors';
export const runtime = 'nodejs';
export async function GET(request: Request) {
  try {
    const organizationId = new URL(request.url).searchParams.get('organizationId') || undefined;
    return Response.json(await listContext(organizationId), { headers: { 'Cache-Control': 'no-store' } });
  } catch (error) { return errorResponse(error); }
}
