import { defineConfig } from "astro/config";
import mdx from "@astrojs/mdx";

// Deployment targets:
//   - GitHub Pages (default):    https://goodhatsllc.github.io/swift-terminal-ui/
//   - Cloudflare Pages:          override via ASTRO_SITE + ASTRO_BASE env vars
//                                (typically ASTRO_BASE=/ for root-served deploys)
//
// Local previews run at http://localhost:4321/swift-terminal-ui/ unless ASTRO_BASE
// is overridden in the environment.
const site = process.env.ASTRO_SITE ?? "https://goodhatsllc.github.io";
const base = process.env.ASTRO_BASE ?? "/swift-terminal-ui";

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
