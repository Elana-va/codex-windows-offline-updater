[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

Write-Host 'Checking PowerShell syntax...'
$scripts = @(Get-ChildItem -LiteralPath $projectRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.ps1', '.psm1') })
foreach ($script in $scripts) {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    foreach ($parseError in @($errors)) {
        $failures.Add("$($script.FullName): $($parseError.Message)")
    }
}

Write-Host 'Checking XML templates...'
Get-ChildItem -LiteralPath (Join-Path $projectRoot 'scripts\storelib-xml') -Filter '*.xml' |
    ForEach-Object {
        try { [xml](Get-Content -Raw -LiteralPath $_.FullName) | Out-Null }
        catch { $failures.Add("$($_.FullName): $($_.Exception.Message)") }
    }

Write-Host 'Testing reversible model-catalog repair...'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("codex-updater-test-" + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($tempRoot) | Out-Null
try {
    $catalogPath = Join-Path $tempRoot 'old-catalog.json'
    $configPath = Join-Path $tempRoot 'config.toml'
    $backupPath = Join-Path $tempRoot 'backups'
    '{"models":[{"slug":"gpt-5.6-sol"}]}' | Set-Content -LiteralPath $catalogPath -Encoding UTF8
    @(
        'model = "gpt-5.6-sol"'
        "model_catalog_json = '$catalogPath'"
        'model_reasoning_effort = "medium"'
    ) | Set-Content -LiteralPath $configPath -Encoding UTF8

    & (Join-Path $projectRoot 'scripts\Fix-StaleModelCatalog.ps1') `
        -ConfigPath $configPath -BackupDirectory $backupPath

    if (Select-String -LiteralPath $configPath -Pattern 'model_catalog_json' -Quiet) {
        $failures.Add('Fix-StaleModelCatalog.ps1 did not remove the override.')
    }
    if (-not (Test-Path -LiteralPath $catalogPath)) {
        $failures.Add('Fix-StaleModelCatalog.ps1 deleted the catalog file.')
    }
    if (@(Get-ChildItem -LiteralPath $backupPath -File).Count -ne 1) {
        $failures.Add('Fix-StaleModelCatalog.ps1 did not create exactly one backup.')
    }
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    throw "$($failures.Count) test failure(s)."
}

Write-Host "All checks passed for $($scripts.Count) PowerShell files."
