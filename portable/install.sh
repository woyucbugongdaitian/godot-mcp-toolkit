#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="${1:-}"
if [[ -z "$PROJECT_PATH" ]]; then echo "Usage: ./portable/install.sh /path/to/godot-project"; exit 2; fi
if [[ ! -f "$PROJECT_PATH/project.godot" ]]; then echo "Not a Godot project: $PROJECT_PATH"; exit 2; fi
command -v node >/dev/null || { echo "Node.js 18+ is required"; exit 2; }
mkdir -p "$PROJECT_PATH/addons"
if [[ -d "$PROJECT_PATH/addons/godot_mcp_pro" ]]; then mv "$PROJECT_PATH/addons/godot_mcp_pro" "$PROJECT_PATH/addons/godot_mcp_pro.backup.$(date +%Y%m%d-%H%M%S)"; fi
cp -R "$ROOT/godot/addons/godot_mcp_pro" "$PROJECT_PATH/addons/godot_mcp_pro"
printf '{\n  "mcpServers": {\n    "godot-mcp-toolkit": {\n      "command": "node",\n      "args": ["%s/server/index.mjs"],\n      "env": {"GODOT_MCP_PROJECT": "%s"}\n    }\n  }\n}\n' "$ROOT" "$PROJECT_PATH" > "$ROOT/mcp-config.generated.json"
echo "Installed Godot MCP Toolkit into: $PROJECT_PATH"
echo "Enable the plugin in Godot Project Settings > Plugins."
