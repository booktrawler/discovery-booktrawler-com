# Upgrade main site with `new-site` content (tomrhodes.me, full SEO/AEO/GEO)

## Context
The repository at `discovery-booktrawler-com` hosts the static site for **tomrhodes.me** (deployed via GitHub Pages, CNAME already `tomrhodes.me`). The root currently contains a placeholder homepage (`index.html` titled "Nothing to see here"), the `discovery/` reading-guide section (395 SEO'd pages), plus `sitemap.xml`, `robots.txt`, `CNAME`.

The `new-site/` folder is a redesign/upgrade:
- New root `index.html` — real homepage (tom/rhodes book brand: The Saint Effect, The Gentle Uprising, The Winners Circle, The Long Middle, Rewind & Reclaim, Trafalgar).
- Four entirely new top-level sections: `blog/` (70 files), `books/` (47 files), `recommends/` (99 files), `downloads/` (34 PDFs), plus `images/` (32 assets incl. favicons, `site.webmanifest`).
- `discovery/` inside `new-site/` is **byte-for-byte identical** to the existing root `discovery/` (same 395 files), so it does not need merging — keep the existing one.

All new content already uses absolute `https://tomrhodes.me/...` URLs in canonical, Open Graph, Twitter, and JSON-LD tags (verified: no external domain references except Google Fonts, schema.org, w3.org). The repo root is already on `tomrhodes.me`; the upgrade simply lands the new content.

## Goal
Replace the placeholder homepage with the upgraded one and publish the new sections, keeping `discovery/` intact, ensuring the whole site is on `tomrhodes.me` with consistent, correct SEO/AEO/GEO metadata and a complete sitemap.

## Plan

### 1. Copy new-site content into the repository root
From `new-site/` into repo root (do NOT touch `discovery/` — it is identical):
- `index.html` → overwrite root `index.html`
- `blog/` → root `blog/`
- `books/` → root `books/`
- `recommends/` → root `recommends/`
- `downloads/` → root `downloads/` (PDFs only; no index.html — that is fine)
- `images/` → root `images/` (overwrites/merges; includes `site.webmanifest`, favicons, covers)

Keep at root: `CNAME`, `robots.txt`, `sitemap.xml` (will be regenerated), `discovery/`.

Do NOT delete `audit-report.csv` / `audit-summary.md` (useful for validation) unless desired.

### 2. Fix canonical conflict in `recommends/index.html`
This is an SEO bug in the source. Currently:
```
<link rel="canonical" href="https://tomrhodes.me/">
<meta property="og:url" content="https://tomrhodes.me/">
```
Change both to `https://tomrhodes.me/recommends/` so it does not collide with the homepage canonical. (Inner `recommends/books/*.html` pages already use correct per-page canonicals.)

### 3. Verify all internal links/assets resolve
- New root `index.html` uses root-relative (`/images/logo.png`) and relative (`images/...`, `blog/`, `books/...`) paths — all resolve once copied to root.
- Confirm every image referenced by `index.html` exists in `images/`: `logo.png`, `saint-effect-cover.jpg`, `gentle-uprising-cover.png`, `The_Winners_Circle.jpg`, `The_Long_Middle.jpg`, `Rewind_Reclaim.jpg`, `trafalgar/jeopardy_cover_publish.jpeg` (all present — verified).
- Spot-check `books/*/index.html` and `blog/*` link targets (the `books/` section uses subfolder `index.html` routing, e.g. `books/winners-circle/`).

### 4. Regenerate `sitemap.xml` for the full site
The current `sitemap.xml` only lists `discovery/` URLs (395). After the upgrade the site has many more indexable pages. Regenerate to include:
- Root: `https://tomrhodes.me/`
- `blog/` and all `blog/**/index.html` + posts
- `books/` and all `books/**/index.html`
- `recommends/` and all `recommends/**/*.html`
- `discovery/` and all existing `discovery/**/*.html` (keep these)
- `downloads/` PDFs: **EXCLUDED** from the sitemap (CONFIRMED: HTML pages only). PDFs remain linked assets, not sitemap entries.

Recommended approach: generate the sitemap programmatically (e.g. a small PowerShell/Node script) by walking the repo for `*.html` files and emitting `<loc>` for each, excluding `new-site/` and any non-public paths. Include `lastmod` where available. Keep the `https://tomrhodes.me/sitemap.xml` reference in `robots.txt` (already present).

### 5. Confirm/extend SEO/AEO/GEO basics (already mostly in place)
- `robots.txt` already: `Sitemap: https://tomrhodes.me/sitemap.xml` and `Allow: /` — keep.
- Optional enhancement: add `<link rel="manifest" href="/images/site.webmanifest">` and the Apple/Android touch icons to the new root `index.html` `<head>` (the `site.webmanifest` and icon files already exist in `images/`). This strengthens PWA/brand SEO signals.
- Ensure each new section index page has `title`, `meta description`, canonical, OG, Twitter, and JSON-LD — verified present on `blog/`, `books/`, `recommends/` (after fix). `downloads/` has no index.html (PDFs only) — acceptable.
- AEO/GEO: confirm FAQ/structured answers exist where relevant (the discovery pages already carry JSON-LD `@graph` with Organization/WebSite/BreadcrumbList). New book/blog pages carry `CreativeWorkSeries`/`Blog` JSON-LD — sufficient for entity coverage.

### 6. Validation
- Re-run the existing SEO audit (the `scripts/` folder likely contains the generator used for `audit-report.csv`). If a script exists, run it against the merged site and confirm: Canonical 100%, OG 100%, Twitter 100%, JSON-LD 100%, Title 100%, Meta description 100%, H1 100% — and especially that `recommends/index.html` now shows `/recommends/` canonical (no longer a duplicate of `/`).
- Grep the merged site for any hardcoded non-`tomrhodes.me` absolute URLs (should be none except fonts/schema).
- Verify no broken internal links by checking referenced local paths exist.
- Confirm `CNAME` still contains `tomrhodes.me`.

## Risks / open questions
- **`downloads/` has no index.html` (CONFIRMED: leave as-is).** Users navigating to `https://tomrhodes.me/downloads/` will 404; PDFs are reached only via direct links from the book pages. No hub page will be added.
- **`recommends/index.html`** is the only metadata bug found; fix is mandatory for clean SEO.
- Merge is non-destructive to `discovery/` (identical). No content from the old placeholder `index.html` is worth preserving.
- Deployment: after commit, GitHub Pages publishes from `main`. No build step detected (pure static). Confirm no CI expects a different publish directory.

## Files touched (summary)
- Modified: root `index.html` (replaced), `recommends/index.html` (canonical fix), `sitemap.xml` (regenerated), optionally root `index.html` `<head>` (webmanifest/icons).
- Added: `blog/`, `books/`, `recommends/`, `downloads/`, `images/` (from new-site).
- Unchanged: `CNAME`, `robots.txt`, `discovery/`.
