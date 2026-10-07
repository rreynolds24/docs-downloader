# Handoff

## Objective

Provide a portable Fortinet documentation downloader that can run on a restricted Windows workstation with Internet access for Fortinet documentation only.

## Current state

**v0.0.1 is merged to `main` via PR #1.**

The release implements a pure Batch/curl workflow:

- `install.bat` checks required inbox tooling and creates runtime directories.
- `run.bat` is the stable launcher.
- `docs-downloader.bat` provides an operator menu plus direct `inventory`, `download`, and `doctor` commands.
- Product/version HTML is fetched from `docs.fortinet.com`.
- Simple `/document/` links are extracted from the product page.
- Each document page is followed with `curl -L`.
- The direct PDF link is extracted from the `reader-pdf` anchor.
- PDFs are downloaded to `runtime\downloads`.
- The human-operated CLI uses the Fortinet ASCII-art convention.

The parser design is grounded in the supplied October 2026 Fortinet Docs HAR captures. Static/HAR validation passed for the initial FortiManagement Cloud 26.3 test case.

## Exact next action

On the restricted Windows workstation, download the repository ZIP from `main`, extract it, and run:

```bat
install.bat
run.bat inventory https://docs.fortinet.com/product/fortimanagement-cloud/26.3
```

Expected inventory count: **4** PDF targets.

If inventory succeeds:

```bat
run.bat download https://docs.fortinet.com/product/fortimanagement-cloud/26.3
```

## Validation boundary

The remaining acceptance gate is real `cmd.exe` execution on the restricted workstation. Do not mark the Windows offline-app contract PASS until that execution evidence exists.
