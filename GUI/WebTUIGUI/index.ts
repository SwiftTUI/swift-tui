export * from "./src/WebTUIApp.ts";
export * from "./src/WebTUISceneManifest.ts";
export * from "./src/WebTUITerminalStyle.ts";
export * from "./src/WebTUISurfaceTransport.ts";
export * from "./src/WebTUISceneRuntime.ts";
export * from "./src/wasi/BrowserWASIBridge.ts";
export * from "./src/wasi/StdIOPipe.ts";
export * from "./src/build/buildAppWasm.ts";
export * from "./src/build/generateSceneManifest.ts";
export * from "./src/build/resolveSwiftArtifacts.ts";

import { mkdir, rm } from "node:fs/promises";
import { join, resolve } from "node:path";
import { generateSceneManifest } from "./src/build/generateSceneManifest.ts";
import { buildAppWasm } from "./src/build/buildAppWasm.ts";

if (import.meta.main) {
  void runCli(process.argv.slice(2));
}

async function runCli(argv: string[]): Promise<void> {
  const command = argv[0] ?? "build";
  const flags = parseFlags(argv.slice(1));
  const packagePath = resolve(flags["package-path"] ?? "../../");
  const distPath = resolve(flags["dist"] ?? "./dist");
  const appExecutable = flags.app ?? flags.product ?? flags["app-product"] ?? "";

  switch (command) {
    case "build:manifest": {
      assertAppExecutable(appExecutable);
      await generateSceneManifest({
        packagePath,
        outputPath: join(distPath, "scene-manifest.json"),
        appExecutable,
      });
      return;
    }
    case "build:wasm": {
      assertAppExecutable(appExecutable);
      await buildAppWasm({
        packagePath,
        outputDirectory: distPath,
        product: appExecutable,
      });
      return;
    }
    case "build:web": {
      await bunBuildWeb({
        outputDirectory: distPath,
      });
      return;
    }
    case "build": {
      assertAppExecutable(appExecutable);
      await rm(distPath, { recursive: true, force: true });
      await mkdir(distPath, { recursive: true });
      await generateSceneManifest({
        packagePath,
        outputPath: join(distPath, "scene-manifest.json"),
        appExecutable,
      });
      await buildAppWasm({
        packagePath,
        outputDirectory: distPath,
        product: appExecutable,
      });
      await bunBuildWeb({
        outputDirectory: distPath,
      });
      return;
    }
    case "dev": {
      await bunServe(packagePath, distPath);
      return;
    }
    default:
      throw new Error(`unknown command: ${command}`);
  }
}

async function bunBuildWeb(options: {
  outputDirectory: string;
}): Promise<void> {
  await mkdir(options.outputDirectory, { recursive: true });
  const proc = Bun.spawn({
    cmd: [
      "bun",
      "build",
      "./index.html",
      "--outdir",
      options.outputDirectory,
    ],
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);

  if (exitCode !== 0) {
    throw new Error([stdout, stderr].filter(Boolean).join("\n").trim() || "web build failed");
  }

}

async function bunServe(
  packagePath: string,
  distPath: string
): Promise<void> {
  const server = Bun.serve({
    port: Number(process.env.PORT ?? "3000"),
    development: {
      hmr: true,
      console: true,
    },
    fetch(request) {
      const url = new URL(request.url);
      if (url.pathname === "/") {
        return new Response(Bun.file(join(distPath, "index.html")));
      }
      if (url.pathname === "/scene-manifest.json") {
        return new Response(Bun.file(join(distPath, "scene-manifest.json")));
      }
      if (url.pathname.startsWith("/assets/")) {
        return new Response(Bun.file(join(distPath, url.pathname.slice(1))));
      }
      if (url.pathname.startsWith("/src/")) {
        return new Response(Bun.file(join(packagePath, url.pathname.slice(1))));
      }
      return new Response("not found", { status: 404 });
    },
  });

  console.log(`WebTUIGUI dev server running at ${server.url.href}`);
  await new Promise<void>(() => {});
}

function parseFlags(
  argv: string[]
): Record<string, string> {
  const flags: Record<string, string> = {};
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (!value.startsWith("--")) {
      continue;
    }
    const name = value.slice(2);
    const next = argv[index + 1];
    if (next && !next.startsWith("--")) {
      flags[name] = next;
      index += 1;
    } else {
      flags[name] = "true";
    }
  }
  return flags;
}

function assertAppExecutable(
  value: string
): asserts value is string {
  if (!value) {
    throw new Error("missing --app or --product flag");
  }
}
