# SEO / AEO / GEO Audit & Remediation Plan — tom/rhodes Discovery

## Context (verified against the codebase)
- 394 static HTML pages under `discovery/` plus a root `index.html` (a "Nothing to see here" placeholder) and root `sitemap.xml`.
- Current per-page `<head>` contains only: `charset`, `viewport`, `title`, `meta description`, stylesheet link. **Nothing else.**
- Scan results across all 394 pages:
  - canonical tags: **0**
  - Open Graph tags: **0**
  - Twitter cards: **0**
  - JSON-LD structured data: **0**
  - meta robots: **0**
  - `<img>` tags: **0** (text-only site)
- No `robots.txt` exists (repo root or `discovery/`).
- `sitemap.xml` URLs still point to `tom/rhodes.github.io/discovery-tom/rhodes-com/...` (wrong domain + stale after custom-domain launch).
- Custom domain `tomrhodes.me` is now live (CNAME + DNS A/CNAME records configured).

## Decisions (confirmed with user)
1. **Deliverable:** Audit **plus** automated fixes applied via script.
2. **Primary/canonical domain:** `https://tomrhodes.me` everywhere. `tom/rhodes.github.io` is only the underlying host (eventual 301 redirect target source).
3. **Audit method:** Automated PowerShell script parsing all pages, emitting a report.
4. **Schema set:** Full — `Organization` + `WebSite`(SearchAction) + `BreadcrumbList` + `ItemList`/`Book` + `FAQPage`.

## URL structure (critical assumption)
Content lives in repo `/discovery/`, so published URLs are `https://tomrhodes.me/discovery/{relpath}`.
- `discovery/fiction/foo.html` → `https://tomrhodes.me/discovery/fiction/foo.html`
- `discovery/fiction/index.html` → canonical = `https://tomrhodes.me/discovery/fiction/` (directory URL, trailing slash).
- Root `index.html` ("Nothing to see here") is **not** the real home; real home is `discovery/index.html`. See "Root home issue" below.

---

## Implementation Task List

### 1. Regenerate `sitemap.xml` (root) for `tomrhodes.me`
- Reuse the generator logic; base URL = `https://tomrhodes.me/`.
- Include root entries `/`, `/index.html`, `/discovery/`, `/discovery/index.html` + all 394 `discovery/...` HTML files.
- **GSC rule:** sitemap must contain ONLY 200-OK, self-canonical, indexable pages. Exclude the gag root `index.html` OR give it a self-canonical + redirect (see Step 5). Recommended: keep `/discovery/index.html` as the home entry; exclude bare `/index.html` from sitemap OR canonical it to `/discovery/`.
- Validate as well-formed XML.

### 2. Create `robots.txt` at repo root
```
User-agent: *
Allow: /

Sitemap: https://tomrhodes.me/sitemap.xml
```
- Do NOT disallow `discovery/` or any content dir. Keep it permissive so Googlebot can crawl everything.

### 3. Build the **audit script** (`scripts/audit-seo.ps1`)
- Walk all `*.html` under repo root (including root + `discovery/`).
- For each page, detect presence of: `<title>` (+length), `meta description` (+length), canonical, `meta robots`, any `og:`, any `twitter:`, `application/ld+json`, internal links count (anchor `<a href>`), structured heading order (h1 present?).
- Emit `audit-report.csv` (one row per page: path, url, has_canonical, has_og, has_twitter, has_jsonld, has_robots, title_len, desc_len, h1_present, internal_links, issues) and `audit-summary.md` (counts, % coverage, top gaps).
- Idempotent / read-only. This doubles as the validation check after fixes.

### 4. Build the **remediation script** (`scripts/fix-seo.ps1`)
For every `*.html` (root + `discovery/`):
- Compute canonical URL from file path per the URL-structure rule above.
- Inject, before `</head>`, a consistent block:
  - `<link rel="canonical" href="{canonical}">`
  - `<meta name="robots" content="index,follow">` (except the gag root `index.html`, handled in Step 5)
  - **Open Graph:** `og:type=website`, `og:site_name=tom/rhodes Discovery`, `og:title` (from `<title>`), `og:description` (from meta description), `og:url={canonical}`, `og:locale=en_US`. (`og:image` omitted — no images exist; note as follow-up to add a brand social card.)
  - **Twitter:** `twitter:card=summary_large_image`, `twitter:title`, `twitter:description`, `twitter:url`.
  - **JSON-LD** (one `<script type="application/ld+json">` block, concatenated graph):
    - `Organization` (constants: name, url `https://tomrhodes.me/`, sameAs if available).
    - `WebSite` with `potentialAction` `SearchAction` (target `https://tomrhodes.me/discovery/?q={search_term_string}` — verify a search route exists; if not, drop SearchAction).
    - `BreadcrumbList` derived from path segments (Home › Section › Page).
    - `ItemList` of `Book` items parsed from the page where `<h3>`+byline exist (title, author, position). Graceful no-op if not parseable.
    - `FAQPage`: **templated** 1–2 Q&As auto-derived from `<h1>` + lead paragraph (e.g., "What are the best {topic} books?" → lead text). Flag every generated FAQ in `audit-summary.md` for human review; do not invent facts.
- **Idempotent:** script must skip re-injection if the block already exists (detect a marker comment `<!-- seo-injected -->`).
- **Dry-run mode** (`-WhatIf`) prints changes without writing.

### 5. Resolve the **root home issue**
- The repo root `index.html` is a JS gag page with no real content and no link to the site. Left as-is it becomes the indexed homepage (bad).
- Fix (pick one, default A):
  - **A (recommended):** Add `<link rel="canonical" href="https://tomrhodes.me/discovery/">` + a meta-refresh (`<meta http-equiv="refresh" content="0;url=/discovery/">`) so visitors and bots land on the real home. Keep it out of the sitemap's "home" slot.
  - **B (cleaner URLs, larger change):** Relocate all `discovery/` content to repo root and change canonicals to `https://tomrhodes.me/fiction/...`. **Out of scope** unless requested (requires mass file moves + link rewrites).

### 6. Apply & verify
- Run `fix-seo.ps1 -WhatIf`, review diff sample, then run for real.
- Re-run `audit-seo.ps1`; target **100%** coverage for canonical/OG/Twitter/JSON-LD on all indexable pages.
- Confirm `robots.txt` and `sitemap.xml` are valid and reference `tomrhodes.me`.

### 7. Google Search Console activation (manual, post-deploy)
1. Submit `https://tomrhodes.me/sitemap.xml` under **Indexing › Sitemaps**.
2. Use **URL Inspection** to request indexing for `https://tomrhodes.me/discovery/` and a sample of section hubs.
3. Monitor **Indexing › Pages** for "Crawled - currently not indexed" / "Duplicate without user-selected canonical" and fix per the checklist below.

---

## GSC Indexing Checklist (fold into validation & handoff)
- **Sitemap:** clean, only 200-OK self-canonical pages; submit in GSC; no 404/301/`noindex` URLs inside it.
- **Robots.txt:** do not disallow content dirs; verify with GSC Robots.txt Tester.
- **Noindex:** ensure injected `meta robots` is `index,follow` on desired pages (never `noindex` by mistake).
- **Canonical:** every indexable page gets a **self-referencing** canonical; prevents duplicate-collapse.
- **Internal linking:** no orphan pages — confirm every `discovery/...` page is reachable from a hub/category page (the header nav already links sections; verify deep pages are linked from their section index).
- **Request indexing:** use URL Inspection for the most important new/updated pages only (daily quota).
- **Pages report:** watch "Not indexed" reasons — thin/duplicate content needs real improvement, not tags.
- **Speed/Core Web Vitals:** static HTML + single CSS is light; keep it that way (no render-blocking bloat).
- **Content quality:** each of the 394 pages must serve a unique purpose (they do — distinct curated lists); keep blurbs substantive.
- **New-page flow:** publish → link from indexed page → add to sitemap → request indexing.

---

## Risks
- **Regex HTML injection** can corrupt files if structure varies. Mitigation: idempotent marker + `-WhatIf` + diff sample before full run; keep a git commit checkpoint first.
- **SearchAction** target assumes a search route exists — verify or omit.
- **FAQPage auto-text** may be low-quality; flagged for review, not shipped as final.
- **Root gag page** indexed as homepage if Step 5 skipped.
- **Crawl budget / thin content:** 394 near-duplicate list templates could be seen as thin — real, distinct blurbs mitigate this.

## Validation
- `audit-report.csv` shows 0 missing canonical/OG/Twitter/JSON-LD on indexable pages.
- `sitemap.xml` parses; all URLs return 200 and self-canonical (spot-check 10).
- `robots.txt` returns 200 and references the sitemap.
- HTML well-formed (head block valid; no broken tags) — spot-check 5 pages in a validator.
- GSC: sitemap "Success", sample URLs "URL is on Google".

## Open Questions
1. Step 5: accept recommended meta-refresh redirect (A), or relocate content for cleaner root URLs (B, out of scope)?
2. Is there a site search route for the `SearchAction` target, or should we omit it?
3. Want a generated brand `og:image` social card (PNG) added later, or ship without `og:image` for now?
