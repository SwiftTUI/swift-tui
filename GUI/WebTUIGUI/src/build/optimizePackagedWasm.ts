import { runCommand } from "./runCommand.ts";

export async function optimizePackagedWasm(
  wasmPath: string
): Promise<void> {
  const wasmOptPath = Bun.which("wasm-opt");
  if (!wasmOptPath) {
    throw new Error(
      "missing wasm-opt in PATH; install Binaryen so wasm packaging is deterministic across environments"
    );
  }

  await runCommand([
    wasmOptPath,
    "-Os",
    wasmPath,
    "-o",
    wasmPath,
  ]);
}
