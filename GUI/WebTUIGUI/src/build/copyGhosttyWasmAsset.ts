import { mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";

export interface CopyGhosttyWasmAssetOptions {
  outputPath: string;
}

export async function copyGhosttyWasmAsset(
  options: CopyGhosttyWasmAssetOptions
): Promise<string> {
  const wasmPath = resolveGhosttyWasmPath();
  const wasmFile = Bun.file(wasmPath);
  if (!(await wasmFile.exists())) {
    throw new Error(`missing ghostty-web wasm asset at ${wasmPath}; run bun install in GUI/WebTUIGUI`);
  }

  await mkdir(dirname(options.outputPath), { recursive: true });
  await Bun.write(options.outputPath, await wasmFile.arrayBuffer());
  return options.outputPath;
}

export function resolveGhosttyWasmPath(): string {
  return resolve(import.meta.dir, "../../node_modules/ghostty-web/ghostty-vt.wasm");
}
