[CmdletBinding()]
param(
    [ValidateSet('x64', 'arm64')]
    [string]$Architecture = $(if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }),
    [string]$OutputDirectory,
    [switch]$DownloadOnly,
    [switch]$FixStaleModelCatalog,
    [switch]$RestartCodex,
    [switch]$ForceDownload
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'This updater supports Windows only.'
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$downloader = Join-Path $scriptRoot 'download-store-package.ps1'
$productId = '9PLM9XGG6VKS'

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $base = if (Test-Path -LiteralPath 'D:\') { 'D:\CodexUpdate' } else { Join-Path $env:USERPROFILE 'Downloads\CodexUpdate' }
    $OutputDirectory = Join-Path $base (Get-Date -Format 'yyyy-MM-dd')
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null

Write-Host 'Step 1/4: Resolving the current Codex package from Microsoft services.'
$downloadParameters = @{
    ProductId = $productId
    Architecture = $Architecture
    OutputDirectory = (Join-Path $OutputDirectory 'packages')
}
if ($ForceDownload) { $downloadParameters.Force = $true }

try {
    $downloaded = @(& $downloader @downloadParameters)
} catch {
    if (-not $ForceDownload -and $_.Exception.Message -match 'Destination already exists') {
        Write-Host 'Existing package files detected; validating the local manifest instead.'
        $manifestPath = Join-Path $downloadParameters.OutputDirectory 'package-manifest.json'
        if (-not (Test-Path -LiteralPath $manifestPath)) { throw }
        $savedManifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
        $downloaded = @($savedManifest.Packages)
    } else {
        throw
    }
}

$main = $downloaded |
    Where-Object { $_.FileName -match '^OpenAI\.Codex_.+\.(msix|msixbundle|appx|appxbundle)$' } |
    Sort-Object FileName -Descending |
    Select-Object -First 1
if (-not $main) { throw 'The OpenAI.Codex application package was not found in the download results.' }

$mainPath = if ($main.PSObject.Properties.Name -contains 'Path') {
    [string]$main.Path
} else {
    Join-Path $downloadParameters.OutputDirectory ([string]$main.FileName)
}

Write-Host 'Step 2/4: Verifying signature, hash, architecture, and MSIX identity.'
$signature = Get-AuthenticodeSignature -LiteralPath $mainPath
if ($signature.Status -ne 'Valid') { throw "Invalid package signature: $($signature.Status)" }
$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $mainPath

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($mainPath)
try {
    $entry = $archive.GetEntry('AppxManifest.xml')
    if (-not $entry) { throw 'AppxManifest.xml is missing from the package.' }
    $reader = [IO.StreamReader]::new($entry.Open())
    try { [xml]$appxManifest = $reader.ReadToEnd() } finally { $reader.Dispose() }
} finally {
    $archive.Dispose()
}

$identity = $appxManifest.Package.Identity
if ($identity.Name -ne 'OpenAI.Codex') { throw "Unexpected package identity: $($identity.Name)" }
if ($identity.ProcessorArchitecture -notin @($Architecture, 'neutral')) {
    throw "Package architecture '$($identity.ProcessorArchitecture)' does not match '$Architecture'."
}
if ($signature.SignerCertificate.Subject -ne $identity.Publisher) {
    throw 'The Authenticode signer does not match the publisher in AppxManifest.xml.'
}

[pscustomobject]@{
    Package = $mainPath
    Version = [string]$identity.Version
    Architecture = [string]$identity.ProcessorArchitecture
    Signature = [string]$signature.Status
    Publisher = [string]$identity.Publisher
    SHA256 = $hash.Hash
} | Format-List

if ($FixStaleModelCatalog) {
    Write-Host 'Step 3/4: Checking for a stale local model catalog override.'
    & (Join-Path $scriptRoot 'Fix-StaleModelCatalog.ps1') -BackupDirectory (Join-Path $OutputDirectory 'config-backups')
} else {
    Write-Host 'Step 3/4: Model catalog configuration left unchanged.'
}

if ($DownloadOnly) {
    Write-Host "Download and verification complete: $mainPath"
    return
}

Write-Host 'Step 4/4: Registering the verified package.'
$dependencies = @($downloaded |
    Where-Object { $_.FileName -ne $main.FileName } |
    ForEach-Object { Join-Path $downloadParameters.OutputDirectory ([string]$_.FileName) })

$appIsRunning = [bool](Get-Process -Name ChatGPT -ErrorAction SilentlyContinue)
if (-not $appIsRunning) {
    if ($dependencies.Count -gt 0) {
        Add-AppxPackage -Path $mainPath -DependencyPath $dependencies
    } else {
        Add-AppxPackage -Path $mainPath
    }
    $installed = Get-AppxPackage -Name OpenAI.Codex
    Write-Host "Codex $($installed.Version) installed successfully."
    return
}

$stageParameters = @{ Path = $mainPath; DeferRegistrationWhenPackagesAreInUse = $true }
if ($dependencies.Count -gt 0) { $stageParameters.DependencyPath = $dependencies }
Add-AppxPackage @stageParameters

if (-not $RestartCodex) {
    Write-Host 'The update is staged. Fully exit Codex and reopen it to complete registration.'
    return
}

$helperPath = Join-Path $OutputDirectory 'complete-update-after-exit.ps1'
$logPath = Join-Path $OutputDirectory 'complete-update-after-exit.log'
$dependencyLiteral = if ($dependencies.Count -gt 0) {
    "`$dependencies = @(" + (($dependencies | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ',') + ')'
} else {
    '$dependencies = @()'
}

$helper = @"
`$ErrorActionPreference = 'Stop'
`$packagePath = '$($mainPath.Replace("'", "''"))'
$dependencyLiteral
`$logPath = '$($logPath.Replace("'", "''"))'
Start-Sleep -Seconds 15
try {
    "`$(Get-Date -Format o) Completing Codex update." | Set-Content -LiteralPath `$logPath
    `$parameters = @{ Path = `$packagePath; ForceApplicationShutdown = `$true }
    if (`$dependencies.Count -gt 0) { `$parameters.DependencyPath = `$dependencies }
    Add-AppxPackage @parameters
    `$installed = Get-AppxPackage -Name OpenAI.Codex
    "`$(Get-Date -Format o) Installed version: `$(`$installed.Version); status: `$(`$installed.Status)" | Add-Content -LiteralPath `$logPath
    Start-Process explorer.exe -ArgumentList 'shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App'
} catch {
    "`$(Get-Date -Format o) Update failed: `$(`$_.Exception.Message)" | Add-Content -LiteralPath `$logPath
}
"@
$helper | Set-Content -LiteralPath $helperPath -Encoding UTF8

$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$launchCommand = "& '$($helperPath.Replace("'", "''"))'"
$encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($launchCommand))
Start-Process -FilePath $windowsPowerShell -WindowStyle Hidden -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encodedCommand
)
Write-Host 'Codex will close in about 15 seconds, finish the update, and reopen automatically.'
Write-Host "Completion log: $logPath"
