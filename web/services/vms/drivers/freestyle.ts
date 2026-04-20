import {
  NotImplementedError,
  type CreateOptions,
  type ExecResult,
  type SSHEndpoint,
  type SnapshotRef,
  type VMHandle,
  type VMProvider,
} from "./types";

// Stub. The upstream Freestyle snapshot-import step was hanging during M0 so we skipped
// shipping this driver. Flip by replacing method bodies with calls to the `freestyle` SDK
// once the baked snapshot lands (see scratch/vm-experiments/FINDINGS.md).
export class FreestyleProvider implements VMProvider {
  readonly id = "freestyle" as const;

  async create(_options: CreateOptions): Promise<VMHandle> {
    throw new NotImplementedError("freestyle", "create");
  }
  async destroy(_vmId: string): Promise<void> {
    throw new NotImplementedError("freestyle", "destroy");
  }
  async pause(_vmId: string): Promise<void> {
    throw new NotImplementedError("freestyle", "pause");
  }
  async resume(_vmId: string): Promise<VMHandle> {
    throw new NotImplementedError("freestyle", "resume");
  }
  async exec(_vmId: string, _cmd: string, _opts?: { timeoutMs?: number }): Promise<ExecResult> {
    throw new NotImplementedError("freestyle", "exec");
  }
  async snapshot(_vmId: string, _name?: string): Promise<SnapshotRef> {
    throw new NotImplementedError("freestyle", "snapshot");
  }
  async restore(_snapshotId: string): Promise<VMHandle> {
    throw new NotImplementedError("freestyle", "restore");
  }
  async openSSH(_vmId: string): Promise<SSHEndpoint> {
    throw new NotImplementedError("freestyle", "openSSH");
  }
}
