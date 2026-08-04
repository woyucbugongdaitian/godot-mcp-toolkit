[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$ProjectPath,
    [string]$GodotPath
)

$ErrorActionPreference = "Stop"

function Normalize-ProjectPath([string]$Path) {
    return ([IO.Path]::GetFullPath($Path) -replace '[\\/]+$','').ToLowerInvariant()
}

function Read-JsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json
}

function Get-GodotVersion([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
    $fileName = [IO.Path]::GetFileNameWithoutExtension($Path)
    $nameMatch = [regex]::Match($fileName, 'v(?<version>\d+\.\d+(?:\.\d+)?)', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($nameMatch.Success) { return $nameMatch.Groups['version'].Value }
    try {
        $versionOutput = (& $Path --version 2>$null | Select-Object -First 1)
        $versionMatch = [regex]::Match([string]$versionOutput, '(?<version>\d+\.\d+(?:\.\d+)?)')
        if ($versionMatch.Success) { return $versionMatch.Groups['version'].Value }
    } catch {}
    return $null
}

function Get-ProjectGodotVersion([string]$ProjectFile) {
    $projectText = Get-Content -LiteralPath $ProjectFile -Raw -Encoding utf8
    $featuresMatch = [regex]::Match($projectText, '(?ms)^\s*config/features\s*=\s*PackedStringArray\((?<features>.*?)\)')
    if (-not $featuresMatch.Success) { return $null }
    $versionMatch = [regex]::Match($featuresMatch.Groups['features'].Value, '(?<version>\d+\.\d+)(?:\.\d+)?')
    if ($versionMatch.Success) { return $versionMatch.Groups['version'].Value }
    return $null
}

$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$PackageRoot = Split-Path -Parent $ScriptDirectory
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
$projectFile = Join-Path $ProjectPath "project.godot"
if (-not (Test-Path -LiteralPath $projectFile)) { throw "Not a Godot project: $ProjectPath" }

$stateRoot = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "GodotMCP" } else { Join-Path $PackageRoot ".state" }
New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
$activeProjectFile = Join-Path $stateRoot "active-project.json"
$projectEnginesFile = Join-Path $stateRoot "project-engines.json"
$globalSettingsPath = Join-Path $PackageRoot "global-settings.json"
$globalSettings = Read-JsonFile $globalSettingsPath
$engineState = Read-JsonFile $projectEnginesFile
$projectKey = Normalize-ProjectPath $ProjectPath
$projectGodotVersion = Get-ProjectGodotVersion $projectFile
$projectEngine = $null
if ($engineState -and $engineState.projects) {
    $projectEngine = @($engineState.projects | Where-Object { $_ -and $_.projectPath -and (Normalize-ProjectPath ([string]$_.projectPath)) -eq $projectKey } | Select-Object -First 1)[0]
}

$registeredGodotPaths = @()
if ($globalSettings) {
    if ($globalSettings.godotBins) { $registeredGodotPaths += @($globalSettings.godotBins) }
    if ($globalSettings.godotBin) { $registeredGodotPaths += [string]$globalSettings.godotBin }
}
if ($env:GODOT_BIN) { $registeredGodotPaths += $env:GODOT_BIN }
foreach ($commandName in @("godot", "godot4")) {
    $godotCommand = Get-Command $commandName -ErrorAction SilentlyContinue
    if ($godotCommand) { $registeredGodotPaths += $godotCommand.Source }
}
$registeredGodotPaths = @($registeredGodotPaths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | ForEach-Object { [IO.Path]::GetFullPath([string]$_) } | Select-Object -Unique)

$selectionReason = $null
if ($GodotPath) {
    $GodotPath = [IO.Path]::GetFullPath($GodotPath)
    if (-not (Test-Path -LiteralPath $GodotPath)) { throw "Godot executable does not exist: $GodotPath" }
    $selectionReason = "explicit"
} elseif ($projectEngine -and $projectEngine.godotBin -and (Test-Path -LiteralPath $projectEngine.godotBin)) {
    $GodotPath = [IO.Path]::GetFullPath([string]$projectEngine.godotBin)
    $selectionReason = "project-memory"
} else {
    $matchingGodotPaths = @()
    if ($projectGodotVersion) {
        $matchingGodotPaths = @($registeredGodotPaths | Where-Object {
            $version = Get-GodotVersion ([string]$_)
            $version -and ($version -eq $projectGodotVersion -or $version.StartsWith("$projectGodotVersion."))
        })
    }
    if ($matchingGodotPaths.Count -gt 0) {
        $GodotPath = $matchingGodotPaths[0]
        $selectionReason = "project-version-match"
    } elseif ($globalSettings -and $globalSettings.godotBin -and (Test-Path -LiteralPath $globalSettings.godotBin)) {
        $GodotPath = [IO.Path]::GetFullPath([string]$globalSettings.godotBin)
        $selectionReason = "global-default"
    } elseif ($registeredGodotPaths.Count -gt 0) {
        $GodotPath = $registeredGodotPaths[0]
        $selectionReason = "registered-fallback"
    }
}

if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath)) {
    throw "Godot executable not found. Pass -GodotPath with the path to a portable Godot .exe, such as E:\\Tools\\Godot\\Godot_v4.4-stable_win64.exe."
}

$godotVersion = Get-GodotVersion $GodotPath
$source = Join-Path $PackageRoot "godot\addons\godot_mcp_pro"
$destination = Join-Path $ProjectPath "addons\godot_mcp_pro"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force

$pluginPath = 'res://addons/godot_mcp_pro/plugin.cfg'
$projectText = Get-Content -LiteralPath $projectFile -Raw -Encoding utf8
if ($projectText -notmatch [regex]::Escape($pluginPath)) {
    if ($projectText -match '(?ms)\[editor_plugins\]\s*\r?\nenabled\s*=\s*PackedStringArray\(([^)]*)\)') {
        $existing = $Matches[1].Trim()
        $updated = if ($existing) { "$existing, `"$pluginPath`"" } else { "`"$pluginPath`"" }
        $projectText = [regex]::Replace($projectText, '(?ms)(\[editor_plugins\]\s*\r?\nenabled\s*=\s*PackedStringArray\()[^)]*(\))', "`$1$updated`$2", 1)
    } elseif ($projectText -notmatch '(?m)^\[editor_plugins\]') {
        $projectText = $projectText.TrimEnd() + "`r`n`r`n[editor_plugins]`r`nenabled=PackedStringArray(`"$pluginPath`")`r`n"
    } else {
        $projectText = $projectText.TrimEnd() + "`r`nenabled=PackedStringArray(`"$pluginPath`")`r`n"
    }
    Set-Content -LiteralPath $projectFile -Value $projectText -Encoding utf8
}

$knownGodotBins = @()
if ($globalSettings) {
    if ($globalSettings.godotBins) { $knownGodotBins += @($globalSettings.godotBins) }
    if ($globalSettings.godotBin) { $knownGodotBins += [string]$globalSettings.godotBin }
}
$knownGodotBins += $GodotPath
$knownGodotBins = @($knownGodotBins | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | ForEach-Object { [IO.Path]::GetFullPath([string]$_) } | Select-Object -Unique)
$globalDefaultGodot = if ($globalSettings -and $globalSettings.godotBin -and (Test-Path -LiteralPath $globalSettings.godotBin)) { [IO.Path]::GetFullPath([string]$globalSettings.godotBin) } else { $GodotPath }
[ordered]@{
    godotBin = $globalDefaultGodot
    godotBins = @($knownGodotBins)
    installedAt = if ($globalSettings -and $globalSettings.installedAt) { [string]$globalSettings.installedAt } else { (Get-Date).ToString("o") }
    updatedAt = (Get-Date).ToString("o")
    packageVersion = if ($globalSettings -and $globalSettings.packageVersion) { [string]$globalSettings.packageVersion } else { "0.2.0" }
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $globalSettingsPath -Encoding utf8
$otherProjects = @()
if ($engineState -and $engineState.projects) {
    $otherProjects = @($engineState.projects | Where-Object { $_ -and $_.projectPath -and (Normalize-ProjectPath ([string]$_.projectPath)) -ne $projectKey })
}
$otherProjects += [pscustomobject]@{
    projectPath = $ProjectPath
    godotBin = $GodotPath
    godotVersion = $godotVersion
    projectGodotVersion = $projectGodotVersion
    selectionReason = $selectionReason
    updatedAt = (Get-Date).ToString("o")
}
[ordered]@{
    schemaVersion = 1
    projects = @($otherProjects)
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $projectEnginesFile -Encoding utf8

[ordered]@{
    projectPath = $ProjectPath
    projectName = (Split-Path -Leaf $ProjectPath)
    godotBin = $GodotPath
    godotVersion = $godotVersion
    projectGodotVersion = $projectGodotVersion
    selectionReason = $selectionReason
    selectedAt = (Get-Date).ToString("o")
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $activeProjectFile -Encoding utf8

$env:GODOT_MCP_PROJECT = $ProjectPath
$env:GODOT_MCP_ACTIVE_PROJECT_FILE = $activeProjectFile
$env:GODOT_BIN = $GodotPath
$arguments = @("--editor", "--path", $ProjectPath)
Start-Process -FilePath $GodotPath -ArgumentList $arguments -WorkingDirectory $ProjectPath
Write-Output "Opened with Godot MCP: $ProjectPath"
Write-Output "Godot: $GodotPath ($selectionReason)"