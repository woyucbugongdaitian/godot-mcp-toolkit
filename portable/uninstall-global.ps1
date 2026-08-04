[CmdletBinding()]
param([string]$InstallPath)
$ErrorActionPreference = "Stop"
$InstallPath = if ($InstallPath) { [IO.Path]::GetFullPath($InstallPath) } else { Join-Path $env:LOCALAPPDATA "GodotMCP" }
Remove-Item -LiteralPath "HKCU:\Software\Classes\Directory\shell\GodotMCP" -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $InstallPath) { Remove-Item -LiteralPath $InstallPath -Recurse -Force }
Write-Output "Godot MCP global launcher removed"
