# Handoff

## Objective

Provide a portable Fortinet documentation downloader that can run on a restricted Windows workstation with Internet access for Fortinet documentation only.

## Current state

v0.0.1 implements a pure Batch/curl workflow:

- `install.bat` checks required inbox tooling and creates runtime directories.
- `run.bat` is the stable launcher.
- `docs-downloader.bat` provides an operator menu plus direct `inventory`, `download`, and `doctor` commands.
- Product/version HTML is fetched from `docs.fortinet.com`.
- Simple `/document/` links are extracted from the product page.
- Each document page is followed with `curl -L`.
- The direct PDF link is extracted from the `reader-pdf` anchor.
- PDFs are downloaded to `runtime\downloads`.

The parser design is grounded in the supplied October 2026 Fortinet Docs HAR captures.

## Exact next action

Download the repository ZIP on the restricted Windows workstation, extract it, run `install.bat`, then run:

```bat
run.bat inventory https://docs.fortinet.com/product/fortimanagement-cloud/26.3
```

If inventory succeeds, run the same URL with `download`.

## Validation boundary

Repository/static validation is possible in the current environment, but Windows `cmd.exe` execution on the actual restricted workstation remains the release acceptance gate.
