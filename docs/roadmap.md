# Roadmap

Godot MCP Toolkit prioritizes stable, verifiable semantic operations over brittle pixel-level UI automation. The table below is the current implementation boundary for version `0.4.0`.

## Implemented

- Headless project, scene, node, script, resource, UID, screenshot, input simulation, profiling, automation-test operations, export-preset inspection, and safe project-relative exports.
- One-to-one live Editor binding with scene tree, Inspector properties, selection, undo/redo, editor screenshots, script navigation plus active-buffer caret/selection/text edits, completion requests, and editor diagnostics.
- 2D cameras/lights, UI screens and semantic components, 3D primitives/cameras/lights/transforms, materials, editable ArrayMesh surfaces, Skeleton3D bones/rest poses, Skin binds, particles, shaders, post-process, and stylized rendering helpers.
- Animation tracks/keys, Bezier curves, timeline settings, AnimationTree state-machine creation/states/transitions, transition removal/configuration, BlendSpace foundations, navigation nodes/agents plus NavigationRegion3D baking, collision shapes, physics-node inspection, and TileSet terrain/proxy authoring.
- Audio players/buses, editor/runtime Audio Bus effect chains, live meter peaks and optional spectrum-analyzer ranges, Theme colors/constants/fonts/icons/StyleBoxes/type variations, generic saved-resource editing, plugins, workspace operations, import inspection, and resource reimport.
- Runtime scene/property inspection, method calls, pause/resume/step, screenshots, ray, point, primitive-shape overlap, navigation path queries, rigid-body contact reports, structured cursor-filterable runtime logs, performance snapshots, AudioServer control, and local runtime binding.
- Runtime observability with watched properties, cursor-based event polling, rolling frame metrics, and key/mouse/pointer/wheel/touch/drag injection.

## Partial or Limited

These areas have useful primitives but do not yet reproduce the full Godot Editor workflow:

- **Script Editor and debugger:** active-buffer text, caret, selection, and completion requests are available; semantic refactoring, completion-result retrieval, full debugger call stacks, local variables, and watch expressions are not exposed by a stable public Editor API.
- **3D authoring:** ArrayMesh, Skeleton3D, Skin, transforms, cameras, lights, and material resources are available; imported-mesh vertex editing, full viewport Gizmo gestures, animation retargeting, and visual/advanced material graph tooling are not.
- **Animation:** state machines, BlendSpace 1D/2D foundations, transitions, keys, curves, and timeline settings are available; full graph-layout parity, BlendTree node families, curve-editor handles/tangents beyond direct values, and non-linear timeline UI workflows are not.
- **Navigation and physics:** NavigationRegion3D baking, agents, queries, collision shapes, and rigid-body contacts are available; full 2D navigation polygon authoring, streaming path-event traces, advanced query exclusions, and complete viewport debug-visualization control are not.
- **Audio:** bus effects, playback, basic peaks, and spectrum-analyzer ranges are available; effect-chain visual routing, record-device workflows, complete mixer UI parity, and long-running spectrum streams are not.
- **Import/export and project management:** import validity inspection, Editor reimport, export-preset listing, and Godot CLI export are available; importer-setting authoring, Project Manager database control, platform SDK provisioning, Export Dock gestures, signing management, and all export-panel controls are not.
- **UI resources and TileMap:** Theme fonts/icons/type variations, generic resource persistence, TileSet atlas alternatives, terrain sets, peering bits, and proxy maps are available; every custom resource picker, all TileSet subresource modes, and complete TileMap paint-panel gestures are not.
- **Editor workspace:** common scene, script, selection, plugin, workspace, and main-screen operations are available; every Dock layout gesture and every editor panel are not.

## Next Priorities

1. **Debugger parity:** stack/local-variable snapshots, semantic watch expressions, completion-result capture, symbol navigation, and safe refactoring APIs if future Godot Editor APIs expose them.
2. **3D and animation graphs:** imported-mesh adapters, visual-shader/advanced material graphs, full Gizmo/view helpers, BlendTree variants, animation retargeting, and richer curve/timeline tooling.
3. **Navigation, physics, and audio visualization:** 2D navigation polygon workflows, debug overlays, event traces, query exclusions, mixer routing, record workflows, and streaming analyzers.
4. **Import, export, and project management:** importer-setting contracts, platform preflight, signing-safe export workflows, Project Manager integration, and broader Import/Export Dock support.
5. **Editor parity:** broader workspace layout support and semantic equivalents for remaining high-value Editor workflows.

Feature work is added through focused tool groups, contract tests, compatibility checks, and versioned documentation. This keeps the MCP surface discoverable instead of exposing an unmanageable flat list of tools.
