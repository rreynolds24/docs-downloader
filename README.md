# Fortinet Docs Downloader

Portable Windows-native CLI for discovering and downloading PDF documentation from the Fortinet Document Library.

## Status

**Current release: v0.0.6**

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

Downloaded PDFs are written to:

```text
runtime\downloads\
```

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

## Current limitations

The current release processes one Fortinet product/version page at a time.

Not yet implemented:

- all-version traversal
- document-type filtering
- manifest generation
- update/delta mode
- de-duplication across multiple requested versions

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
