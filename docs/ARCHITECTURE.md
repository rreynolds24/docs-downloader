# Architecture

## v0.0.5 scope

The supported operator path is deliberately small:

```text
GitHub ZIP
  -> extract
  -> install.bat
  -> run.bat
  -> docs-downloader.bat
  -> curl.exe to docs.fortinet.com
  -> discover <a href="/document/..."> links
  -> curl each document page
  -> extract id="reader-pdf" HTTPS attachment
  -> curl the PDF to runtime/downloads/
```

## Restricted-workstation contract

The normal Windows path uses only inbox Windows tooling:

- `cmd.exe`
- `curl.exe`
- `findstr.exe`
- ordinary Batch built-ins

It does not require PowerShell, Git, Python, Node.js, a package manager, admin rights, registry changes, or a custom executable.

Internet access is used only for the application's declared core function: reading Fortinet document pages and downloading their PDF attachments.

## Parser design

The parser is Fortinet-specific and fail-closed.

1. The product/version page is downloaded to a local temporary file.
2. `findstr` filters anchor lines containing both `<a href=` and `/document/`.
3. The quote-delimited href is extracted from the filtered file.
4. Each document page is downloaded independently.
5. Lines containing `reader-pdf` are filtered to a local file.
6. The expected `id="reader-pdf"` token and HTTPS attachment token are extracted.
7. Inventory mode reports the target; download mode retrieves it with `curl.exe`.
8. Download mode rejects zero-byte files.

HTML-derived text is not re-injected into command syntax.

## Validation model

The repository includes a Windows GitHub Actions gate that executes the real Batch implementation under `cmd.exe`.

It validates:

- installation/doctor
- parser fixtures
- live FortiPAM 7.0 inventory
- live FortiPAM 7.0 downloads
- non-empty downloaded PDFs

The live validated result is 6 discovered documents, 6 resolved PDF targets, and 0 warnings/failures.

The same v0.0.4 core workflow has also been confirmed on the target restricted workstation.

## Runtime data

Mutable content is kept under `runtime/`, which is ignored by Git so repository ZIP overlay upgrades do not replace downloaded PDFs.

## Current limits

- One product/version page per invocation.
- No all-version traversal yet.
- No update manifest yet.
- No guide-type filtering yet.
- No cross-version de-duplication yet.
