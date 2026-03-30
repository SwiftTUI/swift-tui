import { mkdir } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { buildAppWasm, generateSceneManifest } from "webtuigui";

const packagePath = resolve(import.meta.dir, "../TerminalApp");
const outputDirectory = resolve(import.meta.dir, "../TerminalApp/dist");
const appExecutable = "WebExampleApp";
const ghosttyWebPath = resolve(import.meta.dir, "../node_modules/webtuigui/node_modules/ghostty-web");
const ghosttyWebPackagePath = join(ghosttyWebPath, "package.json");
const ghosttyWebWasmPath = join(ghosttyWebPath, "ghostty-vt.wasm");

await mkdir(outputDirectory, { recursive: true });
await ensureGhosttyWasmAsset();
await generateSceneManifest({
  packagePath,
  outputPath: join(outputDirectory, "scene-manifest.json"),
  appExecutable,
});
await buildAppWasm({
  packagePath,
  outputDirectory,
  product: appExecutable,
});

async function ensureGhosttyWasmAsset(): Promise<void> {
  const wasmFile = Bun.file(ghosttyWebWasmPath);
  if (await wasmFile.exists()) {
    return;
  }

  const packageJSON = await Bun.file(ghosttyWebPackagePath).json() as { version?: string };
  const version = packageJSON.version?.trim();
  if (!version) {
    throw new Error("ghostty-web version is missing");
  }

  const assetURL = `https://unpkg.com/ghostty-web@${version}/ghostty-vt.wasm`;
  const response = await fetch(assetURL);
  if (!response.ok) {
    throw new Error(`failed to download ghostty-vt.wasm from ${assetURL}`);
  }

  await mkdir(dirname(ghosttyWebWasmPath), { recursive: true });
  await Bun.write(ghosttyWebWasmPath, await response.arrayBuffer());
}
