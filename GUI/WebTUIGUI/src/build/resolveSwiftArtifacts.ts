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

  // The browser WebAssembly API rejects function types with more than 1000
  // parameters. Swift's wasm release builds can trip that limit when LLVM's
  // merge-functions pass combines large outlined-copy helpers. `-Osize` helps,
  // but some Darwin CI runners still reproduce the failure unless we also
  // disable that merge pass explicitly.
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
    "-Xswiftc",
    "-Xfrontend",
    "-Xswiftc",
    "-disable-llvm-merge-functions-pass",
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
