// cmux-feed-plugin-marker v1
// Bridges OpenCode's plugin event bus to the cmux socket's feed.* verbs.
// Installed by `cmux setup-hooks` or `cmux opencode install-hooks`.
// DO NOT EDIT MANUALLY — cmux upgrades this file in place.

const net = require("node:net");
const os = require("node:os");

const DEFAULT_SOCKET = `${os.homedir()}/.config/cmux/cmux.sock`;
const SOCKET_PATH = process.env.CMUX_SOCKET_PATH || DEFAULT_SOCKET;
const REPLY_TIMEOUT_MS = 120_000;

export const CMUXFeed = async (ctx) => {
  let client = null;
  let buffered = "";
  const pending = new Map();

  const connect = () => {
    try {
      const conn = net.createConnection(SOCKET_PATH);
      conn.setEncoding("utf8");
      conn.on("data", (chunk) => {
        buffered += chunk;
        let idx;
        while ((idx = buffered.indexOf("\n")) >= 0) {
          const line = buffered.slice(0, idx);
          buffered = buffered.slice(idx + 1);
          if (!line) continue;
          try {
            const msg = JSON.parse(line);
            // The socket sends either V2 responses (id/ok/result/error)
            // or push frames keyed by request_id. We only care about
            // results whose result.decision matches a waiter.
            const requestId = msg?.result?.request_id || msg?.request_id;
            if (requestId && pending.has(requestId)) {
              const resolver = pending.get(requestId);
              pending.delete(requestId);
              resolver(msg.result || msg);
            }
          } catch (e) {
            // swallow — malformed line, keep the connection alive.
          }
        }
      });
      conn.on("close", () => { client = null; });
      conn.on("error", () => { client = null; });
      return conn;
    } catch (e) {
      return null;
    }
  };

  const write = (frame) => {
    if (!client) client = connect();
    if (!client) return;
    try {
      client.write(JSON.stringify(frame) + "\n");
    } catch (e) { /* ignore */ }
  };

  const base = (sessionId, extra) => ({
    session_id: `opencode-${sessionId}`,
    _source: "opencode",
    _ppid: process.pid,
    cwd: ctx?.directory,
    ...extra,
  });

  const pushBlocking = (event, requestId) => {
    const reply = new Promise((resolve) => {
      pending.set(requestId, resolve);
      setTimeout(() => {
        if (pending.has(requestId)) {
          pending.delete(requestId);
          resolve({ status: "timed_out" });
        }
      }, REPLY_TIMEOUT_MS);
    });
    write({
      id: `opencode-${requestId}`,
      method: "feed.push",
      params: { event, wait_timeout_seconds: REPLY_TIMEOUT_MS / 1000 },
    });
    return reply;
  };

  const pushTelemetry = (event) => {
    write({
      id: `opencode-telemetry-${Date.now()}`,
      method: "feed.push",
      params: { event, wait_timeout_seconds: 0 },
    });
  };

  return {
    event: async ({ event }) => {
      switch (event.type) {
        case "session.created": {
          const info = event.properties?.info || {};
          pushTelemetry(base(info.id || "unknown", {
            hook_event_name: "SessionStart",
          }));
          break;
        }
        case "session.idle": {
          const sid = event.properties?.sessionID;
          if (!sid) break;
          pushTelemetry(base(sid, {
            hook_event_name: "Stop",
          }));
          break;
        }
        case "session.deleted": {
          const sid = event.properties?.info?.id;
          if (!sid) break;
          pushTelemetry(base(sid, {
            hook_event_name: "SessionEnd",
          }));
          break;
        }
        case "todo.updated": {
          const sid = event.properties?.sessionID;
          if (!sid) break;
          pushTelemetry(base(sid, {
            hook_event_name: "TodoWrite",
            tool_input: event.properties?.todos || [],
          }));
          break;
        }
        case "permission.asked": {
          const props = event.properties || {};
          const requestId = props.id;
          if (!requestId) break;
          const sid = props.sessionID || "unknown";
          const frame = base(sid, {
            hook_event_name: "PermissionRequest",
            _opencode_request_id: requestId,
            tool_name: props.tool,
            tool_input: props.input,
          });
          const result = await pushBlocking(frame, requestId);
          if (result?.status === "resolved" && result.decision?.kind === "permission") {
            const mode = result.decision.mode;
            const response = mode === "deny" ? "deny" : "approve";
            const remember = (mode === "always" || mode === "all" || mode === "bypass");
            try {
              await ctx.client.session.permissions({
                path: { id: sid, permissionID: requestId },
                body: { response, remember },
              });
            } catch (e) { /* ignore — opencode already moved on */ }
          }
          break;
        }
        default:
          // Non-Feed-worthy events pass silently to keep the plugin cheap.
          break;
      }
    },
  };
};
