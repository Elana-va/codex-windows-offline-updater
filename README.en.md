# Codex Windows Offline Updater and Model Catalog Repair

[简体中文](README.md) | English

An auditable Windows workflow refined through multiple real Codex updates since July 2026. It downloads the complete signed MSIX from Microsoft services, validates it, installs updates, and can remove a stale local model catalog override.

This project is not affiliated with OpenAI or Microsoft. It cannot bypass account entitlement, subscription limits, regional restrictions, or server-side rollouts.

Read the Chinese [development history](docs/development-history.md) for the real incident, decisions, failures, and fixes that produced this tool.

## Quick start

```powershell
git clone https://github.com/Elana-va/codex-windows-offline-updater.git
cd codex-windows-offline-updater

# Read-only diagnostics
powershell -NoProfile -File .\scripts\Get-CodexDiagnostics.ps1

# Download, verify, and install
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1

# Also remove a stale model_catalog_json override and restart Codex
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 `
  -FixStaleModelCatalog -RestartCodex
```

Review scripts before running them. Avoid piping an unknown remote script directly into an elevated PowerShell session.

## What it verifies

- Resolves product ID `9PLM9XGG6VKS` through Microsoft Display Catalog and FE3.
- Accepts package downloads only from `*.delivery.mp.microsoft.com`.
- Requires a valid Windows Authenticode signature.
- Requires MSIX identity `OpenAI.Codex` and a matching CPU architecture.
- Requires the signature subject to match the Publisher in `AppxManifest.xml`.
- Records SHA-256 hashes and preserves the original package unchanged.

Downloaded files go to `D:\CodexUpdate\<date>` when D is available, otherwise to the user's Downloads directory.

## Missing models after an update

A current app does not guarantee that a model appears in the picker. Client version, model catalog, and account entitlement are separate layers.

Old workarounds sometimes pin a static catalog in `%USERPROFILE%\.codex\config.toml`:

```toml
model_catalog_json = 'C:\Users\you\.codex\old-catalog.json'
```

That catalog can hide models released later. `Fix-StaleModelCatalog.ps1` backs up `config.toml` and removes only this override; it preserves the JSON file. Fully quit Codex, reopen it, and create a new task afterward.

The commonly shared `codex app-server daemon restart` command is Unix-only. On Windows, fully restart Codex Desktop instead.

If the model is still absent after updating, removing stale overrides, restarting, and opening a new task, the likely cause is server-side entitlement or rollout. This project deliberately does not spoof access.

## Provenance and license

The Microsoft FE3 templates and device-token handling are derived from [StoreDev/StoreLib](https://github.com/StoreDev/StoreLib). The base downloader is adapted from [hanyu1212/microsoft-store-package-downloader-skill](https://github.com/hanyu1212/microsoft-store-package-downloader-skill), with a PowerShell compatibility fix for multi-value `Content-Length` headers.

See [LICENSE](LICENSE), [NOTICE](NOTICE), [UPSTREAM.md](UPSTREAM.md), and the full [Chinese documentation](README.md).
