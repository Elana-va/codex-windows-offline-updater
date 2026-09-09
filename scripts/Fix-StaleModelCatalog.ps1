[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = (Join-Path $env:USERPROFILE '.codex\config.toml'),
    [string]$BackupDirectory,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Codex config was not found: $ConfigPath"
}

$lines = @(Get-Content -LiteralPath $ConfigPath)
$overrideIndexes = @()
for ($index = 0; $index -lt $lines.Count; $index++) {
    if ($lines[$index] -match '^\s*model_catalog_json\s*=') {
        $overrideIndexes += $index
    }
}

if ($overrideIndexes.Count -eq 0) {
    Write-Host 'No model_catalog_json override is configured. Nothing to change.'
    return
}

$overrideLine = $lines[$overrideIndexes[0]]
$catalogPath = $null
$catalogHasAstra = $false
if ($overrideLine -match '^\s*model_catalog_json\s*=\s*["''](?<path>.+?)["'']\s*$') {
    $catalogPath = [Environment]::ExpandEnvironmentVariables($Matches.path)
    if (Test-Path -LiteralPath $catalogPath) {
        $catalogHasAstra = [bool](Select-String -LiteralPath $catalogPath -Pattern 'gpt-6-astra' -Quiet)
    }
}

if ($catalogHasAstra -and -not $Force) {
    throw "The configured catalog already contains gpt-6-astra. Use -Force only if you still intend to remove the override."
}

if ([string]::IsNullOrWhiteSpace($BackupDirectory)) {
    $preferredRoot = if (Test-Path -LiteralPath 'D:\') { 'D:\CodexUpdate' } else { [Environment]::GetFolderPath('MyDocuments') }
    $BackupDirectory = Join-Path $preferredRoot 'config-backups'
}

[IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($BackupDirectory)) | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupPath = Join-Path $BackupDirectory "config.toml.before-model-catalog-fix.$stamp.bak"

if ($PSCmdlet.ShouldProcess($ConfigPath, 'Back up the file and remove model_catalog_json overrides')) {
    Copy-Item -LiteralPath $ConfigPath -Destination $backupPath -Force
    $newLines = for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($index -notin $overrideIndexes) { $lines[$index] }
    }
    $newLines | Set-Content -LiteralPath $ConfigPath -Encoding UTF8

    if (Select-String -LiteralPath $ConfigPath -Pattern '^\s*model_catalog_json\s*=' -Quiet) {
        throw 'The override is still present after the update.'
    }

    Write-Host "Removed stale model catalog override."
    Write-Host "Backup: $backupPath"
    if ($catalogPath) { Write-Host "Catalog file was preserved: $catalogPath" }
}
