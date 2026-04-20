import { registry } from "../../../../services/vms/registry";
import { unauthorized, verifyRequest } from "../../../../services/vms/auth";

export const dynamic = "force-dynamic";

async function handle(request: Request): Promise<Response> {
  const user = await verifyRequest(request);
  if (!user) return unauthorized();
  // Inject the userId as a request header so actor keys can read it if needed. The actor
  // trusts this header because we've verified the session above.
  const patched = new Request(request, {
    headers: new Headers([...request.headers, ["x-cmux-user-id", user.id]]),
  });
  return registry.handler(patched);
}

export const GET = handle;
export const POST = handle;
export const PUT = handle;
export const DELETE = handle;
export const PATCH = handle;
