# Roadmap

Godot MCP Toolkit prioritizes stable, verifiable semantic operations over brittle pixel-level UI automation. The table below is the current implementation boundary for version `0.3.0`.

## Implemented

- Headless project, scene, node, script, resource, UID, screenshot, input simulation, profiling, and automation-test operations.
- One-to-one live Editor binding with scene tree, Inspector properties, selection, undo/redo, editor screenshots, script navigation, and editor diagnostics.
- 2D cameras/lights, UI screens and semantic components, 3D primitives/cameras/lights/transforms, materials, editable ArrayMesh surfaces, particles, shaders, post-process, and stylized rendering helpers.
- Animation tracks/keys, Bezier curves, timeline settings, AnimationTree state-machine creation/states/transitions, navigation nodes/agents, collision shapes, physics-node inspection, audio players/buses, Theme subresources, TileSet atlas/Terrain operations, generic resource assignment, plugins, workspace operations, and resource reimport.
- Runtime scene/property inspection, method calls, pause/resume/step, screenshots, ray, point, primitive-shape overlap, and navigation path queries, AudioServer control, and local runtime binding.
- Runtime observability with watched properties, cursor-based event polling, runtime logs, and rolling frame metrics.
- Runtime input injection for keys, mouse buttons, pointer movement, wheel, touch, touch-drag, and complete mouse drags.

## Partial or Limited

These areas have useful primitives but do not yet reproduce the full Godot Editor workflow:

- **Script Editor:** state, opening, line navigation, breakpoints, save actions, and debugger status are available; write-side selection, completion, refactoring, and full stack/variable views are not.
- **3D authoring:** primitive blockout, transforms, cameras, lights, materials, and scene-owned ArrayMesh creation/inspection/surface updates are available; skeletons, skinning, imported-mesh editing, full gizmo interaction, and advanced material graphs are not.
- **Animation:** tracks, keys, effects, Bezier curves, timeline settings, AnimationTree state-machine creation, states, and transitions are available; transition removal/reordering, blend-space graph authoring, curve tangents beyond explicit key handles, and advanced timeline workflows are not.
- **Navigation and physics:** node creation, agent configuration, collision shapes, inspection, ray queries, point and primitive-shape overlap queries, and navigation path queries are available; baking, path-event streams, contact information, advanced query filters/exclusions, and complete debug visualization are not.
- **Audio:** bus/player inspection and basic playback/volume controls are available; effect-chain authoring, spectrum analysis, meters, and full mixer editing are not.
- **UI resources:** semantic controls, layout, theme overrides, saved Theme color/constant/font-size/StyleBox subresources, and generic node-resource assignment are available; fonts/icons, theme inheritance, and every resource selector are not.
- **TileMap:** cell inspection/editing, connected Terrain painting, and TileSet atlas source/tile creation are available; terrain-set definition, alternatives, proxy mapping, TileSet subresources, and advanced editor workflows are not.
- **Editor workspace:** common scene, script, selection, plugin, workspace, and main-screen operations are available; Project Manager, Import Dock, Export Dock, every Dock layout gesture, and all editor panels are not.

## Next Priorities

1. **Runtime debugging depth:** remote variable watches, richer debugger snapshots, structured log severity/source filters, and more complete frame samples.
2. **2D/3D scene authoring:** stronger transform workflows, batch scene edits, camera/view helpers, navigation baking and debug visualization, contact-level physics diagnostics, and terrain/atlas primitives.
3. **Animation and resources:** transition removal/reordering, blend-space graph operations, advanced curve/keyframe utilities, Theme fonts/icons/inheritance, TileSet terrain-set authoring, and safer resource selection APIs.
4. **Import and export:** importer settings, export presets, platform execution, and preflight validation.
5. **Editor parity:** Script Editor write-side operations, Project Manager integration, Import/Export Dock controls, full gizmo interactions, and broader workspace layout support.

Feature work is added through focused tool groups, contract tests, compatibility checks, and versioned documentation. This keeps the MCP surface discoverable instead of exposing an unmanageable flat list of tools.