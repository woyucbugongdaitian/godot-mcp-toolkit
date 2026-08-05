# Roadmap

Godot MCP Toolkit prioritizes stable, verifiable semantic operations over brittle pixel-level UI automation. The table below is the current implementation boundary for version `0.3.0`.

## Implemented

- Headless project, scene, node, script, resource, UID, screenshot, input simulation, profiling, and automation-test operations.
- One-to-one live Editor binding with scene tree, Inspector properties, selection, undo/redo, editor screenshots, script navigation, and editor diagnostics.
- 2D cameras/lights, UI screens and semantic components, 3D primitives/cameras/lights/transforms, materials, particles, shaders, post-process, and stylized rendering helpers.
- Animation tracks/keys, AnimationTree state parameters, navigation nodes/agents, collision shapes, physics-node inspection, audio players/buses, themes, plugins, workspace operations, and resource reimport.
- Runtime scene/property inspection, method calls, pause/resume/step, screenshots, ray queries, AudioServer control, and local runtime binding.
- Runtime observability with watched properties, cursor-based event polling, runtime logs, and rolling frame metrics.
- Runtime input injection for keys, mouse buttons, pointer movement, wheel, touch, touch-drag, and complete mouse drags.

## Partial or Limited

These areas have useful primitives but do not yet reproduce the full Godot Editor workflow:

- **Script Editor:** state, opening, line navigation, breakpoints, save actions, and debugger status are available; write-side selection, completion, refactoring, and full stack/variable views are not.
- **3D authoring:** primitive blockout, transforms, cameras, lights, and materials are available; mesh editing, skeletons, skinning, and full gizmo interaction are not.
- **Animation:** tracks, keys, effects, and basic AnimationTree parameters are available; state-machine graph editing, curve tools, and advanced timeline workflows are not.
- **Navigation and physics:** node creation, agent configuration, collision shapes, inspection, and ray queries are available; baking, path-event streams, contacts, shape-query suites, and complete debug visualization are not.
- **Audio:** bus/player inspection and basic playback/volume controls are available; effect-chain authoring, spectrum analysis, meters, and full mixer editing are not.
- **UI resources:** semantic controls, layout, and theme overrides are available; advanced Theme subresources and every resource selector are not.
- **TileMap:** cell inspection and editing are available; terrain painting, atlas authoring, TileSet subresources, and advanced editor workflows are not.
- **Editor workspace:** common scene, script, selection, plugin, workspace, and main-screen operations are available; Project Manager, Import Dock, Export Dock, every Dock layout gesture, and all editor panels are not.

## Next Priorities

1. **Runtime debugging depth:** remote variable watches, richer debugger snapshots, structured log severity/source filters, and more complete frame samples.
2. **2D/3D scene authoring:** stronger transform workflows, batch scene edits, camera/view helpers, navigation and physics debug visualization, and terrain/atlas primitives.
3. **Animation and resources:** state-machine graph operations, curve/keyframe utilities, Theme/TileSet subresources, and safer resource selection APIs.
4. **Import and export:** importer settings, export presets, platform execution, and preflight validation.
5. **Editor parity:** Script Editor write-side operations, Project Manager integration, Import/Export Dock controls, and broader workspace layout support.

Feature work is added through focused tool groups, contract tests, compatibility checks, and versioned documentation. This keeps the MCP surface discoverable instead of exposing an unmanageable flat list of tools.