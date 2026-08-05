# Capabilities

## Tool Count

The current built-in tool surface is:

- **45 tools by default** — headless project, scene, script, resource, screenshot, test, and diagnostic operations.
- **164 unique tools with `GODOT_MCP_ENABLE_EDITOR_BRIDGE=1` and `GODOT_MCP_TOOL_GROUPS=all`** — adds live Editor, visual authoring, Runtime Agent, and deeper authoring operations.
- **23 documentation categories** — a reader-friendly classification of the 164 unique tools. The categories below are a partition, so the counts add up to 164.
- **Extensions can increase the total** — tools loaded through `GODOT_MCP_EXTENSIONS_DIR` are not included in the built-in count.

> The number of tools exposed to an MCP client depends on the environment variables and enabled tool groups. Do not compare a headless session with an `all` session as if they exposed the same surface.

## 23-Category Inventory

| Category | Count | Representative tools | Coverage |
| --- | ---: | --- | --- |
| **Service and diagnostics** | 3 | `get_server_info`, `get_capabilities`, `get_godot_version` | Server health, capabilities, and Godot version |
| **Project and context** | 7 | `list_projects`, `get_project_info`, `set_project_setting`, `list_export_presets`, `export_project` | Project discovery, settings, context, and preset-based delivery |
| **Files and search** | 4 | `list_files`, `read_file`, `write_file`, `search_project` | Safe project file access and code/resource search |
| **Resources and UIDs** | 4 | `list_resources`, `find_resource_references`, `get_uid`, `update_project_uids` | Resource inventory, references, and UID maintenance |
| **Scenes** | 6 | `create_scene`, `list_scenes`, `duplicate_scene`, `save_scene`, `inspect_scene_tree`, `inspect_node` | Scene creation, duplication, inspection, and serialization |
| **Nodes** | 5 | `add_node`, `remove_node`, `set_node_property`, `load_sprite`, `create_ui_node` | Headless node authoring and property changes |
| **Scripts** | 3 | `create_script`, `attach_script`, `analyze_script` | Script creation, attachment, and parser checks |
| **Headless screenshots and checks** | 3 | `capture_screenshot`, `check_project`, `profile_scene` | Render captures, project health, and lightweight profiling |
| **Headless launch and tests** | 6 | `launch_editor`, `run_project`, `get_debug_output`, `stop_project`, `simulate_input`, `run_automation_test` | Deterministic launches, output, input simulation, and tests |
| **Editor binding and workspace** | 13 | `bind_editor`, `get_editor_info`, `get_editor_workspace`, `inspect_editor_imports`, `reimport_editor_resources` | Live Editor connection, workspace, plugins, import health, logs, and filesystem reload |
| **Editor scenes and selection** | 16 | `get_editor_scene_tree`, `open_scene`, `save_current_scene`, `select_editor_nodes`, `set_editor_property`, `capture_editor_screenshot` | Live scene tree, selection, Undo/Redo authoring, and viewport capture |
| **Editor scripts and debugging** | 10 | `get_script_editor_state`, `edit_editor_script`, `open_editor_script`, `goto_editor_script_line`, `get_editor_breakpoints` | Script buffers, caret/selection edits, navigation, and debugger state |
| **UI, themes, and resources** | 9 | `create_ui_screen`, `configure_control_layout`, `edit_theme_resource`, `edit_editor_resource`, `assign_editor_resource` | Responsive UI, Theme inheritance, and saved resource editing |
| **2D and 3D scenes** | 10 | `create_primitive_mesh`, `edit_array_mesh`, `edit_skeleton_3d`, `edit_skin_resource`, `set_editor_transform` | Blockout, cameras, lights, transforms, meshes, and skeleton/skin resources |
| **Materials and rendering** | 4 | `create_standard_material`, `assign_editor_material`, `configure_stylized_rendering`, `set_canvas_modulate` | Materials, palette tint, and stylized render configuration |
| **Particles, shaders, and effects** | 7 | `create_particles`, `configure_particles`, `create_shader_effect`, `set_shader_parameter`, `create_screen_flash`, `create_post_process` | Particles, shaders, transitions, post-processing, and effect inspection |
| **Animation and timelines** | 10 | `create_animation`, `create_animation_track`, `set_animation_key`, `inspect_animation_timeline`, `set_animation_tree_state`, `edit_animation_curve` | AnimationPlayer, AnimationTree, tracks, keys, curves, and timeline authoring |
| **Navigation** | 5 | `create_navigation_node`, `configure_navigation_agent`, `bake_navigation_region`, `query_runtime_navigation_path` | Navigation regions, agents, baking, inspection, and runtime paths |
| **Physics** | 6 | `create_collision_shape`, `configure_physics_node`, `query_runtime_physics`, `query_runtime_physics_shape`, `get_runtime_body_contacts` | Collision setup, contact reports, rays, points, and overlaps |
| **Audio** | 10 | `edit_editor_audio_bus_effects`, `get_runtime_audio_analysis`, `edit_runtime_audio_bus_effects`, `play_runtime_audio` | Effect chains, peaks/spectrum ranges, players, and live bus control |
| **TileMap** | 6 | `inspect_tilemaps`, `edit_tileset_atlas`, `configure_tileset_terrain`, `configure_tileset_proxy`, `paint_tilemap_terrain` | Cells, atlas alternatives, terrain structure, proxy maps, and painting |
| **Runtime inspection and control** | 10 | `get_runtime_info`, `get_runtime_scene_tree`, `get_runtime_node_properties`, `set_runtime_property`, `call_runtime_method`, `pause_runtime`, `step_runtime`, `get_runtime_binding` | Remote tree/properties, methods, pause/resume/step, and binding lifecycle |
| **Runtime input, observability, and screenshots** | 7 | `send_runtime_input`, `inject_runtime_pointer`, `configure_runtime_observability`, `get_runtime_performance_snapshot`, `get_runtime_logs` | Keyboard/pointer input, watches, structured logs, and runtime evidence |

## Tool Groups

Tool groups control what an MCP client sees. The 23 categories above are for documentation; the server's configurable groups are the operational boundary:

- `editor` — live Editor binding, scene tree, selection, Inspector, screenshots, and Undo/Redo.
- `ui` — UI screen creation, Control layout, Theme overrides, and UI layout inspection.
- `effects` — particles, shaders, screen flash, post-process, canvas modulation, and visual effects.
- `advanced_editor` — Script Editor state, 2D/3D authoring, materials, animation, navigation, physics, audio, themes, plugins, and workspace controls.
- `deep_authoring` — advanced animation state machines, curves, timelines, Skeleton/Skin, Theme and generic Resources, plus TileSet atlas/terrain/proxy authoring.
- `professional_workflows` — Script Editor buffer edits, import inspection, navigation baking, and editor Audio Bus effect chains.
- `runtime_diagnostics` — structured runtime logs, performance snapshots, rigid-body contacts, and live Audio Bus analysis/effects.
- `project`, `scenes`, `nodes`, `scripts`, `resources` — headless project and content workflows.
- `runtime` — project launches plus Runtime Agent inspection, input, observability, physics, navigation, audio, and binding lifecycle.
- `visuals`, `animation`, `tilemap`, `performance`, `ai`, `diagnostics` — focused capture, animation, TileMap, profiling, context, and health tools.

Example configuration:

```json
{
  "env": {
    "GODOT_MCP_ENABLE_EDITOR_BRIDGE": "1",
    "GODOT_MCP_TOOL_GROUPS": "project,scenes,nodes,scripts,resources,diagnostics"
  }
}
```

Use `GODOT_MCP_TOOL_GROUPS=all` only when exploring the complete surface. Smaller groups make tool selection easier and reduce MCP context usage.

## Headless Automation

- Project discovery, creation, settings, files, resources, UID checks, and project health checks.
- Scene, node, sprite, UI, TileMap, animation, script, screenshot, input simulation, and automation-test operations.
- Resource references, lightweight profiling, and machine-readable project context.

## Live Editor Bridge

- One-to-one editor binding, selection, scene tree, undo/redo, Inspector properties, scene opening/saving, viewport screenshots, and filesystem reload.
- Script Editor state, script opening, line navigation, breakpoints, save actions, and editor debug status.
- 2D cameras/lights, UI components, 3D primitives/cameras/lights/transforms/materials, editable ArrayMesh surfaces, animation tracks/keys/Bezier curves/state machines, Navigation nodes, physics shapes, audio buses/players, Theme subresources, TileSet atlases/Terrain painting, generic resource assignment, plugins, workspace, and resource reimport.

## Runtime Agent

- Runtime scene tree/property inspection, property updates, method calls, pause/resume/step, screenshots, 2D/3D ray, point, primitive-shape overlap, and navigation path queries, plus AudioServer control.
- Keyboard and mouse-button injection plus pointer movement, wheel, touch, touch-drag, and complete mouse drags.
- Property watch configuration and cursor-based polling for change events, Runtime Agent logs, and rolling frame metrics.

## Visual Authoring

- UI screen hierarchy and semantic UI controls.
- Particles, shader materials, animation effects, global 2D canvas modulation, and 3D environments.
- 2D palette tint and 3D filmic stylized rendering helpers.
