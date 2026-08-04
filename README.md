# Godot MCP Toolkit

**Godot MCP Toolkit** is a practical MCP server for Godot 4 automation. It combines safe headless project tools with an optional live Editor Bridge and Runtime Agent, so AI assistants can inspect, build, run, test, and iterate on Godot projects.

## Highlights

- **Headless project automation** — create projects and scenes, edit nodes and resources, write GDScript, run checks, capture screenshots, and execute automation tests.
- **Live editor control** — bind one MCP conversation to one Godot editor for undoable scene edits, Inspector changes, selections, scripts, UI, 2D/3D authoring, animation, navigation, physics, audio, themes, plugins, and workspace controls.
- **Runtime remote control** — inspect scene trees and properties, call methods, pause/resume/step, inject keyboard and pointer input, capture game views, query physics, and control AudioServer.
- **Runtime observability** — poll watched property changes, Runtime Agent events, log cursors, and rolling frame metrics without opening another network service.
- **Stylized rendering helpers** — configure 2D palette tinting or 3D filmic environments with ambient color, glow, fog, saturation, contrast, and brightness.

## Quick Start

### Requirements

- Node.js 18 or later.
- A Godot 4 executable. Set its path through `GODOT_BIN` or `GODOT_PATH`.

### Install and build

```powershell
npm.cmd install
npm.cmd run build
```

### MCP configuration

```json
{
  "mcpServers": {
    "godot-mcp-toolkit": {
      "command": "node",
      "args": ["E:/Tools/godot-mcp-toolkit/build/index.mjs"],
      "env": {
        "GODOT_PATH": "E:/Tools/Godot/Godot_v4.7-stable_win64.exe"
      }
    }
  }
}
```

Use `projectPath` with each tool call, or set `GODOT_MCP_PROJECT` for a default project.

## Optional Live Editor and Runtime Control

1. Copy `godot/addons/godot_mcp_pro` to the target project's `addons/godot_mcp_pro` directory.
2. Enable **Godot MCP Toolkit** in **Project Settings → Plugins**.
3. Set `GODOT_MCP_ENABLE_EDITOR_BRIDGE=1` and, when needed, `GODOT_MCP_TOOL_GROUPS=all` in the MCP server environment.
4. Reload Godot and the MCP client.

The plugin automatically registers the Runtime Agent as an autoload. Both the editor and runtime enforce a 90-second one-to-one conversation binding; release it with `release_editor_binding` or `release_runtime_binding` when finished.

## Tool Groups

| Group | Focus |
| --- | --- |
| Project, scenes, nodes, scripts | Safe headless project automation and CI workflows |
| Editor and advanced editor | Live Inspector, scene graph, Script Editor, 2D/3D, animation, navigation, physics, audio, themes, and workspace |
| UI and effects | UI screens/components, particles, shaders, post-process, and stylized rendering |
| Runtime | Remote game control, input, screenshots, metrics, property watches, physics, and audio |
| Resources, performance, AI | Resource inspection, profiling, automated tests, and project context |

See [Capabilities](docs/capabilities.md), [Editor Bridge setup](docs/editor-bridge.md), [Multi-project usage](docs/multi-project.md), [Compatibility](docs/compatibility.md), and the [Roadmap](docs/roadmap.md).

## Development

```powershell
npm.cmd run check
npm.cmd test
npm.cmd run build
```

The test suite validates the MCP contract plus editor and runtime one-to-one binding behavior.

## License

MIT. See [LICENSE](LICENSE). This project is an independent community implementation; see [NOTICE.md](NOTICE.md) for attribution.
