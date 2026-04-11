import { afterEach, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { packageBrowserValidatedWasm } from "./buildAppWasm.ts";

const minimalWasmBytes = new Uint8Array([
  0x00, 0x61, 0x73, 0x6d,
  0x01, 0x00, 0x00, 0x00,
]);

const temporaryDirectories: string[] = [];

afterEach(async () => {
  for (const directory of temporaryDirectories.splice(0)) {
    await rm(directory, { recursive: true, force: true });
  }
});

test("falls back to the original wasm when strip tooling throws", async () => {
  const fixture = await createFixture();
  const warnings: string[] = [];

  await packageBrowserValidatedWasm({
    sourceWasmPath: fixture.sourceWasmPath,
    outputWasmPath: fixture.outputWasmPath,
    strip: async () => {
      throw new Error("missing llvm-objcopy");
    },
    onWarning: (warning) => warnings.push(warning),
  });

  expect(await Bun.file(fixture.outputWasmPath).bytes())
    .toEqual(minimalWasmBytes);
  expect(warnings).toHaveLength(1);
  expect(warnings[0]).toContain("keeping unstripped wasm");
  expect(warnings[0]).toContain("missing llvm-objcopy");
  await WebAssembly.compile(await Bun.file(fixture.outputWasmPath).arrayBuffer());
});

test("falls back to the original wasm when stripping corrupts the artifact", async () => {
  const fixture = await createFixture();
  const warnings: string[] = [];

  await packageBrowserValidatedWasm({
    sourceWasmPath: fixture.sourceWasmPath,
    outputWasmPath: fixture.outputWasmPath,
    strip: async (wasmPath) => {
      await Bun.write(wasmPath, new Uint8Array([0x00, 0x61, 0x73, 0x6d]));
    },
    onWarning: (warning) => warnings.push(warning),
  });

  expect(await Bun.file(fixture.outputWasmPath).bytes())
    .toEqual(minimalWasmBytes);
  expect(warnings).toHaveLength(1);
  expect(warnings[0])
    .toContain("stripped wasm does not parse in browser WebAssembly");
  await WebAssembly.compile(await Bun.file(fixture.outputWasmPath).arrayBuffer());
});

test("fails when the source wasm itself is not browser-parseable", async () => {
  const fixture = await createFixture(new Uint8Array([0x00, 0x61, 0x73, 0x6d]));

  await expect(
    packageBrowserValidatedWasm({
      sourceWasmPath: fixture.sourceWasmPath,
      outputWasmPath: fixture.outputWasmPath,
      strip: async () => {},
    })
  ).rejects.toThrow("generated wasm does not parse in browser WebAssembly");
});

async function createFixture(
  sourceBytes: Uint8Array = minimalWasmBytes
): Promise<{ sourceWasmPath: string; outputWasmPath: string }> {
  const directory = await mkdtemp(join(tmpdir(), "webtuigui-wasm-"));
  temporaryDirectories.push(directory);

  const sourceWasmPath = join(directory, "source.wasm");
  const outputWasmPath = join(directory, "output.wasm");
  await Bun.write(sourceWasmPath, sourceBytes);

  return {
    sourceWasmPath,
    outputWasmPath,
  };
}
