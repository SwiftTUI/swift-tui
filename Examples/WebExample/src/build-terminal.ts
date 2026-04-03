import { mkdir, rm } from "node:fs/promises";
import { join, resolve } from "node:path";
import {
  buildAppWasm,
  copyGhosttyWasmAsset,
  generateSceneManifest,
} from "../../../GUI/WebTUIGUI/index.ts";

const packagePath = resolve(import.meta.dir, "../TerminalApp");
const outputDirectory = resolve(import.meta.dir, "../TerminalApp/dist");
const appExecutable = "WebExampleApp";
const distDirectory = resolve(import.meta.dir, "../dist");
const coiServiceWorkerPath = resolve(import.meta.dir, "./coi-serviceworker.js");

await rm(outputDirectory, { recursive: true, force: true });
await rm(distDirectory, { recursive: true, force: true });
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
await Bun.write(
  join(distDirectory, "coi-serviceworker.js"),
  await Bun.file(coiServiceWorkerPath).arrayBuffer()
);
