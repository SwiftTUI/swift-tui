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

  await runCommand([
    ...swiftCommandPrefix(),
    "build",
    "--package-path",
    options.packagePath,
    "--swift-sdk",
    "swift-6.3-RELEASE_wasm",
    "--product",
    options.product,
    "-c",
    "release",
    "-Xlinker",
    "--initial-memory=536870912",
    "-Xlinker",
    "--max-memory=4294967296",
     "-Xlinker",
     "-z",
     "-Xlinker",
    "stack-size=1048576",
  ], {
    cwd: swiftlyWorkingDirectory,
    env: environment,
  });

  const binPath = await runCommand([
    ...swiftCommandPrefix(),
    "build",
    "--package-path",
    options.packagePath,
    "--swift-sdk",
    "swift-6.3-RELEASE_wasm",
    "-c",
    "release",
    "-Xlinker",
    "--initial-memory=536870912",
    "-Xlinker",
    "--max-memory=4294967296",
     "-Xlinker",
     "-z",
     "-Xlinker",
    "stack-size=1048576",
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
