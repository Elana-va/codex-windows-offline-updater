# Contributing

Contributions are welcome, especially reproducible Windows compatibility fixes.

1. Keep package downloads restricted to Microsoft delivery hosts.
2. Do not weaken signature, identity, publisher, hash, or architecture checks.
3. Do not add entitlement bypasses, model-catalog spoofing, telemetry, or credential collection.
4. Preserve MPL-2.0 notices for StoreLib-derived and downloader-derived files.
5. Run `pwsh -NoProfile -File .\tests\Run-Tests.ps1` before submitting a pull request.

Bug reports should include the Windows version, Codex package version, CLI version, architecture, exact error, and whether Microsoft Store is available. Remove usernames, tokens, and unrelated project paths.
