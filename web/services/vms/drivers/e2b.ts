import { Sandbox } from "e2b";
import {
  NotImplementedError,
  ProviderError,
  type CreateOptions,
  type ExecResult,
  type SSHEndpoint,
  type SnapshotRef,
  type VMHandle,
  type VMProvider,
} from "./types";

// Default cmux-sandbox template. Built from scratch/vm-experiments/images/build-e2b.ts and
// kept in sync via the E2B_SANDBOX_TEMPLATE env var. The template already bakes sshd, mutagen-agent,
// git, and the `cmux` user; sshd is started on demand by openSSH (not as the E2B start command,
// because E2B sandboxes run unprivileged and can't bind port 22).
const DEFAULT_TEMPLATE = process.env.E2B_SANDBOX_TEMPLATE ?? "cmux-sandbox:v0-71a954b8e53b";

export class E2BProvider implements VMProvider {
  readonly id = "e2b" as const;

  async create(options: CreateOptions): Promise<VMHandle> {
    const image = options.image || DEFAULT_TEMPLATE;
    try {
      const sandbox = await Sandbox.create(image);
      return {
        provider: "e2b",
        providerVmId: sandbox.sandboxId,
        status: "running",
        image,
        createdAt: Date.now(),
      };
    } catch (err) {
      throw new ProviderError("e2b", `create(${image}) failed`, err);
    }
  }

  async destroy(vmId: string): Promise<void> {
    await Sandbox.kill(vmId);
  }

  async pause(vmId: string): Promise<void> {
    await Sandbox.pause(vmId);
  }

  async resume(vmId: string): Promise<VMHandle> {
    const sbx = await Sandbox.connect(vmId);
    const info = await Sandbox.getInfo(vmId);
    return {
      provider: "e2b",
      providerVmId: sbx.sandboxId,
      status: "running",
      image: info.templateId,
      createdAt: info.startedAt.getTime(),
    };
  }

  async exec(vmId: string, command: string, opts?: { timeoutMs?: number }): Promise<ExecResult> {
    const sbx = await Sandbox.connect(vmId);
    const r = await sbx.commands.run(command, {
      timeoutMs: opts?.timeoutMs ?? 30_000,
    });
    return { exitCode: r.exitCode, stdout: r.stdout, stderr: r.stderr };
  }

  async snapshot(vmId: string, name?: string): Promise<SnapshotRef> {
    const sbx = await Sandbox.connect(vmId);
    const snap = await sbx.createSnapshot();
    const id =
      (snap as { snapshotId?: string }).snapshotId ??
      (snap as { snapshot_id?: string }).snapshot_id ??
      JSON.stringify(snap);
    return { id, createdAt: Date.now(), name };
  }

  async restore(snapshotId: string): Promise<VMHandle> {
    const sbx = await Sandbox.create(snapshotId);
    return {
      provider: "e2b",
      providerVmId: sbx.sandboxId,
      status: "running",
      image: snapshotId,
      createdAt: Date.now(),
    };
  }

  async openSSH(_vmId: string): Promise<SSHEndpoint> {
    // E2B sandboxes expose ports only via https://<port>-<sandbox-id>.e2b.app — they don't
    // route raw TCP/22 from outside, so mac client can't SSH directly into an E2B VM.
    // cmux's interactive paths (`cmux vm new` shell, `cmux vm new --workspace`) require
    // direct SSH + cmuxd-remote, so we surface a user-facing error. Use --provider freestyle
    // for interactive work, or --provider e2b --detach for scratch `vm exec` use.
    throw new ProviderError(
      "e2b",
      "E2B sandboxes don't support interactive attach (no raw TCP egress). " +
        "Use `cmux vm new` without `--provider e2b` (Freestyle is the default), " +
        "or `cmux vm new --provider e2b --detach` to create without attach, " +
        "then `cmux vm exec <id> -- <cmd>`.",
    );
  }
}
