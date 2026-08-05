import { spawn } from "node:child_process";
import { once } from "node:events";
import { strict as assert } from "node:assert";
import { promises as fs } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { WebSocketServer } from "ws";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const serverPath = process.env.GODOT_MCP_SERVER_PATH ? resolve(process.env.GODOT_MCP_SERVER_PATH) : resolve(root, "server/index.mjs");
const projectPath = resolve(tmpdir(), `godot-mcp-toolkit-editor-binding-${process.pid}`);
const otherProjectPath = resolve(tmpdir(), `godot-mcp-toolkit-editor-binding-other-${process.pid}`);

await fs.mkdir(projectPath, { recursive: true });
await fs.mkdir(otherProjectPath, { recursive: true });
await fs.writeFile(resolve(projectPath, "project.godot"), '[application]\nconfig/name="Editor Binding Test"\n', "utf8");
await fs.writeFile(resolve(otherProjectPath, "project.godot"), '[application]\nconfig/name="Other Editor Binding Test"\n', "utf8");

let boundSessionId = null;
let boundProjectPath = null;
const bridge = new WebSocketServer({ host: "127.0.0.1", port: 0 });
await once(bridge, "listening");
const bridgePort = bridge.address().port;
const bridgeUrl = `ws://127.0.0.1:${bridgePort}`;

function bindingStatus() {
  return {
    mode: "one_to_one",
    bound: Boolean(boundSessionId),
    projectPath: boundProjectPath,
    sessionFingerprint: boundSessionId ? boundSessionId.slice(0, 8) : "",
    leaseSecondsRemaining: boundSessionId ? 90 : 0,
  };
}

bridge.on("connection", (socket) => {
  socket.on("message", (raw) => {
    const request = JSON.parse(raw.toString("utf8"));
    const params = request.params ?? {};
    const send = (ok, result = null, error = "", details = {}) => socket.send(JSON.stringify({ id: request.id, ok, result, error, details }));
    const projectMatches = params.projectPath === projectPath;
    if (!projectMatches) {
      send(false, null, "Editor project does not match the requested MCP project", { code: "project_mismatch", projectPath });
      return;
    }
    if (request.operation === "bind_session") {
      if (boundSessionId && boundSessionId !== params.sessionId) {
        send(false, null, "Editor is already bound to another MCP conversation", { code: "editor_binding_conflict", projectPath, leaseSecondsRemaining: 90 });
        return;
      }
      boundSessionId = params.sessionId;
      boundProjectPath = projectPath;
      send(true, { projectPath, binding: bindingStatus() });
      return;
    }
    if (request.operation === "release_session") {
      if (!boundSessionId) {
        send(true, { released: false, binding: bindingStatus() });
        return;
      }
      if (boundSessionId !== params.sessionId) {
        send(false, null, "Only the bound MCP conversation can release this editor", { code: "editor_binding_conflict", projectPath });
        return;
      }
      boundSessionId = null;
      boundProjectPath = null;
      send(true, { released: true, binding: bindingStatus() });
      return;
    }
    if (!boundSessionId || boundSessionId !== params.sessionId) {
      send(false, null, "Editor is already bound to another MCP conversation", { code: "editor_binding_conflict", projectPath });
      return;
    }
    if (request.operation === "get_editor_info") {
      send(true, { projectPath, bridgePort, binding: bindingStatus(), scenePath: "", selection: [] });
      return;
    }
    send(true, { projectPath, binding: bindingStatus() });
  });
});

function createClient(label) {
  const child = spawn(process.execPath, [serverPath], {
    env: {
      ...process.env,
      GODOT_MCP_ENABLE_EDITOR_BRIDGE: "1",
      GODOT_MCP_EDITOR_URL: bridgeUrl,
      GODOT_MCP_PROJECT: projectPath,
      GODOT_MCP_TOOL_GROUPS: "all",
    },
    stdio: ["pipe", "pipe", "pipe"],
  });
  const messages = new Map();
  let buffer = "";
  let stderr = "";
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", (chunk) => {
    buffer += chunk;
    for (;;) {
      const newline = buffer.indexOf("\n");
      if (newline < 0) break;
      const line = buffer.slice(0, newline).trim();
      buffer = buffer.slice(newline + 1);
      if (line) messages.set(JSON.parse(line).id, JSON.parse(line));
    }
  });
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  let requestId = 1;
  const waitFor = async (id) => {
    const started = Date.now();
    while (!messages.has(id)) {
      if (Date.now() - started > 3000) throw new Error(`${label} timed out waiting for ${id}: ${stderr}`);
      await new Promise((resolvePromise) => setTimeout(resolvePromise, 10));
    }
    return messages.get(id);
  };
  const request = async (method, params) => {
    const id = requestId;
    requestId += 1;
    child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
    return waitFor(id);
  };
  const initialize = async () => {
    const response = await request("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: label, version: "0" } });
    assert.equal(response.result.serverInfo.name, "godot-mcp-toolkit");
  };
  const call = async (name, args = {}) => {
    const response = await request("tools/call", { name, arguments: args });
    if (response.result.isError) return { error: response.result.content[0].text };
    return { value: JSON.parse(response.result.content[0].text) };
  };
  return { child, request, initialize, call };
}

async function stopClient(client) {
  client.child.stdin.end();
  await once(client.child, "close");
}

let firstClient;
let secondClient;
try {
  firstClient = createClient("first");
  secondClient = createClient("second");
  await firstClient.initialize();
  await secondClient.initialize();

  const listing = await firstClient.request("tools/list", {});
  const toolNames = new Set(listing.result.tools.map((tool) => tool.name));
  for (const name of ["bind_editor", "get_editor_binding", "release_editor_binding", "create_2d_camera", "create_2d_light", "create_ui_component", "configure_stylized_rendering", "edit_animation_state_machine", "edit_animation_curve", "configure_animation_timeline", "edit_theme_resource", "assign_editor_resource", "edit_tileset_atlas", "paint_tilemap_terrain", "edit_array_mesh", "edit_skeleton_3d", "edit_skin_resource", "edit_editor_script", "edit_editor_resource", "configure_tileset_terrain", "configure_tileset_proxy", "inspect_editor_imports", "bake_navigation_region", "edit_editor_audio_bus_effects"]) assert.equal(toolNames.has(name), true, name);

  const initialBinding = await firstClient.call("get_editor_binding");
  assert.equal(initialBinding.value.bound, false);

  const firstBinding = await firstClient.call("bind_editor");
  assert.equal(firstBinding.value.binding.bound, true);
  assert.equal(firstBinding.value.projectPath, projectPath);

  const firstInfo = await firstClient.call("get_editor_info");
  assert.equal(firstInfo.value.projectPath, projectPath);
  assert.equal(firstInfo.value.binding.bound, true);

  const projectSwitch = await firstClient.call("get_editor_info", { projectPath: otherProjectPath });
  assert.match(projectSwitch.error, /already bound/);

  const secondBindingConflict = await secondClient.call("bind_editor");
  assert.match(secondBindingConflict.error, /already bound to another MCP conversation/);

  const released = await firstClient.call("release_editor_binding");
  assert.equal(released.value.released, true);
  assert.equal(released.value.binding.bound, false);

  const secondBinding = await secondClient.call("bind_editor");
  assert.equal(secondBinding.value.binding.bound, true);

  const firstConflict = await firstClient.call("get_editor_info");
  assert.match(firstConflict.error, /already bound to another MCP conversation/);

  console.log("Editor binding checks passed");
} finally {
  if (firstClient) await stopClient(firstClient);
  if (secondClient) await stopClient(secondClient);
  await new Promise((resolvePromise) => bridge.close(resolvePromise));
  await fs.rm(projectPath, { recursive: true, force: true });
  await fs.rm(otherProjectPath, { recursive: true, force: true });
}
