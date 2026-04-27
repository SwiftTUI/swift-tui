/*
 * inject-docs-css.ts
 *
 * Post-processes the swift-docc-plugin static-hosting output by injecting a
 * project-owned override stylesheet (`docs-overrides.css`) into every
 * generated HTML page.
 *
 * The DocC archive's renderer (swift-docc-render) reads `theme-settings.json`
 * for color and typography tokens, but a handful of layout/chrome details
 * cannot be reached from that JSON. This script adds a single <link> tag to
 * the rendered HTML so we can ship arbitrary CSS overrides next to it.
 *
 * Inputs:
 *   - DOCS_ROOT env (default: ../pages-dist/docs)
 *   - HOSTING_BASE_PATH env (default: /swift-terminal-ui/docs)
 *   - source CSS at ./docs-overrides.css
 *
 * Outputs:
 *   - copies docs-overrides.css into <DOCS_ROOT>/css/docs-overrides.css
 *   - rewrites every index.html under DOCS_ROOT to include the override link
 *
 * The script is idempotent: if a page already has the override link it is
 * left alone. Safe to re-run.
 */

import { Glob } from "bun";
import { resolve } from "node:path";

const ROOT = import.meta.dir;
const DOCS_ROOT = resolve(
  ROOT,
  process.env.DOCS_ROOT ?? "../pages-dist/docs",
);
const HOSTING_BASE_PATH = (
  process.env.HOSTING_BASE_PATH ?? "/swift-terminal-ui/docs"
).replace(/\/+$/, "");
const SOURCE_CSS = resolve(ROOT, "docs-overrides.css");
const TARGET_CSS_REL = "css/docs-overrides.css";
const TARGET_CSS = resolve(DOCS_ROOT, TARGET_CSS_REL);
const LINK_HREF = `${HOSTING_BASE_PATH}/${TARGET_CSS_REL}`;
const LINK_TAG =
  `<link rel="stylesheet" data-source="docs-overrides" href="${LINK_HREF}">`;

async function copyOverrideCSS(): Promise<void> {
  const sourceFile = Bun.file(SOURCE_CSS);
  if (!(await sourceFile.exists())) {
    throw new Error(`Override CSS not found at ${SOURCE_CSS}`);
  }
  await Bun.write(TARGET_CSS, sourceFile);
}

async function injectIntoHtmlFiles(): Promise<number> {
  let touched = 0;
  const glob = new Glob("**/*.html");
  for await (const relPath of glob.scan({ cwd: DOCS_ROOT })) {
    const fullPath = resolve(DOCS_ROOT, relPath);
    const html = await Bun.file(fullPath).text();

    if (html.includes('data-source="docs-overrides"')) {
      continue;
    }
    if (!html.includes("</head>")) {
      continue;
    }

    const next = html.replace("</head>", `  ${LINK_TAG}\n  </head>`);
    if (next === html) continue;

    await Bun.write(fullPath, next);
    touched += 1;
  }
  return touched;
}

async function main(): Promise<void> {
  const docsRootFile = Bun.file(`${DOCS_ROOT}/index.html`);
  if (!(await docsRootFile.exists())) {
    console.error(
      `[inject-docs-css] No DocC output found at ${DOCS_ROOT}. ` +
        `Run \`swift package generate-documentation --transform-for-static-hosting\` first.`,
    );
    process.exit(1);
  }

  await copyOverrideCSS();
  const touched = await injectIntoHtmlFiles();
  console.log(
    `[inject-docs-css] Wrote ${TARGET_CSS_REL}; injected override link into ${touched} HTML file(s).`,
  );
}

await main();
