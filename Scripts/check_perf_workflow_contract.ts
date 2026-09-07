import { readFileSync } from "node:fs";
import { parse } from "yaml";

// The Linux core lane delegates TermUIPerf to this workflow. Its trigger must
// follow the framework dependency closure, not only the benchmark tool files.
export const requiredPerfPaths = [
  ".github/workflows/termui-perf-tests.yml",
  ".swift-version",
  "Package.swift",
  "Package.resolved",
  "Sources/**",
  "Platforms/**",
  "Tests/**",
  "Scripts/**",
  "Tools/TermUIPerf/**",
] as const;

export function validatePerfWorkflow(document: unknown): string[] {
  const failures: string[] = [];
  if (!document || typeof document !== "object" || !("on" in document)) {
    return ["performance workflow has no triggers"];
  }
  const triggers = document.on;
  if (!triggers || typeof triggers !== "object") {
    return ["performance workflow triggers must include push and pull_request"];
  }
  for (const event of ["push", "pull_request"] as const) {
    if (!(event in triggers)) {
      failures.push(`performance workflow has no ${event} trigger`);
      continue;
    }
    const config = (triggers as Record<string, unknown>)[event];
    if (config == null) continue; // An unfiltered event covers every source.
    if (typeof config !== "object") {
      failures.push(`${event}: invalid trigger configuration`);
      continue;
    }
    if ("paths-ignore" in config) {
      failures.push(`${event}: review exclusions before narrowing performance coverage`);
    }
    if (!("paths" in config)) continue;
    const paths = config.paths;
    if (!Array.isArray(paths) || paths.some((path) => typeof path !== "string")) {
      failures.push(`${event}: paths must be strings`);
      continue;
    }
    if (paths.some((path) => path.startsWith("!"))) {
      failures.push(`${event}: negative path filters can exclude framework work`);
    }
    for (const path of requiredPerfPaths) {
      if (!paths.includes(path) && !paths.includes("**")) {
        failures.push(`${event}: missing dependency path ${path}`);
      }
    }
  }
  return failures;
}

if (import.meta.main) {
  const file = new URL("../.github/workflows/termui-perf-tests.yml", import.meta.url);
  const failures = validatePerfWorkflow(parse(readFileSync(file, "utf8")));
  if (failures.length > 0) {
    console.error(failures.join("\n"));
    process.exitCode = 1;
  } else {
    console.log("[perf_workflow_contract] framework changes reach performance CI");
  }
}
