$ErrorActionPreference = "Stop"
$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDirectory
$stateRoot = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "GodotMCP" } else { Join-Path $Root ".state" }
$activeProjectFile = Join-Path $stateRoot "active-project.json"
$env:GODOT_MCP_ACTIVE_PROJECT_FILE = $activeProjectFile

if (Test-Path -LiteralPath $activeProjectFile) {
    $activeProject = Get-Content -LiteralPath $activeProjectFile -Raw -Encoding utf8 | ConvertFrom-Json
    if ($activeProject.godotBin -and -not $env:GODOT_BIN -and (Test-Path -LiteralPath $activeProject.godotBin)) {
        $env:GODOT_BIN = [string]$activeProject.godotBin
    }
}

$globalSettingsPath = Join-Path $Root "global-settings.json"
if (Test-Path -LiteralPath $globalSettingsPath) {
    $globalSettings = Get-Content -LiteralPath $globalSettingsPath -Raw -Encoding utf8 | ConvertFrom-Json
    if ($globalSettings.godotBin -and -not $env:GODOT_BIN -and (Test-Path -LiteralPath $globalSettings.godotBin)) {
        $env:GODOT_BIN = [string]$globalSettings.godotBin
    }
}

$settingsPath = Join-Path $Root "settings.local.json"
if (Test-Path -LiteralPath $settingsPath) {
    $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding utf8 | ConvertFrom-Json
    if ($settings.godotBin -and -not $env:GODOT_BIN) { $env:GODOT_BIN = [string]$settings.godotBin }
    if ($settings.projectPath -and -not (Test-Path -LiteralPath $activeProjectFile)) { $env:GODOT_MCP_PROJECT = [string]$settings.projectPath }
}

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { throw "Node.js 18+ is required." }
& node (Join-Path $Root "server\index.mjs")
exit $LASTEXITCODE