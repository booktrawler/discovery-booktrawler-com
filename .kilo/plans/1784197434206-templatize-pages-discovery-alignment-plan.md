# Plan: Templatize all site pages (head / header / content / footer) + align discovery styling

## Context

The site is a **static HTML site** of **599 pages** (no `package.json`, no build system), mirrored into a `new-site/` folder (also 599 pages). Today the markup is duplicated and inconsistent:

- **`blog/`, `books/`** → inline `<style>` block (variants differ even between index and sub-pages) + a `<nav>` "logo" header (`<a class="logo">` + `.nav-links` + a Discovery link) + a simple `<footer>`.
- **`discovery/`** → external `../style.css` + a `<header class="site-header">` "brand" header (`<a class="brand">` + `<nav>` of section links). It currently has a **bug**: a duplicated `<a href="/">Home</a>` in the header (see `discovery/fiction/index.html:27`).
- **`recommends/`** → a *third* design system entirely (Poppins/Source Serif fonts, indigo/amber palette, `sg-` classes, `@import` fonts) and `recommends/index.html` has **no rendered header element at all**.

Two header/footer templates plus three visual systems make the site hard to maintain. Goal: extract shared partials — `<head>`, header nav, page content, footer nav — so every page (including discovery) is assembled from the same templates, and align discovery's styling to the shared site look.

`new-site/` is a work-in-progress mirror (it already carries the *fixed* discovery header without the duplicated Home link). Treat `new-site/` as the **target output location** for the templated/aligned pages; the live root tree is the source of truth for content until `new-site/` is promoted.

## Decisions (confirmed with user)

1. **Build mechanism:** PowerShell templating script(s), consistent with the existing `scripts/*.ps1` toolset. No new runtime deps, no Node/SSG.
2. **Scope:** Whole site at once — `blog/`, `books/`, `recommends/`, and `discovery/` all standardized onto one head/header/content/footer structure.

## Target architecture

Introduce a `templates/` directory with partials and a single shared stylesheet, then a build script that renders each `.html` page from its content + the shared partials.

### Partial files (`templates/`)
- `templates/head.html` — the static portion of `<head>`: `<meta charset>`, viewport, font `<link>`/preconnect, and the shared stylesheet `<link rel="stylesheet" href="...">`. Per-page values (title, description, canonical, OG/Twitter, JSON-LD) stay **in the page content file** as a small `<head>-vars` block OR are passed as parameters — see "Page content format" below.
- `templates/header.html` — ONE standardized site header for all sections:
  - `tom/rhodes` logo (img) + `logo-wordmark` span, linking to site root.
  - Nav links: **Home, Books, Blog, Discovery, About** (root-relative `/`). Discovery section pages keep their in-section sub-nav (Nonfiction/Fiction/Kids/Young Adult/Reading Journeys) **below or within** the header as a secondary nav — preserve that behaviour, don't drop the section links.
  - Fixes the discovery duplicated-Home bug automatically (single source = template).
- `templates/footer.html` — standardized footer nav mirroring the header links + the existing copyright/reader-supported disclaimer copy. Discovery's extra `eeat` `<footer>` block is preserved as part of discovery page *content* (it's content, not chrome).

### Shared stylesheet
- Create one canonical `style.css` (placed so every page can reference it via a normalized relative path — recommend root `style.css` referenced as `/style.css` absolute, or per-section relative path computed by the build script).
- Consolidate the three fragmented design systems (blog/books navy+Cormorant, discovery `style.css`, recommends indigo/amber) into this single sheet. **Discovery is aligned to the dominant site look** (the blog/books "rest of the site" system, since that is the majority). Keep discovery's `topic-card` / `topics` component styles; carry over recommends functionality but restyle to match.

### Page content format
Each page becomes: `<head>` per-page vars (title/description/canonical/OG/JSON-LD) + the `<main>` body content (everything currently between `</header>` and `<footer>`, including discovery's `eeat` footer block which is content). The build script wraps: `head partial (title/description injected) + header partial + page content + footer partial`.

Recommended representation: keep a `<!-- PAGE-META -->` block at the top of each content file with the page-specific `<title>`, `<meta description>`, canonical, OG/Twitter, and JSON-LD; the build script extracts it into the head partial position. This keeps pages still openable-ish and diff-friendly, and means page-specific meta stays with the page.

## Implementation steps

1. **Create `templates/` partials** (`head.html`, `header.html`, `footer.html`) from the consolidated markup described above. Header must include the logo/wordmark + Home/Books/Blog/Discovery/About, plus a secondary section-nav slot for discovery.
2. **Create the unified `style.css`** merging blog/books + discovery + recommends styles, with discovery aligned to the shared look. Remove the now-redundant `discovery/style.css`.
3. **Write `scripts/build-templates.ps1`** that, for each `.html` in scope (respecting `new-site` vs live):
   - Splits the existing file into per-page meta + `<main>` content (detect boundaries: `<head>`…`</head>` for meta; header element to first `<footer>`/end-of-`<main>` for content).
   - Emits `head partial` (with injected page meta) + `header partial` (with correct relative paths + active-section marking) + `content` + `footer partial`.
   - Computes the correct relative `style.css` path per file depth (root vs `section/`, `section/sub/`, `discovery/cat/`).
   - Is **idempotent / `--WhatIf`** like the existing scripts (see `scripts/add-header-links.ps1`).
   - Skips `index.html` root if it defines its own hero (handle separately) and skips `scripts/`, `.kilo/`, `.git/`.
4. **Reuse existing tooling**: the new script should sit alongside `add-header-links.ps1`, `audit-seo.ps1`, `build-sitemap.ps1`, `fix-seo*.ps1`. After templating, re-run `build-sitemap.ps1` and `audit-seo.ps1` to confirm no regressions.
5. **Discovery alignment pass**: ensure discovery pages use the same header/footer and shared `style.css`; remove the duplicated Home link; verify `topic-card`, `topics`, `lead`, `page` classes exist in the unified sheet.
6. **`recommends/` normalization**: inject the missing header on `recommends/index.html`; restyle to shared look; keep its list functionality.
7. **Output location**: generate into `new-site/` (the WIP mirror) first so the live tree is untouched, then diff before promoting. Provide a `--Live` switch to also write the live root tree if desired.

## Validation

- `pwsh -File scripts/build-templates.ps1 -WhatIf` reports page counts per section and any files it cannot cleanly split (boundary detection failures) — fix those manually or extend the splitter.
- After a real run into `new-site/`: every page contains exactly one `<head>`, one header partial include, one footer partial include; no inline `<style>` remains except the page-meta; discovery pages have **no** duplicated Home link.
- Visual spot-check: open `new-site/discovery/fiction/index.html`, `new-site/blog/index.html`, `new-site/recommends/index.html`, `new-site/books/winners-circle/index.html` and confirm consistent header/footer and aligned styling.
- Re-run `scripts/audit-seo.ps1` and `scripts/build-sitemap.ps1`; confirm no broken internal links (especially the new `/style.css` path resolves from every depth — add `style.css` at root and/or verify relative path math).
- Confirm CSS-only changes: no content/links altered, only structure + styling consolidated.

## Risks / open questions

- **CSS merge conflicts:** the three design systems differ materially (navy vs indigo, Cormorant vs Poppins). Aligning discovery (and recommends) to the blog/books look is a visible visual change — confirm that is intended vs. merely *sharing* the template structure while keeping discovery's own `style.css`. **(Assumption in plan: align to shared look.)**
- **`recommends` has no header** and a different component vocabulary (`sg-*`); normalization may need manual component mapping.
- **Path depth math** for the shared `style.css` must be correct for root, `section/`, `section/sub/`, and `discovery/category/` pages; simplest safe choice is absolute `/style.css` if the site is served from domain root (it is: `https://tomrhodes.me/`).
- **`new-site` vs live:** `new-site/` is a stale throwaway and can now be removed.
