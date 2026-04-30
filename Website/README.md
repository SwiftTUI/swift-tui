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

## Development

Requires [Bun](https://bun.sh) ≥ 1.3.

```bash
bun install
bun run dev      # http://localhost:4321/
bun run build    # static export to dist/
bun run preview  # serve dist/ locally
bun run check    # astro check (TypeScript + content schema)
```

The site is built with `base: "/"` (root-served on Cloudflare Pages).
Override the base path via `ASTRO_BASE=/something bun run build` if you
ever need a path-prefixed deploy.

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

## Deployment

`.github/workflows/cloudflare-pages.yml` builds and deploys to Cloudflare
Pages on every push to `main`. The composed artifact uploaded to
Cloudflare is:

```
/                ← Website/dist/        (this Astro project)
/docs/           ← .build-docs/         (combined DocC archive)
/webexample/     ← Examples/WebExample/pages-dist/  (live WASI demo)
```

The `/docs/` path is historical — DocC has been served there since before
this site existed. The site's `/api` landing deep-links into the DocC
archive at `/docs/documentation/<module>/`.

One-time setup:

1. Create the Cloudflare Pages project (Direct Upload, no Git connection
   needed since the GitHub workflow handles deploys):
   ```bash
   bunx wrangler@latest pages project create swift-terminal-ui \
     --production-branch main
   ```
2. Add repo secrets in GitHub → Settings → Secrets and variables → Actions:
   - `CLOUDFLARE_API_TOKEN` — token with `Cloudflare Pages: Edit` permission
   - `CLOUDFLARE_ACCOUNT_ID` — account ID from the Cloudflare dashboard sidebar
3. (Optional) Add repo variables:
   - `CLOUDFLARE_PAGES_PROJECT` — defaults to `swift-terminal-ui`
   - `CLOUDFLARE_SITE_URL` — absolute URL Astro should canonicalize to
     (e.g. `https://swift-terminal-ui.example.com`); defaults to
     `https://<project>.pages.dev`

Pushes to `main` deploy to production. PRs deploy to a preview URL and
the workflow comments the URL on the PR. Cache headers (and any future
redirects) live in [`public/_headers`](public/_headers).

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
