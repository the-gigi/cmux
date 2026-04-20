import { createClient } from "rivetkit/client";
import type { Registry } from "./registry";

/**
 * Returns a RivetKit client that talks back to this same Next.js app at `/api/rivet/*`.
 * Use from server-side REST facades that want to invoke actor actions without duplicating logic.
 *
 * The bearer header is the Stack Auth access token for the calling user; the rivet route checks
 * it via `verifyRequest` and rejects with 401 if missing.
 */
export function clientForRequest(
  request: Request,
  bearer: { accessToken: string; refreshToken: string },
) {
  const origin = new URL(request.url).origin;
  return createClient<Registry>({
    endpoint: `${origin}/api/rivet`,
    headers: {
      authorization: `Bearer ${bearer.accessToken}`,
      "x-stack-refresh-token": bearer.refreshToken,
    },
  });
}
