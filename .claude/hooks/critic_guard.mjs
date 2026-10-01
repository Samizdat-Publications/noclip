// Guard for the player-critic subagent.
// Runs as a PreToolUse hook defined in .claude/agents/player-critic.md, so it only fires
// while that subagent is active. It blocks any tool call that reaches outside review/inbox.
// Exit code 2 blocks the call and sends stderr back to the critic.
import path from "node:path";

let raw = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (c) => (raw += c));
process.stdin.on("end", () => {
  let input;
  try {
    input = JSON.parse(raw);
  } catch {
    block("Guard could not parse tool input.");
  }

  const tool = input.tool_name || "";
  const ti = input.tool_input || {};
  const cwd = input.cwd || process.cwd();
  const inbox = norm(path.resolve(cwd, "review", "inbox"));

  const inside = (p) => {
    if (!p) return false;
    const abs = norm(path.resolve(cwd, p));
    return abs === inbox || abs.startsWith(inbox + "/");
  };

  if (tool === "Read") {
    if (inside(ti.file_path)) allow();
    block(`Blocked: you can only look at files inside review/inbox/. (${ti.file_path})`);
  }

  if (tool === "Glob") {
    const pattern = String(ti.pattern || "");
    if (pattern.includes("..")) block("Blocked: stay inside review/inbox/.");
    if (ti.path) {
      if (inside(ti.path)) allow();
      block("Blocked: you can only search inside review/inbox/.");
    }
    if (path.isAbsolute(pattern) ? inside(pattern.split("*")[0]) : norm(pattern).startsWith("review/inbox/")) allow();
    block("Blocked: you can only search inside review/inbox/. Use a pattern like review/inbox/**/*");
  }

  block(`Blocked: the ${tool} tool is not available to you. Use Read and Glob on review/inbox/ only.`);
});

function norm(p) {
  let s = String(p).replace(/\\/g, "/");
  if (process.platform === "win32") s = s.toLowerCase();
  return s.replace(/\/+$/, "");
}
function allow() {
  process.exit(0);
}
function block(msg) {
  process.stderr.write(msg + "\n");
  process.exit(2);
}
