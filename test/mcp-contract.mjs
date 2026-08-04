import { spawn } from "node:child_process";
import { once } from "node:events";
import { strict as assert } from "node:assert";
import { promises as fs } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const activeProjectFile = resolve(tmpdir(), `godot-mcp-toolkit-active-${process.pid}.json`);
const serverPath = process.env.GODOT_MCP_SERVER_PATH ? resolve(process.env.GODOT_MCP_SERVER_PATH) : resolve(root, "server/index.mjs");
const child = spawn(process.execPath, [serverPath], { env: { ...process.env, GODOT_MCP_ACTIVE_PROJECT_FILE: activeProjectFile }, stdio: ["pipe", "pipe", "pipe"] });
let buffer = "";
const messages = new Map();
child.stdout.setEncoding("utf8");
child.stdout.on("data", (chunk) => {
  buffer += chunk;
  for (;;) {
    const newline = buffer.indexOf("\n");
    if (newline < 0) break;
    const line = buffer.slice(0, newline).trim();
    buffer = buffer.slice(newline + 1);
    if (!line) continue;
    const message = JSON.parse(line);
    messages.set(message.id, message);
  }
});

function send(message) {
  child.stdin.write(`${JSON.stringify(message)}\n`);
}

async function waitFor(id) {
  const started = Date.now();
  while (!messages.has(id)) {
    if (Date.now() - started > 3000) throw new Error(`Timed out waiting for message ${id}`);
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 10));
  }
  return messages.get(id);
}

send({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "0" } } });
const initialized = await waitFor(1);
assert.equal(initialized.result.serverInfo.name, "godot-mcp-toolkit");
send({ jsonrpc: "2.0", id: 2, method: "tools/list", params: {} });
const listing = await waitFor(2);
const names = new Set(listing.result.tools.map((entry) => entry.name));
for (const name of [
  "create_project",
  "get_project_info",
  "inspect_scene_tree",
  "inspect_node",
  "create_script",
  "analyze_script",
  "run_project",
  "capture_screenshot",
  "create_ui_node",
  "create_animation",
  "inspect_tilemaps",
  "simulate_input",
  "run_automation_test",
  "list_resources",
  "profile_scene",
  "get_game_context",
]) assert.equal(names.has(name), true, name);

assert.equal(names.has("get_editor_info"), false, "Live editor tools stay opt-in");
let requestId = 3;
async function callTool(name, args) {
  const id = requestId;
  requestId += 1;
  send({ jsonrpc: "2.0", id, method: "tools/call", params: { name, arguments: args } });
  const response = await waitFor(id);
  assert.equal(response.result?.isError, false, response.result?.content?.[0]?.text ?? name);
  return JSON.parse(response.result.content[0].text);
}

const projectPath = resolve(tmpdir(), `godot-mcp-toolkit-contract-${process.pid}`);
await fs.rm(projectPath, { recursive: true, force: true });
const created = await callTool("create_project", { projectPath, name: "Contract Test" });
assert.equal(created.created, true);
const info = await callTool("get_project_info", { projectPath });
assert.equal(info.name, "Contract Test");
await fs.writeFile(activeProjectFile, JSON.stringify({ projectPath }), "utf8");
const defaultInfo = await callTool("get_project_info", {});
assert.equal(defaultInfo.name, "Contract Test");
assert.equal(listing.result.tools.find((entry) => entry.name === "get_project_info").inputSchema.required?.includes("projectPath") ?? false, false);
await callTool("write_file", { projectPath, path: "scripts/test.gd", content: "extends Node\n" });
const file = await callTool("read_file", { projectPath, path: "scripts/test.gd" });
assert.equal(file.content, "extends Node\n");
send({ jsonrpc: "2.0", id: requestId, method: "tools/call", params: { name: "read_file", arguments: { projectPath, path: "../outside.txt" } } });
const traversal = await waitFor(requestId);
requestId += 1;
assert.equal(traversal.result.isError, true);
const context = await callTool("get_game_context", { projectPath });
assert.equal(context.project.name, "Contract Test");
send({ jsonrpc: "2.0", id: requestId, method: "tools/call", params: { name: "get_editor_info", arguments: {} } });
const editorUnavailable = await waitFor(requestId);
requestId += 1;
assert.equal(editorUnavailable.result.isError, true);
await fs.rm(projectPath, { recursive: true, force: true });
await fs.rm(activeProjectFile, { force: true });
child.stdin.end();
await once(child, "close");
console.log(`MCP contract checks passed (${listing.result.tools.length} tools)`);

