# Download tracking

## Purpose

v0.0.7 adds persistent local knowledge of PDFs already downloaded by the tool and detects when a live Fortinet document now resolves to a different PDF.

## State location

```text
runtime\state\downloads.db
```

This file is intentionally stored under `runtime/` so a newer GitHub ZIP can be overlaid without replacing download history.

## Record format

One record is stored for each successfully downloaded Fortinet document page:

```text
document_url|pdf_url|filename|etag
```

The document page URL is the key.

## Classification rules

For every currently resolved PDF:

- **NEW**: no record exists for the document URL.
- **CHANGED**: the PDF URL or filename differs from the stored record, or the remote ETag differs. If a current ETag becomes available when the stored record has none, the item is also treated as changed so a stronger baseline can be established.
- **MISSING_LOCAL**: the remote identity is unchanged but the tracked local file no longer exists.
- **UNCHANGED**: remote identity matches the stored record and the local file exists.

If the server does not provide an ETag, change detection falls back to the resolved PDF URL and filename.

## Download behavior

`download` mode retrieves `NEW`, `CHANGED`, and `MISSING_LOCAL` PDFs.

`UNCHANGED` PDFs are skipped.

The tracking record is updated only after a non-empty PDF is downloaded successfully. A failed download does not advance the stored state.

## First tracked run after upgrading

PDFs downloaded by releases before v0.0.7 have no tracking record. The first v0.0.7 download run therefore treats them as `NEW` and downloads them once to establish an authoritative tracking baseline. Subsequent runs can skip them when unchanged.

## Persistence

Both `runtime\downloads\` and `runtime\state\` are runtime data and are ignored by Git. ZIP-overlay upgrades therefore preserve both the downloaded corpus and the tracking database.
