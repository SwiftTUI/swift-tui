import { existsSync } from "node:fs";
import { join, resolve, sep } from "node:path";

import { serve } from "bun";

const defaultTerminalAppDist = resolve(import.meta.dir, "../TerminalApp/dist");
const defaultWebDist = resolve(import.meta.dir, "../dist");
const isolationHeaders = {
  "Cross-Origin-Embedder-Policy": "require-corp",
  "Cross-Origin-Opener-Policy": "same-origin",
};

export interface BuiltWebExampleServerOptions {
  hostname?: string;
  port?: number;
  terminalAppDist?: string;
  webDist?: string;
}

export function serveBuiltWebExample(
  options: BuiltWebExampleServerOptions = {}
) {
  const terminalAppDist = options.terminalAppDist ?? defaultTerminalAppDist;
  const webDist = options.webDist ?? defaultWebDist;

  return serve({
    hostname: options.hostname ?? "127.0.0.1",
    port: options.port ?? 0,
    fetch: (req) => {
      const url = new URL(req.url);

      if (url.pathname.startsWith("/TerminalApp/dist/")) {
        const pathname = url.pathname.slice("/TerminalApp/dist/".length);
        return fileResponse(resolveWithin(terminalAppDist, pathname));
      }

      const pathname = url.pathname === "/" ? "index.html" : url.pathname.slice(1);
      return fileResponse(resolveWithin(webDist, pathname));
    },
  });
}

function resolveWithin(
  root: string,
  pathname: string
): string {
  const filePath = resolve(root, pathname);
  if (filePath === root || filePath.startsWith(`${root}${sep}`)) {
    return filePath;
  }

  return join(root, "index.html");
}

function fileResponse(
  filePath: string
): Response {
  if (!existsSync(filePath)) {
    return withIsolationHeaders(
      new Response("Not found", {
        status: 404,
        headers: {
          "Content-Type": "text/plain; charset=utf-8",
        },
      })
    );
  }

  const file = Bun.file(filePath);
  return withIsolationHeaders(
    new Response(file, {
      headers: file.type
        ? {
            "Content-Type": file.type,
          }
        : undefined,
    })
  );
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
