# Fortinet Docs Downloader

Portable Windows-native CLI for discovering and downloading PDF documentation from the Fortinet Document Library.

## Restricted workstation design

The supported runtime path uses only Windows inbox tooling:

- `cmd.exe`
- `curl.exe`
- `findstr.exe`
- standard Batch built-ins

There is no PowerShell, Git, Python, Node.js, package manager, custom executable, admin-rights requirement, or registry modification in the supported path.

Internet access is used only for the tool's core function: retrieving pages and PDF attachments from Fortinet documentation endpoints.

## v0.0.1

The initial release accepts a Fortinet **product/version** URL, for example:

```text
https://docs.fortinet.com/product/fortimanagement-cloud/26.3
```

It discovers the documents listed on that page, follows each document page, resolves the direct `reader-pdf` link, and optionally downloads the PDFs.

## Restricted workstation test

Download the repository ZIP from GitHub and extract it. No Git client is required.

Run:

```bat
install.bat
```

Then inventory the HAR-validated test product:

```bat
run.bat inventory https://docs.fortinet.com/product/fortimanagement-cloud/26.3
```

Expected v0.0.1 inventory result: four PDF targets should be discovered:

- Administration Guide
- Release Notes
- GUI Mapping Guide for Edge
- MSSP Deployment Guide

If inventory succeeds:

```bat
run.bat download https://docs.fortinet.com/product/fortimanagement-cloud/26.3
```

PDFs are written beneath:

```text
runtime\downloads\
```

You can also start the interactive menu with:

```bat
run.bat
```

and run the local environment check with:

```bat
run.bat doctor
```

## Current limitations

v0.0.1 intentionally supports one product/version page at a time. All-version crawling, document-type filters, manifests, and delta/update mode are planned after restricted-workstation validation.

See `docs/ARCHITECTURE.md` for implementation and design details.
