import { mkdir, rm } from "node:fs/promises";
import { join } from "node:path";
import { optimizePackagedWasm } from "./optimizePackagedWasm.ts";
import { resolveSwiftArtifacts, type SwiftArtifactPaths } from "./resolveSwiftArtifacts.ts";
import { stripPackagedWasm } from "./stripPackagedWasm.ts";
import { formatWasmTypeDiagnostics } from "./wasmTypeDiagnostics.ts";

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
  optimize?: (wasmPath: string) => Promise<void>;
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

  const optimize = options.optimize ?? optimizePackagedWasm;
  try {
    await optimize(options.outputWasmPath);
    await validateBrowserWasm(options.outputWasmPath, "optimized wasm");
  } catch (error) {
    await Bun.write(options.outputWasmPath, sourceBytes);
    const message = error instanceof Error ? error.message : String(error);

    try {
      await validateBrowserWasm(options.outputWasmPath, "generated wasm");
    } catch (rawError) {
      const rawMessage = rawError instanceof Error ? rawError.message : String(rawError);
      throw new Error([
        rawMessage,
        `wasm optimization step failed: ${message}`,
      ].join("\n"));
    }

    const warning = [
      `warning: keeping unoptimized wasm at ${options.outputWasmPath}`,
      `wasm optimization step failed or did not produce browser-parseable output: ${message}`,
    ].join("\n");
    (options.onWarning ?? console.warn)(warning);
  }

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
  const bytes = await Bun.file(wasmPath).bytes();
  try {
    // Validate against the same JS API the browser uses before we publish it.
    await WebAssembly.compile(bytes);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error([
      `${description} does not parse in browser WebAssembly (${wasmPath}): ${message}`,
      formatWasmTypeDiagnostics(bytes),
    ].join("\n"));
  }
}
