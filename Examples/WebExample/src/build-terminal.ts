import { mkdir } from "node:fs/promises";
import { join, resolve } from "node:path";
import { buildAppWasm, copyGhosttyWasmAsset, generateSceneManifest } from "webtuigui";

const packagePath = resolve(import.meta.dir, "../TerminalApp");
const outputDirectory = resolve(import.meta.dir, "../TerminalApp/dist");
const appExecutable = "WebExampleApp";
const distDirectory = resolve(import.meta.dir, "../dist");

await mkdir(outputDirectory, { recursive: true });
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
await mkdir(distDirectory, { recursive: true });
await copyGhosttyWasmAsset({
  outputPath: join(distDirectory, "ghostty-vt.wasm"),
});
