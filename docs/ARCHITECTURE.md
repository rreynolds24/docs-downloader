# Architecture

## v0.0.7 scope

The supported operator path is deliberately small:

```text
GitHub ZIP
  -> extract
  -> install.bat
  -> run.bat
  -> docs-downloader.bat
  -> curl.exe to docs.fortinet.com
  -> discover /document/... links
  -> resolve reader-pdf HTTPS attachment
  -> compare with runtime/state/downloads.db
  -> skip unchanged PDFs
  -> download new/changed/missing PDFs
  -> update tracking state after successful download
```

## Restricted-workstation contract

The normal Windows path uses only inbox Windows tooling:

- `cmd.exe`
- `curl.exe`
- `findstr.exe`
- ordinary Batch built-ins

It does not require PowerShell, Git, Python, Node.js, a package manager, admin rights, registry changes, or a custom executable.

Internet access is used only for the application's declared core function: reading Fortinet document pages, checking PDF metadata, and downloading PDF attachments.

## Parser design

The parser is Fortinet-specific and fail-closed.

1. The product page is downloaded to a local temporary file.
2. `findstr` selects anchor lines containing `/document/`.
3. Relative document hrefs are extracted across supported attribute positions and de-duplicated.
4. Each document page is downloaded independently.
5. Lines containing `reader-pdf` are filtered to a local file.
6. The direct HTTPS PDF attachment is extracted.
7. Pages without a PDF are counted as non-fatal skips.
8. Download mode rejects failed or zero-byte downloads.

HTML-derived text is not re-injected into command syntax.

## Persistent tracking state

Mutable content is kept under `runtime/`, which is ignored by Git so ZIP-overlay upgrades preserve downloaded PDFs and tracking state.

The tracking database is:

```text
runtime\state\downloads.db
```

Each successful download stores one pipe-delimited record:

```text
document_url|pdf_url|filename|etag
```

The document page URL is the stable key.

For every currently resolved PDF the tool compares the live PDF URL, filename, and remote ETag with the stored record and classifies it as:

- `NEW`
- `UNCHANGED`
- `CHANGED`
- `MISSING_LOCAL`

If the server does not expose an ETag, comparison falls back to PDF URL and filename.

Tracking state is advanced only after a non-empty PDF is downloaded successfully. Existing records are rewritten through a temporary file plus `move /y` so a partial update does not become the authoritative state.

## Validation model

Windows GitHub Actions executes the real Batch implementation under `cmd.exe`.

The gate validates:

- installation/doctor
- parser and tracking self-tests
- live FortiPAM 7.0 inventory
- first FortiPAM tracked download
- second FortiPAM download with all six PDFs skipped as unchanged
- live FortiCamera root inventory
- live FortiWeb root inventory

## Current limits

- One product/version page per invocation.
- No all-version traversal yet.
- No guide-type filtering yet.
- No removed-document reporting yet.
- No product/version-aware output directories yet.
