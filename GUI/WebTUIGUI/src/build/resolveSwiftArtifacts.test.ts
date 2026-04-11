import { expect, test } from "bun:test";
import {
  formatCommandForLogs,
  hasRequiredWasmFlags,
  requiredWasmSwiftFlags,
} from "./resolveSwiftArtifacts.ts";

test("detects the required wasm Swift flag sequence", () => {
  expect(
    hasRequiredWasmFlags([
      "build",
      "--swift-sdk",
      "swift-6.3-RELEASE_wasm",
      "-c",
      "release",
      ...requiredWasmSwiftFlags,
      "-Xlinker",
      "--initial-memory=1",
    ])
  ).toBe(true);

  expect(
    hasRequiredWasmFlags([
      "build",
      "--swift-sdk",
      "swift-6.3-RELEASE_wasm",
      "-c",
      "release",
      "-Xswiftc",
      "-Osize",
      "-Xswiftc",
      "-disable-llvm-merge-functions-pass",
    ])
  ).toBe(false);
});

test("formats commands for readable CI logs", () => {
  expect(
    formatCommandForLogs([
      "swiftly",
      "run",
      "swift",
      "build",
      "--package-path",
      "/tmp/My Project",
      "-Xlinker",
      "stack-size=1048576",
    ])
  ).toBe(
    "swiftly run swift build --package-path '/tmp/My Project' -Xlinker stack-size=1048576"
  );
});
