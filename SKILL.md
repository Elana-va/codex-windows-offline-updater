---
name: codex-windows-offline-updater
description: Diagnose, download, verify, and update the official OpenAI Codex Windows MSIX package when Microsoft Store is unavailable, and repair stale model_catalog_json overrides that can hide newly released models.
---

# Codex Windows Offline Updater

Use this skill only on Windows for Codex Desktop installation, update, offline package transfer, or a missing-model diagnosis.

## Safe workflow

1. Run read-only diagnostics first:

```powershell
powershell -NoProfile -File scripts/Get-CodexDiagnostics.ps1
```

2. Explain the distinction between client version, local model catalog, and server-side account entitlement.
3. Download and verify without installing unless the user requested installation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -DownloadOnly
```

4. When installation is authorized, run `install.ps1`. Add `-FixStaleModelCatalog` only when diagnostics show an obsolete override or the user explicitly asks to remove it.
5. Add `-RestartCodex` only when the user expects the running desktop app to close and reopen.
6. Report package version, architecture, signature status, publisher, SHA-256, and output path.

## Boundaries

- Never weaken package validation or accept non-Microsoft delivery hosts.
- Never claim that a client update grants model access.
- Never spoof account entitlement or add fabricated model entries.
- Preserve config backups and downloaded signed packages until the user chooses to remove them.
- On Windows, do not recommend Unix-only `codex app-server daemon` lifecycle commands.

The FE3 protocol files and base downloader have MPL-2.0 provenance documented in `NOTICE`.
