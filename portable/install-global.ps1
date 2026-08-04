[CmdletBinding()]
param([string]$InstallPath, [string]$GodotPath, [switch]$NoShellIntegration)

$ErrorActionPreference = "Stop"
$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$PackageRoot = Split-Path -Parent $ScriptDirectory
$InstallPath = if ($InstallPath) { [IO.Path]::GetFullPath($InstallPath) } else { Join-Path $env:LOCALAPPDATA "GodotMCP" }
New-Item -ItemType Directory -Force -Path $InstallPath | Out-Null
if (-not $GodotPath) { $GodotPath = $env:GODOT_BIN }
if (-not $GodotPath) {
    $godotCommand = Get-Command godot -ErrorAction SilentlyContinue
    if (-not $godotCommand) { $godotCommand = Get-Command godot4 -ErrorAction SilentlyContinue }
    if ($godotCommand) { $GodotPath = $godotCommand.Source }
}
if ($GodotPath -and -not (Test-Path -LiteralPath $GodotPath)) { throw "Godot executable does not exist: $GodotPath" }
Get-ChildItem -LiteralPath $PackageRoot -Force | Where-Object { $_.Name -notin @("settings.local.json", "mcp-config.generated.json", "node_modules", "global-settings.json", "active-project.json") } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $InstallPath -Recurse -Force }

$globalSettingsFile = Join-Path $InstallPath "global-settings.json"
$existingSettings = if (Test-Path -LiteralPath $globalSettingsFile) { Get-Content -LiteralPath $globalSettingsFile -Raw -Encoding utf8 | ConvertFrom-Json } else { $null }
$godotBins = @()
if ($existingSettings) {
    if ($existingSettings.godotBins) { $godotBins += @($existingSettings.godotBins) }
    if ($existingSettings.godotBin) { $godotBins += [string]$existingSettings.godotBin }
}
if ($GodotPath) { $godotBins += [IO.Path]::GetFullPath($GodotPath) }
$godotBins = @($godotBins | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | ForEach-Object { [IO.Path]::GetFullPath([string]$_) } | Select-Object -Unique)
$defaultGodotBin = if ($GodotPath) { [IO.Path]::GetFullPath($GodotPath) } elseif ($existingSettings -and $existingSettings.godotBin -and (Test-Path -LiteralPath $existingSettings.godotBin)) { [IO.Path]::GetFullPath([string]$existingSettings.godotBin) } elseif ($godotBins.Count -gt 0) { $godotBins[0] } else { $null }

[ordered]@{
    godotBin = $defaultGodotBin
    godotBins = @($godotBins)
    installedAt = (Get-Date).ToString("o")
    packageVersion = "0.2.0"
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $globalSettingsFile -Encoding utf8

$launcher = Join-Path $InstallPath "portable\start-mcp.cmd"
[ordered]@{
    mcpServers = [ordered]@{
        "godot-mcp-toolkit" = [ordered]@{
            command = "cmd.exe"
            args = @("/d", "/s", "/c", ('"{0}"' -f $launcher))
        }
    }
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $InstallPath "mcp-config.generated.json") -Encoding utf8

if (-not $NoShellIntegration) {
    $menuKey = "HKCU:\Software\Classes\Directory\shell\GodotMCP"
    New-Item -Path "$menuKey\command" -Force | Out-Null
    Set-ItemProperty -Path $menuKey -Name "(default)" -Value "Open with Godot MCP"
    $launcher = Join-Path $InstallPath "portable\launch-project.ps1"
    $command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$launcher`" -ProjectPath `"%1`""
    Set-ItemProperty -Path "$menuKey\command" -Name "(default)" -Value $command
}

Write-Output "Godot MCP installed globally at: $InstallPath"
Write-Output "MCP client config: $(Join-Path $InstallPath 'mcp-config.generated.json')"`r`nWrite-Output "Registered Godot versions: $($godotBins.Count)"
if ($NoShellIntegration) {
    Write-Output "Shell integration skipped. Launch portable\\launch-project.ps1 manually."
} else {
    Write-Output "Right-click any Godot project folder and choose: Open with Godot MCP"
}
