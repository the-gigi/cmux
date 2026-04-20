import { createClient } from "rivetkit/client";
import type { Registry } from "../../../../services/vms/registry";
import { unauthorized, verifyRequest } from "../../../../services/vms/auth";

export const dynamic = "force-dynamic";

function bearerFrom(request: Request): { accessToken: string; refreshToken: string } | null {
  const auth = request.headers.get("authorization");
  const refresh = request.headers.get("x-stack-refresh-token");
  if (!auth?.toLowerCase().startsWith("bearer ") || !refresh) return null;
  const a = auth.slice("bearer ".length).trim();
  const r = refresh.trim();
  if (!a || !r) return null;
  return { accessToken: a, refreshToken: r };
}

function clientFor(request: Request, bearer: { accessToken: string; refreshToken: string }) {
  const origin = new URL(request.url).origin;
  return createClient<Registry>({
    endpoint: `${origin}/api/rivet`,
    headers: {
      authorization: `Bearer ${bearer.accessToken}`,
      "x-stack-refresh-token": bearer.refreshToken,
    },
  });
}

export async function DELETE(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
): Promise<Response> {
  const user = await verifyRequest(request);
  if (!user) return unauthorized();
  const bearer = bearerFrom(request);
  if (!bearer) return unauthorized();
  const { id } = await params;
  const client = clientFor(request, bearer);
  // vmActor.destroy() via rivet's built-in destroy action; this triggers onDestroy which
  // tears down the provider VM. Then drop the id from the user coordinator.
  const vm = client.vmActor.getOrCreate([id]);
  await vm.remove();
  await client.userVmsActor.getOrCreate([user.id]).forget(id);
  return Response.json({ ok: true });
}
