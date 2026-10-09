# Architecture

## v0.0.8 scope

The supported operator path remains Windows-native and repository-local:

```text
GitHub ZIP
  -> extract
  -> install.bat
  -> run.bat
  -> docs-downloader.bat
  -> discover Fortinet /document/... links
  -> resolve reader-pdf attachment
  -> inspect ETag + Content-Length
  -> classify tracked download state
  -> classify product / family / version state
  -> calculate SHA-256 with certutil.exe
  -> avoid duplicate content
  -> preserve changed-in-place history
  -> update downloads.db + catalogue.db
```

## Restricted-workstation contract

The supported runtime path uses Windows inbox tooling only:

- `cmd.exe`
- `curl.exe`
- `findstr.exe`
- `certutil.exe`
- Batch built-ins

It does not require PowerShell, Git, Python, Node.js, a package manager, admin rights, registry changes, or a custom executable.

Internet access is used only for the declared application function: reading Fortinet documentation pages, inspecting PDF metadata, and downloading PDF attachments.

## Persistent state

Mutable state remains under `runtime/` so GitHub ZIP overlays preserve it.

### Acquisition tracking

```text
runtime\state\downloads.db
```

v0.0.8 supports both the previous four-field records and the new five-field form:

```text
document_url|pdf_url|remote_filename|etag|local_filename
```

The separate local filename allows multiple Fortinet document entries to reference one canonical local PDF when their content is identical.

### Historical version catalogue

```text
runtime\state\catalogue.db
```

Records use:

```text
document_url|product|family|source_version|document_version|pdf_url|remote_filename|etag|content_length|sha256|first_seen|last_seen|local_filename|status|catalogue_url
```

Empty/unknown persisted values use `-` so Batch `FOR /F` token positions remain stable.

A document URL can have multiple catalogue rows over time. The active row is `CURRENT` when local bytes are present or `AVAILABLE` when observed remotely but not yet downloaded. A superseded row is retained as `HISTORICAL`.

## Version identity

The document URL path provides product, source version, and document-family slug.

For paths such as:

```text
/document/forticamera/latest/release-notes
```

the source version remains `latest`, while a concrete version such as `2.2.3` is inferred from filenames like `FortiCamera-v2.2.3-Release_Notes.pdf` when possible.

## Content identity and de-duplication

Remote pre-download duplicate detection uses:

1. identical PDF URL with no conflicting ETag/Content-Length evidence; or
2. matching ETag plus Content-Length.

After download, SHA-256 is authoritative.

If SHA-256 matches an existing catalogue entry whose local file exists, the temporary download is discarded and the new document/version points at the existing local file.

If a destination filename already exists with different bytes, the replacement is stored as:

```text
<base>__<first-12-sha256><extension>
```

This preserves prior bytes when Fortinet silently republishes a nominally identical version.

## Classification

Acquisition state remains:

- `NEW`
- `UNCHANGED`
- `CHANGED`
- `MISSING_LOCAL`

Version state adds:

- `NEW_DOCUMENT`
- `NEW_VERSION`
- `UPDATED_IN_PLACE`
- `KNOWN_VERSION`
- `AVAILABLE_NOT_DOWNLOADED`

## Validation model

The Windows CI gate exercises the real Batch implementation under `cmd.exe` and must pass before merge.

It covers parser fixtures, tracking, version inference, catalogue history, SHA-256 lookup, live FortiPAM inventory/download/check behavior, unchanged second-run behavior, FortiCamera, and FortiWeb.

## Current limits

- One explicitly supplied product/product-version URL per invocation.
- No product/version directory restructuring yet.
- No removed-from-catalogue lifecycle reporting yet.
- No selective guide-type filter yet.
