import { serve } from "bun";
import { join, resolve } from "node:path";
import index from "./index.html";

const terminalAppDist = resolve(import.meta.dir, "../TerminalApp/dist");
const webDist = resolve(import.meta.dir, "../dist");

const server = serve({
  routes: {
    "/TerminalApp/dist/*": (req) => {
      const pathname = new URL(req.url).pathname.slice("/TerminalApp/dist/".length);
      return new Response(Bun.file(join(terminalAppDist, pathname)));
    },
    "/ghostty-vt.wasm": () => new Response(Bun.file(join(webDist, "ghostty-vt.wasm"))),
    "/*": index,
  },
  development: process.env.NODE_ENV !== "production" && {
    hmr: true,
    console: true,
  },
});

console.log(`WebExample running at ${server.url}`);
