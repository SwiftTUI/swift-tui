import { mkdir, rm } from "node:fs/promises";
import { join } from "node:path";
import { resolveSwiftArtifacts, type SwiftArtifactPaths } from "./resolveSwiftArtifacts.ts";
import { stripPackagedWasm } from "./stripPackagedWasm.ts";

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

  const packagedWasmPath = join(options.outputDirectory, "assets", "app.wasm");
  await mkdir(join(options.outputDirectory, "assets"), { recursive: true });
  await rm(packagedWasmPath, { force: true });
  await Bun.write(packagedWasmPath, await Bun.file(artifacts.wasmPath).arrayBuffer());
  await stripPackagedWasm(packagedWasmPath);
  await validatePackagedWasm(packagedWasmPath);
  return artifacts;
}

async function validatePackagedWasm(
  wasmPath: string
): Promise<void> {
  try {
    // Validate against the same JS API the browser uses before we publish it.
    await WebAssembly.compile(await Bun.file(wasmPath).arrayBuffer());
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`generated wasm does not parse in browser WebAssembly (${wasmPath}): ${message}`);
  }
}
