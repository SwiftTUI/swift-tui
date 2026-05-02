import { defineConfig } from "astro/config";
import {
  closeSync,
  createReadStream,
  existsSync,
  openSync,
  readSync,
  statSync,
} from "node:fs";
import { extname, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

// Deployed to Cloudflare Pages at the project root. CI overrides ASTRO_SITE
// to the canonical URL (pages.dev or a custom domain via the
// CLOUDFLARE_SITE_URL repo variable).
const site = process.env.ASTRO_SITE ?? "http://localhost:4321";
const base = process.env.ASTRO_BASE ?? "/";
const webExampleRoute = "/webexample";
const webExampleRoot = fileURLToPath(
  new URL("../Examples/WebExample/pages-dist", import.meta.url)
);
const isolationHeaders = {
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "Cross-Origin-Opener-Policy": "same-origin",
  "Cross-Origin-Embedder-Policy": "require-corp",
  "Cross-Origin-Resource-Policy": "same-origin",
};

export default defineConfig({
  site,
  base,
  trailingSlash: "ignore",
  integrations: [],
  vite: {
    server: {
      headers: isolationHeaders,
    },
    plugins: [localWebExamplePlugin()],
  },
  build: {
    format: "directory",
  },
});

function localWebExamplePlugin() {
  return {
    name: "local-webexample-mount",
    configureServer(server) {
      server.middlewares.use((request, response, next) => {
        for (const [header, value] of Object.entries(isolationHeaders)) {
          response.setHeader(header, value);
        }

        const url = new URL(request.url ?? "/", "http://localhost");
        if (
          url.pathname !== webExampleRoute
          && !url.pathname.startsWith(`${webExampleRoute}/`)
        ) {
          next();
          return;
        }

        if (url.pathname === webExampleRoute) {
          response.statusCode = 308;
          response.setHeader("Location", `${webExampleRoute}/`);
          response.end();
          return;
        }

        const filePath = resolveWebExamplePath(url.pathname.slice(`${webExampleRoute}/`.length));
        if (!filePath || !existsSync(filePath)) {
          response.statusCode = 404;
          response.setHeader("Content-Type", "text/plain; charset=utf-8");
          response.end("WebExample artifact not found. Run `bun run build:wasm:dev` in Website/.");
          return;
        }

        const stat = statSync(filePath);
        if (stat.isDirectory()) {
          const indexPath = resolveWebExamplePath(
            `${url.pathname
              .slice(`${webExampleRoute}/`.length)
              .replace(/\/?$/, "/")}index.html`
          );
          if (!indexPath || !existsSync(indexPath)) {
            response.statusCode = 404;
            response.end("Not found");
            return;
          }
          serveFile(indexPath, response);
          return;
        }

        serveFile(filePath, response);
      });
    },
  };
}

function resolveWebExamplePath(pathname) {
  let decodedPathname;
  try {
    decodedPathname = decodeURIComponent(pathname);
  } catch {
    return undefined;
  }

  const filePath = resolve(webExampleRoot, decodedPathname || "index.html");
  if (filePath === webExampleRoot || filePath.startsWith(`${webExampleRoot}${sep}`)) {
    return filePath;
  }
  return undefined;
}

function serveFile(filePath, response) {
  response.statusCode = 200;
  response.setHeader("Content-Type", contentTypeForPath(filePath));
  if (filePath.endsWith("/TerminalApp/dist/assets/app.wasm") && isBrotliCompressedWasm(filePath)) {
    response.setHeader("Content-Encoding", "br");
    response.setHeader("Cache-Control", "public, max-age=31536000, immutable, no-transform");
  }

  createReadStream(filePath).pipe(response);
}

function isBrotliCompressedWasm(filePath) {
  const descriptor = openSync(filePath, "r");
  try {
    const magic = Buffer.alloc(4);
    readSync(descriptor, magic, 0, magic.length, 0);
    return !(
      magic[0] === 0x00
      && magic[1] === 0x61
      && magic[2] === 0x73
      && magic[3] === 0x6d
    );
  } finally {
    closeSync(descriptor);
  }
}

function contentTypeForPath(filePath) {
  switch (extname(filePath)) {
    case ".css":
      return "text/css; charset=utf-8";
    case ".html":
      return "text/html; charset=utf-8";
    case ".js":
    case ".mjs":
      return "text/javascript; charset=utf-8";
    case ".json":
    case ".map":
      return "application/json; charset=utf-8";
    case ".png":
      return "image/png";
    case ".svg":
      return "image/svg+xml";
    case ".wasm":
      return "application/wasm";
    default:
      return "application/octet-stream";
  }
}
