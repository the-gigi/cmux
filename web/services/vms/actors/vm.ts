import { actor } from "rivetkit";
import { defaultProviderId, getProvider, type ProviderId, type VMStatus } from "../drivers";

export type VMState = {
  provider: ProviderId;
  providerVmId: string;
  userId: string; // Stack Auth user id, immutable after create.
  image: string;
  status: VMStatus;
  createdAt: number;
  pausedAt: number | null;
  snapshots: Array<{ id: string; name?: string; createdAt: number }>;
};

export type VMCreateInput = {
  provider: ProviderId;
  userId: string;
  image: string;
};

const IDLE_PAUSE_MS = 10 * 60 * 1000;

// Actor per VM. Key is a cmux-owned UUID, not the provider's sandbox id, so we can change
// providers without re-keying. providerVmId lives in state.
export const vmActor = actor({
  options: { name: "VM", icon: "cloud" },

  createState: (_c, input: VMCreateInput): VMState => ({
    provider: input.provider,
    providerVmId: "",
    userId: input.userId,
    image: input.image,
    status: "creating",
    createdAt: Date.now(),
    pausedAt: null,
    snapshots: [],
  }),

  onCreate: async (c) => {
    // Bootstrap the provider VM on first create. If this throws, the actor destroys itself.
    try {
      const driver = getProvider(c.state.provider);
      const handle = await driver.create({ image: c.state.image });
      c.state.providerVmId = handle.providerVmId;
      c.state.status = "running";
    } catch (err) {
      c.state.status = "destroyed";
      throw err;
    }
  },

  onDestroy: async (c) => {
    if (c.state.status !== "destroyed" && c.state.providerVmId) {
      try {
        await getProvider(c.state.provider).destroy(c.state.providerVmId);
      } catch {
        // Best-effort cleanup; provider may already have evicted the VM.
      }
    }
  },

  onConnect: (_c, _conn) => {
    // New client attached. We don't explicitly cancel any scheduled autoPause here — the action
    // itself re-checks c.conns.size before pausing, so a reconnect races cleanly.
  },

  onDisconnect: (c, _conn) => {
    if (c.conns.size === 0) {
      void c.schedule.after(IDLE_PAUSE_MS, "autoPause");
    }
  },

  actions: {
    autoPause: async (c) => {
      if (c.conns.size !== 0) return; // raced with a reconnect
      if (c.state.status !== "running") return;
      await getProvider(c.state.provider).pause(c.state.providerVmId);
      c.state.status = "paused";
      c.state.pausedAt = Date.now();
    },

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

    status: (c) => c.state,

    // Explicit destroy: calls the provider driver then removes this actor instance. The
    // built-in RivetKit actor-destroy isn't exposed over the HTTP action path, so we ship
    // our own verb the REST facade can call.
    remove: async (c) => {
      if (c.state.status !== "destroyed" && c.state.providerVmId) {
        try {
          await getProvider(c.state.provider).destroy(c.state.providerVmId);
        } catch {
          // Best-effort; the actor-destroy below will still run.
        }
      }
      c.state.status = "destroyed";
      c.destroy();
    },
  },
});

export function vmCreateInput(opts: { userId: string; provider?: ProviderId; image: string }): VMCreateInput {
  return {
    userId: opts.userId,
    provider: opts.provider ?? defaultProviderId(),
    image: opts.image,
  };
}
