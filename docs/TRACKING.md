# Download and version tracking

## State files

v0.0.8 maintains two persistent files:

```text
runtime\state\downloads.db
runtime\state\catalogue.db
```

Both live under `runtime/` so normal ZIP-overlay upgrades preserve them.

## downloads.db

The current acquisition record is:

```text
document_url|pdf_url|remote_filename|etag|local_filename
```

Older v0.0.7 four-field rows remain readable. If the fifth field is absent, the remote filename is used as the local filename.

The document URL remains the stable key.

### Acquisition classification

- **NEW**: no acquisition record exists.
- **CHANGED**: PDF URL, remote filename, or available ETag changed.
- **MISSING_LOCAL**: remote identity is unchanged but the tracked local file is absent.
- **UNCHANGED**: remote identity matches and the local file exists.

## catalogue.db

The historical record is:

```text
document_url|product|family|source_version|document_version|pdf_url|remote_filename|etag|content_length|sha256|first_seen|last_seen|local_filename|status|catalogue_url
```

Statuses:

- `CURRENT`: authoritative local content is present.
- `AVAILABLE`: observed remotely but not yet downloaded.
- `HISTORICAL`: a prior revision retained after the same document URL changed.

### Version classification

- **NEW_DOCUMENT**: the document family has never been observed for the product.
- **NEW_VERSION**: the family exists, but this version has never been observed.
- **UPDATED_IN_PLACE**: the same document URL/version now resolves differently.
- **KNOWN_VERSION**: an already known version remains current.
- **AVAILABLE_NOT_DOWNLOADED**: the version was observed by inventory/check but has not yet been acquired.

## SHA-256 identity

Downloaded bytes are hashed with Windows inbox `certutil.exe`.

SHA-256 is the authoritative local duplicate identity. ETag and Content-Length are used only as pre-download optimization signals.

When the same SHA-256 already exists, the new document/version points to the existing local file and the duplicate temporary file is discarded.

## Same-version republishing

If Fortinet republishes the same nominal version and the existing filename would overwrite different bytes, the new local filename uses a 12-character SHA-256 suffix. The prior bytes and catalogue row remain historical.

## Read-only check

Use:

```bat
run.bat check https://docs.fortinet.com/product/<product>
```

This updates first/last-seen catalogue observations but does not download PDFs. Remote-only observations are stored as `AVAILABLE`.

## Upgrade behavior from v0.0.7

Existing `downloads.db` records remain valid.

On the first v0.0.8 run, an unchanged existing local PDF can be hashed in place and inserted into `catalogue.db` without re-downloading. This seeds the version-aware history from the already-downloaded corpus.
