import assert from "node:assert/strict";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { apply, findHookBinary, normalizeTool, normalizeToolInput } from "../cctop-dsh.mjs";

// A fake cctop-hook that logs each call as "<event>\t<stdin json>".
function createHookHome() {
  const home = mkdtempSync(join(tmpdir(), "cctop-dsh-plugin-"));
  const hookDir = join(home, ".cctop", "bin");
  mkdirSync(hookDir, { recursive: true });
  const hookLog = join(home, "hook.log");
  writeFileSync(hookLog, "");
  const hookBin = join(hookDir, "cctop-hook");
  writeFileSync(
    hookBin,
    `#!/bin/sh
printf '%s\\t' "$1" >> ${JSON.stringify(hookLog)}
cat >> ${JSON.stringify(hookLog)}
printf '\\n' >> ${JSON.stringify(hookLog)}
`,
  );
  chmodSync(hookBin, 0o755);
  return { home, hookLog };
}

function loadPlugin() {
  const { home, hookLog } = createHookHome();
  const previousHome = process.env.HOME;
  process.env.HOME = home;
  const listeners = new Map();
  const prepended = new Set();
  apply({
    on(event, listener, prepend) {
      listeners.set(event, listener);
      if (prepend) prepended.add(event);
    },
  });
  process.env.HOME = previousHome;
  return {
    listeners,
    prepended,
    emit: (event, ...args) => listeners.get(event)(...args),
    calls() {
      const log = readFileSync(hookLog, "utf8").trim();
      if (!log) return [];
      return log.split("\n").map((line) => {
        const [event, json] = line.split("\t");
        return { event, payload: JSON.parse(json) };
      });
    },
  };
}

const agent = (overrides = {}) => ({
  session: { header: { id: "session-abc", cwd: "/tmp/project", ...overrides } },
});
const next = async () => "decided";

test("reports a turn from start to finish", async () => {
  const plugin = loadPlugin();
  plugin.emit("agent/created", { agent: agent(), source: "fresh" });
  plugin.emit("agent/inbox/claimed", { agent: agent(), message: { content: "fix the build" }, turn: 1 });
  assert.equal(await plugin.emit("tools/pre-execute", { agent: agent(), name: "bash", arguments: { command: "make" } }, next), "decided");
  assert.equal(await plugin.emit("tools/post-execute", { agent: agent(), name: "bash" }, {}, next), "decided");
  plugin.emit("agent/status", { agent: agent(), status: "running" });
  plugin.emit("agent/status", { agent: agent(), status: "idle" });
  plugin.emit("agent/disposed", { agent: agent() });

  const calls = plugin.calls();
  assert.deepEqual(calls.map((call) => call.event), [
    "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "SessionEnd",
  ]);
  for (const { payload } of calls) {
    assert.equal(payload.session_id, "session-abc");
    assert.equal(payload.cwd, "/tmp/project");
    assert.equal(payload.harness_name, "dsh");
  }
  assert.equal(calls[1].payload.prompt, "fix the build");
  assert.equal(calls[2].payload.tool_name, "Bash");
  assert.deepEqual(calls[2].payload.tool_input, { command: "make" });
});

test("approvals and questions mark the session as waiting, ahead of other listeners", async () => {
  const plugin = loadPlugin();
  assert.ok(plugin.prepended.has("approval/request"));
  assert.ok(plugin.prepended.has("user-questions/request"));
  assert.equal(await plugin.emit("approval/request", { agent: agent(), toolName: "write" }, next), "decided");
  assert.equal(await plugin.emit("user-questions/request", { agent: agent(), questions: [] }, next), "decided");
  assert.deepEqual(plugin.calls().map(({ event, payload }) => [event, payload.tool_name]), [
    ["PermissionRequest", "Write"],
    ["PreToolUse", "AskUserQuestion"],
  ]);
});

test("subagent sessions and agents without a session stay out of cctop", async () => {
  const plugin = loadPlugin();
  plugin.emit("agent/created", { agent: agent({ origin: "subagent" }) });
  plugin.emit("agent/created", { agent: {} });
  assert.equal(await plugin.emit("tools/pre-execute", { name: "bash", arguments: {} }, next), "decided");
  assert.deepEqual(plugin.calls(), []);
});

test("finds cctop-hook in the user's cctop folder first, else nowhere", () => {
  assert.equal(findHookBinary("/home/u", (path) => path === "/home/u/.cctop/bin/cctop-hook"), "/home/u/.cctop/bin/cctop-hook");
  assert.equal(findHookBinary("/home/u", () => false), null);
});

test("tool names and arguments match what cctop shows for Claude Code", () => {
  assert.equal(normalizeTool("web_fetch"), "WebFetch");
  assert.equal(normalizeTool("str_replace_editor"), "Edit");
  assert.equal(normalizeTool("custom_tool"), "Custom_tool");
  assert.deepEqual(normalizeToolInput({ path: "a.txt", limit: 3 }), { file_path: "a.txt" });
  assert.equal(normalizeToolInput(null), undefined);
});
