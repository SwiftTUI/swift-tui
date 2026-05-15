import { findExecutable, runCommand } from "./runCommand.ts";

export async function stripPackagedWasm(
  wasmPath: string
): Promise<void> {
  const objcopyPath = findExecutable("llvm-objcopy");
  if (!objcopyPath) {
    throw new Error(
      "missing llvm-objcopy in PATH; install the swiftly-managed toolchain before packaging wasm"
    );
  }

  await runCommand([
    objcopyPath,
    "--strip-debug",
    "--remove-section=name",
    wasmPath,
  ]);
}
