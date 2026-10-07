# Authoritative state

Project: `docs-downloader`
Release target: `0.0.1`
State: active / awaiting target-workstation validation

## Authority

- Runtime implementation: `docs-downloader.bat`
- Bootstrap: `install.bat`
- Launcher: `run.bat`
- Architecture: `docs/ARCHITECTURE.md`
- Handoff: `HANDOFF.md`
- Next actions: `TODO.md`
- Decisions: `DECISIONS.md`

## Approval boundary

The user explicitly authorized development of v0.0.1 and full merge to the dedicated `rreynolds24/docs-downloader` repository for restricted-workstation testing.

No deployment to the workstation is authorized or possible from this workspace.

## Release constraints

- No PowerShell.
- No unsigned custom executable.
- No Git/runtime package manager requirement.
- Windows inbox `cmd.exe`, `curl.exe`, and `findstr.exe` only for v0.0.1.
- Network access is only for Fortinet documentation retrieval.
