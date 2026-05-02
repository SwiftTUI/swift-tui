import { mkdir, rm } from "node:fs/promises";
import { join, resolve } from "node:path";
import {
  buildAppWasm,
  generateSceneManifest,
} from "webtuigui";
import type { WasmBuildConfiguration } from "webtuigui";

const packagePath = resolve(import.meta.dir, "../TerminalApp");
const outputDirectory = resolve(import.meta.dir, "../TerminalApp/dist");
const appExecutable = "WebExampleApp";
const distDirectory = resolve(import.meta.dir, "../dist");
const configuration = parseConfiguration(process.argv.slice(2));

await rm(outputDirectory, { recursive: true, force: true });
await rm(distDirectory, { recursive: true, force: true });
await mkdir(outputDirectory, { recursive: true });
await generateSceneManifest({
  packagePath,
  outputPath: join(outputDirectory, "scene-manifest.json"),
  appExecutable,
});
await buildAppWasm({
  configuration,
  packagePath,
  outputDirectory,
  product: appExecutable,
});
await mkdir(distDirectory, { recursive: true });

function parseConfiguration(argv: string[]): WasmBuildConfiguration {
  const fromEnvironment = process.env.WEBEXAMPLE_WASM_CONFIGURATION;
  let configuration: string | undefined = fromEnvironment;

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--configuration" || argument === "-c") {
      configuration = argv[index + 1];
      index += 1;
      continue;
    }
    if (argument.startsWith("--configuration=")) {
      configuration = argument.slice("--configuration=".length);
    }
  }

  switch (configuration ?? "release") {
    case "debug":
      return "debug";
    case "release":
      return "release";
    default:
      throw new Error(`unsupported WebExample wasm configuration: ${configuration}`);
  }
}
