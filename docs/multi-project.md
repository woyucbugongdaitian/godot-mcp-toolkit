# Multi-Project Usage

Every project-facing tool accepts an absolute `projectPath`. This makes headless automation safe across multiple Godot projects without installing the live plugin everywhere.

Use `GODOT_MCP_PROJECT` only when one project should be the default. For projects that require different Godot versions, use separate MCP configurations with different `GODOT_BIN` or `GODOT_PATH` values.

Install the Editor Bridge only in projects that need live editor or runtime control. One live conversation stays bound to one editor/project until released.
