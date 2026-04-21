import { registry } from "../../../../services/vms/registry";
import { unauthorized, verifyRequest } from "../../../../services/vms/auth";
import { assertRivetInternal } from "../../../../services/vms/routeHelpers";

export const dynamic = "force-dynamic";

async function handle(request: Request): Promise<Response> {
  // `/api/rivet/*` is the raw RivetKit protocol surface. Actor keys are client-chosen, so a
  // plain "is this user authenticated" check is not enough: a signed-in user could point a
  // raw Rivet client here and target another user's actor by keying with their id. Gate on
  // a shared secret so only our own REST routes — which do user + ownership checks first —
  // can reach actors. External callers cannot forge the secret.
  if (!assertRivetInternal(request)) return unauthorized();
  const user = await verifyRequest(request);
  if (!user) return unauthorized();
  // Inject the userId as a request header so actor hooks can double-check if they ever
  // need to. The internal-gate above already scopes this path to our own REST routes.
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
