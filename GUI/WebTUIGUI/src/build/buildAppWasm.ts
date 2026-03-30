import { mkdir, rm } from "node:fs/promises";
import { dirname, join } from "node:path";
import { resolveSwiftArtifacts, type SwiftArtifactPaths } from "./resolveSwiftArtifacts.ts";

export interface BuildAppWasmOptions {
  packagePath: string;
  outputDirectory: string;
  product: string;
}

export async function buildAppWasm(
  options: BuildAppWasmOptions
): Promise<SwiftArtifactPaths> {
  const artifacts = await resolveSwiftArtifacts({
    packagePath: options.packagePath,
    product: options.product,
  });

  await mkdir(join(options.outputDirectory, "assets"), { recursive: true });
  await rm(join(options.outputDirectory, "assets", "app.wasm"), { force: true });
  await Bun.write(join(options.outputDirectory, "assets", "app.wasm"), await Bun.file(artifacts.wasmPath).arrayBuffer());
  return artifacts;
}
