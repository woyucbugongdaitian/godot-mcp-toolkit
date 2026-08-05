import { createInterface } from "node:readline";
import { spawn, spawnSync } from "node:child_process";
import { createWriteStream, existsSync, promises as fs, readFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, dirname, extname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { randomUUID } from "node:crypto";

const SERVER_NAME = "godot-mcp-toolkit";
const SERVER_VERSION = "0.3.0";
const PROTOCOL_VERSION = "2025-06-18";
const SUPPORTED_PROTOCOL_VERSIONS = new Set(["2025-06-18", "2025-03-26", "2024-11-05"]);
const MAX_FILE_BYTES = 2 * 1024 * 1024;
const MAX_SEARCH_RESULTS = 200;
const projectProcesses = new Map();
const editorProjectPorts = new Map();
const runtimeProjectPorts = new Map();
const EDITOR_BINDING_MODE = "one_to_one";
const editorSessionId = getEditorSessionId();
let editorBinding = null;
let runtimeBinding = null;
const runtimeDirectory = join(tmpdir(), "godot-mcp-toolkit");
const moduleDirectory = dirname(fileURLToPath(import.meta.url));
const operationScript = resolveOperationScript(moduleDirectory);

const coreTools = [
  tool("get_server_info", "Return server capabilities and runtime information.", {
    type: "object",
    properties: {},
    additionalProperties: false,
  }, async () => getServerInfo()),
  tool("get_capabilities", "Return versioned feature groups and compatibility information.", {
    type: "object",
    properties: {},
    additionalProperties: false,
  }, async () => getCapabilities()),
  ...createEditorTools(),
  ...createUiEffectTools(),
  ...createAdvancedEditorTools(),
  ...createRuntimeTools(),
  tool("get_godot_version", "Read the installed Godot version.", {
    type: "object",
    properties: { godotBinary: { type: "string" } },
    additionalProperties: false,
  }, async ({ godotBinary }) => runGodotVersion(godotBinary)),
  tool("list_projects", "Find Godot projects below a directory.", {
    type: "object",
    properties: {
      root: { type: "string", description: "Directory to scan. Defaults to the current working directory." },
      maxDepth: { type: "integer", minimum: 0, maximum: 8, default: 3 },
    },
    additionalProperties: false,
  }, async ({ root = process.cwd(), maxDepth = 3 }) => listProjects(root, maxDepth)),
  tool("get_project_info", "Read project.godot metadata and selected settings.", projectSchema(), async ({ projectPath }) => getProjectInfo(requireProject(projectPath))),
  tool("create_project", "Create a minimal Godot 4 project with a project.godot file.", {
    type: "object",
    required: ["projectPath"],
    properties: {
      projectPath: { type: "string" },
      name: { type: "string" },
      renderer: { type: "string", enum: ["gl_compatibility", "mobile", "forward_plus"], default: "gl_compatibility" },
      createMainScene: { type: "boolean", default: true },
    },
    additionalProperties: false,
  }, async ({ projectPath, name, renderer = "gl_compatibility", createMainScene = true }) => createProject(projectPath, name, renderer, createMainScene)),
  tool("set_project_setting", "Set a project.godot setting using section/key notation.", {
    type: "object",
    required: ["projectPath", "setting", "value"],
    properties: {
      projectPath: { type: "string" },
      setting: { type: "string", description: "Examples: application/config/name or display/window/size/viewport_width." },
      value: {},
    },
    additionalProperties: false,
  }, async ({ projectPath, setting, value }) => setProjectSetting(requireProject(projectPath), setting, value)),
  tool("list_files", "List project files with safe, project-relative paths.", {
    type: "object",
    required: ["projectPath"],
    properties: {
      projectPath: { type: "string" },
      path: { type: "string", default: "." },
      recursive: { type: "boolean", default: true },
      extensions: { type: "array", items: { type: "string" } },
      maxResults: { type: "integer", minimum: 1, maximum: 2000, default: 500 },
    },
    additionalProperties: false,
  }, async ({ projectPath, path = ".", recursive = true, extensions, maxResults = 500 }) => listFiles(requireProject(projectPath), path, recursive, extensions, maxResults)),
  tool("read_file", "Read a UTF-8 text file inside a Godot project.", {
    type: "object",
    required: ["projectPath", "path"],
    properties: { projectPath: { type: "string" }, path: { type: "string" } },
    additionalProperties: false,
  }, async ({ projectPath, path }) => readProjectFile(requireProject(projectPath), path)),
  tool("write_file", "Write a UTF-8 text file inside a Godot project.", {
    type: "object",
    required: ["projectPath", "path", "content"],
    properties: {
      projectPath: { type: "string" },
      path: { type: "string" },
      content: { type: "string" },
      createDirectories: { type: "boolean", default: true },
    },
    additionalProperties: false,
  }, async ({ projectPath, path, content, createDirectories = true }) => writeProjectFile(requireProject(projectPath), path, content, createDirectories)),
  tool("list_scenes", "List all .tscn scenes in a project.", {
    type: "object",
    required: ["projectPath"],
    properties: { projectPath: { type: "string" }, path: { type: "string", default: "." } },
    additionalProperties: false,
  }, async ({ projectPath, path = "." }) => listFiles(requireProject(projectPath), path, true, [".tscn"], 2000)),
  tool("duplicate_scene", "Copy a scene to another project-relative .tscn path.", {
    type: "object",
    required: ["projectPath", "sourcePath", "destinationPath"],
    properties: { projectPath: { type: "string" }, sourcePath: { type: "string" }, destinationPath: { type: "string" } },
    additionalProperties: false,
  }, async ({ projectPath, sourcePath, destinationPath }) => duplicateScene(requireProject(projectPath), sourcePath, destinationPath)),
  tool("search_project", "Search UTF-8 project files for a literal or regular expression pattern.", {
    type: "object",
    required: ["projectPath", "pattern"],
    properties: {
      projectPath: { type: "string" },
      pattern: { type: "string" },
      regex: { type: "boolean", default: false },
      path: { type: "string", default: "." },
      extensions: { type: "array", items: { type: "string" } },
      maxResults: { type: "integer", minimum: 1, maximum: MAX_SEARCH_RESULTS, default: 50 },
    },
    additionalProperties: false,
  }, async ({ projectPath, pattern, regex = false, path = ".", extensions, maxResults = 50 }) => searchProject(requireProject(projectPath), pattern, regex, path, extensions, maxResults)),
  tool("check_project", "Run Godot in headless editor mode and return parser/runtime diagnostics.", {
    type: "object",
    required: ["projectPath"],
    properties: {
      projectPath: { type: "string" },
      timeoutMs: { type: "integer", minimum: 1000, maximum: 120000, default: 30000 },
    },
    additionalProperties: false,
  }, async ({ projectPath, timeoutMs = 30000 }) => checkProject(requireProject(projectPath), timeoutMs)),
  tool("launch_editor", "Launch the Godot editor for a project and return its process id.", {
    type: "object",
    required: ["projectPath"],
    properties: { projectPath: { type: "string" }, godotBinary: { type: "string" } },
    additionalProperties: false,
  }, async ({ projectPath, godotBinary }) => launchEditor(requireProject(projectPath), godotBinary)),
  tool("run_project", "Run a Godot project in the background and capture stdout/stderr.", {
    type: "object",
    required: ["projectPath"],
    properties: {
      projectPath: { type: "string" },
      scene: { type: "string", description: "Optional project-relative scene path." },
      godotBinary: { type: "string" },
      headless: { type: "boolean", default: false },
    },
    additionalProperties: false,
  }, async ({ projectPath, scene, godotBinary, headless = false }) => runProject(requireProject(projectPath), scene, godotBinary, headless)),
  tool("get_debug_output", "Read captured output from a background Godot run.", {
    type: "object",
    properties: {
      runId: { type: "string" },
      projectPath: { type: "string" },
      tailLines: { type: "integer", minimum: 1, maximum: 2000, default: 200 },
      clear: { type: "boolean", default: false },
    },
    additionalProperties: false,
  }, async ({ runId, projectPath, tailLines = 200, clear = false }) => getDebugOutput(runId, projectPath, tailLines, clear)),
  tool("stop_project", "Stop a background Godot run.", {
    type: "object",
    properties: { runId: { type: "string" }, projectPath: { type: "string" } },
    additionalProperties: false,
  }, async ({ runId, projectPath }) => stopProject(runId, projectPath)),
  tool("create_scene", "Create and save a minimal Godot scene.", sceneOperationSchema({
    rootType: { type: "string", default: "Node2D" },
    rootName: { type: "string", default: "Main" },
  }), async (params) => runSceneOperation(params, "create_scene")),
  tool("inspect_scene_tree", "Inspect a scene tree recursively without modifying the scene.", sceneOperationSchema({
    maxDepth: { type: "integer", minimum: 0, maximum: 32, default: 8 },
  }), async (params) => runSceneOperation(params, "inspect_scene_tree")),
  tool("inspect_node", "Read a node's serializable Inspector properties.", sceneOperationSchema({
    nodePath: { type: "string", default: "." },
  }), async (params) => runSceneOperation(params, "inspect_node")),
  tool("add_node", "Add a node to a scene and save it.", sceneOperationSchema({
    parentPath: { type: "string", default: "." },
    nodeType: { type: "string" },
    nodeName: { type: "string" },
    properties: { type: "object", additionalProperties: true },
  }, ["nodeType", "nodeName"]), async (params) => runSceneOperation(params, "add_node")),
  tool("remove_node", "Remove a node from a scene and save it.", sceneOperationSchema({
    nodePath: { type: "string" },
  }, ["nodePath"]), async (params) => runSceneOperation(params, "remove_node")),
  tool("set_node_property", "Set a serializable node property and save the scene.", sceneOperationSchema({
    nodePath: { type: "string" },
    property: { type: "string" },
    value: {},
  }, ["nodePath", "property", "value"]), async (params) => runSceneOperation(params, "set_node_property")),
  tool("save_scene", "Load and re-save a scene to validate its serialization.", sceneOperationSchema({}), async (params) => runSceneOperation(params, "save_scene")),
  tool("load_sprite", "Add a Sprite2D using a project-relative texture path.", sceneOperationSchema({
    texturePath: { type: "string" },
    parentPath: { type: "string", default: "." },
    nodeName: { type: "string", default: "Sprite2D" },
  }, ["texturePath"]), async (params) => runSceneOperation(params, "load_sprite")),
  tool("create_ui_node", "Add a Control-derived UI node to a scene with optional layout properties.", sceneOperationSchema({
    parentPath: { type: "string", default: "." },
    nodeType: { type: "string", default: "Control" },
    nodeName: { type: "string" },
    properties: { type: "object", additionalProperties: true },
  }, ["nodeName"]), async (params) => runSceneOperation({ ...params, operation: "add_node" }, "add_node")),
  tool("create_script", "Create a GDScript file with a safe starter template.", {
    type: "object",
    required: ["projectPath", "scriptPath"],
    properties: {
      projectPath: { type: "string" },
      scriptPath: { type: "string" },
      extends: { type: "string", default: "Node" },
      body: { type: "string", default: "" },
      overwrite: { type: "boolean", default: false },
    },
    additionalProperties: false,
  }, async ({ projectPath, scriptPath, extends: baseClass = "Node", body = "", overwrite = false }) => createScript(requireProject(projectPath), scriptPath, baseClass, body, overwrite)),
  tool("attach_script", "Attach a project-relative GDScript to a scene node.", sceneOperationSchema({
    nodePath: { type: "string" },
    scriptPath: { type: "string" },
  }, ["nodePath", "scriptPath"]), async (params) => runSceneOperation({ ...params, property: "script", value: { resourcePath: normalizeProjectPath(params.scriptPath) } }, "set_node_property")),
  tool("analyze_script", "Run Godot's script checker and return diagnostics.", {
    type: "object",
    required: ["projectPath", "scriptPath"],
    properties: { projectPath: { type: "string" }, scriptPath: { type: "string" }, timeoutMs: { type: "integer", minimum: 1000, maximum: 120000, default: 30000 } },
    additionalProperties: false,
  }, async ({ projectPath, scriptPath, timeoutMs = 30000 }) => analyzeScript(requireProject(projectPath), scriptPath, timeoutMs)),
  tool("capture_screenshot", "Render a scene in a controlled viewport and save a PNG inside the project.", sceneOperationSchema({
    outputPath: { type: "string" },
    width: { type: "integer", minimum: 64, maximum: 4096, default: 1280 },
    height: { type: "integer", minimum: 64, maximum: 4096, default: 720 },
  }), async (params) => captureScreenshot(params)),
  tool("create_animation", "Create an empty AnimationPlayer animation resource in a scene.", sceneOperationSchema({
    nodePath: { type: "string", default: "." },
    animationName: { type: "string" },
    length: { type: "number", minimum: 0, default: 1.0 },
  }, ["animationName"]), async (params) => runSceneOperation(params, "create_animation")),
  tool("inspect_animation_players", "Inspect AnimationPlayer nodes and animation names.", sceneOperationSchema({}), async (params) => runSceneOperation(params, "inspect_animation_players")),
  tool("inspect_tilemaps", "Inspect TileMap and TileMapLayer nodes in a scene.", sceneOperationSchema({}), async (params) => runSceneOperation(params, "inspect_tilemaps")),
  tool("set_tile_cell", "Set a TileMap or TileMapLayer cell using Godot's native API.", sceneOperationSchema({
    nodePath: { type: "string" },
    layer: { type: "integer", default: 0 },
    x: { type: "integer" },
    y: { type: "integer" },
    sourceId: { type: "integer" },
    atlasX: { type: "integer", default: 0 },
    atlasY: { type: "integer", default: 0 },
    alternativeTile: { type: "integer", default: 0 },
  }, ["nodePath", "x", "y", "sourceId"]), async (params) => runSceneOperation(params, "set_tile_cell")),
  tool("simulate_input", "Inject a keyboard or mouse input event while a scene runs headlessly.", sceneOperationSchema({
    eventType: { type: "string", enum: ["key", "mouse_button"] },
    keycode: { type: "integer" },
    pressed: { type: "boolean", default: true },
    buttonIndex: { type: "integer", default: 1 },
    durationFrames: { type: "integer", minimum: 1, maximum: 120, default: 3 },
  }, ["eventType"]), async (params) => runSceneOperation(params, "simulate_input")),
  tool("run_automation_test", "Run a project-relative GDScript test in headless mode.", {
    type: "object",
    required: ["projectPath", "testPath"],
    properties: { projectPath: { type: "string" }, testPath: { type: "string" }, timeoutMs: { type: "integer", minimum: 1000, maximum: 300000, default: 60000 } },
    additionalProperties: false,
  }, async ({ projectPath, testPath, timeoutMs = 60000 }) => runAutomationTest(requireProject(projectPath), testPath, timeoutMs)),
  tool("list_resources", "List project resources filtered by extension.", {
    type: "object",
    required: ["projectPath"],
    properties: { projectPath: { type: "string" }, extensions: { type: "array", items: { type: "string" } }, path: { type: "string", default: "." } },
    additionalProperties: false,
  }, async ({ projectPath, extensions, path = "." }) => listFiles(requireProject(projectPath), path, true, extensions, 2000)),
  tool("find_resource_references", "Find text references to a project-relative resource path.", {
    type: "object",
    required: ["projectPath", "resourcePath"],
    properties: { projectPath: { type: "string" }, resourcePath: { type: "string" }, maxResults: { type: "integer", minimum: 1, maximum: 200, default: 100 } },
    additionalProperties: false,
  }, async ({ projectPath, resourcePath, maxResults = 100 }) => searchProject(requireProject(projectPath), resourcePath, false, ".", [".tscn", ".tres", ".gd", ".godot", ".cfg"], maxResults)),
  tool("profile_scene", "Collect lightweight frame and memory counters for a scene.", sceneOperationSchema({
    frames: { type: "integer", minimum: 1, maximum: 300, default: 60 },
  }), async (params) => runSceneOperation(params, "profile_scene")),
  tool("get_game_context", "Build a compact project graph for AI-assisted game understanding.", {
    type: "object",
    required: ["projectPath"],
    properties: { projectPath: { type: "string" }, includeScripts: { type: "boolean", default: true }, maxFiles: { type: "integer", minimum: 1, maximum: 500, default: 200 } },
    additionalProperties: false,
  }, async ({ projectPath, includeScripts = true, maxFiles = 200 }) => getGameContext(requireProject(projectPath), includeScripts, maxFiles)),
  tool("get_uid", "Read a resource UID using Godot's resource database.", {
    type: "object",
    required: ["projectPath", "resourcePath"],
    properties: { projectPath: { type: "string" }, resourcePath: { type: "string" } },
    additionalProperties: false,
  }, async (params) => runSceneOperation(params, "get_uid")),
  tool("update_project_uids", "Ask Godot to refresh resource UIDs for a project.", {
    type: "object",
    required: ["projectPath"],
    properties: { projectPath: { type: "string" } },
    additionalProperties: false,
  }, async (params) => runSceneOperation(params, "update_project_uids")),
];

const extensionTools = await loadExtensionTools();
const coreToolNames = new Set(coreTools.map((entry) => entry.name));
const extensionToolNames = new Set();
for (const extensionTool of extensionTools) {
  if (coreToolNames.has(extensionTool.name) || extensionToolNames.has(extensionTool.name)) throw new Error(`Duplicate MCP tool name: ${extensionTool.name}`);
  extensionToolNames.add(extensionTool.name);
}
const tools = [...coreTools, ...extensionTools];
const toolMap = new Map(tools.map((entry) => [entry.name, entry]));

const TOOL_GROUPS = {
  editor: ["bind_editor", "get_editor_binding", "release_editor_binding", "get_editor_info", "get_editor_scene_tree", "open_scene", "save_current_scene", "play_current_scene", "stop_running_scene", "get_editor_selection", "select_editor_nodes", "clear_editor_selection", "add_editor_node", "delete_editor_node", "duplicate_editor_node", "move_editor_node", "rename_editor_node", "get_editor_node_properties", "set_editor_property", "capture_editor_screenshot", "reload_editor_filesystem", "execute_editor_script", "get_editor_logs", "undo_editor", "redo_editor"],
  ui: ["create_ui_screen", "configure_control_layout", "set_theme_override", "inspect_ui_layout"],
  effects: ["create_particles", "configure_particles", "create_shader_effect", "set_shader_parameter", "create_screen_flash", "create_post_process", "configure_stylized_rendering", "create_animation_effect", "set_canvas_modulate", "inspect_visual_effects"],
  advanced_editor: ["get_script_editor_state","open_editor_script","goto_editor_script_line","get_editor_breakpoints","save_editor_scripts","get_editor_debugger_state","create_primitive_mesh","create_3d_camera","create_3d_light","create_2d_camera","create_2d_light","create_ui_component","set_editor_transform","inspect_3d_scene","create_standard_material","assign_editor_material","create_animation_track","set_animation_key","inspect_animation_timeline","set_animation_tree_state","create_navigation_node","configure_navigation_agent","inspect_navigation","create_collision_shape","configure_physics_node","inspect_physics","get_editor_audio_buses","set_editor_audio_bus","configure_editor_audio_player","inspect_editor_audio_nodes","create_theme_resource","list_editor_plugins","set_editor_plugin_enabled","get_editor_workspace","set_editor_main_screen","set_distraction_free_mode","reimport_editor_resources"],
  deep_authoring: ["edit_animation_state_machine", "edit_animation_curve", "configure_animation_timeline", "edit_theme_resource", "assign_editor_resource", "edit_tileset_atlas", "paint_tilemap_terrain", "edit_array_mesh"],
  project: ["create_project", "get_project_info", "set_project_setting", "list_projects"],
  scenes: ["create_scene", "list_scenes", "duplicate_scene", "save_scene", "inspect_scene_tree", "inspect_node"],
  nodes: ["add_node", "remove_node", "set_node_property", "load_sprite", "create_ui_node"],
  scripts: ["create_script", "attach_script", "read_file", "write_file", "analyze_script", "search_project"],
  runtime: ["launch_editor", "run_project", "get_debug_output", "stop_project", "simulate_input", "run_automation_test", "get_runtime_info", "get_runtime_scene_tree", "get_runtime_node_properties", "set_runtime_property", "call_runtime_method", "pause_runtime", "resume_runtime", "step_runtime", "send_runtime_input", "inject_runtime_pointer", "configure_runtime_observability", "poll_runtime_observability", "capture_runtime_screenshot", "query_runtime_physics", "query_runtime_physics_shape", "query_runtime_navigation_path", "get_runtime_audio_state", "set_runtime_audio_bus", "play_runtime_audio", "get_runtime_logs", "get_runtime_binding", "release_runtime_binding"],
  visuals: ["capture_screenshot"],
  animation: ["create_animation", "inspect_animation_players"],
  tilemap: ["inspect_tilemaps", "set_tile_cell"],
  resources: ["list_resources", "find_resource_references", "get_uid", "update_project_uids"],
  performance: ["profile_scene", "check_project"],
  ai: ["get_game_context"],
  diagnostics: ["get_godot_version", "get_server_info", "get_capabilities"],
};
const toolGroupByName = new Map(Object.entries(TOOL_GROUPS).flatMap(([group, names]) => names.map((name) => [name, group])));
const enabledToolGroups = process.env.GODOT_MCP_TOOL_GROUPS ? new Set(process.env.GODOT_MCP_TOOL_GROUPS.split(",").map((item) => item.trim()).filter(Boolean)) : null;
const liveEditorGroups = new Set(["editor", "ui", "effects", "advanced_editor", "deep_authoring"]);
const liveRuntimeTools = new Set(["get_runtime_info", "get_runtime_scene_tree", "get_runtime_node_properties", "set_runtime_property", "call_runtime_method", "pause_runtime", "resume_runtime", "step_runtime", "send_runtime_input", "inject_runtime_pointer", "configure_runtime_observability", "poll_runtime_observability", "capture_runtime_screenshot", "query_runtime_physics", "query_runtime_physics_shape", "query_runtime_navigation_path", "get_runtime_audio_state", "set_runtime_audio_bus", "play_runtime_audio", "get_runtime_logs", "get_runtime_binding", "release_runtime_binding"]);
const editorBridgeEnabled = process.env.GODOT_MCP_ENABLE_EDITOR_BRIDGE === "1";

function getToolGroup(name) {
  return toolGroupByName.get(name) ?? "extension";
}

function createEditorTools() {
  return [
    editorTool("bind_editor", "Bind this MCP conversation to one live Godot editor. Later live-editor calls stay locked to this project until released.", "bind_session", {}),
    tool("get_editor_binding", "Read this MCP conversation's one-to-one live editor binding.", { type: "object", properties: {}, additionalProperties: false }, async () => getEditorBinding()),
    tool("release_editor_binding", "Release this MCP conversation's live editor binding so another conversation can use the editor.", { type: "object", properties: { projectPath: { type: "string", description: "Optional absolute Godot project path. Must match the active editor binding." }, port: { type: "integer", minimum: 1, maximum: 65535 } }, additionalProperties: false }, async (params) => releaseEditorBinding(params)),
    editorTool("get_editor_info", "Read the live Godot editor version, scene, selection, and bridge status.", "get_editor_info", {}),
    editorTool("get_editor_scene_tree", "Inspect the currently edited scene in the live editor.", "get_scene_tree", { maxDepth: { type: "integer", minimum: 0, maximum: 64, default: 16 } }),
    editorTool("open_scene", "Open a project-relative scene in the live Godot editor.", "open_scene", { scenePath: { type: "string" } }, ["scenePath"]),
    editorTool("save_current_scene", "Save the currently edited scene through Godot's editor.", "save_current_scene", {}),
    editorTool("play_current_scene", "Run the currently edited scene in Godot.", "play_current_scene", {}),
    editorTool("stop_running_scene", "Stop the currently running Godot scene.", "stop_running_scene", {}),
    editorTool("get_editor_selection", "Read the current Godot editor selection.", "get_selection", {}),
    editorTool("select_editor_nodes", "Select nodes in the Godot editor by scene-relative paths.", "select_nodes", { nodePaths: { type: "array", items: { type: "string" } } }, ["nodePaths"]),
    editorTool("clear_editor_selection", "Clear the Godot editor selection.", "clear_selection", {}),
    editorTool("add_editor_node", "Add a node to the live edited scene using UndoRedo.", "add_node", { parentPath: { type: "string", default: "." }, nodeType: { type: "string" }, nodeName: { type: "string" }, properties: { type: "object", additionalProperties: true } }, ["nodeType", "nodeName"]),
    editorTool("delete_editor_node", "Delete a node from the live edited scene using UndoRedo.", "delete_node", { nodePath: { type: "string" } }, ["nodePath"]),
    editorTool("duplicate_editor_node", "Duplicate a node in the live edited scene using UndoRedo.", "duplicate_node", { nodePath: { type: "string" }, newName: { type: "string" } }, ["nodePath"]),
    editorTool("move_editor_node", "Reparent a node in the live edited scene using UndoRedo.", "move_node", { nodePath: { type: "string" }, parentPath: { type: "string" }, index: { type: "integer", minimum: -1, default: -1 } }, ["nodePath", "parentPath"]),
    editorTool("rename_editor_node", "Rename a live scene node using UndoRedo.", "rename_node", { nodePath: { type: "string" }, newName: { type: "string" } }, ["nodePath", "newName"]),
    editorTool("get_editor_node_properties", "Read the Inspector-like properties of a live scene node.", "get_node_properties", { nodePath: { type: "string", default: "." } }),
    editorTool("set_editor_property", "Set a live Inspector property using UndoRedo.", "set_property", { nodePath: { type: "string" }, property: { type: "string" }, value: {} }, ["nodePath", "property", "value"]),
    editorTool("capture_editor_screenshot", "Capture the live Godot 2D or 3D editor viewport.", "capture_viewport", { viewport: { type: "string", enum: ["2d", "3d"], default: "2d" }, outputPath: { type: "string" } }, ["outputPath"]),
    editorTool("reload_editor_filesystem", "Refresh Godot's editor filesystem scan.", "reload_filesystem", {}),
    editorTool("execute_editor_script", "Call a method on a project-relative script through the editor bridge.", "execute_script", { scriptPath: { type: "string" }, method: { type: "string", default: "run" }, args: { type: "array", default: [] } }, ["scriptPath"]),
    editorTool("get_editor_logs", "Read logs emitted by the live MCP editor bridge.", "get_logs", { tailLines: { type: "integer", minimum: 1, maximum: 1000, default: 200 } }),
    editorTool("undo_editor", "Undo the last editor MCP action.", "undo", {}),
    editorTool("redo_editor", "Redo the last editor MCP action.", "redo", {}),
  ];
}

function editorTool(name, description, operation, properties, required = []) {
  return tool(name, description, { type: "object", required, properties: { projectPath: { type: "string", description: "Optional absolute Godot project path for multi-project routing." }, port: { type: "integer", minimum: 1, maximum: 65535 }, ...properties }, additionalProperties: false }, async (params) => callEditorBridge(operation, params));
}

function createRuntimeTools() {
  return [
    runtimeTool("get_runtime_info", "Read the live game's process, scene, pause state, runtime port, and binding status.", "get_runtime_info", {}),
    runtimeTool("get_runtime_scene_tree", "Inspect the currently running game scene tree.", "get_scene_tree", { maxDepth: { type: "integer", minimum: 0, maximum: 64, default: 16 } }),
    runtimeTool("get_runtime_node_properties", "Read live properties from a node in the running game.", "get_node_properties", { nodePath: { type: "string", default: "." } }),
    runtimeTool("set_runtime_property", "Set a live game node property without changing the saved scene.", "set_property", { nodePath: { type: "string" }, property: { type: "string" }, value: {} }, ["nodePath", "property", "value"]),
    runtimeTool("call_runtime_method", "Call a method on a node in the running game.", "call_method", { nodePath: { type: "string" }, method: { type: "string" }, args: { type: "array", default: [] } }, ["nodePath", "method"]),
    runtimeTool("pause_runtime", "Pause the running game while leaving the runtime bridge responsive.", "pause", {}),
    runtimeTool("resume_runtime", "Resume the running game.", "resume", {}),
    runtimeTool("step_runtime", "Advance the paused running game by a small number of process frames.", "step", { frames: { type: "integer", minimum: 1, maximum: 120, default: 1 } }),
    runtimeTool("send_runtime_input", "Inject key or mouse-button input into the running game.", "send_input", { eventType: { type: "string", enum: ["key", "mouse_button"] }, keycode: { type: "integer" }, physicalKeycode: { type: "integer" }, buttonIndex: { type: "integer", minimum: 1, maximum: 8, default: 1 }, pressed: { type: "boolean", default: true }, echo: { type: "boolean", default: false }, position: { type: "object", additionalProperties: true } }, ["eventType"]),
    runtimeTool("inject_runtime_pointer", "Inject pointer movement, wheel, touch, touch-drag, or a complete mouse drag into the running game.", "inject_pointer", { pointerType: { type: "string", enum: ["move", "wheel", "touch", "touch_drag", "drag"] }, position: { type: "object", additionalProperties: true }, relative: { type: "object", additionalProperties: true }, scrollY: { type: "integer", minimum: -24, maximum: 24 }, touchIndex: { type: "integer", minimum: 0, maximum: 31, default: 0 }, pressed: { type: "boolean", default: true }, from: { type: "object", additionalProperties: true }, to: { type: "object", additionalProperties: true }, buttonIndex: { type: "integer", minimum: 1, maximum: 8, default: 1 }, steps: { type: "integer", minimum: 1, maximum: 120, default: 8 } }, ["pointerType"]),
    runtimeTool("configure_runtime_observability", "Configure property watches that emit runtime change events and collect rolling frame metrics.", "configure_observability", { watches: { type: "array", default: [], items: { type: "object", required: ["nodePath", "property"], properties: { nodePath: { type: "string" }, property: { type: "string" } }, additionalProperties: false } } }),
    runtimeTool("poll_runtime_observability", "Poll property-change events, runtime-agent logs, and frame-level performance metrics after a cursor.", "poll_observability", { since: { type: "integer", minimum: 0, default: 0 }, limit: { type: "integer", minimum: 1, maximum: 1000, default: 200 } }),
    tool("capture_runtime_screenshot", "Capture the running game viewport to a PNG inside the project.", runtimeInputSchema({ outputPath: { type: "string" } }, ["outputPath"]), async (params) => captureRuntimeScreenshot(params)),
    runtimeTool("query_runtime_physics", "Run a 2D or 3D ray query against the running game physics world.", "query_physics", { dimension: { type: "string", enum: ["2d", "3d"], default: "2d" }, from: { type: "object", additionalProperties: true }, to: { type: "object", additionalProperties: true }, collisionMask: { type: "integer", minimum: 0, default: 2147483647 } }, ["from", "to"]),
    runtimeTool("query_runtime_physics_shape", "Run a 2D or 3D point or primitive-shape overlap query against the running game physics world.", "query_physics_shape", { dimension: { type: "string", enum: ["2d", "3d"], default: "2d" }, queryType: { type: "string", enum: ["point", "shape"], default: "point" }, position: { type: "object", additionalProperties: true }, shape: { type: "string", enum: ["circle", "rectangle", "capsule", "sphere", "box", "cylinder"], default: "circle" }, size: { type: "object", additionalProperties: true }, rotation: { type: "number", default: 0 }, rotationDegrees: { type: "object", additionalProperties: true }, collisionMask: { type: "integer", minimum: 0, default: 2147483647 }, maxResults: { type: "integer", minimum: 1, maximum: 128, default: 32 }, collideWithBodies: { type: "boolean", default: true }, collideWithAreas: { type: "boolean", default: true } }, ["position"]),
    runtimeTool("query_runtime_navigation_path", "Query a 2D or 3D navigation path in the running game world.", "query_navigation_path", { dimension: { type: "string", enum: ["2d", "3d"], default: "2d" }, from: { type: "object", additionalProperties: true }, to: { type: "object", additionalProperties: true }, optimize: { type: "boolean", default: true }, navigationLayers: { type: "integer", minimum: 1, default: 1 } }, ["from", "to"]),
    runtimeTool("get_runtime_audio_state", "Read live AudioServer bus, volume, mute, solo, and effect state.", "get_audio_state", {}),
    runtimeTool("set_runtime_audio_bus", "Set live AudioServer bus volume, mute, or solo state.", "set_audio_bus", { bus: { type: "string", default: "Master" }, volumeDb: { type: "number" }, mute: { type: "boolean" }, solo: { type: "boolean" } }),
    runtimeTool("play_runtime_audio", "Play and tune an AudioStreamPlayer node in the running game.", "play_audio", { nodePath: { type: "string" }, volumeDb: { type: "number" }, pitchScale: { type: "number", minimum: 0.01 }, fromPosition: { type: "number", minimum: 0, default: 0 } }, ["nodePath"]),
    runtimeTool("get_runtime_logs", "Read logs emitted by the running game's MCP runtime agent.", "get_logs", { tailLines: { type: "integer", minimum: 1, maximum: 1000, default: 200 } }),
    tool("get_runtime_binding", "Read this MCP conversation's one-to-one runtime binding.", { type: "object", properties: {}, additionalProperties: false }, async () => getRuntimeBinding()),
    tool("release_runtime_binding", "Release this MCP conversation's running-game binding.", runtimeInputSchema({}, []), async (params) => releaseRuntimeBinding(params)),
  ];
}

function runtimeInputSchema(properties, required = []) {
  return {
    type: "object",
    required,
    properties: { runId: { type: "string", description: "Optional run identifier returned by run_project." }, projectPath: { type: "string", description: "Optional absolute Godot project path for runtime routing." }, port: { type: "integer", minimum: 1, maximum: 65535 }, ...properties },
    additionalProperties: false,
  };
}

function runtimeTool(name, description, operation, properties, required = []) {
  return tool(name, description, runtimeInputSchema(properties, required), async (params) => callRuntimeBridge(operation, params));
}

function createAdvancedEditorTools() {
  return [
    editorTool("get_script_editor_state", "Read the live Script Editor script, caret, selection, open scripts, and breakpoints.", "get_script_editor_state", {}),
    editorTool("open_editor_script", "Open a project-relative script in Godot's Script Editor.", "open_editor_script", { scriptPath: { type: "string" } }, ["scriptPath"]),
    editorTool("goto_editor_script_line", "Move the Script Editor caret to a line in the current script.", "goto_editor_script_line", { line: { type: "integer", minimum: 1 } }, ["line"]),
    editorTool("get_editor_breakpoints", "Read Script Editor breakpoints.", "get_editor_breakpoints", {}),
    editorTool("save_editor_scripts", "Save all unsaved Script Editor files.", "save_editor_scripts", {}),
    editorTool("get_editor_debugger_state", "Read available live debugger and running-scene state.", "get_editor_debugger_state", {}),
    editorTool("create_primitive_mesh", "Create a BoxMesh, SphereMesh, CapsuleMesh, CylinderMesh, PlaneMesh, or QuadMesh instance in the edited 3D scene.", "create_primitive_mesh", { parentPath: { type: "string", default: "." }, nodeName: { type: "string", default: "McpMesh" }, primitive: { type: "string", enum: ["box", "sphere", "capsule", "cylinder", "plane", "quad"], default: "box" }, size: { type: "object", additionalProperties: true }, properties: { type: "object", additionalProperties: true } }),
    editorTool("create_3d_camera", "Create a Camera3D in the edited scene.", "create_3d_camera", { parentPath: { type: "string", default: "." }, nodeName: { type: "string", default: "McpCamera3D" }, transform: { type: "object", additionalProperties: true }, current: { type: "boolean", default: false } }),
    editorTool("create_3d_light", "Create a DirectionalLight3D, OmniLight3D, or SpotLight3D in the edited scene.", "create_3d_light", { parentPath: { type: "string", default: "." }, nodeName: { type: "string", default: "McpLight3D" }, lightType: { type: "string", enum: ["directional", "omni", "spot"], default: "directional" }, color: { type: "string", default: "#ffffff" }, energy: { type: "number", minimum: 0, default: 1 }, transform: { type: "object", additionalProperties: true } }),
    editorTool("create_2d_camera", "Create a configured Camera2D with zoom, rotation, smoothing, and enabled state.", "create_2d_camera", { parentPath: { type: "string", default: "." }, nodeName: { type: "string", default: "McpCamera2D" }, position: { type: "object", additionalProperties: true }, zoom: { type: "object", additionalProperties: true }, rotationDegrees: { type: "number", default: 0 }, enabled: { type: "boolean", default: true }, positionSmoothing: { type: "boolean", default: false }, positionSmoothingSpeed: { type: "number", minimum: 0, default: 5 } }),
    editorTool("create_2d_light", "Create a PointLight2D or DirectionalLight2D with position, color, energy, and texture scale.", "create_2d_light", { parentPath: { type: "string", default: "." }, nodeName: { type: "string", default: "McpLight2D" }, lightType: { type: "string", enum: ["point", "directional"], default: "point" }, position: { type: "object", additionalProperties: true }, rotationDegrees: { type: "number", default: 0 }, color: { type: "string", default: "#ffffff" }, energy: { type: "number", minimum: 0, default: 1 }, textureScale: { type: "number", minimum: 0 } }),
    editorTool("create_ui_component", "Create common UI controls and containers with semantic text, color, texture, progress, and layout defaults.", "create_ui_component", { parentPath: { type: "string", default: "." }, componentType: { type: "string", enum: ["PanelContainer", "Label", "Button", "TextureRect", "ProgressBar", "ColorRect", "HBoxContainer", "VBoxContainer", "MarginContainer", "CenterContainer"], default: "PanelContainer" }, nodeName: { type: "string" }, fullRect: { type: "boolean", default: false }, minimumSize: { type: "object", additionalProperties: true }, text: { type: "string" }, color: { type: "string" }, texturePath: { type: "string" }, value: { type: "number" }, maxValue: { type: "number", minimum: 0 }, properties: { type: "object", additionalProperties: true } }),
    editorTool("set_editor_transform", "Set a Node3D position, rotation in degrees, scale, and optional editor snap behavior with UndoRedo.", "set_editor_transform", { nodePath: { type: "string" }, position: { type: "object", additionalProperties: true }, rotationDegrees: { type: "object", additionalProperties: true }, scale: { type: "object", additionalProperties: true } }, ["nodePath"]),
    editorTool("inspect_3d_scene", "Inspect Node3D transforms, meshes, cameras, lights, and material overrides.", "inspect_3d_scene", { rootPath: { type: "string", default: "." } }),
    editorTool("create_standard_material", "Create and assign a StandardMaterial3D to a MeshInstance3D or GeometryInstance3D.", "create_standard_material", { nodePath: { type: "string" }, albedoColor: { type: "string", default: "#ffffff" }, metallic: { type: "number", minimum: 0, maximum: 1, default: 0 }, roughness: { type: "number", minimum: 0, maximum: 1, default: 0.5 }, emissionColor: { type: "string" }, savePath: { type: "string" } }, ["nodePath"]),
    editorTool("assign_editor_material", "Assign a saved Material resource to a GeometryInstance3D.", "assign_editor_material", { nodePath: { type: "string" }, materialPath: { type: "string" } }, ["nodePath", "materialPath"]),
    editorTool("create_animation_track", "Create a value track in an AnimationPlayer animation.", "create_animation_track", { animationPlayerPath: { type: "string" }, animationName: { type: "string" }, targetNodePath: { type: "string" }, property: { type: "string" } }, ["animationPlayerPath", "animationName", "targetNodePath", "property"]),
    editorTool("set_animation_key", "Insert or replace a value keyframe in an AnimationPlayer animation.", "set_animation_key", { animationPlayerPath: { type: "string" }, animationName: { type: "string" }, targetNodePath: { type: "string" }, property: { type: "string" }, time: { type: "number", minimum: 0 }, value: {} }, ["animationPlayerPath", "animationName", "targetNodePath", "property", "time", "value"]),
    editorTool("inspect_animation_timeline", "Inspect AnimationPlayer libraries, animations, tracks, paths, and key counts.", "inspect_animation_timeline", { animationPlayerPath: { type: "string" } }, ["animationPlayerPath"]),
    editorTool("set_animation_tree_state", "Enable an AnimationTree and set serializable parameters.", "set_animation_tree_state", { nodePath: { type: "string" }, active: { type: "boolean" }, parameters: { type: "object", additionalProperties: true } }, ["nodePath"]),
    editorTool("edit_animation_state_machine", "Create, inspect, and extend an AnimationTree state machine with animation states and transitions.", "edit_animation_state_machine", { animationTreePath: { type: "string" }, action: { type: "string", enum: ["create", "inspect", "add_state", "add_transition"] }, stateName: { type: "string" }, animationPath: { type: "string" }, position: { type: "object", additionalProperties: true }, fromState: { type: "string" }, toState: { type: "string" }, xfadeTime: { type: "number", minimum: 0, default: 0.2 }, reset: { type: "boolean", default: false }, priority: { type: "integer", default: 1 } }, ["animationTreePath", "action"]),
    editorTool("edit_animation_curve", "Create a Bezier property track or insert a Bezier key with explicit in/out handles.", "edit_animation_curve", { animationPlayerPath: { type: "string" }, animationName: { type: "string" }, action: { type: "string", enum: ["create_track", "set_key"] }, targetNodePath: { type: "string" }, property: { type: "string" }, time: { type: "number", minimum: 0 }, value: { type: "number" }, inHandle: { type: "object", additionalProperties: true }, outHandle: { type: "object", additionalProperties: true } }, ["animationPlayerPath", "animationName", "action", "targetNodePath", "property"]),
    editorTool("configure_animation_timeline", "Set Animation resource length, step, and loop behavior through an AnimationPlayer.", "configure_animation_timeline", { animationPlayerPath: { type: "string" }, animationName: { type: "string" }, length: { type: "number", minimum: 0.01 }, step: { type: "number", minimum: 0 }, loopMode: { type: "string", enum: ["none", "linear", "pingpong"] } }, ["animationPlayerPath", "animationName"]),
    editorTool("edit_theme_resource", "Inspect a Theme resource or set a color, constant, font size, or StyleBox subresource and save it.", "edit_theme_resource", { resourcePath: { type: "string" }, action: { type: "string", enum: ["inspect", "set_item"] }, itemType: { type: "string", enum: ["color", "constant", "font_size", "stylebox"] }, controlType: { type: "string", default: "Control" }, name: { type: "string" }, value: {}, style: { type: "object", additionalProperties: true } }, ["resourcePath", "action"]),
    editorTool("assign_editor_resource", "Load a saved resource and assign it to a serializable property of a node in the edited scene.", "assign_editor_resource", { nodePath: { type: "string" }, property: { type: "string" }, resourcePath: { type: "string" } }, ["nodePath", "property", "resourcePath"]),
    editorTool("edit_tileset_atlas", "Inspect a TileSet atlas, create an atlas source from a texture, or create an atlas tile.", "edit_tileset_atlas", { tileMapPath: { type: "string" }, action: { type: "string", enum: ["inspect", "create_source", "create_tile"] }, texturePath: { type: "string" }, sourceId: { type: "integer", default: -1 }, regionSize: { type: "object", additionalProperties: true }, tileCoordinates: { type: "object", additionalProperties: true }, tileSize: { type: "object", additionalProperties: true } }, ["tileMapPath", "action"]),
    editorTool("paint_tilemap_terrain", "Paint connected terrain cells on a TileMapLayer or TileMap using an existing TileSet terrain definition.", "paint_tilemap_terrain", { tileMapPath: { type: "string" }, layer: { type: "integer", minimum: 0, default: 0 }, terrainSet: { type: "integer", minimum: 0 }, terrain: { type: "integer", minimum: -1 }, cells: { type: "array", items: { type: "object", additionalProperties: true } }, ignoreEmptyTerrains: { type: "boolean", default: true } }, ["tileMapPath", "terrainSet", "terrain", "cells"]),
    editorTool("edit_array_mesh", "Create, inspect, or update a scene-owned ArrayMesh with editable vertices, normals, UVs, and indices.", "edit_array_mesh", { action: { type: "string", enum: ["create", "inspect", "update_surface"] }, parentPath: { type: "string", default: "." }, nodePath: { type: "string" }, nodeName: { type: "string", default: "McpArrayMesh" }, primitive: { type: "string", enum: ["triangles", "lines", "line_strip", "points"], default: "triangles" }, vertices: { type: "array", items: { type: "object", additionalProperties: true } }, normals: { type: "array", items: { type: "object", additionalProperties: true } }, uvs: { type: "array", items: { type: "object", additionalProperties: true } }, indices: { type: "array", items: { type: "integer", minimum: 0 } }, materialPath: { type: "string" }, transform: { type: "object", additionalProperties: true }, surface: { type: "integer", minimum: 0, default: 0 }, includeVertices: { type: "boolean", default: false }, maxVertices: { type: "integer", minimum: 1, maximum: 10000, default: 256 } }, ["action"]),
    editorTool("create_navigation_node", "Create NavigationRegion2D/3D or NavigationAgent2D/3D nodes in the edited scene.", "create_navigation_node", { parentPath: { type: "string", default: "." }, nodeName: { type: "string", default: "McpNavigation" }, nodeType: { type: "string", enum: ["NavigationRegion2D", "NavigationRegion3D", "NavigationAgent2D", "NavigationAgent3D"] } }, ["nodeType"]),
    editorTool("configure_navigation_agent", "Configure a NavigationAgent2D or NavigationAgent3D target and movement settings.", "configure_navigation_agent", { nodePath: { type: "string" }, targetPosition: { type: "object", additionalProperties: true }, properties: { type: "object", additionalProperties: true } }, ["nodePath"]),
    editorTool("inspect_navigation", "Inspect navigation region and agent nodes in the edited scene.", "inspect_navigation", { rootPath: { type: "string", default: "." } }),
    editorTool("create_collision_shape", "Create a CollisionShape2D or CollisionShape3D with a primitive shape resource.", "create_collision_shape", { parentPath: { type: "string", default: "." }, nodeName: { type: "string", default: "McpCollisionShape" }, dimension: { type: "string", enum: ["2d", "3d"], default: "2d" }, shape: { type: "string", enum: ["rectangle", "circle", "box", "sphere"], default: "rectangle" }, size: { type: "object", additionalProperties: true } }),
    editorTool("configure_physics_node", "Configure collision layer, mask, gravity, mass, freeze, and other available physics node properties.", "configure_physics_node", { nodePath: { type: "string" }, properties: { type: "object", additionalProperties: true } }, ["nodePath"]),
    editorTool("inspect_physics", "Inspect physics bodies, areas, and collision shapes in the edited scene.", "inspect_physics", { rootPath: { type: "string", default: "." } }),
    editorTool("get_editor_audio_buses", "Read the editor AudioServer bus and effect configuration.", "get_editor_audio_buses", {}),
    editorTool("set_editor_audio_bus", "Set editor AudioServer bus volume, mute, or solo state.", "set_editor_audio_bus", { bus: { type: "string", default: "Master" }, volumeDb: { type: "number" }, mute: { type: "boolean" }, solo: { type: "boolean" } }),
    editorTool("configure_editor_audio_player", "Configure an AudioStreamPlayer, AudioStreamPlayer2D, or AudioStreamPlayer3D resource and playback settings.", "configure_editor_audio_player", { nodePath: { type: "string" }, streamPath: { type: "string" }, bus: { type: "string" }, volumeDb: { type: "number" }, pitchScale: { type: "number", minimum: 0.01 }, autoplay: { type: "boolean" } }, ["nodePath"]),
    editorTool("inspect_editor_audio_nodes", "Inspect audio player nodes in the edited scene.", "inspect_editor_audio_nodes", { rootPath: { type: "string", default: "." } }),
    editorTool("create_theme_resource", "Create a reusable Theme resource with optional default font size and panel style.", "create_theme_resource", { savePath: { type: "string" }, defaultFontSize: { type: "integer", minimum: 1 }, panelStyle: { type: "object", additionalProperties: true } }, ["savePath"]),
    editorTool("list_editor_plugins", "List project addon plugins and whether Godot currently enables them.", "list_editor_plugins", {}),
    editorTool("set_editor_plugin_enabled", "Enable or disable a project addon plugin through Godot's EditorInterface.", "set_editor_plugin_enabled", { pluginPath: { type: "string" }, enabled: { type: "boolean" } }, ["pluginPath", "enabled"]),
    editorTool("get_editor_workspace", "Read current editor scene tabs, selected files, selection, and distraction-free state.", "get_editor_workspace", {}),
    editorTool("set_editor_main_screen", "Switch Godot's main editor screen, such as 2D, 3D, Script, AssetLib, or Game.", "set_editor_main_screen", { screen: { type: "string" } }, ["screen"]),
    editorTool("set_distraction_free_mode", "Toggle Godot's distraction-free editor layout.", "set_distraction_free_mode", { enabled: { type: "boolean" } }, ["enabled"]),
    editorTool("reimport_editor_resources", "Reimport selected project resources through the live editor filesystem dock when the engine supports it.", "reimport_editor_resources", { paths: { type: "array", items: { type: "string" } } }, ["paths"]),
  ];
}

function createUiEffectTools() {
  return [
    editorTool("create_ui_screen", "Create a structured full-screen UI hierarchy with header, content, and footer containers.", "create_ui_screen", { parentPath: { type: "string", default: "." }, rootName: { type: "string", default: "UIScreen" }, margin: { type: "integer", default: 24 }, addHeader: { type: "boolean", default: true }, addContent: { type: "boolean", default: true }, addFooter: { type: "boolean", default: true } }),
    editorTool("configure_control_layout", "Configure Control anchors, offsets, size flags, and grow direction with UndoRedo.", "configure_control_layout", { nodePath: { type: "string" }, anchors: { type: "object", additionalProperties: true }, offsets: { type: "object", additionalProperties: true }, sizeFlags: { type: "object", additionalProperties: true }, growDirection: { type: "object", additionalProperties: true } }, ["nodePath"]),
    editorTool("set_theme_override", "Set a Control theme color, font size, constant, or StyleBox override.", "set_theme_override", { nodePath: { type: "string" }, kind: { type: "string", enum: ["color", "font_size", "constant", "stylebox"] }, name: { type: "string" }, value: {} }, ["nodePath", "kind", "name", "value"]),
    editorTool("inspect_ui_layout", "Inspect Control layout geometry and theme override state.", "inspect_ui_layout", { nodePath: { type: "string", default: "." } }),
    editorTool("create_particles", "Create a tuned GPUParticles2D or GPUParticles3D effect with a process material.", "create_particles", { parentPath: { type: "string", default: "." }, nodeName: { type: "string", default: "McpParticles" }, dimension: { type: "string", enum: ["2d", "3d"], default: "2d" }, amount: { type: "integer", minimum: 1, maximum: 100000, default: 64 }, lifetime: { type: "number", minimum: 0.01, maximum: 120, default: 1.5 }, oneShot: { type: "boolean", default: false }, explosiveness: { type: "number", minimum: 0, maximum: 1, default: 0 }, randomness: { type: "number", minimum: 0, maximum: 1, default: 0 }, color: { type: "string", default: "#ffffff" }, texturePath: { type: "string" } }, ["nodeName"]),
    editorTool("configure_particles", "Tune an existing particle node and its ParticleProcessMaterial.", "configure_particles", { nodePath: { type: "string" }, properties: { type: "object", additionalProperties: true }, material: { type: "object", additionalProperties: true } }, ["nodePath"]),
    editorTool("create_shader_effect", "Create a ShaderMaterial effect and assign it to a CanvasItem or GeometryInstance3D.", "create_shader_effect", { nodePath: { type: "string" }, shaderCode: { type: "string" }, savePath: { type: "string" } }, ["nodePath", "shaderCode"]),
    editorTool("set_shader_parameter", "Set a ShaderMaterial parameter with an UndoRedo action.", "set_shader_parameter", { nodePath: { type: "string" }, parameter: { type: "string" }, value: {} }, ["nodePath", "parameter", "value"]),
    editorTool("create_screen_flash", "Create a full-rect ColorRect flash layer for hit, damage, or transition effects.", "create_screen_flash", { parentPath: { type: "string", default: "." }, nodeName: { type: "string", default: "McpScreenFlash" }, color: { type: "string", default: "#ffffff00" } }),
    editorTool("create_post_process", "Create a WorldEnvironment with safe glow, fog, and background defaults.", "create_post_process", { parentPath: { type: "string", default: "." }, nodeName: { type: "string", default: "McpWorldEnvironment" }, glowEnabled: { type: "boolean", default: true }, fogEnabled: { type: "boolean", default: false }, backgroundColor: { type: "string", default: "#101522" } }),
    editorTool("configure_stylized_rendering", "Create or tune a 2D palette CanvasModulate or 3D WorldEnvironment with filmic tone mapping, palette, glow, fog, and color adjustment.", "configure_stylized_rendering", { dimension: { type: "string", enum: ["2d", "3d"], default: "2d" }, parentPath: { type: "string", default: "." }, nodePath: { type: "string" }, nodeName: { type: "string" }, paletteColor: { type: "string", default: "#ffffff" }, backgroundColor: { type: "string", default: "#1b2135" }, ambientColor: { type: "string", default: "#a9c4ff" }, ambientEnergy: { type: "number", minimum: 0, default: 0.8 }, glowEnabled: { type: "boolean", default: true }, glowIntensity: { type: "number", minimum: 0, default: 0.8 }, saturation: { type: "number", minimum: 0, default: 1.1 }, contrast: { type: "number", minimum: 0, default: 1.05 }, brightness: { type: "number", minimum: 0, default: 1 }, fogEnabled: { type: "boolean", default: false }, fogColor: { type: "string", default: "#aab8d0" }, fogDensity: { type: "number", minimum: 0, default: 0.01 } }),
    editorTool("create_animation_effect", "Create an AnimationPlayer value-track effect from explicit keyframes.", "create_animation_effect", { animationPlayerPath: { type: "string" }, targetNodePath: { type: "string" }, property: { type: "string" }, animationName: { type: "string" }, length: { type: "number", minimum: 0.01, default: 0.5 }, keys: { type: "array", items: { type: "object" } } }, ["animationPlayerPath", "targetNodePath", "property", "animationName", "keys"]),
    editorTool("set_canvas_modulate", "Set a CanvasModulate color with UndoRedo for global 2D tint effects.", "set_canvas_modulate", { nodePath: { type: "string" }, color: { type: "string" } }, ["nodePath", "color"]),
    editorTool("inspect_visual_effects", "Scan the edited scene for particles, shader materials, environments, animation, and canvas effects.", "inspect_visual_effects", { rootPath: { type: "string", default: "." } }),
  ];
}

function isToolEnabled(name) {
  const group = getToolGroup(name);
  if (liveEditorGroups.has(group) && !editorBridgeEnabled) return false;
  if (liveRuntimeTools.has(name) && !editorBridgeEnabled) return false;
  return !enabledToolGroups || enabledToolGroups.has(group) || enabledToolGroups.has("all");
}

async function loadExtensionTools() {
  const directory = process.env.GODOT_MCP_EXTENSIONS_DIR;
  if (!directory) return [];
  let entries;
  try {
    entries = await fs.readdir(resolve(directory), { withFileTypes: true });
  } catch {
    return [];
  }
  const loaded = [];
  for (const entry of entries) {
    if (!entry.isFile() || !entry.name.endsWith(".mjs") || entry.name.startsWith("_")) continue;
    const modulePath = join(resolve(directory), entry.name);
    const extension = await import(pathToFileURL(modulePath).href);
    if (!Array.isArray(extension.tools)) continue;
    for (const extensionTool of extension.tools) {
      if (!extensionTool?.name || typeof extensionTool.handler !== "function" || !extensionTool.inputSchema) continue;
      loaded.push(extensionTool);
    }
  }
  return loaded;
}

function getServerInfo() {
  const godotBinary = findGodotBinary();
  return {
    name: SERVER_NAME,
    version: SERVER_VERSION,
    protocolVersion: PROTOCOL_VERSION,
    supportedProtocolVersions: [...SUPPORTED_PROTOCOL_VERSIONS],
    nodeVersion: process.version,
    godotBinary,
    godotCompatibility: getGodotCompatibility(godotBinary),
    runtimeDirectory,
    enabledToolGroups: enabledToolGroups ? [...enabledToolGroups] : ["all"],
    editorBridgeEnabled,
    editorBinding: getEditorBinding(),
    runtimeBinding: getRuntimeBinding(),
    toolCount: tools.filter((entry) => isToolEnabled(entry.name)).length,
    extensionDirectory: process.env.GODOT_MCP_EXTENSIONS_DIR ?? null,
    activeRuns: [...projectProcesses.values()].map((entry) => ({ runId: entry.runId, projectPath: entry.projectPath, pid: entry.child.pid, runtimePort: entry.runtimePort })),
  };
}

function getCapabilities() {
  return {
    schemaVersion: 1,
    server: { name: SERVER_NAME, version: SERVER_VERSION },
    protocol: { current: PROTOCOL_VERSION, supported: [...SUPPORTED_PROTOCOL_VERSIONS] },
    godot: getGodotCompatibility(findGodotBinary()),
    groups: Object.fromEntries(Object.entries(TOOL_GROUPS).map(([group, names]) => [group, { enabled: names.some(isToolEnabled), tools: names.filter((name) => toolMap.has(name) && isToolEnabled(name)) }])),
    extensions: extensionTools.map((entry) => ({ name: entry.name, group: getToolGroup(entry.name) })),
    toolCount: tools.filter((entry) => isToolEnabled(entry.name)).length,
  };
}

function resolveOperationScript(currentModuleDirectory) {
  const bundledScript = join(currentModuleDirectory, "godot", "mcp_operations.gd");
  return existsSync(bundledScript) ? bundledScript : resolve(currentModuleDirectory, "..", "godot", "mcp_operations.gd");
}
function getGodotCompatibility(binary) {
  if (!binary) return { status: "unavailable", supportedMajor: 4, detected: null, warning: "Set GODOT_BIN or GODOT_PATH, or add godot/godot4 to PATH." };
  const result = spawnSync(binary, ["--version"], { encoding: "utf8", windowsHide: true });
  const version = `${result.stdout ?? ""}\n${result.stderr ?? ""}`.trim();
  const match = version.match(/(\d+)\.(\d+)(?:\.(\d+))?/);
  const major = match ? Number(match[1]) : null;
  return {
    status: major === 4 ? "supported" : major === null ? "unknown" : "forward-compatible-warning",
    supportedMajor: 4,
    detected: version,
    major,
    warning: major === 4 ? null : "Godot operations use runtime feature detection; verify scene APIs on this engine version.",
  };
}

let webSocketImplementation;

async function getWebSocketImplementation() {
  if (webSocketImplementation) return webSocketImplementation;
  if (typeof globalThis.WebSocket === "function") {
    webSocketImplementation = globalThis.WebSocket;
    return webSocketImplementation;
  }
  try {
    const module = await import("ws");
    webSocketImplementation = module.WebSocket ?? module.default;
    return webSocketImplementation;
  } catch {
    throw new McpError(-32003, "Live editor bridge requires Node WebSocket support or the optional ws package");
  }
}

async function callEditorBridge(operation, params = {}) {
  const projectPath = requireProject(params.projectPath);
  if (editorBinding && operation !== "release_session" && editorBinding.projectPath !== projectPath) {
    throw new McpError(-32602, `This MCP conversation is already bound to ${editorBinding.projectPath}. Call release_editor_binding before selecting ${projectPath}.`);
  }
  const bridgeParams = { ...params, projectPath, sessionId: editorSessionId, bindingMode: EDITOR_BINDING_MODE };
  const candidatePorts = getEditorPortCandidates(bridgeParams);
  let lastError;
  for (const port of candidatePorts) {
    const url = process.env.GODOT_MCP_EDITOR_URL ? process.env.GODOT_MCP_EDITOR_URL : `ws://127.0.0.1:${port}`;
    for (let attempt = 0; attempt < 2; attempt += 1) {
      try {
        const result = await callEditorBridgeOnce(url, operation, bridgeParams);
        if (!process.env.GODOT_MCP_EDITOR_URL) editorProjectPorts.set(projectPath, port);
        if (operation !== "release_session") editorBinding = { projectPath, port, boundAt: new Date().toISOString() };
        return result;
      } catch (error) {
        lastError = error;
        if (attempt < 1) await new Promise((resolvePromise) => setTimeout(resolvePromise, 100));
      }
    }
  }
  throw normalizeError(lastError);
}

function getEditorSessionId() {
  const configured = process.env.GODOT_MCP_SESSION_ID?.trim();
  return configured && configured.length <= 128 ? configured : randomUUID();
}

function getEditorBinding() {
  return {
    mode: EDITOR_BINDING_MODE,
    sessionId: editorSessionId,
    bound: Boolean(editorBinding),
    projectPath: editorBinding?.projectPath ?? null,
    port: editorBinding?.port ?? null,
    boundAt: editorBinding?.boundAt ?? null,
  };
}

async function releaseEditorBinding(params = {}) {
  if (!editorBinding) return { released: false, binding: getEditorBinding() };
  const requestedProjectPath = params.projectPath ? requireProject(params.projectPath) : editorBinding.projectPath;
  if (requestedProjectPath !== editorBinding.projectPath) {
    throw new McpError(-32602, `This MCP conversation is bound to ${editorBinding.projectPath}, not ${requestedProjectPath}.`);
  }
  const result = await callEditorBridge("release_session", { ...params, projectPath: requestedProjectPath, port: params.port ?? editorBinding.port });
  editorBinding = null;
  return { ...result, binding: getEditorBinding() };
}


function getRuntimeBinding() {
  return {
    mode: EDITOR_BINDING_MODE,
    sessionId: editorSessionId,
    bound: Boolean(runtimeBinding),
    projectPath: runtimeBinding?.projectPath ?? null,
    port: runtimeBinding?.port ?? null,
    runId: runtimeBinding?.runId ?? null,
    boundAt: runtimeBinding?.boundAt ?? null,
  };
}

function getRuntimeTarget(params = {}) {
  const run = params.runId ? projectProcesses.get(params.runId) : [...projectProcesses.values()].find((entry) => params.projectPath && entry.projectPath === resolve(params.projectPath));
  if (params.runId && !run) throw new McpError(-32602, "No matching Godot run found: " + params.runId);
  const projectPath = run?.projectPath ?? requireProject(params.projectPath);
  return { projectPath, run };
}

async function callRuntimeBridge(operation, params = {}) {
  const target = getRuntimeTarget(params);
  const projectPath = target.projectPath;
  const run = target.run;
  if (runtimeBinding && operation !== "release_session" && runtimeBinding.projectPath !== projectPath) {
    throw new McpError(-32602, "This MCP conversation is already bound to the runtime for " + runtimeBinding.projectPath + ". Call release_runtime_binding before selecting " + projectPath + ".");
  }
  const bridgeParams = { ...params, projectPath, sessionId: editorSessionId, bindingMode: EDITOR_BINDING_MODE };
  const candidatePorts = getRuntimePortCandidates(bridgeParams, run);
  let lastError;
  for (const port of candidatePorts) {
    const url = process.env.GODOT_MCP_RUNTIME_URL ? process.env.GODOT_MCP_RUNTIME_URL : "ws://127.0.0.1:" + port;
    for (let attempt = 0; attempt < 2; attempt += 1) {
      try {
        const result = await callRuntimeBridgeOnce(url, operation, bridgeParams);
        if (!process.env.GODOT_MCP_RUNTIME_URL) runtimeProjectPorts.set(projectPath, port);
        if (operation !== "release_session") runtimeBinding = { projectPath, port, runId: run?.runId ?? null, boundAt: new Date().toISOString() };
        return result;
      } catch (error) {
        lastError = error;
        if (attempt < 1) await new Promise((resolvePromise) => setTimeout(resolvePromise, 100));
      }
    }
  }
  throw normalizeError(lastError instanceof McpError ? lastError : new McpError(-32003, "Godot runtime bridge connection failed"));
}

async function releaseRuntimeBinding(params = {}) {
  if (!runtimeBinding) return { released: false, binding: getRuntimeBinding() };
  const target = getRuntimeTarget({ ...params, projectPath: params.projectPath ?? runtimeBinding.projectPath });
  if (target.projectPath !== runtimeBinding.projectPath) {
    throw new McpError(-32602, "This MCP conversation is bound to the runtime for " + runtimeBinding.projectPath + ", not " + target.projectPath + ".");
  }
  const result = await callRuntimeBridge("release_session", { ...params, projectPath: target.projectPath, port: params.port ?? runtimeBinding.port });
  runtimeBinding = null;
  return { ...result, binding: getRuntimeBinding() };
}

async function captureRuntimeScreenshot(params = {}) {
  const target = getRuntimeTarget(params);
  const projectPath = target.projectPath;
  const outputPath = resolveInside(projectPath, normalizeProjectPath(params.outputPath ?? ""));
  const result = await callRuntimeBridge("capture_viewport", { ...params, projectPath, outputPath });
  return { ...result, outputPath, projectRelativePath: relative(projectPath, outputPath).replaceAll(sep, "/") };
}

function getRuntimePortCandidates(params, run) {
  if (params.port) return [Number(params.port)];
  const projectPath = resolve(params.projectPath);
  const cached = runtimeProjectPorts.get(projectPath);
  const stable = stableProjectPort(projectPath) + 1;
  return [...new Set([cached, run?.runtimePort, stable, ...Array.from({ length: 16 }, (_, index) => stable + index)].filter((port) => port >= 1 && port <= 65535))];
}

function getEditorPortCandidates(params) {
  if (params.port) return [Number(params.port)];
  if (params.projectPath) {
    const projectPath = resolve(params.projectPath);
    const cached = editorProjectPorts.get(projectPath);
    const stable = stableProjectPort(projectPath);
    return [...new Set([cached, stable, ...Array.from({ length: 16 }, (_, index) => stable + index), Number(process.env.GODOT_MCP_PORT ?? 6505)].filter((port) => port >= 1 && port <= 65535))];
  }
  return [Number(process.env.GODOT_MCP_PORT ?? 6505)];
}

function stableProjectPort(projectPath) {
  const normalized = resolve(projectPath).replaceAll("\\", "/").replace(/\/$/, "").toLowerCase();
  let hash = 0;
  for (const character of normalized) hash = (hash * 31 + character.codePointAt(0)) % 500;
  return 6505 + hash;
}

async function callEditorBridgeOnce(url, operation, params) {
  const WebSocketImpl = await getWebSocketImplementation();
  const requestId = randomUUID();
  const timeoutMs = Number(params.timeoutMs ?? 10000);
  return new Promise((resolveResult, rejectResult) => {
    const socket = new WebSocketImpl(url);
    let settled = false;
    const timer = setTimeout(() => finishReject(new McpError(-32003, `Godot editor bridge timed out: ${url}`)), timeoutMs);
    const finishResolve = (value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try { socket.close(); } catch {}
      resolveResult(value);
    };
    const finishReject = (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try { socket.close(); } catch {}
      rejectResult(error instanceof Error ? error : new Error(String(error)));
    };
    const sendRequest = () => {
      try {
        socket.send(JSON.stringify({ id: requestId, operation, params }));
      } catch (error) {
        finishReject(error);
      }
    };
    const handleMessage = (event) => {
      const raw = event?.data ?? event;
      const text = Buffer.isBuffer(raw) ? raw.toString("utf8") : String(raw);
      let response;
      try { response = JSON.parse(text); } catch { return; }
      if (response.id !== requestId) return;
      if (response.ok === false) finishReject(new McpError(-32003, response.error ?? "Godot editor operation failed", response.details));
      else finishResolve(response.result ?? response);
    };
    const handleError = (error) => finishReject(error instanceof Error ? error : new Error("Godot editor bridge connection failed"));
    if (typeof socket.addEventListener === "function") {
      socket.addEventListener("open", sendRequest);
      socket.addEventListener("message", handleMessage);
      socket.addEventListener("error", handleError);
    } else {
      socket.on("open", sendRequest);
      socket.on("message", (data) => handleMessage({ data }));
      socket.on("error", handleError);
    }
  });
}


async function callRuntimeBridgeOnce(url, operation, params) {
  const WebSocketImpl = await getWebSocketImplementation();
  const requestId = randomUUID();
  const timeoutMs = Number(params.timeoutMs ?? 10000);
  return new Promise((resolveResult, rejectResult) => {
    const socket = new WebSocketImpl(url);
    let settled = false;
    const timer = setTimeout(() => finishReject(new McpError(-32003, "Godot runtime bridge timed out: " + url)), timeoutMs);
    const finishResolve = (value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try { socket.close(); } catch {}
      resolveResult(value);
    };
    const finishReject = (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try { socket.close(); } catch {}
      rejectResult(error instanceof Error ? error : new Error(String(error)));
    };
    const sendRequest = () => {
      try {
        socket.send(JSON.stringify({ id: requestId, operation, params }));
      } catch (error) {
        finishReject(error);
      }
    };
    const handleMessage = (event) => {
      const raw = event?.data ?? event;
      const text = Buffer.isBuffer(raw) ? raw.toString("utf8") : String(raw);
      let response;
      try { response = JSON.parse(text); } catch { return; }
      if (response.id !== requestId) return;
      if (response.ok === false) finishReject(new McpError(-32003, response.error ?? "Godot runtime operation failed", response.details));
      else finishResolve(response.result ?? response);
    };
    const handleError = (error) => finishReject(error instanceof Error ? error : new Error("Godot runtime bridge connection failed"));
    if (typeof socket.addEventListener === "function") {
      socket.addEventListener("open", sendRequest);
      socket.addEventListener("message", handleMessage);
      socket.addEventListener("error", handleError);
    } else {
      socket.on("open", sendRequest);
      socket.on("message", (data) => handleMessage({ data }));
      socket.on("error", handleError);
    }
  });
}

function tool(name, description, inputSchema, handler) {
  return { name, description, inputSchema: makeProjectPathOptional(inputSchema), handler };
}

function makeProjectPathOptional(inputSchema) {
  if (!inputSchema?.required?.includes("projectPath")) return inputSchema;
  return {
    ...inputSchema,
    required: inputSchema.required.filter((name) => name !== "projectPath"),
    properties: {
      ...inputSchema.properties,
      projectPath: {
        ...inputSchema.properties?.projectPath,
        description: "Optional absolute Godot project path. Defaults to the project selected in Godot MCP Toolkit.",
      },
    },
  };
}

function projectSchema() {
  return {
    type: "object",
    required: ["projectPath"],
    properties: { projectPath: { type: "string" } },
    additionalProperties: false,
  };
}

function sceneOperationSchema(properties, required = []) {
  return {
    type: "object",
    required: ["projectPath", "scenePath", ...required],
    properties: { projectPath: { type: "string" }, scenePath: { type: "string" }, ...properties },
    additionalProperties: false,
  };
}

function writeMessage(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

function sendResult(id, result) {
  if (id === undefined) return;
  writeMessage({ jsonrpc: "2.0", id, result });
}

function sendError(id, code, message, data) {
  if (id === undefined) return;
  writeMessage({ jsonrpc: "2.0", id, error: { code, message, ...(data === undefined ? {} : { data }) } });
}

function mcpText(value) {
  return typeof value === "string" ? value : JSON.stringify(value, null, 2);
}

async function handleMessage(message) {
  if (!message || message.jsonrpc !== "2.0") return;
  const method = message.method;
  if (method === "notifications/initialized" || method === "notifications/cancelled") return;
  try {
    if (method === "initialize") {
      const requestedProtocol = message.params?.protocolVersion;
      sendResult(message.id, {
        protocolVersion: SUPPORTED_PROTOCOL_VERSIONS.has(requestedProtocol) ? requestedProtocol : PROTOCOL_VERSION,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: SERVER_NAME, version: SERVER_VERSION },
        instructions: "projectPath may be omitted when a current project is configured by the launcher. Live editor tools use one-to-one conversation binding: the first live call claims one editor and project until release_editor_binding or lease expiry. Use an absolute Godot project directory when switching projects. Scene and file paths are project-relative.",
      });
      return;
    }
    if (method === "ping") {
      sendResult(message.id, {});
      return;
    }
    if (method === "tools/list") {
      sendResult(message.id, { tools: tools.filter((entry) => isToolEnabled(entry.name)).map(({ handler, ...definition }) => definition) });
      return;
    }
    if (method === "tools/call") {
      const name = message.params?.name;
      const entry = toolMap.get(name);
      if (!entry) throw new McpError(-32602, `Unknown tool: ${name}`);
      if (!isToolEnabled(name)) throw new McpError(-32602, `Tool group disabled: ${getToolGroup(name)}`);
      const value = await entry.handler(message.params?.arguments ?? {});
      sendResult(message.id, { content: [{ type: "text", text: mcpText(value) }], isError: false });
      return;
    }
    throw new McpError(-32601, `Method not found: ${method}`);
  } catch (error) {
    const normalized = normalizeError(error);
    if (method === "tools/call") {
      sendResult(message.id, { content: [{ type: "text", text: normalized.message }], isError: true });
    } else {
      sendError(message.id, normalized.code ?? -32000, normalized.message, normalized.data);
    }
  }
}

class McpError extends Error {
  constructor(code, message, data) {
    super(message);
    this.code = code;
    this.data = data;
  }
}

function normalizeError(error) {
  if (error instanceof McpError) return error;
  return new McpError(-32000, error instanceof Error ? error.message : String(error));
}

function requireProject(projectPath) {
  const selectedProject = typeof projectPath === "string" && projectPath.trim() ? projectPath : getDefaultProjectPath();
  if (!selectedProject) throw new McpError(-32602, "No Godot project is selected. Open a project with Godot MCP Toolkit or provide projectPath.");
  const absolutePath = resolve(selectedProject);
  if (!existsSync(join(absolutePath, "project.godot"))) throw new McpError(-32602, `Not a Godot project: ${absolutePath}`);
  return absolutePath;
}

function getDefaultProjectPath() {
  const configured = process.env.GODOT_MCP_PROJECT?.trim();
  if (configured) return configured;
  const stateFile = getActiveProjectFile();
  if (!existsSync(stateFile)) return null;
  try {
    const state = JSON.parse(readFileSync(stateFile, "utf8"));
    return typeof state.projectPath === "string" && state.projectPath.trim() ? state.projectPath : null;
  } catch {
    return null;
  }
}

function getActiveProjectFile() {
  if (process.env.GODOT_MCP_ACTIVE_PROJECT_FILE) return resolve(process.env.GODOT_MCP_ACTIVE_PROJECT_FILE);
  const stateRoot = process.env.LOCALAPPDATA ?? process.env.XDG_STATE_HOME ?? join(homedir(), ".local", "state");
  return join(stateRoot, "GodotMCP", "active-project.json");
}

function resolveInside(projectPath, projectRelativePath, allowProjectRoot = false) {
  if (!projectRelativePath || typeof projectRelativePath !== "string") throw new McpError(-32602, "A project-relative path is required");
  if (isAbsolute(projectRelativePath)) throw new McpError(-32602, `Path must be project-relative: ${projectRelativePath}`);
  const root = resolve(projectPath);
  const target = resolve(root, projectRelativePath);
  const rel = relative(root, target);
  if (!allowProjectRoot && !rel) throw new McpError(-32602, "The project root is not a file path");
  if (rel === ".." || rel.startsWith(`..${sep}`) || isAbsolute(rel)) throw new McpError(-32602, `Path escapes project root: ${projectRelativePath}`);
  return target;
}

function normalizeExtensions(extensions) {
  if (!Array.isArray(extensions) || extensions.length === 0) return null;
  return new Set(extensions.map((item) => (item.startsWith(".") ? item.toLowerCase() : `.${item.toLowerCase()}`)));
}

async function listProjects(root, maxDepth) {
  const start = resolve(root);
  const results = [];
  async function walk(directory, depth) {
    if (depth > maxDepth || results.length >= 200) return;
    let entries;
    try {
      entries = await fs.readdir(directory, { withFileTypes: true });
    } catch {
      return;
    }
    if (entries.some((entry) => entry.isFile() && entry.name === "project.godot")) {
      results.push({ projectPath: directory, name: basename(directory) });
      return;
    }
    for (const entry of entries) {
      if (!entry.isDirectory() || entry.name.startsWith(".") || ["node_modules", ".git", ".godot"].includes(entry.name)) continue;
      await walk(join(directory, entry.name), depth + 1);
    }
  }
  await walk(start, 0);
  return { root: start, projects: results, count: results.length };
}

async function getProjectInfo(projectPath) {
  const content = await fs.readFile(join(projectPath, "project.godot"), "utf8");
  const settings = {};
  let section = "";
  for (const line of content.split(/\r?\n/)) {
    const sectionMatch = line.match(/^\[([^\]]+)\]$/);
    if (sectionMatch) {
      section = sectionMatch[1];
      continue;
    }
    const match = line.match(/^([^=;#]+?)\s*=\s*(.+)$/);
    if (match) settings[`${section}/${match[1].trim()}`] = match[2].trim();
  }
  return {
    projectPath,
    projectFile: join(projectPath, "project.godot"),
    name: unquoteGodotValue(settings["application/config/name"]) ?? basename(projectPath),
    runMainScene: unquoteGodotValue(settings["application/run/main_scene"]) ?? null,
    configVersion: settings["config_version"] ?? null,
    settings,
  };
}

function unquoteGodotValue(value) {
  if (value === undefined) return null;
  if (value.startsWith('"') && value.endsWith('"')) return value.slice(1, -1).replaceAll('\\"', '"').replaceAll('\\\\', '\\');
  return value;
}

async function createProject(projectPath, name, renderer, createMainScene) {
  if (!projectPath || typeof projectPath !== "string") throw new McpError(-32602, "projectPath is required");
  const root = resolve(projectPath);
  if (existsSync(join(root, "project.godot"))) throw new McpError(-32602, `A Godot project already exists: ${root}`);
  await fs.mkdir(root, { recursive: true });
  const projectName = name || basename(root);
  const mainScene = createMainScene ? "res://main.tscn" : "";
  const projectFile = [
    "; Engine configuration file.",
    "; Generated by Godot MCP Toolkit.",
    "",
    "config_version=5",
    "",
    "[application]",
    `config/name=${formatGodotValue(projectName)}`,
    ...(mainScene ? [`run/main_scene=${formatGodotValue(mainScene)}`] : []),
    "",
    "[display]",
    "",
    "[rendering]",
    `renderer/rendering_method=${formatGodotValue(renderer)}`,
    `renderer/rendering_method.mobile=${formatGodotValue(renderer === "forward_plus" ? "mobile" : renderer)}`,
    "",
  ].join("\n");
  await fs.writeFile(join(root, "project.godot"), projectFile, "utf8");
  if (createMainScene) {
    await fs.writeFile(join(root, "main.tscn"), `[gd_scene load_steps=1 format=3]\n\n[node name="Main" type="Node2D"]\n`, "utf8");
  }
  return { projectPath: root, name: projectName, renderer, mainScene: mainScene || null, created: true };
}

async function setProjectSetting(projectPath, setting, value) {
  if (typeof setting !== "string" || !setting.trim()) throw new McpError(-32602, "setting is required");
  const target = join(projectPath, "project.godot");
  const original = await fs.readFile(target, "utf8");
  const parts = setting.split("/").filter(Boolean);
  const knownSections = new Set(["application", "display", "rendering", "input", "physics", "audio", "editor", "layer_names", "debug", "filesystem", "network", "gui"]);
  let section = parts[0];
  let key = parts.slice(1).join("/");
  if (parts[0] === "config") {
    section = "application";
    key = parts.join("/");
  } else if (!knownSections.has(parts[0]) || !key) {
    section = "application";
    key = parts.join("/");
  }
  const newLine = `${key}=${formatGodotValue(value)}`;
  const lines = original.split(/\r?\n/);
  const header = `[${section}]`;
  let sectionStart = lines.findIndex((line) => line.trim() === header);
  if (sectionStart < 0) {
    if (lines.length && lines[lines.length - 1] !== "") lines.push("");
    lines.push(header, newLine, "");
  } else {
    let sectionEnd = lines.length;
    for (let index = sectionStart + 1; index < lines.length; index += 1) {
      if (/^\[[^\]]+\]$/.test(lines[index].trim())) {
        sectionEnd = index;
        break;
      }
    }
    const keyPattern = new RegExp(`^${escapeRegExp(key)}\\s*=`);
    const existingIndex = lines.slice(sectionStart + 1, sectionEnd).findIndex((line) => keyPattern.test(line.trim()));
    if (existingIndex >= 0) lines[sectionStart + 1 + existingIndex] = newLine;
    else lines.splice(sectionEnd, 0, newLine);
  }
  await fs.writeFile(target, lines.join("\n"), "utf8");
  return { projectPath, setting, section, key, value, updated: true };
}

function formatGodotValue(value) {
  if (typeof value === "string") return `"${value.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`;
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "number") return String(value);
  if (value === null) return "null";
  if (Array.isArray(value)) return `[${value.map(formatGodotValue).join(", ")}]`;
  if (value && typeof value === "object") return `{${Object.entries(value).map(([key, item]) => `${formatGodotValue(key)}: ${formatGodotValue(item)}`).join(", ")}}`;
  throw new McpError(-32602, `Unsupported Godot setting value: ${typeof value}`);
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

async function duplicateScene(projectPath, sourcePath, destinationPath) {
  const source = resolveInside(projectPath, sourcePath);
  const destination = resolveInside(projectPath, destinationPath);
  if (!sourcePath.endsWith(".tscn") || !destinationPath.endsWith(".tscn")) throw new McpError(-32602, "Both scene paths must end with .tscn");
  await fs.stat(source);
  await fs.mkdir(dirname(destination), { recursive: true });
  await fs.copyFile(source, destination);
  return { sourcePath: normalizeProjectPath(sourcePath), destinationPath: normalizeProjectPath(destinationPath), duplicated: true };
}

async function createScript(projectPath, scriptPath, baseClass, body, overwrite) {
  const target = resolveInside(projectPath, scriptPath);
  if (!scriptPath.endsWith(".gd")) throw new McpError(-32602, "scriptPath must end with .gd");
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(baseClass)) throw new McpError(-32602, "extends must be a simple Godot class name");
  const existed = existsSync(target);
  if (existed && !overwrite) throw new McpError(-32602, `Script already exists: ${scriptPath}`);
  await fs.mkdir(dirname(target), { recursive: true });
  const content = `extends ${baseClass}\n\n${body ? `${body.trim()}\n` : ""}`;
  await fs.writeFile(target, content, "utf8");
  return { scriptPath: normalizeProjectPath(scriptPath), bytes: Buffer.byteLength(content, "utf8"), created: true, overwritten: overwrite && existed };
}

async function analyzeScript(projectPath, scriptPath, timeoutMs) {
  const normalized = normalizeProjectPath(scriptPath);
  resolveInside(projectPath, normalized);
  const binary = findGodotBinary();
  if (!binary) throw new McpError(-32001, "Godot executable not found. Set GODOT_BIN.");
  const result = await runProcess(binary, ["--headless", "--path", projectPath, "--check-only", "--script", normalized], { timeoutMs });
  return { projectPath, scriptPath: normalized, ok: result.code === 0, exitCode: result.code, signal: result.signal, stdout: result.stdout, stderr: result.stderr, diagnostics: `${result.stdout}\n${result.stderr}`.trim() };
}

async function captureScreenshot(params) {
  const projectPath = requireProject(params.projectPath);
  const requested = params.outputPath || join("screenshots", `${basename(params.scenePath, ".tscn")}-${Date.now()}.png`);
  const outputPath = resolveInside(projectPath, requested);
  await fs.mkdir(dirname(outputPath), { recursive: true });
  const result = await runSceneOperation({ ...params, projectPath, outputPath }, "capture_screenshot");
  return { ...result, outputPath, projectRelativePath: relative(projectPath, outputPath).replaceAll(sep, "/") };
}

async function runAutomationTest(projectPath, testPath, timeoutMs) {
  const normalized = normalizeProjectPath(testPath);
  resolveInside(projectPath, normalized);
  const binary = findGodotBinary();
  if (!binary) throw new McpError(-32001, "Godot executable not found. Set GODOT_BIN.");
  const result = await runProcess(binary, ["--headless", "--path", projectPath, "--script", normalized], { timeoutMs });
  return { projectPath, testPath: normalized, passed: result.code === 0, exitCode: result.code, signal: result.signal, stdout: result.stdout, stderr: result.stderr };
}

async function getGameContext(projectPath, includeScripts, maxFiles) {
  const project = await getProjectInfo(projectPath);
  const files = await listFiles(projectPath, ".", true, null, maxFiles);
  const sceneFiles = files.files.filter((file) => file.extension.toLowerCase() === ".tscn");
  const scriptFiles = includeScripts ? files.files.filter((file) => file.extension.toLowerCase() === ".gd") : [];
  const scenes = [];
  for (const file of sceneFiles.slice(0, 100)) {
    let content = "";
    try { content = await fs.readFile(resolveInside(projectPath, file.path), "utf8"); } catch { continue; }
    const nodes = [...content.matchAll(/\[node\s+name="([^"]+)"\s+type="([^"]+)"[^\]]*\]/g)].map((match) => ({ name: match[1], type: match[2] }));
    const resources = [...content.matchAll(/path="(res:\/\/[^" ]+)"/g)].map((match) => match[1]);
    scenes.push({ path: file.path, nodeCount: nodes.length, nodes: nodes.slice(0, 200), resources: [...new Set(resources)] });
  }
  const scripts = [];
  for (const file of scriptFiles.slice(0, 100)) {
    let content = "";
    try { content = await fs.readFile(resolveInside(projectPath, file.path), "utf8"); } catch { continue; }
    scripts.push({ path: file.path, lines: content.split(/\r?\n/).length, extends: content.match(/^extends\s+([^\s]+)/m)?.[1] ?? null, classes: [...content.matchAll(/^class_name\s+([^\s]+)/gm)].map((match) => match[1]), signals: [...content.matchAll(/^signal\s+([^\s(]+)/gm)].map((match) => match[1]), functions: [...content.matchAll(/^func\s+([^\s(]+)/gm)].map((match) => match[1]).slice(0, 100) });
  }
  return { schemaVersion: 1, project, files: files.files, scenes, scripts, entryScene: project.runMainScene, truncated: files.truncated };
}

async function walkFiles(root, directory, recursive, extensions, result, maxResults) {
  if (result.length >= maxResults) return;
  const entries = await fs.readdir(directory, { withFileTypes: true });
  for (const entry of entries) {
    if (result.length >= maxResults) return;
    if (entry.name.startsWith(".") && entry.name !== ".godot") continue;
    const target = join(directory, entry.name);
    if (entry.isDirectory()) {
      if (recursive && ![".godot", "node_modules"].includes(entry.name)) await walkFiles(root, target, true, extensions, result, maxResults);
      continue;
    }
    if (extensions && !extensions.has(extname(entry.name).toLowerCase())) continue;
    const stat = await fs.stat(target);
    result.push({ path: relative(root, target).replaceAll(sep, "/"), size: stat.size, extension: extname(entry.name) });
  }
}

async function listFiles(projectPath, path, recursive, extensions, maxResults) {
  const target = resolveInside(projectPath, path, true);
  const stat = await fs.stat(target);
  if (!stat.isDirectory()) throw new McpError(-32602, `Not a directory: ${path}`);
  const result = [];
  await walkFiles(projectPath, target, recursive, normalizeExtensions(extensions), result, maxResults);
  return { projectPath, path: relative(projectPath, target).replaceAll(sep, "/") || ".", files: result, truncated: result.length >= maxResults };
}

async function readProjectFile(projectPath, path) {
  const target = resolveInside(projectPath, path);
  const stat = await fs.stat(target);
  if (stat.size > MAX_FILE_BYTES) throw new McpError(-32602, `File is larger than ${MAX_FILE_BYTES} bytes: ${path}`);
  return { path, content: await fs.readFile(target, "utf8"), size: stat.size };
}

async function writeProjectFile(projectPath, path, content, createDirectories) {
  const target = resolveInside(projectPath, path);
  if (typeof content !== "string") throw new McpError(-32602, "content must be a string");
  if (Buffer.byteLength(content, "utf8") > MAX_FILE_BYTES) throw new McpError(-32602, `Content is larger than ${MAX_FILE_BYTES} bytes`);
  const extension = extname(target).toLowerCase();
  const blocked = new Set([".exe", ".dll", ".com", ".bat", ".cmd", ".ps1", ".vbs", ".scr"]);
  if (blocked.has(extension) && process.env.GODOT_MCP_ALLOW_UNSAFE_WRITES !== "1") throw new McpError(-32602, `Refusing to write executable file: ${path}`);
  if (createDirectories) await fs.mkdir(dirname(target), { recursive: true });
  await fs.writeFile(target, content, "utf8");
  return { path, size: Buffer.byteLength(content, "utf8"), written: true };
}

async function searchProject(projectPath, pattern, regex, path, extensions, maxResults) {
  const listed = await listFiles(projectPath, path, true, extensions, 5000);
  const matcher = regex ? new RegExp(pattern, "g") : null;
  const results = [];
  for (const file of listed.files) {
    if (results.length >= maxResults) break;
    let content;
    try {
      content = await fs.readFile(resolveInside(projectPath, file.path), "utf8");
    } catch {
      continue;
    }
    const lines = content.split(/\r?\n/);
    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index];
      const match = regex ? matcher.exec(line) : line.toLowerCase().includes(String(pattern).toLowerCase()) ? [pattern] : null;
      if (match) {
        results.push({ path: file.path, line: index + 1, text: line, match: match[0] });
        if (results.length >= maxResults) break;
      }
      if (regex) matcher.lastIndex = 0;
    }
  }
  return { pattern, regex, results, truncated: results.length >= maxResults };
}

function findGodotBinary(explicit) {
  for (const candidate of [explicit, process.env.GODOT_BIN, process.env.GODOT_PATH, "godot", "godot4"].filter(Boolean)) {
    const result = spawnSync(candidate, ["--version"], { encoding: "utf8", windowsHide: true });
    if (result.status === 0) return candidate;
  }
  return null;
}

function runGodotVersion(explicit) {
  const binary = findGodotBinary(explicit);
  if (!binary) throw new McpError(-32001, "Godot executable not found. Set GODOT_BIN or GODOT_PATH, or pass godotBinary.");
  const result = spawnSync(binary, ["--version"], { encoding: "utf8", windowsHide: true });
  if (result.status !== 0) throw new McpError(-32001, result.stderr || "Godot version check failed");
  return { godotBinary: binary, version: result.stdout.trim(), stderr: result.stderr.trim() };
}

async function checkProject(projectPath, timeoutMs) {
  const binary = findGodotBinary();
  if (!binary) throw new McpError(-32001, "Godot executable not found. Set GODOT_BIN.");
  const result = await runProcess(binary, ["--headless", "--editor", "--path", projectPath, "--quit"], { timeoutMs });
  return { projectPath, ok: result.code === 0, exitCode: result.code, signal: result.signal, stdout: result.stdout, stderr: result.stderr, diagnostics: `${result.stdout}\n${result.stderr}`.trim() };
}

function launchEditor(projectPath, explicit) {
  const binary = findGodotBinary(explicit);
  if (!binary) throw new McpError(-32001, "Godot executable not found. Set GODOT_BIN or GODOT_PATH, or pass godotBinary.");
  const child = spawn(binary, ["--editor", "--path", projectPath], { detached: true, stdio: "ignore", windowsHide: false });
  child.unref();
  return { projectPath, godotBinary: binary, pid: child.pid, launched: true };
}

async function runProject(projectPath, scene, explicit, headless) {
  const binary = findGodotBinary(explicit);
  if (!binary) throw new McpError(-32001, "Godot executable not found. Set GODOT_BIN or GODOT_PATH, or pass godotBinary.");
  const runId = randomUUID();
  await fs.mkdir(runtimeDirectory, { recursive: true });
  const logPath = join(runtimeDirectory, `${runId}.log`);
  const args = [...(headless ? ["--headless"] : []), "--path", projectPath];
  if (scene) args.push(scene);
  const log = createWriteStream(logPath, { encoding: "utf8" });
  const runtimePort = stableProjectPort(projectPath) + 1;
  const child = spawn(binary, args, { cwd: projectPath, stdio: ["ignore", "pipe", "pipe"], windowsHide: true, env: { ...process.env, GODOT_MCP_RUNTIME_PORT: String(runtimePort) } });
  child.stdout.pipe(log);
  child.stderr.pipe(log);
  const entry = { runId, projectPath, logPath, child, runtimePort, startedAt: new Date().toISOString(), exitCode: null, signal: null };
  projectProcesses.set(runId, entry);
  child.once("exit", (code, signal) => {
    entry.exitCode = code;
    entry.signal = signal;
    log.end();
  });
  return { runId, projectPath, pid: child.pid, logPath, runtimePort, startedAt: entry.startedAt, running: true };
}

async function getDebugOutput(runId, projectPath, tailLines, clear) {
  const entry = runId ? projectProcesses.get(runId) : [...projectProcesses.values()].find((item) => projectPath && item.projectPath === resolve(projectPath));
  if (!entry) throw new McpError(-32602, "No matching Godot run found");
  let content = "";
  try {
    content = await fs.readFile(entry.logPath, "utf8");
  } catch {
    content = "";
  }
  if (clear) await fs.writeFile(entry.logPath, "", "utf8");
  return { runId: entry.runId, projectPath: entry.projectPath, pid: entry.child.pid, running: entry.exitCode === null, exitCode: entry.exitCode, signal: entry.signal, output: content.split(/\r?\n/).slice(-tailLines).join("\n") };
}

async function stopProject(runId, projectPath) {
  const entry = runId ? projectProcesses.get(runId) : [...projectProcesses.values()].find((item) => projectPath && item.projectPath === resolve(projectPath));
  if (!entry) throw new McpError(-32602, "No matching Godot run found");
  if (entry.exitCode !== null) return { runId: entry.runId, stopped: false, alreadyExited: true, exitCode: entry.exitCode };
  if (process.platform === "win32") spawnSync("taskkill", ["/PID", String(entry.child.pid), "/T", "/F"], { windowsHide: true });
  else entry.child.kill("SIGTERM");
  return { runId: entry.runId, stopped: true, pid: entry.child.pid };
}

async function runSceneOperation(params, operation) {
  const projectPath = requireProject(params.projectPath);
  const scenePath = normalizeProjectPath(params.scenePath ?? "");
  const sceneRequired = !["get_uid", "update_project_uids"].includes(operation);
  if (sceneRequired && (!scenePath || !scenePath.endsWith(".tscn") || scenePath.startsWith(".."))) throw new McpError(-32602, `Invalid scene path: ${params.scenePath}`);
  const request = { operation, ...params, scenePath };
  const requestId = randomUUID();
  await fs.mkdir(runtimeDirectory, { recursive: true });
  const requestFile = join(runtimeDirectory, `${requestId}.request.json`);
  const responseFile = join(runtimeDirectory, `${requestId}.response.json`);
  await fs.writeFile(requestFile, JSON.stringify(request), "utf8");
  const binary = findGodotBinary();
  if (!binary) throw new McpError(-32001, "Godot executable not found. Set GODOT_BIN.");
  const result = await runProcess(binary, ["--headless", "--path", projectPath, "--script", operationScript, "--", requestFile, responseFile], { timeoutMs: 60000 });
  let response;
  try {
    response = JSON.parse(await fs.readFile(responseFile, "utf8"));
  } catch {
    response = { ok: false, error: "Godot did not produce a response", stdout: result.stdout, stderr: result.stderr };
  }
  await Promise.allSettled([fs.rm(requestFile, { force: true }), fs.rm(responseFile, { force: true })]);
  if (result.code !== 0 && response?.ok !== true) throw new McpError(-32002, response?.error ?? result.stderr ?? "Godot operation failed", response);
  if (response?.ok !== true) throw new McpError(-32002, response?.error ?? "Godot operation failed", response);
  return response.result ?? response;
}

function normalizeProjectPath(path) {
  return String(path).replaceAll("\\", "/").replace(/^\.\//, "");
}

function runProcess(command, args, { timeoutMs = 30000 } = {}) {
  return new Promise((resolveResult) => {
    const child = spawn(command, args, { stdio: ["ignore", "pipe", "pipe"], windowsHide: true });
    let stdout = "";
    let stderr = "";
    let settled = false;
    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      child.kill();
      resolveResult({ code: null, signal: "TIMEOUT", stdout, stderr: `${stderr}\nProcess timed out after ${timeoutMs}ms`.trim() });
    }, timeoutMs);
    child.stdout.on("data", (chunk) => { stdout += chunk.toString(); });
    child.stderr.on("data", (chunk) => { stderr += chunk.toString(); });
    child.on("error", (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolveResult({ code: null, signal: null, stdout, stderr: `${stderr}\n${error.message}`.trim() });
    });
    child.on("close", (code, signal) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolveResult({ code, signal, stdout, stderr });
    });
  });
}

const readline = createInterface({ input: process.stdin, crlfDelay: Infinity });
readline.on("line", (line) => {
  if (!line.trim()) return;
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    process.stderr.write("godot-mcp-toolkit: ignored invalid JSON line\n");
    return;
  }
  void handleMessage(message);
});
readline.on("close", () => {
  for (const entry of projectProcesses.values()) {
    if (entry.exitCode === null) entry.child.kill();
  }
});

