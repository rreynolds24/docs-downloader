# Architecture

## v0.0.1 scope

The supported operator path is deliberately small:

```text
GitHub ZIP
  -> extract
  -> install.bat
  -> run.bat
  -> docs-downloader.bat
  -> curl.exe to docs.fortinet.com
  -> discover /document/ links
  -> curl each document page
  -> extract id="reader-pdf" href
  -> curl the PDF to runtime/downloads/
```

## Restricted-workstation contract

The normal Windows path uses only inbox Windows tooling:

- `cmd.exe`
- `curl.exe`
- `findstr.exe`
- ordinary batch built-ins

It does not require PowerShell, Git, Python, Node.js, a package manager, admin rights, registry changes, or a custom executable.

Internet access is used only for the application's declared core function: reading Fortinet document pages and downloading their PDF attachments.

## Parser evidence

v0.0.1 is intentionally scoped to the server-rendered Fortinet HTML observed in the supplied October 2026 HAR captures:

1. Product/version pages contain simple anchors of the form `<a href="/document/...">`.
2. Document pages contain a PDF control with `id="reader-pdf"` and an HTTPS attachment URL.

The parser fails closed when those expected markers are absent.

## Runtime data

Mutable content is kept under `runtime/`, which is ignored by Git so repository ZIP overlay upgrades do not replace downloaded PDFs.

## Known v0.0.1 limits

- Product/version URLs only.
- No all-versions traversal yet.
- No update manifest yet.
- No filtering by guide type yet.
- HTML extraction is deliberately Fortinet-specific rather than a general HTML parser.
