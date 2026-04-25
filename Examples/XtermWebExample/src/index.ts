import { serve } from "bun";
import { join, resolve } from "node:path";
import index from "./index.html";

const terminalAppDist = resolve(import.meta.dir, "../TerminalApp/dist");
const wasmSceneWorkerSource = resolve(import.meta.dir, "./wasm-scene-worker.ts");
const isolationHeaders = {
  "Cross-Origin-Embedder-Policy": "require-corp",
  "Cross-Origin-Opener-Policy": "same-origin",
};

const upstream = serve({
  hostname: "127.0.0.1",
  port: 0,
  routes: {
    "/wasm-scene-worker.js": async () => wasmSceneWorkerResponse(),
    "/TerminalApp/dist/*": (req) => {
      const pathname = new URL(req.url).pathname.slice("/TerminalApp/dist/".length);
      return new Response(Bun.file(join(terminalAppDist, pathname)));
    },
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

console.log(`XtermWebExample running at ${server.url}`);

async function wasmSceneWorkerResponse(): Promise<Response> {
  const result = await Bun.build({
    entrypoints: [wasmSceneWorkerSource],
    target: "browser",
    format: "esm",
  });

  const output = result.outputs[0];
  if (!result.success || !output) {
    return new Response("Failed to build wasm scene worker", {
      status: 500,
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
      },
    });
  }

  return new Response(output, {
    headers: {
      "Content-Type": output.type || "text/javascript; charset=utf-8",
    },
  });
}

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
