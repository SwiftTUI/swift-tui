import { defineConfig } from "astro/config";

// Deployed to Cloudflare Pages at the project root. CI overrides ASTRO_SITE
// to the canonical URL (pages.dev or a custom domain via the
// CLOUDFLARE_SITE_URL repo variable).
const site = process.env.ASTRO_SITE ?? "http://localhost:4321";
const base = process.env.ASTRO_BASE ?? "/";

export default defineConfig({
  site,
  base,
  trailingSlash: "ignore",
  integrations: [],
  build: {
    format: "directory",
  },
});
