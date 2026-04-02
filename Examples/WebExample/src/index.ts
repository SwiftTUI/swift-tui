import { serve } from "bun";
import { join, resolve } from "node:path";
import index from "./index.html";

const terminalAppDist = resolve(import.meta.dir, "../TerminalApp/dist");
const webDist = resolve(import.meta.dir, "../dist");
const isolationHeaders = {
  "Cross-Origin-Embedder-Policy": "require-corp",
  "Cross-Origin-Opener-Policy": "same-origin",
};

const upstream = serve({
  hostname: "127.0.0.1",
  port: 0,
  routes: {
    "/TerminalApp/dist/*": (req) => {
      const pathname = new URL(req.url).pathname.slice("/TerminalApp/dist/".length);
      return new Response(Bun.file(join(terminalAppDist, pathname)));
    },
    "/ghostty-vt.wasm": () => new Response(Bun.file(join(webDist, "ghostty-vt.wasm"))),
    "/*": index,
  },
  development: process.env.NODE_ENV !== "production" && {
    // HMR and browser-console streaming use a websocket endpoint that this
    // isolation proxy does not forward. Rebuild on refresh instead.
    hmr: false,
    console: false,
  },
});

const server = serve({
  port: Number(process.env.PORT ?? "3000"),
  async fetch(request) {
    const upstreamURL = new URL(request.url);
    upstreamURL.protocol = upstream.url.protocol ?? upstreamURL.protocol;
    upstreamURL.hostname = upstream.url.hostname ?? upstreamURL.hostname;
    upstreamURL.port = upstream.url.port ? String(upstream.url.port) : "";

    const response = await fetch(new Request(upstreamURL, request));
    return withIsolationHeaders(response);
  },
});

console.log(`WebExample running at ${server.url}`);

function withIsolationHeaders(
  response: Response
): Response {
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(isolationHeaders)) {
    headers.set(key, value);
  }

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}
