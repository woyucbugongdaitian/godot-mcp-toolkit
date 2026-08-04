# Editor Bridge and Runtime Agent

## Setup

1. Copy `godot/addons/godot_mcp_pro` into the target project as `addons/godot_mcp_pro`.
2. Enable **Godot MCP Toolkit** in **Project Settings → Plugins**.
3. Set `GODOT_MCP_ENABLE_EDITOR_BRIDGE=1`; set `GODOT_MCP_TOOL_GROUPS=all` to expose every live group.
4. Reload Godot and the MCP client.

The plugin registers `GodotMcpRuntimeAgent` as an autoload. Do not add another autoload with the same name.

## Session Binding

Each MCP server process represents one conversation. The first live editor or runtime request claims that Godot instance. The binding expires after 90 seconds without requests, or can be explicitly released. Editor and runtime bindings are independent.

## Runtime Flow

1. Ensure `application/run/main_scene` references a valid scene.
2. Call `run_project`.
3. Call `get_runtime_info` and use runtime operations.
4. Call `release_runtime_binding` and `stop_project` when finished.

Runtime ports default to the stable editor bridge port plus one. `GODOT_MCP_RUNTIME_PORT` can override the runtime port for a launch.
