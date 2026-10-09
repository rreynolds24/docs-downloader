# Version catalogue

## Purpose

`runtime\state\catalogue.db` records which Fortinet document families and versions have been observed and which exact PDF bytes are stored locally.

The catalogue complements `downloads.db`: the latter answers what should be downloaded now; the catalogue preserves history and provenance.

## Schema

```text
document_url|
product|
family|
source_version|
document_version|
pdf_url|
remote_filename|
etag|
content_length|
sha256|
first_seen|
last_seen|
local_filename|
status|
catalogue_url
```

The physical file is one pipe-delimited record per line.

Unknown fields are written as `-` instead of empty strings so Batch token positions remain deterministic.

## Identity layers

- **Document identity:** Fortinet document page URL.
- **Family identity:** product + document-family slug.
- **Version identity:** product + family + inferred/concrete document version.
- **Content identity:** SHA-256 of the downloaded PDF.

These are intentionally separate because a new Fortinet URL can expose old bytes, and an unchanged nominal version can be silently republished with new bytes.

## First/last seen

Every observation records a local first-seen and last-seen value. Re-observing the same revision updates last-seen without creating another row.

A later release can use these fields to mark entries that disappear from a product catalogue as removed without deleting their local PDFs.

## Source version vs document version

For numeric document paths, these normally match.

For product channels such as FortiCamera `latest`, the catalogue preserves:

```text
source_version=latest
document_version=<version inferred from filename when available>
```

If no concrete filename version can be inferred, `document_version` remains `latest`.

## Historical revisions

When a document URL that already has a current revision is observed with different content, the prior active row becomes `HISTORICAL` and the new revision becomes `CURRENT`.

If both revisions would use the same filename, the newer local file receives a short SHA-256 suffix so the historical bytes are not overwritten.

## Duplicate content

A single local PDF may be referenced by multiple catalogue rows.

Before download, identical PDF URL or matching ETag + Content-Length can avoid a redundant transfer when there is no conflicting metadata.

After download, SHA-256 decides whether content is truly identical. A matching SHA-256 reuses the already-stored local file and discards the temporary duplicate.
