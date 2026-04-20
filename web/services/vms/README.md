# Cloud VMs service

Backend for `cmux vm new/ls/rm` and the upcoming sidebar Cloud button. Stack Auth gated, manaflow-owned provider keys (no BYO). Default provider is E2B; Freestyle is stubbed until its baked snapshot lands.

## Layout

```
services/vms/
  drivers/
    types.ts       VMProvider interface, shared types, errors
    e2b.ts         E2BProvider — real driver over @e2b SDK
    freestyle.ts   FreestyleProvider — stub, throws NotImplemented
    index.ts       getProvider / defaultProviderId
  actors/
    vm.ts          One per VM. Tracks connection count for idle-pause.
    userVms.ts     Coordinator per Stack Auth user. Lists/creates/forgets VMs.
  registry.ts      RivetKit setup({ use: { vmActor, userVmsActor } })
  client.ts        Helper: in-app fetch client with bearer forwarded
  auth.ts          verifyRequest / unauthorized — Stack Auth bearer verification
```

## HTTP surface

- `/api/rivet/*` — authoritative. `registry.handler(request)` speaks the native RivetKit
  protocol (HTTP POST to action endpoints, WebSocket for attach). Swift client hits this directly.
- `/api/vm` — REST facade for curl + debug: `GET` (list) / `POST` (create).
- `/api/vm/:id` — REST facade for curl + debug: `DELETE` (destroy).

All endpoints verify `Authorization: Bearer <stack access token>` plus `X-Stack-Refresh-Token:
<refresh>` from the mac client (matches the tokens the mac app stashes in keychain after
`cmux auth login`). Browsers going through `/handler/*` hit the same functions via the Stack
Auth cookie path.

## Env

See `web/.env.example`. The VM-specific vars:

- `E2B_API_KEY` — manaflow's key, used by E2BProvider.
- `FREESTYLE_API_KEY` — populated but unused (driver stubbed).
- `E2B_SANDBOX_TEMPLATE` — template name to spawn from. Defaults to
  `cmux-sandbox:v0-71a954b8e53b`, produced by
  `scratch/vm-experiments/images/build-e2b.ts`.
- `FREESTYLE_SANDBOX_SNAPSHOT` — empty until the Freestyle baked snapshot lands.
- `CMUX_VM_DEFAULT_PROVIDER` — `e2b` or `freestyle`. Defaults to `e2b`.

## Lifecycle

- `userVmsActor.create({ image, provider })` allocates a cmux UUID, spawns `vmActor(uuid)` with
  input, appends to the user's list, returns `{ id, provider, image }`.
- `vmActor.onCreate` calls the provider driver to provision a real sandbox and stores
  `providerVmId` in actor state.
- A client WebSocket connection keeps `c.conns.size >= 1`. Disconnecting schedules `autoPause`
  10 minutes out.
- `autoPause` re-checks `c.conns.size` first, so a reconnect race is a no-op. If still zero,
  it calls `driver.pause()`.
- `vmActor.remove` calls `driver.destroy()` then `c.destroy()`. `userVmsActor.forget(id)`
  removes the id from the coordinator.

## Next steps

- Add `/api/vm/:id/pause`, `/api/vm/:id/resume`, `/api/vm/:id/exec`, `/api/vm/:id/snapshot` REST
  wrappers once Swift client wants them (or let the Swift side hit `/api/rivet/*` actions
  directly, which is what the plan prefers).
- Wire the Freestyle driver once the baked snapshot lands.
- Implement `openSSH` for the real mutagen-over-ssh sync path.

See `plans/task-cmux-vm-cloud/cloud-vms-and-per-surface-ssh.md` for the full roadmap.
