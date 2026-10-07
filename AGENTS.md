# Project rules

- This is a restricted-workstation Windows CLI.
- The supported operator path must not require PowerShell, Git, Python, Node.js, package managers, admin rights, registry writes, or unsigned custom executables.
- Prefer Windows inbox tooling. v0.0.1 is `cmd.exe` + `curl.exe` + `findstr.exe`.
- Keep runtime/downloaded data under `runtime/`.
- Fail closed when expected Fortinet HTML markers are absent.
- Preserve the Fortinet terminal ASCII silhouette for human-operated CLI output.
- Do not introduce a PowerShell helper for convenience.
