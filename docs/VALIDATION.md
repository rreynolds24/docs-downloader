# Validation

## Current validated baseline

The working parser baseline was established in v0.0.4 and retained in v0.0.5.

### Windows CI

GitHub Actions run `37592012850` executed the real Batch application on Windows Server 2025 and passed:

- `install.bat`
- `run.bat doctor`
- `run.bat selftest`
- live FortiPAM 7.0 inventory
- live FortiPAM 7.0 download
- non-empty PDF checks

Live result:

```text
Documents discovered : 6
PDF targets resolved  : 6
Warnings/failures     : 0
```

### Restricted workstation

The same v0.0.4 workflow was subsequently confirmed on the restricted Windows workstation. FortiPAM 7.0 PDF downloads completed successfully.

## FortiPAM 7.0 corpus

The validated product page resolves:

- Getting Started
- Administration Guide
- Release Notes
- FortiPAM Ports
- Examples
- Best Practices

## Release discipline

Parser changes must continue to pass the Windows validation workflow before merge. Static review alone is not sufficient for CMD parsing changes.


## v0.0.6 multi-product regression coverage

Windows CI now validates:
- FortiPAM 7.0 inventory and full PDF download
- FortiWeb root inventory using class-before-href document anchors
- FortiCamera root inventory using `/document/forticamera/latest/...` paths

A document page with no `reader-pdf` target is treated as a non-fatal skip and is counted separately from warnings/failures.


## v0.0.7 tracking regression

Windows validation now performs two consecutive live FortiPAM 7.0 downloads in the same workspace.

The first run must:
- create `runtime\state\downloads.db`;
- download non-empty PDFs;
- write FortiPAM document records into the tracking database.

The second run must:
- return success;
- report `Downloaded/updated : 0`;
- report `Unchanged/skipped : 6`;
- report `Unchanged PDFs : 6`.

The cmd.exe self-test also validates the four tracking classifications: `NEW`, `UNCHANGED`, `CHANGED`, and `MISSING_LOCAL`.
