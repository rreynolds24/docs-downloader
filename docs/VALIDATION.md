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
