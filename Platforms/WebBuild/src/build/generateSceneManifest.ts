import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import {
  loadWebHostSceneManifest,
  webTUISceneManifestToJSON,
  type WebHostSceneManifest,
} from "@swifttui/web/manifest";
import { runCommand } from "./runCommand.ts";
import { swiftCommandPrefix } from "./swiftCommandPrefix.ts";

export interface GenerateSceneManifestOptions {
  packagePath: string;
  outputPath: string;
  appExecutable: string;
  swiftCommand?: readonly string[];
}

export async function generateSceneManifest(
  options: GenerateSceneManifestOptions
): Promise<WebHostSceneManifest> {
  const output = await runManifestCommand(options);
  const manifest = await loadWebHostSceneManifest(output.trim());
  await mkdir(dirname(options.outputPath), { recursive: true });
  await writeFile(options.outputPath, webTUISceneManifestToJSON(manifest));
  return manifest;
}

async function runManifestCommand(
  options: GenerateSceneManifestOptions
): Promise<string> {
  return await runCommand(
    [
      ...(options.swiftCommand ?? swiftCommandPrefix()),
      "run",
      "--package-path",
      options.packagePath,
      options.appExecutable,
    ],
    {
      env: {
        ...process.env,
        TUIGUI_MODE: "manifest",
      },
    }
  );
}
