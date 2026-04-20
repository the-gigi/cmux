import { actor } from "rivetkit";
import { defaultProviderId, type ProviderId } from "../drivers";
import type { registry } from "../registry";

export type UserVmsState = {
  vms: Array<{
    id: string; // our cmux-owned UUID (vmActor key)
    provider: ProviderId;
    image: string;
    createdAt: number;
  }>;
};

// One coordinator per Stack Auth user. Tracks the set of vmActor keys the user owns.
export const userVmsActor = actor({
  options: { name: "UserVMs", icon: "users" },

  state: { vms: [] } as UserVmsState,

  actions: {
    list: (c) => c.state.vms,

    create: async (
      c,
      opts: { image: string; provider?: ProviderId },
    ): Promise<{ id: string; provider: ProviderId; image: string }> => {
      const id = crypto.randomUUID();
      const provider = opts.provider ?? defaultProviderId();
      const client = c.client<typeof registry>();
      // Spawn the per-VM actor. Its onCreate provisions the sandbox; this await blocks until
      // the provider returns an id.
      const userId = c.key[0] as string;
      await client.vmActor.create([id], {
        input: { userId, provider, image: opts.image },
      });
      c.state.vms.push({ id, provider, image: opts.image, createdAt: Date.now() });
      return { id, provider, image: opts.image };
    },

    forget: (c, vmId: string) => {
      c.state.vms = c.state.vms.filter((v) => v.id !== vmId);
    },
  },
});
