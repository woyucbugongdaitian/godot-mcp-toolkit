[CmdletBinding()]
param(
    [Parameter(Position = 0)] [string]$ProjectPath,
    [string]$GodotPath,
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"
$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDirectory
$ProjectPath = if ($ProjectPath) { [IO.Path]::GetFullPath($ProjectPath) } elseif ($env:GODOT_MCP_PROJECT) { [IO.Path]::GetFullPath($env:GODOT_MCP_PROJECT) } else { Read-Host "Godot project path" | ForEach-Object { [IO.Path]::GetFullPath($_) } }

if (-not (Test-Path -LiteralPath (Join-Path $ProjectPath "project.godot"))) { throw "Not a Godot project: $ProjectPath" }

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { throw "Node.js 18+ is required. Install Node.js, then run this installer again." }
$nodeVersion = (& node --version).Trim()
$nodeMajor = [int]($nodeVersion.TrimStart('v').Split('.')[0])
if ($nodeMajor -lt 18) { throw "Node.js 18+ is required. Detected $nodeVersion" }

if (-not $GodotPath) { $GodotPath = $env:GODOT_BIN }
if (-not $GodotPath) {
    $godotCommand = Get-Command godot -ErrorAction SilentlyContinue
    if (-not $godotCommand) { $godotCommand = Get-Command godot4 -ErrorAction SilentlyContinue }
    if ($godotCommand) { $GodotPath = $godotCommand.Source }
}
if ($GodotPath -and -not (Test-Path -LiteralPath $GodotPath)) { throw "Godot executable does not exist: $GodotPath" }

$addonSource = Join-Path $Root "godot\addons\godot_mcp_pro"
$addonDestination = Join-Path $ProjectPath "addons\godot_mcp_pro"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $addonDestination) | Out-Null
if (Test-Path -LiteralPath $addonDestination) {
    $backup = "$addonDestination.backup.$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item -LiteralPath $addonDestination -Destination $backup -Recurse -Force
    Write-Output "Existing plugin backed up to $backup"
}
Copy-Item -LiteralPath $addonSource -Destination $addonDestination -Recurse -Force

$settings = [ordered]@{
    projectPath = $ProjectPath
    godotBin = $GodotPath
    installedAt = (Get-Date).ToString("o")
    packageVersion = "0.4.0"
}
$settings | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Root "settings.local.json") -Encoding utf8

$launcher = Join-Path $Root "portable\start-mcp.cmd"
$clientConfig = [ordered]@{
    mcpServers = [ordered]@{
        "godot-mcp-toolkit" = [ordered]@{
            command = "cmd.exe"
            args = @("/d", "/s", "/c", ('"{0}"' -f $launcher))
            env = [ordered]@{ GODOT_MCP_PROJECT = $ProjectPath }
        }
    }
}
if ($GodotPath) { $clientConfig.mcpServers."godot-mcp-toolkit".env.GODOT_BIN = $GodotPath }
$configFile = if ($ConfigPath) { [IO.Path]::GetFullPath($ConfigPath) } else { Join-Path $Root "mcp-config.generated.json" }
$clientConfig | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configFile -Encoding utf8

Write-Output "Installed Godot MCP Toolkit into: $ProjectPath"
Write-Output "MCP client configuration: $configFile"
Write-Output "Enable Godot MCP Toolkit in Project Settings > Plugins."


