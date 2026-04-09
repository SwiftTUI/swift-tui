import { dirname, join, resolve } from "node:path";
import { runCommand } from "./runCommand.ts";
import { swiftCommandPrefix } from "./swiftCommandPrefix.ts";

export interface ResolveSwiftArtifactsOptions {
  packagePath: string;
  product: string;
}

export interface SwiftArtifactPaths {
  binPath: string;
  wasmPath: string;
}

export async function resolveSwiftArtifacts(
  options: ResolveSwiftArtifactsOptions
): Promise<SwiftArtifactPaths> {
  const swiftlyWorkingDirectory = await resolveSwiftlyWorkingDirectory(options.packagePath);
  const environment = {
    ...process.env
  };

  // -Osize is required (not just a size tweak): the default -O release mode
  // emits Swift-side merged outlined-copy helpers (e.g.
  // `$s4Core15ListDisplayLineV4KindOWOyTm`) with ~1200 i32 parameters, which
  // exceeds the WebAssembly JS API's 1000-parameter-per-function limit and
  // causes `WebAssembly.Module doesn't parse` errors in every browser.
  // `-Osize` keeps the max signature comfortably under the limit.
  const swiftBuildArgs = [
    "build",
    "--package-path",
    options.packagePath,
    "--swift-sdk",
    "swift-6.3-RELEASE_wasm",
    "-c",
    "release",
    "-Xswiftc",
    "-Osize",
    "-Xlinker",
    "--initial-memory=536870912",
    "-Xlinker",
    "--max-memory=4294967296",
    "-Xlinker",
    "-z",
    "-Xlinker",
    "stack-size=1048576",
  ];

  await runCommand([
    ...swiftCommandPrefix(),
    ...swiftBuildArgs,
    "--product",
    options.product,
  ], {
    cwd: swiftlyWorkingDirectory,
    env: environment,
  });

  const binPath = await runCommand([
    ...swiftCommandPrefix(),
    ...swiftBuildArgs,
    "--show-bin-path",
  ], {
    cwd: swiftlyWorkingDirectory,
    env: environment,
  });

  const wasmPath = join(binPath.trim(), `${options.product}.wasm`);
  return {
    binPath: binPath.trim(),
    wasmPath,
  };
}

async function resolveSwiftlyWorkingDirectory(
  startPath: string
): Promise<string> {
  let currentPath = resolve(startPath);

  while (true) {
    if (await Bun.file(join(currentPath, ".swift-version")).exists()) {
      return currentPath;
    }

    const parentPath = dirname(currentPath);
    if (parentPath === currentPath) {
      return resolve(startPath);
    }

    currentPath = parentPath;
  }
}
