import { join } from "node:path";

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
  const environment = {
    ...process.env,
    TERMINALUI_ENABLE_WASM: "1",
  };

  await runCommand([
    "swift",
    "build",
    "--package-path",
    options.packagePath,
    "--swift-sdk",
    "swift-6.3-RELEASE_wasm",
    "--product",
    options.product,
    "-c",
    "release",
  ], environment);

  const binPath = await runCommand([
    "swift",
    "build",
    "--package-path",
    options.packagePath,
    "--swift-sdk",
    "swift-6.3-RELEASE_wasm",
    "-c",
    "release",
    "--show-bin-path",
  ], environment);

  const wasmPath = join(binPath.trim(), `${options.product}.wasm`);
  return {
    binPath: binPath.trim(),
    wasmPath,
  };
}

async function runCommand(
  cmd: string[],
  env?: Record<string, string | undefined>
): Promise<string> {
  const proc = Bun.spawn({
    cmd,
    env,
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);

  if (exitCode !== 0) {
    throw new Error([stdout, stderr].filter(Boolean).join("\n").trim() || `command failed: ${cmd.join(" ")}`);
  }

  return stdout;
}
