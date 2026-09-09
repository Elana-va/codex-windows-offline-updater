[CmdletBinding()]
param(
    [switch]$DownloadOnly,
    [switch]$FixStaleModelCatalog,
    [switch]$RestartCodex,
    [switch]$ForceDownload
)

$updater = Join-Path $PSScriptRoot 'scripts\Update-CodexWindows.ps1'
& $updater @PSBoundParameters
