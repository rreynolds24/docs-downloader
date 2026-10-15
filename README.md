# Fortinet Docs Downloader

Portable Windows-native CLI for discovering and downloading PDF documentation from the Fortinet Document Library.

## Status

**Current release: v0.0.15**

The core workflow is validated end to end on both:

- GitHub Actions running Windows Server 2025 with the real `cmd.exe` Batch implementation.
- The target restricted Windows workstation.

For the live FortiPAM 7.0 test page:

```text
https://docs.fortinet.com/product/fortipam/7.0
```

the validated result is:

```text
Documents discovered : 6
PDF targets resolved  : 6
Warnings/failures     : 0
```

All six PDFs were also downloaded successfully.

## Restricted workstation design

The supported runtime path uses only Windows inbox tooling:

- `cmd.exe`
- `curl.exe`
- `findstr.exe`
- standard Batch built-ins

There is no PowerShell, Git, Python, Node.js, package manager, custom executable, admin-rights requirement, or registry modification in the supported path.

Internet access is used only for the tool's declared function: retrieving Fortinet documentation pages and PDF attachments.

## Install

Download the repository ZIP from GitHub, extract it, and run:

```bat
install.bat
```

The installer performs capability checks and creates the local runtime directories. It does not download dependencies.

## Usage

Start the interactive menu:

```bat
run.bat
```

Or use the command form directly.

Inventory a product/version without downloading:

```bat
run.bat inventory https://docs.fortinet.com/product/fortipam/7.0
```

Download all PDFs exposed by that product/version page:

```bat
run.bat download https://docs.fortinet.com/product/fortipam/7.0
```

Run the environment check:

```bat
run.bat doctor
```

Run the parser regression test:

```bat
run.bat selftest
```

## Output

Downloaded PDFs are written beneath an organized corpus root:

```text
runtime\downloads\
  products\<product>\<version>\
  solution-hubs\<solution>\<version>\
  ordering-guides\
```

The catalogue remains authoritative for SHA-256 content identity. If the same PDF is referenced by multiple sources, the existing physical file is reused rather than duplicated merely to populate another folder.

For FortiPAM 7.0, the live validation resolved and downloaded:

```text
FortiPAM-7.0.0-Getting_Started.pdf
FortiPAM-7.0.0-Administration_Guide.pdf
FortiPAM-7.0.0-Release-Notes.pdf
FortiPAM-7.0.0-Ports.pdf
FortiPAM-7.0.0-Examples.pdf
FortiPAM-7.0.0-Best_Practices.pdf
```

## How discovery works

The downloader follows the same server-rendered HTML path used by the Fortinet Document Library:

```text
product/version page
  -> discover <a href="/document/..."> links
  -> fetch each document page
  -> locate id="reader-pdf"
  -> resolve the direct HTTPS PDF attachment
  -> optionally download with curl.exe
```

The parser deliberately targets Fortinet's current document markup rather than attempting to be a general HTML parser.

## Validation

Every parser change is now gated by a Windows GitHub Actions workflow that runs:

1. `install.bat`
2. `run.bat doctor`
3. `run.bat selftest`
4. live FortiPAM 7.0 inventory
5. live FortiPAM 7.0 PDF download
6. non-empty PDF verification

The v0.0.4 validation run passed all of those stages before the working implementation was merged. v0.0.5 contains only documentation and deterministic CLI-banner alignment changes on top of that working parser.

## Download tracking

v0.0.7 maintains persistent state under:

```text
runtime\state\downloads.db
```

Each successful download records the Fortinet document URL, resolved PDF URL, local filename, and remote ETag when available. Future inventory/download runs classify each PDF as:

- `NEW` - no previous tracked download.
- `UNCHANGED` - same document/PDF identity and the local file is present.
- `CHANGED` - the resolved PDF URL, filename, or ETag changed.
- `MISSING_LOCAL` - the PDF was tracked previously but the local file is gone.

Download mode automatically skips `UNCHANGED` files and retrieves only new, changed, or missing PDFs. Tracking state lives under `runtime/`, so normal ZIP-overlay upgrades preserve it.

## Version-aware catalogue

v0.0.8 adds a historical documentation catalogue:

```text
runtime\state\catalogue.db
```

The catalogue records the Fortinet document URL, product, document family, source-path version, inferred document version, PDF URL, remote filename, ETag, Content-Length, SHA-256, first seen, last seen, local filename, lifecycle status, and the product catalogue URL that exposed it.

The new command:

```bat
run.bat check https://docs.fortinet.com/product/<product>
```

checks the live product page without downloading and reports newly observed documents/versions, in-place updates, known versions, duplicate content, and locally missing PDFs.

SHA-256 is the authoritative local content identity. If the same bytes are exposed through another document URL or filename, the downloader reuses the existing local PDF rather than storing another copy. If a nominally identical version is republished with different bytes, the old file is retained and the replacement receives a short SHA-256 suffix so history is not overwritten.

## Current limitations

The current release processes one Fortinet product/version page at a time.

Not yet implemented:

- all-version traversal beyond what a product root already exposes
- document-type filtering
- removed-from-catalogue reporting
- richer human-readable corpus manifests

See `docs/ARCHITECTURE.md` and `docs/VALIDATION.md` for implementation and validation details.


## FortiWeb note

FortiWeb product pages use document anchors where attributes such as `class` can appear before `href`. v0.0.6 discovers relative `/document/...` targets regardless of that attribute ordering and de-duplicates repeated links.

Use the product root:

```bat
run.bat inventory https://docs.fortinet.com/product/fortiweb/
```

The Windows CI suite includes this FortiWeb root inventory as a regression test.


## FortiCamera note

FortiCamera uses the same class-before-href anchor pattern as FortiWeb and publishes document paths under `/document/forticamera/latest/...`. v0.0.6 supports this structure directly.

Use:

```bat
run.bat inventory https://docs.fortinet.com/product/forticamera
```

The Windows CI suite includes FortiCamera root inventory as a permanent regression test.

## Documents without PDFs

Some Fortinet product pages contain documentation entries that do not expose a `reader-pdf` target. v0.0.6 reports these as `No PDF available` and skips them without treating them as parser/download failures. Network errors, broken document pages, failed downloads, and zero-byte PDFs remain failures.


See `docs/TRACKING.md` for the tracking-state format and change-detection rules.


See `docs/CATALOGUE.md` for the version/history schema and de-duplication rules.


## v0.0.9 multi-source acquisition

The downloader now supports three Fortinet source families while preserving a shared local corpus.

### Product documentation

Existing product URLs continue to work unchanged:

```bat
run.bat inventory https://docs.fortinet.com/product/fortipam/7.0
run.bat check https://docs.fortinet.com/product/fortipam/7.0
run.bat download https://docs.fortinet.com/product/fortipam/7.0
```

### Specialist Solution Hubs

List the current Solution Hub entries:

```bat
run.bat hubs
```

Use a solution page with the normal inventory/check/download commands:

```bat
run.bat inventory https://docs.fortinet.com/sdwan/8.0
run.bat check https://docs.fortinet.com/sdwan/8.0
run.bat download https://docs.fortinet.com/sdwan/8.0
```

Solution pages can curate deep links into existing product guides and direct Fortinet-hosted PDF resources. They use the same `catalogue.db` and SHA-256 content identity as product downloads, so a guide already present through a product page is reused rather than downloaded again.

Solution-to-resource provenance is retained in:

```text
runtime\state\sources.db
```

### Fortinet Community Knowledge Base

List discoverable KB product/use-case categories:

```bat
run.bat kb categories
```

Inventory or check a category without fetching article bodies:

```bat
run.bat kb inventory https://community.fortinet.com/fortigate-3
run.bat kb check https://community.fortinet.com/fortigate-3
```

Synchronize the category's article corpus:

```bat
run.bat kb sync https://community.fortinet.com/fortigate-3
```

An optional final numeric argument limits processing, which is useful for testing:

```bat
run.bat kb sync https://community.fortinet.com/fortigate-3 10
```

Article discovery uses Fortinet Community's topic sitemaps rather than the category page's featured-content stream. Raw article HTML is retained losslessly under:

```text
runtime\kb\articles\<category>\
```

Current state and prior changed revisions are tracked in:

```text
runtime\state\kb.db
runtime\state\kb-history.db
```

### Native self-update

Update the application from the current `main` branch:

```bat
run.bat update
```

The updater uses Windows-native `curl.exe`, `tar.exe`, `robocopy.exe`, and `cscript.exe`. It stages itself under `runtime\temp`, downloads/extracts the GitHub ZIP, overlays application files, verifies the new version, and runs the updated installer. The entire `runtime\` tree is excluded from the overlay so PDFs, KB articles, and state databases survive upgrades.

Starting with v0.0.15, the updater then runs a transactional corpus-layout migration. Existing flat PDFs are retained and moved into deterministic product/version, Solution Hub, or Ordering Guides folders, and `downloads.db`, `catalogue.db`, and `sources.db` are rewritten to the new relative paths. If the migration cannot complete safely, it rolls back the file moves/database rewrites and the update fails closed.

## Metadata-only documentation indexing (v0.0.17)

`run.bat docs products` discovers products from the Fortinet documentation catalogue. `run.bat docs index [product]` visits HTML document pages, reads `reader-pdf` links, and records metadata into `runtime\state\docs-index.db` without downloading PDF bodies. `run.bat docs check [product]` performs read-only comparison, `run.bat docs status` reports index size, and `run.bat docs reconcile --preview` lists unique filename-based candidate matches for already downloaded `runtime\downloads\unclassified` PDFs without moving them. Remote filename matches are **not** verified SHA-256 matches and are never applied automatically.

The indexer requires HTTPS connectivity for discovery only; the existing offline install/doctor remain offline-compatible. Product discovery reflects URLs exposed by the website and may not be exhaustive. Indexing may take time; run scoped product indexing for targeted scans.
