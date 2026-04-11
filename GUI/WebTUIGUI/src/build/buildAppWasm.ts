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
  await packageBrowserValidatedWasm({
    sourceWasmPath: artifacts.wasmPath,
    outputWasmPath: packagedWasmPath,
  });
  return artifacts;
}

interface PackageBrowserValidatedWasmOptions {
  sourceWasmPath: string;
  outputWasmPath: string;
  strip?: (wasmPath: string) => Promise<void>;
  onWarning?: (message: string) => void;
}

export async function packageBrowserValidatedWasm(
  options: PackageBrowserValidatedWasmOptions
): Promise<void> {
  const sourceBytes = await Bun.file(options.sourceWasmPath).arrayBuffer();
  await Bun.write(options.outputWasmPath, sourceBytes);
  await validateBrowserWasm(options.outputWasmPath, "generated wasm");

  const strip = options.strip ?? stripPackagedWasm;

  try {
    await strip(options.outputWasmPath);
    await validateBrowserWasm(options.outputWasmPath, "stripped wasm");
  } catch (error) {
    // Stripping is a size optimization only. Keep the known-good raw wasm
    // whenever toolchain-specific objcopy output fails browser validation.
    await Bun.write(options.outputWasmPath, sourceBytes);
    const message = error instanceof Error ? error.message : String(error);
    const warning = [
      `warning: keeping unstripped wasm at ${options.outputWasmPath}`,
      `strip step failed browser validation or tooling requirements: ${message}`,
    ].join("\n");
    (options.onWarning ?? console.warn)(warning);
  }
}

async function validateBrowserWasm(
  wasmPath: string,
  description: string
): Promise<void> {
  try {
    // Validate against the same JS API the browser uses before we publish it.
    await WebAssembly.compile(await Bun.file(wasmPath).arrayBuffer());
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`${description} does not parse in browser WebAssembly (${wasmPath}): ${message}`);
  }
}
