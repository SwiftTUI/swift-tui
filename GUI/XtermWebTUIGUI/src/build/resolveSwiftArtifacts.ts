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

export const requiredWasmSwiftFlags = [
  "-Xswiftc",
  "-Osize",
  "-Xswiftc",
  "-Xfrontend",
  "-Xswiftc",
  "-disable-llvm-merge-functions-pass",
] as const;

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
    "swift-6.3.1-RELEASE_wasm",
    "-c",
    "release",
    ...requiredWasmSwiftFlags,
    "-Xlinker",
    "--initial-memory=536870912",
    "-Xlinker",
    "--max-memory=4294967296",
    "-Xlinker",
    "-z",
    "-Xlinker",
    "stack-size=1048576",
  ];

  confirmRequiredWasmFlags(swiftBuildArgs);

  const buildCommand = [
    ...swiftCommandPrefix(),
    ...swiftBuildArgs,
    "--product",
    options.product,
  ];
  const showBinPathCommand = [
    ...swiftCommandPrefix(),
    ...swiftBuildArgs,
    "--show-bin-path",
  ];

  logWasmBuildConfiguration({
    packagePath: options.packagePath,
    product: options.product,
    swiftlyWorkingDirectory,
    buildCommand,
    showBinPathCommand,
  });

  await runCommand(buildCommand, {
    cwd: swiftlyWorkingDirectory,
    env: environment,
  });

  const binPath = await runCommand(showBinPathCommand, {
    cwd: swiftlyWorkingDirectory,
    env: environment,
  });

  const wasmPath = join(binPath.trim(), `${options.product}.wasm`);
  return {
    binPath: binPath.trim(),
    wasmPath,
  };
}

interface WasmBuildConfigurationLog {
  packagePath: string;
  product: string;
  swiftlyWorkingDirectory: string;
  buildCommand: string[];
  showBinPathCommand: string[];
}

export function hasRequiredWasmFlags(args: readonly string[]): boolean {
  return containsSubsequence(args, requiredWasmSwiftFlags);
}

function confirmRequiredWasmFlags(args: readonly string[]): void {
  if (hasRequiredWasmFlags(args)) {
    return;
  }

  throw new Error(
    `missing required wasm Swift flags: ${requiredWasmSwiftFlags.join(" ")}`
  );
}

function logWasmBuildConfiguration(config: WasmBuildConfigurationLog): void {
  for (const line of wasmBuildConfigurationLogLines(config)) {
    console.error(line);
  }
}

export function wasmBuildConfigurationLogLines(
  config: WasmBuildConfigurationLog
): string[] {
  return [
    "WASM_REQUIRED_FLAGS_CONFIRMED=true",
    `WASM_REQUIRED_FLAGS=${requiredWasmSwiftFlags.join(" ")}`,
    `WASM_REQUIRED_FLAGS_JSON=${JSON.stringify([...requiredWasmSwiftFlags])}`,
    `WASM_BUILD_COMMAND=${formatCommandForLogs(config.buildCommand)}`,
    `WASM_BUILD_COMMAND_ARGS_JSON=${JSON.stringify(config.buildCommand)}`,
    `WASM_SHOW_BIN_PATH_COMMAND=${formatCommandForLogs(config.showBinPathCommand)}`,
    `WASM_SHOW_BIN_PATH_COMMAND_ARGS_JSON=${JSON.stringify(config.showBinPathCommand)}`,
    `WASM_BUILD_CONFIGURATION ${JSON.stringify({
      packagePath: config.packagePath,
      product: config.product,
      swiftlyWorkingDirectory: config.swiftlyWorkingDirectory,
      requiredFlags: [...requiredWasmSwiftFlags],
      buildCommand: formatCommandForLogs(config.buildCommand),
      showBinPathCommand: formatCommandForLogs(config.showBinPathCommand),
    })}`,
  ];
}

export function formatCommandForLogs(args: readonly string[]): string {
  return args.map(shellQuote).join(" ");
}

function containsSubsequence(
  args: readonly string[],
  expected: readonly string[]
): boolean {
  if (expected.length == 0) {
    return true;
  }

  for (let index = 0; index <= args.length - expected.length; index += 1) {
    let matches = true;
    for (let expectedIndex = 0; expectedIndex < expected.length; expectedIndex += 1) {
      if (args[index + expectedIndex] !== expected[expectedIndex]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      return true;
    }
  }

  return false;
}

function shellQuote(arg: string): string {
  if (/^[A-Za-z0-9_./:=+-]+$/.test(arg)) {
    return arg;
  }

  return `'${arg.replaceAll("'", `'\\''`)}'`;
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
