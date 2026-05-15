import { expect, test } from "bun:test";
import {
  formatCommandForLogs,
  hasRequiredWasmFlags,
  requiredWasmSwiftFlags,
  wasmBuildConfigurationLogLines,
} from "./resolveSwiftArtifacts.ts";

test("detects the required wasm Swift flag sequence", () => {
  expect(
    hasRequiredWasmFlags([
      "build",
      "--swift-sdk",
      "swift-6.3.1-RELEASE_wasm",
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
      "swift-6.3.1-RELEASE_wasm",
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

test("emits explicit CI log lines for flag confirmation and commands", () => {
  const lines = wasmBuildConfigurationLogLines({
    configuration: "release",
    packagePath: "/tmp/pkg",
    product: "WebExampleApp",
    swiftlyWorkingDirectory: "/tmp",
    buildCommand: ["swiftly", "run", "swift", "build", "--product", "WebExampleApp"],
    showBinPathCommand: ["swiftly", "run", "swift", "build", "--show-bin-path"],
  });

  expect(lines).toContain("WASM_REQUIRED_FLAGS_CONFIRMED=true");
  expect(lines).toContain("WASM_BUILD_CONFIGURATION_NAME=release");
  expect(lines).toContain(
    "WASM_REQUIRED_FLAGS=-Xswiftc -Osize -Xswiftc -Xfrontend -Xswiftc -disable-llvm-merge-functions-pass"
  );
  expect(lines).toContain(
    'WASM_BUILD_COMMAND_ARGS_JSON=["swiftly","run","swift","build","--product","WebExampleApp"]'
  );
  expect(lines).toContain(
    'WASM_SHOW_BIN_PATH_COMMAND_ARGS_JSON=["swiftly","run","swift","build","--show-bin-path"]'
  );
});

test("marks required release flags as skipped for debug wasm builds", () => {
  const lines = wasmBuildConfigurationLogLines({
    configuration: "debug",
    packagePath: "/tmp/pkg",
    product: "WebExampleApp",
    swiftlyWorkingDirectory: "/tmp",
    buildCommand: ["swiftly", "run", "swift", "build", "-c", "debug"],
    showBinPathCommand: ["swiftly", "run", "swift", "build", "-c", "debug", "--show-bin-path"],
  });

  expect(lines).toContain("WASM_BUILD_CONFIGURATION_NAME=debug");
  expect(lines).toContain("WASM_REQUIRED_FLAGS_CONFIRMED=skipped");
});
