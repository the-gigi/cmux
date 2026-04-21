import { actor } from "rivetkit";
import { getProvider, type ProviderId, type VMStatus } from "../drivers";

export type VMState = {
  provider: ProviderId;
  providerVmId: string; // also the actor key now — no cmux UUID layer.
  userId: string;       // Stack Auth user id, immutable after create.
  image: string;
  status: VMStatus;
  createdAt: number;
  pausedAt: number | null;
  /**
   * Identity handles returned by `openSSH`. Kept here (not thrown away after the endpoint is
   * handed out) so we can revoke them on VM destroy and before minting a fresh replacement.
   * Without this, every `cmux vm shell` call would leak a live Freestyle credential.
   */
  sshIdentityHandles: string[];
  snapshots: Array<{ id: string; name?: string; createdAt: number }>;
};

export type VMCreateInput = {
  provider: ProviderId;
  providerVmId: string;
  userId: string;
  image: string;
};

// One actor per VM. Actor key is the provider's own id. The provider VM is already created by
// the caller (userVmsActor.create) before we spawn this actor — we just own lifecycle,
// per-VM actions (exec, snapshot, openSSH, remove, …), and cleanup of the credential material
// we mint on the user's behalf.
//
// Note on idle auto-pause: the previous design scheduled `autoPause` from `onDisconnect`, but
// `c.conns.size` tracks Rivet *actor* connections — not the SSH session the user actually
// cares about. Because our REST routes open stateless one-shot actor connections that close
// immediately, disconnect fired on every request and queued a 10-minute pause even while the
// user's SSH shell was wide open. That behavior is gone until we track real SSH session
// liveness (see the follow-up task for heartbeat wiring). Explicit `pause`/`resume` actions
// still work; we just don't fire them on our own schedule.
export const vmActor = actor({
  options: { name: "VM", icon: "cloud" },

  createState: (_c, input: VMCreateInput): VMState => ({
    provider: input.provider,
    providerVmId: input.providerVmId,
    userId: input.userId,
    image: input.image,
    status: "running",
    createdAt: Date.now(),
    pausedAt: null,
    sshIdentityHandles: [],
    snapshots: [],
  }),

  onDestroy: async (c) => {
    await revokeAllIdentities(c.state);
    if (c.state.status !== "destroyed" && c.state.providerVmId) {
      try {
        await getProvider(c.state.provider).destroy(c.state.providerVmId);
      } catch {
        // Best-effort; provider may have already evicted the VM.
      }
    }
  },

  actions: {
    pause: async (c) => {
      if (c.state.status === "paused") return;
      await getProvider(c.state.provider).pause(c.state.providerVmId);
      c.state.status = "paused";
      c.state.pausedAt = Date.now();
    },

    resume: async (c) => {
      if (c.state.status === "running") return;
      const handle = await getProvider(c.state.provider).resume(c.state.providerVmId);
      c.state.providerVmId = handle.providerVmId;
      c.state.status = "running";
      c.state.pausedAt = null;
    },

    snapshot: async (c, name?: string) => {
      const ref = await getProvider(c.state.provider).snapshot(c.state.providerVmId, name);
      c.state.snapshots.push({ id: ref.id, name: ref.name, createdAt: ref.createdAt });
      return ref;
    },

    exec: async (c, command: string, timeoutMs?: number) => {
      return await getProvider(c.state.provider).exec(c.state.providerVmId, command, { timeoutMs });
    },

    openSSH: async (c) => {
      // Before minting a new identity, revoke any prior ones we've handed out for this VM.
      // `cmux vm shell` can be invoked repeatedly; without this step each call leaks a live
      // credential that outlives its usefulness.
      await revokeAllIdentities(c.state);
      c.state.sshIdentityHandles = [];
      const endpoint = await getProvider(c.state.provider).openSSH(c.state.providerVmId);
      if (endpoint.identityHandle) {
        c.state.sshIdentityHandles = [endpoint.identityHandle];
      }
      return endpoint;
    },

    status: (c) => c.state,

    remove: async (c) => {
      await revokeAllIdentities(c.state);
      c.state.sshIdentityHandles = [];
      if (c.state.status !== "destroyed" && c.state.providerVmId) {
        // Surface provider destroy failures. Previously this path swallowed them, returned
        // success, and then the coordinator forget() dropped the last tracking reference —
        // the result was a ghost billable VM the user could no longer manage via cmux.
        // Rethrow so the REST layer returns 500 and the caller can retry. Codex P1.
        try {
          await getProvider(c.state.provider).destroy(c.state.providerVmId);
        } catch (err) {
          // Exception: if the provider says the VM is already gone (dashboard-deleted,
          // evicted for inactivity, etc.), treat that as success. Otherwise the user gets
          // stuck with a stale entry they can never remove via cmux because every retry
          // hits the same "not found". Codex P2.
          if (!isProviderNotFoundError(err)) throw err;
        }
      }
      c.state.status = "destroyed";
      c.destroy();
    },
  },
});

async function revokeAllIdentities(state: VMState): Promise<void> {
  if (state.sshIdentityHandles.length === 0) return;
  const provider = getProvider(state.provider);
  await Promise.all(
    state.sshIdentityHandles.map((handle) => provider.revokeSSHIdentity(handle)),
  );
}

/**
 * Best-effort detection of "VM already gone on the provider side" for destroy retries.
 * Freestyle and E2B both surface it as a 404/NotFound status on their REST client errors
 * or as a human-readable message; match broadly so a user who deleted the sandbox from
 * the provider dashboard can still clean up the cmux-side tracking.
 */
function isProviderNotFoundError(err: unknown): boolean {
  if (!err || typeof err !== "object") return false;
  const candidate = err as {
    status?: number;
    statusCode?: number;
    response?: { status?: number };
    message?: string;
    cause?: unknown;
  };
  const status =
    candidate.status ??
    candidate.statusCode ??
    candidate.response?.status ??
    undefined;
  if (status === 404) return true;
  const message = (candidate.message ?? "").toLowerCase();
  if (
    message.includes("not found") ||
    message.includes("does not exist") ||
    message.includes("no such") ||
    message.includes("already deleted") ||
    message.includes("404")
  ) {
    return true;
  }
  if (candidate.cause) return isProviderNotFoundError(candidate.cause);
  return false;
}
