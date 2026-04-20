// Convenience REST facade over the VM actors. The authoritative path is `/api/rivet/*`; this
// route exists so curl + tests can exercise the service without speaking the full RivetKit
// protocol. Swift clients talk to /api/rivet/* directly and skip this file.

import { createClient } from "rivetkit/client";
import type { Registry } from "../../../services/vms/registry";
import { unauthorized, verifyRequest } from "../../../services/vms/auth";
import { defaultProviderId, type ProviderId } from "../../../services/vms/drivers";

export const dynamic = "force-dynamic";

function requireBearer(request: Request): { accessToken: string; refreshToken: string } | null {
  const auth = request.headers.get("authorization");
  const refresh = request.headers.get("x-stack-refresh-token");
  if (!auth?.toLowerCase().startsWith("bearer ") || !refresh) return null;
  const accessToken = auth.slice("bearer ".length).trim();
  const refreshToken = refresh.trim();
  if (!accessToken || !refreshToken) return null;
  return { accessToken, refreshToken };
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

export async function GET(request: Request): Promise<Response> {
  const user = await verifyRequest(request);
  if (!user) return unauthorized();
  const bearer = requireBearer(request);
  if (!bearer) return unauthorized();
  const client = clientFor(request, bearer);
  const vms = await client.userVmsActor.getOrCreate([user.id]).list();
  return Response.json({ vms });
}

export async function POST(request: Request): Promise<Response> {
  const user = await verifyRequest(request);
  if (!user) return unauthorized();
  const bearer = requireBearer(request);
  if (!bearer) return unauthorized();

  const body = (await request.json().catch(() => ({}))) as { image?: string; provider?: ProviderId };
  const image = body.image ?? defaultImageFor(body.provider ?? defaultProviderId());
  const provider = body.provider ?? defaultProviderId();

  const client = clientFor(request, bearer);
  const created = await client.userVmsActor.getOrCreate([user.id]).create({ image, provider });
  return Response.json({ id: created.id, provider: created.provider, image: created.image });
}

function defaultImageFor(provider: ProviderId): string {
  if (provider === "e2b") {
    return process.env.E2B_SANDBOX_TEMPLATE ?? "cmux-sandbox:v0-71a954b8e53b";
  }
  // Freestyle default populated when its snapshot lands.
  return process.env.FREESTYLE_SANDBOX_SNAPSHOT ?? "";
}
