# Authoritative state

Project: `docs-downloader`
Release: `0.0.1`
State: merged to `main`; awaiting restricted-workstation validation
Main merge commit: `316e4e97acda1e0d4525e449fd2a32fc41ade591`
Pull request: `#1`

## Authority

- Runtime implementation: `docs-downloader.bat`
- Bootstrap: `install.bat`
- Launcher: `run.bat`
- Architecture: `docs/ARCHITECTURE.md`
- Handoff: `HANDOFF.md`
- Next actions: `TODO.md`
- Decisions: `DECISIONS.md`

## Verified evidence

- The supplied FortiManagement Cloud 26.3 product-page HAR contains four unique simple `/document/` links.
- The supplied Release Notes HAR contains one `reader-pdf` anchor whose sixth quote-delimited token is the direct HTTPS PDF URL.
- Repository tree contains no custom executable or PowerShell script.

## Approval boundary

The user explicitly authorized development of v0.0.1 and full merge to the dedicated `rreynolds24/docs-downloader` repository for restricted-workstation testing.

No workstation deployment was performed from this workspace.

## Release constraints

- No PowerShell.
- No unsigned custom executable.
- No Git/runtime package manager requirement.
- Windows inbox `cmd.exe`, `curl.exe`, and `findstr.exe` only for v0.0.1.
- Network access is only for Fortinet documentation retrieval.
