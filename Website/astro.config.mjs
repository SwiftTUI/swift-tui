import { defineConfig } from "astro/config";
import mdx from "@astrojs/mdx";

// Deployed to Cloudflare Pages at the project root. CI overrides ASTRO_SITE
// to the canonical URL (pages.dev or a custom domain via the
// CLOUDFLARE_SITE_URL repo variable). ASTRO_BASE is overridable for any
// future path-prefixed deploys; the default `/` serves at the root.
const site = process.env.ASTRO_SITE ?? "http://localhost:4321";
const base = process.env.ASTRO_BASE ?? "/";

export default defineConfig({
  site,
  base,
  trailingSlash: "ignore",
  integrations: [mdx()],
  build: {
    format: "directory",
  },
  markdown: {
    shikiConfig: {
      themes: {
        light: "github-light",
        dark: "github-dark-default",
      },
      defaultColor: false,
    },
  },
});
