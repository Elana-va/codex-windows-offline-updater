# Security Policy

## Trust model

This project treats the Microsoft Store package as untrusted until all checks pass. It limits package URLs to `delivery.mp.microsoft.com` and subdomains, requires a valid Authenticode signature, validates the `OpenAI.Codex` MSIX identity and CPU architecture, compares the signature subject with the manifest Publisher, and records SHA-256.

The updater does not disable certificate checks, Developer Mode, SmartScreen, antivirus, or Windows package validation. It never modifies or re-signs an MSIX.

## Sensitive data

The scripts do not request OpenAI credentials, API keys, browser cookies, GitHub tokens, or Microsoft account passwords. Diagnostics remain local and do not call a model.

Before sharing diagnostic output, review local paths and process information for usernames or project names.

## Reporting a vulnerability

Open a GitHub security advisory for vulnerabilities that could cause arbitrary code execution, package-source substitution, signature-check bypass, unsafe path handling, or disclosure of local data. Avoid publishing exploit details in a public issue before a fix is available.
