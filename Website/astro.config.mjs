import { defineConfig } from "astro/config";
import mdx from "@astrojs/mdx";

// The site is published under https://goodhatsllc.github.io/swift-terminal-ui/
// alongside the DocC export at /docs/. The site path uses the repo name as
// `base`. Local previews run at http://localhost:4321/swift-terminal-ui/.
export default defineConfig({
  site: "https://goodhatsllc.github.io",
  base: "/swift-terminal-ui",
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
