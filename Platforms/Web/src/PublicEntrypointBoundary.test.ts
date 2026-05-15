import { expect, test } from "bun:test";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

const runtimeEntrypoints = [
  "index.ts",
  "manifest.ts",
  "testing.ts",
  "wasi.ts",
  "wasi-worker.ts",
  "websocket.ts",
] as const;

test("public browser runtime entrypoints do not import build tooling", async () => {
  for (const entrypoint of runtimeEntrypoints) {
    const source = await readFile(resolve(import.meta.dir, "..", entrypoint), "utf8");
    expect(source).not.toContain("@swifttui/build");
    expect(source).not.toContain("node:");
  }
});
