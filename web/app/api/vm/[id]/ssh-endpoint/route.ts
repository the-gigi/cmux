import { createClient } from "rivetkit/client";
import type { Registry } from "../../../../../services/vms/registry";
import { unauthorized, verifyRequest } from "../../../../../services/vms/auth";

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

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json" },
  });
}

/**
 * Returns the SSH endpoint the mac client will dial to reach this VM's cmuxd-remote.
 *
 * Freestyle response shape: `{ host: "vm-ssh.freestyle.sh", port: 22,
 * username: "<vmId>+cmux", credential: { kind: "password", value: "<one-time token>" } }`.
 * Mac client hands this to the existing `cmux ssh` transport; no Next.js in the data plane.
 *
 * E2B returns 501-ish (provider throws) because E2B sandboxes don't expose raw TCP.
 *
 * Short-lived: each call mints a fresh identity + token. vmActor.remove revokes the identity
 * alongside the VM on destroy, so idle sessions don't accumulate zombie credentials.
 */
export async function POST(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
): Promise<Response> {
  try {
    const user = await verifyRequest(request);
    if (!user) return unauthorized();
    const bearer = bearerFrom(request);
    if (!bearer) return unauthorized();

    const { id } = await params;
    const client = clientFor(request, bearer);
    const endpoint = await client.vmActor.getOrCreate([id]).openSSH();
    return jsonResponse(endpoint);
  } catch (err) {
    console.error("/api/vm/[id]/ssh-endpoint failed", err);
    const message = err instanceof Error ? `${err.name}: ${err.message}` : String(err);
    return jsonResponse({ error: message }, 500);
  }
}
