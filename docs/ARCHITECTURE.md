# Architecture

## v0.0.9 scope

v0.0.9 turns the downloader into a multi-source Fortinet corpus collector while retaining the proven restricted-Windows deployment model.

```text
run.bat
  |
  +-- product docs ------ docs-downloader.bat
  |      -> docs.fortinet.com/product/...
  |      -> reader-pdf
  |
  +-- Solution Hubs ----- solution-downloader.bat
  |      -> docs.fortinet.com/<solution>/<version>
  |      -> deep product-document links
  |      -> Fortinet-hosted direct PDFs
  |
  +-- Knowledge Base ---- kb-downloader.bat
  |      -> community.fortinet.com sitemap index
  |      -> topic sitemaps
  |      -> per-category article corpus
  |
  +-- self update ------- update.bat
         -> GitHub main ZIP
         -> native extract/overlay
         -> preserve runtime/
```

## Restricted-workstation runtime

Core product acquisition remains Batch plus Windows inbox tools. v0.0.9 adds Windows Script Host `cscript.exe` for deterministic parsing of Solution Hub HTML and large minified Community XML sitemaps.

Runtime tools:

- `cmd.exe`
- `curl.exe`
- `findstr.exe`
- `certutil.exe`
- `cscript.exe` for Solution Hub / Knowledge Base parsing
- `tar.exe` and `robocopy.exe` only when `run.bat update` is invoked

No PowerShell, Git, Python, Node.js, package manager, custom executable, admin rights, registry mutation, or installer download is required.

## Shared PDF content identity

Product docs and Solution Hub resources use the same:

```text
runtime\downloads\
runtime\state\downloads.db
runtime\state\catalogue.db
```

SHA-256 remains authoritative local PDF content identity. Solution Hub deep links may resolve to the same full guide through many chapter URLs. Once a matching PDF URL/remote identity or SHA-256 is known, the existing local file is reused.

Curated-source membership is independent of content storage and is tracked in:

```text
runtime\state\sources.db
```

Schema:

```text
source_url|resource_url|pdf_url|sha256|first_seen|last_seen|local_filename
```

This preserves the fact that a PDF belongs to one or more curated solution pages without storing duplicate bytes.

## Solution Hub parsing

The Windows Script Host parser scans anchor tags and accepts only:

- relative or absolute `docs.fortinet.com/document/...` links;
- direct PDFs hosted on approved Fortinet domains.

Third-party links from a curated page are not downloaded automatically.

Each docs document link is fetched and resolved through the normal `reader-pdf` mechanism.

## Knowledge Base corpus

The KB category page is used for category discovery only. Full per-category article discovery comes from the Community sitemap index and its `sitemap-topics-*.xml` members.

The bundled WSH parser extracts:

```text
article_url|lastmod|article_id
```

and filters by category path.

Raw article HTML is stored under:

```text
runtime\kb\articles\<category>\article-<id>.html
```

Current article state:

```text
runtime\state\kb.db
```

Historical changed article state:

```text
runtime\state\kb-history.db
```

`lastmod` is used for inexpensive change classification. On sync, downloaded article bytes are SHA-256 hashed. If sitemap metadata changed but bytes did not, only state metadata advances. If content changed, the prior HTML is retained with a short hash suffix before the current article is replaced.

## Native self-update

`run.bat update` dispatches to `update.bat`.

The updater:

1. copies itself under `runtime\temp` so its source can be overwritten safely;
2. downloads the GitHub `main.zip` using `curl.exe`;
3. extracts with `tar.exe`;
4. validates the extracted app root;
5. compares `VERSION`;
6. overlays application files with `robocopy.exe`, explicitly excluding `runtime` and `.git`;
7. verifies the installed version and critical files;
8. invokes the updated `install.bat`.

`robocopy` exit codes below 8 are treated as success.

## Validation

The Windows gate retains all v0.0.8 product regressions and adds:

- live SD-WAN Solution Hub inventory;
- live Community KB category discovery;
- bounded live FortiGate KB article sync plus repeat unchanged check;
- synthetic native update that proves application files change while a runtime marker survives.

## Deferred scope

- automated global sync of every KB category in one command;
- normalized text/Markdown conversion of KB HTML;
- removed-from-source lifecycle reporting;
- product/version directory migration for PDFs.
