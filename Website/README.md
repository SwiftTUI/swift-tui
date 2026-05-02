# Website

The TerminalUI documentation and marketing site. An Astro 6 project that
projects the canonical `/docs/` markdown corpus into a curated public site
without duplicating it.

This package replaces the marketing fragment that previously lived inside
[`Examples/WebExample`](../Examples/WebExample). `Examples/WebExample` keeps
its job of being a runnable demo of TerminalUI in the browser.

## Architecture

The site has a single **source-of-truth rule**:

- Strategic prose lives in `/docs/` (repo root).
- DocC-generated symbol reference lives at `/api/` (built from
  `Sources/*/*.docc/` and published alongside this site).
- The Website renders both — and never duplicates either.

Three categories of page:

- **Site-native pages** (`src/pages/*.astro`) — landing, principles, start,
  section indexes, decisions ledger. Hand-authored Astro pages.
- **Doc-sourced pages** (`src/pages/[...slug].astro`) — every essay under
  `/design/`, `/principles/<page>`, `/research/`, `/policy/`,
  `/contribute/<page>`, and `/platforms/<page>`. Sourced from
  `../docs/*.md` via Astro's content-collection glob loader.
- **DocC export** (out of scope here) — built separately by the existing
  `swift package generate-documentation` flow and hosted at the same
  origin under `/api/`.

The mapping between repo doc files and site URLs lives in
[`src/lib/doc-overlays.ts`](src/lib/doc-overlays.ts). Adding a doc to the
site is a one-line edit there. Removing one is a one-line deletion. Doc
files don't need frontmatter.

## Local workflow

### Prerequisites

| Tool | Required for | Notes |
|------|--------------|-------|
| [Bun](https://bun.sh) ≥ 1.3 | All site work | Pinned via [`mise.toml`](../mise.toml). `mise install` provisions it. |
| Swift toolchain (release in [`.swift-version`](../.swift-version)) | Building the DocC archive locally | Optional. Most website edits don't need it. Install via [swiftly](https://www.swift.org/install/). |
| Swift wasm SDK + Binaryen | Building the WebExample WASI demo locally | Optional. See `.github/workflows/cloudflare-pages.yml` for the exact SDK URL/checksum and `brew install binaryen`. |
| Brotli | Cloudflare Pages deploy compression for the WebExample wasm | Optional locally. CI installs it with `brew install brotli`. |

The repo is a [Bun workspace](../package.json) containing
`GUI/WebTUIGUI`, `Examples/WebExample`, and this `Website` package. The
shared lockfile lives at the repo root.

### First-time setup

From the repo root:

```bash
bun install               # installs deps for every workspace
cd Website                # all subsequent commands run from here
```

### Day-to-day commands

```bash
bun run dev               # http://localhost:4321/  — HMR, source maps, fast
bun run check             # astro check: TS types + content collection schema
bun run build             # static export → Website/dist/
bun run preview           # serve dist/ locally (no HMR, closer to production)
```

**Source-of-truth note.** The site reads doc prose from `../docs/*.md` and
plan prose from `../docs/plans/**/*.md` via Astro's content collection
loader (see [`src/content.config.ts`](src/content.config.ts)). If `../docs/`
is missing or out of sync, builds will surface schema errors from
`bun run check` before they break `bun run build`.

### Environment overrides

Two variables are read by [`astro.config.mjs`](astro.config.mjs):

- `ASTRO_SITE` — absolute origin used for canonical URLs, sitemaps, and
  Open Graph tags. Defaults to `http://localhost:4321`. CI sets this to
  the production URL.
- `ASTRO_BASE` — path prefix. Defaults to `/`. Override only if you need
  to preview a path-prefixed deploy: `ASTRO_BASE=/foo bun run dev`.

### Previewing the full deployed artifact locally (optional)

`bun run preview` only serves the Astro layer. Production also serves
DocC at `/docs/` and the WASI demo at `/webexample/`. To rehearse the
full Cloudflare layout end-to-end (rarely needed, useful when changing
cross-artifact links):

```bash
# from repo root, with Swift + wasm SDK + Binaryen installed:

# 1. Astro
(cd Website && bun run build)

# 2. DocC archive (root-relative, matches CI)
swift package \
  --allow-writing-to-directory .build-docs \
  generate-documentation \
  --target Core --target View \
  --target TerminalUI --target TerminalUICharts \
  --enable-experimental-combined-documentation \
  --transform-for-static-hosting \
  --hosting-base-path docs \
  --output-path .build-docs

# 3. WebExample (WASI demo)
(cd Examples/WebExample && bun install && bun run build)

# 4. Compose into one directory
rm -rf _local-artifact
mkdir -p _local-artifact/docs _local-artifact/webexample
cp -R Website/dist/.                            _local-artifact/
cp -R .build-docs/.                             _local-artifact/docs/
cp -R Examples/WebExample/pages-dist/.          _local-artifact/webexample/
bun run Examples/WebExample/src/inject-docs-css.ts

# 5. Serve
bunx serve _local-artifact -l 4321
```

Note: the [`public/_headers`](public/_headers) cache rules are
Cloudflare-specific. The [`public/_redirects`](public/_redirects) rules are
also Cloudflare-specific; local servers (`astro preview`, `bunx serve`)
ignore them, so caching and Cloudflare-only DocC rewrites differ between
local and production.

## Adding a doc to the site

1. Open `src/lib/doc-overlays.ts`.
2. Add an entry keyed by the doc's filename (lowercased basename, no
   extension — e.g. `RUNTIME.md` → `runtime`).
3. Set `title`, `description`, `audience`, `section`, `order`, and `slug`.
4. `bun run build` to verify it appears at `/<slug>/`.

That's the entire mechanism. Doc edits in the repo flow through to the
site at the next build.

## Adding a site-native page

Site-native pages (tutorials, ADR pages, hand-authored landing content)
live in `src/pages/*.astro` for full control, or as MDX/markdown in
`src/content/essays/` if they want to participate in the typed `essays`
content collection.

## Production workflow

The site is hosted on Cloudflare Pages. The single source of deploy
truth is
[`.github/workflows/cloudflare-pages.yml`](../.github/workflows/cloudflare-pages.yml).

### Triggers

| Event | Result |
|-------|--------|
| Push to `main` | **Production deploy** at the project URL (and any custom domain). |
| Pull request | **Preview deploy** at `<branch>.<project>.pages.dev`. The workflow comments the URL on the PR. |
| `workflow_dispatch` | Manual deploy from the GitHub Actions tab; treated as a branch deploy. |

Concurrency is grouped per ref, so superseded runs cancel — only the
latest commit on a branch ever lands.

### What CI runs

The workflow runs on `macos-26` because the deploy artifact requires the
Swift toolchain. End to end:

1. Install swiftly + the toolchain pinned in [`.swift-version`](../.swift-version).
2. Set up Bun and restore SwiftPM + Bun caches.
3. Install the Swift wasm SDK, Binaryen, and Brotli (for WebExample and
   Pages upload compression).
4. Install workspace deps with `bun install --frozen-lockfile`.
5. Build the WASI demo: `Examples/WebExample` → `pages-dist/`.
6. Validate the emitted `.wasm` actually parses in `WebAssembly.compile`.
7. Build the Astro site with `ASTRO_BASE=/` and `ASTRO_SITE` pointed at
   the canonical production URL → `Website/dist/`.
8. Build the combined DocC archive (Core + View + TerminalUI +
   TerminalUICharts) with `--hosting-base-path docs` → `.build-docs/`.
9. Compose the final upload tree, remove DocC's duplicate per-symbol HTML
   shells, rely on `Website/public/_redirects` to route direct DocC links
   through `/docs/index.html`, and Brotli-compress
   `/webexample/TerminalApp/dist/assets/app.wasm` in place so the single
   asset remains under Cloudflare Pages' 25 MiB upload limit:
   ```
   /              ← Website/dist/                       (Astro site)
   /docs/         ← .build-docs/                        (DocC, combined)
   /webexample/   ← Examples/WebExample/pages-dist/     (WASI demo)
   ```
10. Count files in the composed artifact and fail before upload if it exceeds
    Cloudflare Pages' deployment file-count limit.
11. Upload via `bunx wrangler pages deploy` with the right
    `--branch` / `--commit-hash` so the Cloudflare deployment record
    matches the Git commit.
12. On PRs, parse the preview URL out of wrangler's output and post (or
    update) a sticky comment on the PR.

The `/docs/` path is historical — DocC has been served there since
before this site existed. The site's `/api` landing deep-links into
`/docs/documentation/<module>/`.

Cold runs take roughly 8–12 minutes (toolchain install dominates).
Warm runs with caches hit are 3–5 minutes.

> **Cost note.** Every push to `main` rebuilds DocC, so changes that
> only touch Swift sources also redeploy the site. That's intentional —
> DocC contents change when symbols change — but worth knowing.

### One-time Cloudflare setup

1. Create the Cloudflare Pages project (Direct Upload — no Git
   connection in the dashboard, since this workflow handles uploads):
   ```bash
   bunx wrangler@latest pages project create swift-terminal-ui \
     --production-branch main
   ```
2. In GitHub → *Settings → Secrets and variables → Actions*, add:
   - `CLOUDFLARE_API_TOKEN` — token with the **Cloudflare Pages: Edit**
     template (My Profile → API Tokens).
   - `CLOUDFLARE_ACCOUNT_ID` — from the right sidebar of the Cloudflare
     dashboard.
3. (Optional) Add repo variables:
   - `CLOUDFLARE_PAGES_PROJECT` — defaults to `swift-terminal-ui`.
   - `CLOUDFLARE_SITE_URL` — absolute URL Astro should canonicalize
     against (canonical tags, sitemap, OG). Defaults to
     `https://<project>.pages.dev`. Set this when you attach a custom
     domain.

### Custom domain

1. Cloudflare dashboard → *Workers & Pages → swift-terminal-ui →
   Custom domains → Set up a custom domain.* Add the hostname (e.g.
   `swift-terminal-ui.example.com`); Cloudflare provisions the
   certificate.
2. Set the GitHub repo variable `CLOUDFLARE_SITE_URL` to that absolute
   URL so canonical metadata matches the user-facing origin.
3. Re-run the workflow (push or `workflow_dispatch`) to bake the new
   `ASTRO_SITE` into the next deploy.

### Rolling back

Cloudflare Pages keeps every prior deployment. To revert without
shipping a new commit: dashboard → *swift-terminal-ui → Deployments*,
hover any past deployment, **⋯ → Rollback to this deployment.** The
production alias flips immediately.

To revert *and* keep the rollback in Git, revert the offending commit
on `main` — the next push redeploys to the older content.

### Manual / out-of-band deploys

If you need to push a build from your machine without going through CI
(e.g. an emergency patch when Actions is down):

```bash
# Build the artifact locally using the same steps as the workflow
# (see "Previewing the full deployed artifact locally" above), into
# _local-artifact/. Then:

bunx wrangler@latest pages deploy _local-artifact \
  --project-name=swift-terminal-ui \
  --branch=main \
  --commit-hash="$(git rev-parse HEAD)"
```

You'll need `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` exported
in your shell, scoped to your Cloudflare account.

### Where to find logs and status

- Build logs: GitHub repo → *Actions → Deploy Website to Cloudflare
  Pages.*
- Deployment history, traffic, custom domains: Cloudflare dashboard →
  *Workers & Pages → swift-terminal-ui.*

## Project structure

```
Website/
├── astro.config.mjs            # Astro 6 config (site, base, mdx)
├── package.json                # Bun workspace member
├── tsconfig.json               # path aliases for @components, @layouts, etc.
├── public/                     # static assets served at /
└── src/
    ├── content.config.ts       # content collections (docs from ../docs/)
    ├── layouts/Base.astro      # shell with header + footer + meta
    ├── components/             # SiteHeader, SiteFooter, PipelineStrip,
    │                           #   ArticleHeader, CodeSample
    ├── pages/                  # site-native + [...slug].astro catch-all
    ├── styles/global.css       # Nothing-style palette + typography
    └── lib/doc-overlays.ts     # the doc → site mapping
```

## Aesthetic

The site inherits the Nothing-style aesthetic established in
`Examples/WebExample` — matte black surfaces, dot-matrix backdrop,
restrained red `#d71921` accent, Doto display + Space Grotesk body +
Space Mono code. CSS variables live at the top of
`src/styles/global.css`.
