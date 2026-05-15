#!/usr/bin/env bun

import { resolve } from "node:path";
import {
  buildAppWasm,
  buildSwiftTUIWebApp,
  generateSceneManifest,
  type WasmBuildConfiguration,
} from "./index.ts";

void runCli(process.argv.slice(2));

async function runCli(argv: string[]): Promise<void> {
  const command = argv[0] ?? "build";
  const flags = parseFlags(argv.slice(1));
  const packagePath = resolve(flags["package-path"] ?? "../../");
  const distPath = resolve(flags["dist"] ?? "./dist");
  const appExecutable = flags.app ?? flags.product ?? flags["app-product"] ?? "";
  const configuration = parseWasmBuildConfiguration(flags.configuration ?? "release");

  switch (command) {
    case "build:manifest":
      assertAppExecutable(appExecutable);
      await generateSceneManifest({
        packagePath,
        outputPath: resolve(distPath, "scene-manifest.json"),
        appExecutable,
      });
      return;
    case "build:wasm":
      assertAppExecutable(appExecutable);
      await buildAppWasm({
        configuration,
        packagePath,
        outputDirectory: distPath,
        product: appExecutable,
      });
      return;
    case "build":
      assertAppExecutable(appExecutable);
      await buildSwiftTUIWebApp({
        configuration,
        packagePath,
        outputDirectory: distPath,
        product: appExecutable,
      });
      return;
    default:
      throw new Error(`unknown command: ${command}`);
  }
}

function parseFlags(
  argv: string[]
): Record<string, string> {
  const flags: Record<string, string> = {};
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (!value.startsWith("--")) {
      continue;
    }
    const equalsIndex = value.indexOf("=");
    if (equalsIndex !== -1) {
      flags[value.slice(2, equalsIndex)] = value.slice(equalsIndex + 1);
      continue;
    }
    const name = value.slice(2);
    const next = argv[index + 1];
    if (next && !next.startsWith("--")) {
      flags[name] = next;
      index += 1;
    } else {
      flags[name] = "true";
    }
  }
  return flags;
}

function parseWasmBuildConfiguration(
  value: string
): WasmBuildConfiguration {
  switch (value) {
    case "debug":
      return "debug";
    case "release":
      return "release";
    default:
      throw new Error(`unsupported wasm build configuration: ${value}`);
  }
}

function assertAppExecutable(
  value: string
): asserts value is string {
  if (!value) {
    throw new Error("missing --app or --product flag");
  }
}
