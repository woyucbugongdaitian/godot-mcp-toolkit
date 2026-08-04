# Compatibility

Godot MCP Toolkit targets Godot 4. It negotiates MCP protocol versions `2024-11-05`, `2025-03-26`, and `2025-06-18`.

The server uses runtime feature checks for Godot APIs that vary across 4.x releases. Unsupported nodes, properties, or methods return structured errors instead of terminating the MCP process.

Public tool schemas are additive where possible. New optional fields preserve existing client calls; breaking schema changes require a major release.
