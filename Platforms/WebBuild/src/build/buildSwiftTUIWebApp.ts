import { mkdir, rm } from "node:fs/promises";
import { join } from "node:path";
import { buildAppWasm, type BuildAppWasmOptions } from "./buildAppWasm.ts";
import { generateSceneManifest } from "./generateSceneManifest.ts";

export interface BuildSwiftTUIWebAppOptions extends BuildAppWasmOptions {
  appExecutable?: string;
}

export async function buildSwiftTUIWebApp(
  options: BuildSwiftTUIWebAppOptions
): Promise<void> {
  await rm(options.outputDirectory, { recursive: true, force: true });
  await mkdir(options.outputDirectory, { recursive: true });
  await generateSceneManifest({
    packagePath: options.packagePath,
    outputPath: join(options.outputDirectory, "scene-manifest.json"),
    appExecutable: options.appExecutable ?? options.product,
    swiftCommand: options.swiftCommand,
  });
  await buildAppWasm(options);
}
