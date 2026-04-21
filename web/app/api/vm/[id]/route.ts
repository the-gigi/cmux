import { unauthorized, verifyRequest } from "../../../../services/vms/auth";
import {
  destroyTrackedProviderVm,
  isActorMissingError,
  jsonResponse,
  notFoundVm,
  parseForwardedCreds,
  rivetClient,
  userVmEntry,
} from "../../../../services/vms/routeHelpers";

export const dynamic = "force-dynamic";

export async function DELETE(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
): Promise<Response> {
  try {
    const user = await verifyRequest(request);
    if (!user) return unauthorized();
    const creds = parseForwardedCreds(request);
    if (!creds) return unauthorized();
    const { id } = await params;
    const client = rivetClient(creds);
    // Prevent IDOR: a user may only destroy VMs tracked in their own coordinator actor.
    const tracked = await userVmEntry(client, user.id, id);
    if (!tracked) return notFoundVm(id);
    // `get` not `getOrCreate`: a coordinator entry without a live actor (partial cleanup
    // failure) should 404 instead of spawning an uninitialised actor that 500s. For the
    // DELETE path specifically we also forget() the coordinator entry regardless, so a
    // stale mapping can be cleaned up via retry.
    try {
      await client.vmActor.get([id]).remove();
    } catch (err) {
      // If the actor is genuinely missing, drop the coordinator reference so the user
      // isn't permanently stuck with an un-removable entry. This can happen when
      // userVmsActor.create provisioned the provider VM, vmActor.create failed, and the
      // rollback destroy also failed. Use the coordinator's preserved provider metadata to
      // retry direct provider cleanup before forget().
      if (isActorMissingError(err)) {
        await destroyTrackedProviderVm(tracked);
      } else {
        throw err;
      }
    }
    await client.userVmsActor.getOrCreate([user.id]).forget(id);
    return jsonResponse({ ok: true });
  } catch (err) {
    console.error("/api/vm/[id] DELETE failed", err);
    // Return a safe summary only — don't echo the provider's error shape, which can
    // contain internal URLs or tokens.
    return jsonResponse({ error: err instanceof Error ? err.message : "internal error" }, 500);
  }
}
