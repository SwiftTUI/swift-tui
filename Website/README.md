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
bun run dev      # http://localhost:4321/swift-terminal-ui/
bun run build    # static export to dist/
bun run preview  # serve dist/ locally
bun run check    # astro check (TypeScript + content schema)
```

The site is built with `base: "/swift-terminal-ui"` because it deploys
under that path on GitHub Pages. Local previews include the path prefix.

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

The static site builds to `Website/dist/`. Deployment alongside the DocC
export is handled by the repo's `pages-build.yml` workflow (out of scope
for this README).

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
