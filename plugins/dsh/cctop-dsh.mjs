// cctop plugin for DeepSeek Harness (dsh): a Cordis plugin that reports session lifecycle to
// cctop-hook. Zero dependencies. cctop installs it by appending an `insert` row to
// ~/.dsh/cordis.patch.yml that names this file by absolute path.

import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export const name = "cctop";

// dsh tool names are lowercase; cctop shows Claude Code's names.
const TOOL_NAME_MAP = {
  bash: "Bash",
  read: "Read",
  edit: "Edit",
  str_replace_editor: "Edit",
  write: "Write",
  glob: "Glob",
  grep: "Grep",
  web_fetch: "WebFetch",
  web_search: "WebSearch",
  todo_write: "TodoWrite",
  ask_user_question: "AskUserQuestion",
};

export function findHookBinary(home = homedir(), exists = existsSync) {
  const candidates = [
    join(home, ".cctop/bin/cctop-hook"),
    "/Applications/AgentTally.app/Contents/MacOS/cctop-hook",
    join(home, "Applications/AgentTally.app/Contents/MacOS/cctop-hook"),
  ];
  return candidates.find((path) => exists(path)) ?? null;
}

export function normalizeTool(toolName) {
  if (!toolName) return null;
  const lower = String(toolName).toLowerCase();
  return TOOL_NAME_MAP[lower] ?? lower.charAt(0).toUpperCase() + lower.slice(1);
}

// cctop shows one string argument per tool (the command, the path, the pattern).
export function normalizeToolInput(args) {
  if (!args || typeof args !== "object") return undefined;
  const result = {};
  for (const [key, value] of Object.entries(args)) {
    if (typeof value === "string") result[key === "filePath" || key === "path" ? "file_path" : key] = value;
  }
  return Object.keys(result).length > 0 ? result : undefined;
}

function messageText(message) {
  const content = message?.content;
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    const text = content.map((part) => (typeof part?.text === "string" ? part.text : "")).join("");
    return text || undefined;
  }
  return undefined;
}

export function apply(ctx) {
  const hookBin = findHookBinary();
  if (!hookBin) return;

  // Subagents run as child sessions; only the user's own session belongs in cctop.
  const send = (event, agent, extra = {}) => {
    const header = agent?.session?.header;
    if (!header?.id || header.origin === "subagent") return;
    try {
      execFileSync(hookBin, [event], {
        input: JSON.stringify({
          session_id: header.id,
          cwd: header.cwd ?? process.cwd(),
          hook_event_name: event,
          harness_name: "dsh",
          ...extra,
        }),
        timeout: 5000,
        stdio: ["pipe", "ignore", "ignore"],
      });
    } catch {
      // Best effort: never disturb the dsh process.
    }
  };

  ctx.on("agent/created", ({ agent }) => {
    send("SessionStart", agent);
  });

  // One user message entering a turn: the user asked for work.
  ctx.on("agent/inbox/claimed", ({ agent, message }) => {
    const prompt = messageText(message);
    send("UserPromptSubmit", agent, prompt ? { prompt } : {});
  });

  ctx.on("tools/pre-execute", async (exec, next) => {
    const toolInput = normalizeToolInput(exec?.arguments);
    send("PreToolUse", exec?.agent, {
      tool_name: normalizeTool(exec?.name),
      ...(toolInput && { tool_input: toolInput }),
    });
    return next();
  });

  ctx.on("tools/post-execute", async (exec, _result, next) => {
    send("PostToolUse", exec?.agent, { tool_name: normalizeTool(exec?.name) });
    return next();
  });

  // Prepended: another listener may answer the request and end the chain before us.
  ctx.on("approval/request", async (request, next) => {
    send("PermissionRequest", request?.agent, { tool_name: normalizeTool(request?.toolName) });
    return next();
  }, true);

  ctx.on("user-questions/request", async (request, next) => {
    send("PreToolUse", request?.agent, { tool_name: "AskUserQuestion" });
    return next();
  }, true);

  // `idle` means nothing is scheduled or running: the turn is over.
  ctx.on("agent/status", ({ agent, status }) => {
    if (status === "idle") send("Stop", agent);
  });

  ctx.on("agent/disposed", ({ agent }) => {
    send("SessionEnd", agent);
  });
}
