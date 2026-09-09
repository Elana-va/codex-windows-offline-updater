[CmdletBinding()]
param(
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$configPath = Join-Path $env:USERPROFILE ".codex\config.toml"
$overridePath = $null
$overrideHasAstra = $null

if (Test-Path -LiteralPath $configPath) {
    $overrideLine = Get-Content -LiteralPath $configPath |
        Where-Object { $_ -match '^\s*model_catalog_json\s*=' } |
        Select-Object -First 1

    if ($overrideLine -and $overrideLine -match '^\s*model_catalog_json\s*=\s*["''](?<path>.+?)["'']\s*$') {
        $overridePath = [Environment]::ExpandEnvironmentVariables($Matches.path)
        if (Test-Path -LiteralPath $overridePath) {
            $overrideHasAstra = [bool](Select-String -LiteralPath $overridePath -Pattern 'gpt-6-astra' -Quiet)
        }
    }
}

$appPackage = Get-AppxPackage -Name OpenAI.Codex -ErrorAction SilentlyContinue
$cliVersion = $null
$cliPath = $null
$codexCommand = Get-Command codex -ErrorAction SilentlyContinue
if ($codexCommand) {
    $cliPath = $codexCommand.Source
    $cliVersion = (& $codexCommand.Source --version 2>$null | Select-Object -First 1)
}

$codexProcesses = @(Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -in @('ChatGPT', 'codex', 'codex-code-mode-host') } |
    ForEach-Object {
        [pscustomobject]@{
            Id = $_.Id
            Name = $_.ProcessName
            Path = $_.Path
        }
    })

$result = [ordered]@{
    CheckedAt = (Get-Date).ToString('o')
    WindowsPackageVersion = if ($appPackage) { [string]$appPackage.Version } else { $null }
    WindowsPackageStatus = if ($appPackage) { [string]$appPackage.Status } else { $null }
    WindowsPackagePath = if ($appPackage) { $appPackage.InstallLocation } else { $null }
    CliVersion = $cliVersion
    CliPath = $cliPath
    ConfigPath = $configPath
    ModelCatalogOverride = $overridePath
    OverrideContainsGpt6Astra = $overrideHasAstra
    RunningProcesses = $codexProcesses
    Notes = @(
        'A current client does not guarantee account entitlement or immediate rollout access.'
        'A model_catalog_json override can hide models added after the local catalog was created.'
        'Windows Codex does not support the Unix-only app-server daemon lifecycle commands.'
    )
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 5
} else {
    [pscustomobject]$result | Format-List
}
