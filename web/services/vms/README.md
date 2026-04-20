# Cloud VMs service

Backend for `cmux vm new/ls/rm/exec/attach` and the upcoming sidebar Cloud button. Stack Auth gated, manaflow-owned provider keys (no BYO). **Default provider is Freestyle** for all interactive work (shell attach, workspace attach). E2B stays available for scratch `vm exec` use via `--provider e2b --detach`; E2B sandboxes don't expose raw TCP so they can't be attached to interactively.

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
- `FREESTYLE_API_KEY` — manaflow's key, used by FreestyleProvider.
- `E2B_SANDBOX_TEMPLATE` — E2B template name for `vm exec` scratch sandboxes. Produced by
  `scratch/vm-experiments/images/build-e2b.ts`.
- `FREESTYLE_SANDBOX_SNAPSHOT` — Freestyle snapshot id for `vm new` / `vm attach`. Produced by
  `scratch/vm-experiments/images/build-freestyle.ts`.
- `CMUX_VM_DEFAULT_PROVIDER` — `freestyle` (default, interactive) or `e2b` (scratch-only).

## Provider matrix

| Verb                        | Freestyle | E2B            |
|-----------------------------|-----------|----------------|
| `cmux vm new` (shell)       | ✓         | error          |
| `cmux vm new --workspace`   | ✓         | error          |
| `cmux vm new --detach`      | ✓         | ✓              |
| `cmux vm attach <id>`       | ✓         | error          |
| `cmux vm exec <id> -- ...`  | ✓         | ✓              |
| `cmux vm ls / rm`           | ✓         | ✓              |

E2B interactive paths return a user-facing error explaining the limitation. See `drivers/e2b.ts`.

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

- Finish the Freestyle driver (today stubbed) and ship the baked snapshot. Unblocks
  `cmux vm new` shell + workspace modes.
- Add `POST /api/vm/:id/ssh-endpoint` that mints short-lived ssh keys per attach session and
  returns `{ host, port, username, privateKeyPem, fingerprint }`. Mac client hands those to the
  existing `cmux ssh` transport — no Next.js tunneling in the data plane.
- Add `/api/vm/:id/pause`, `/api/vm/:id/resume`, `/api/vm/:id/snapshot` REST wrappers once Swift
  client wants them.

See `plans/task-cmux-vm-cloud/cloud-vms-and-per-surface-ssh.md` for the full roadmap and
`plans/task-cmux-vm-cloud/cli-vm-new-shell-and-workspace.md` for the latest CLI shape.
