import { mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { loadWebTUISceneManifest, webTUISceneManifestToJSON, type WebTUISceneManifest } from "../WebTUISceneManifest.ts";
import { swiftCommandPrefix } from "./swiftCommandPrefix.ts";

export interface GenerateSceneManifestOptions {
  packagePath: string;
  outputPath: string;
  appExecutable: string;
}

export async function generateSceneManifest(
  options: GenerateSceneManifestOptions
): Promise<WebTUISceneManifest> {
  const output = await runManifestCommand(options);
  const manifest = await loadWebTUISceneManifest(output.trim());
  await mkdir(dirname(options.outputPath), { recursive: true });
  await Bun.write(options.outputPath, webTUISceneManifestToJSON(manifest));
  return manifest;
}

async function runManifestCommand(
  options: GenerateSceneManifestOptions
): Promise<string> {
  const proc = Bun.spawn({
    cmd: [
      ...swiftCommandPrefix(),
      "run",
      "--package-path",
      options.packagePath,
      options.appExecutable,
    ],
    env: {
      ...process.env,
      TUIGUI_MODE: "manifest",
    },
    stdout: "pipe",
    stderr: "pipe",
  });

  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);

  if (exitCode !== 0) {
    throw new Error([stdout, stderr].filter(Boolean).join("\n").trim() || "manifest generation failed");
  }

  return stdout;
}
