import { mkdir, rm } from "node:fs/promises";
import { join, resolve } from "node:path";
import {
  buildAppWasm,
  generateSceneManifest,
} from "webtuigui";

const packagePath = resolve(import.meta.dir, "../TerminalApp");
const outputDirectory = resolve(import.meta.dir, "../TerminalApp/dist");
const appExecutable = "WebExampleApp";
const distDirectory = resolve(import.meta.dir, "../dist");

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
