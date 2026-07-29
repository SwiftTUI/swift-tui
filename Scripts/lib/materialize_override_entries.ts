#!/usr/bin/env bun
//
// Materializes explicit public-API classification entries from a committed
// PUBLIC_API_BASELINE.md. This is a review aid for retiring a module default
// or moving declarations between modules: the baseline preserves the current
// effective classification, while public_api_overrides.yml records which
// entries are already explicit.
//
// The tool never edits the ledger. Without --check it prints the missing YAML
// entries for review; with --check it fails if any selected baseline entry is
// still implicit.
//
// Example:
//   bun run Scripts/lib/materialize_override_entries.ts \
//     --baseline docs/PUBLIC_API_BASELINE.md \
//     --overrides docs/public_api_overrides.yml \
//     --module SwiftTUIRuntime

import { parse as parseYaml } from "yaml";

type Classification =
  | "canonical"
  | "package-only-seam"
  | "test-support"
  | "deprecated"
  | "pending-review"
  | "removed";

const CLASSIFICATION_ORDER: readonly Classification[] = [
  "canonical",
  "package-only-seam",
  "test-support",
  "deprecated",
  "pending-review",
  "removed",
];

const HEADING_CLASSIFICATIONS: Readonly<Record<string, Classification>> = {
  "Canonical surface": "canonical",
  "Package-only seams": "package-only-seam",
  "Test-support": "test-support",
  "Deprecated": "deprecated",
  "Pending review ⚠": "pending-review",
  "Removed (must not appear)": "removed",
};

interface Args {
  baseline: string;
  overrides: string;
  modules: string[];
  check: boolean;
}

interface OverrideFile {
  classifications?: Partial<Record<Classification, string[]>>;
}

interface BaselineEntry {
  qualifiedName: string;
  classification: Classification;
}

function values(argv: readonly string[], flag: string): string[] {
  const result: string[] = [];
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === flag && argv[index + 1]) {
      result.push(argv[index + 1]!);
    }
  }
  return result;
}

function parseArgs(argv: readonly string[]): Args {
  const value = (flag: string): string | undefined => {
    const index = argv.indexOf(flag);
    return index >= 0 ? argv[index + 1] : undefined;
  };
  const required = (flag: string): string => {
    const result = value(flag);
    if (!result) throw new Error(`Missing required argument: ${flag}`);
    return result;
  };
  const modules = values(argv, "--module");
  if (modules.length === 0) {
    throw new Error("Pass at least one --module to materialize");
  }
  return {
    baseline: required("--baseline"),
    overrides: required("--overrides"),
    modules,
    check: argv.includes("--check"),
  };
}

async function loadExplicitClassifications(
  path: string,
): Promise<Map<string, Classification>> {
  const parsed = (parseYaml(await Bun.file(path).text()) ?? {}) as OverrideFile;
  const result = new Map<string, Classification>();
  for (const classification of CLASSIFICATION_ORDER) {
    for (const key of parsed.classifications?.[classification] ?? []) {
      const existing = result.get(key);
      if (existing) {
        throw new Error(
          `Duplicate classification key '${key}' in '${existing}' and '${classification}'`,
        );
      }
      result.set(key, classification);
    }
  }
  return result;
}

async function loadBaselineEntries(
  path: string,
  selectedModules: ReadonlySet<string>,
): Promise<{
  entries: BaselineEntry[];
  seenModules: Set<string>;
  summaryCounts: Map<string, number>;
}> {
  const entries: BaselineEntry[] = [];
  const seenModules = new Set<string>();
  const summaryCounts = new Map<string, number>();
  const parsedCounts = new Map<string, number>();
  let currentModule: string | undefined;
  let currentClassification: Classification | undefined;

  for (const line of (await Bun.file(path).text()).split("\n")) {
    const summaryMatch = line.match(
      /^\| `([A-Za-z_][A-Za-z0-9_]*)` \| (\d+) \| \d+ \|$/,
    );
    if (summaryMatch?.[1] && selectedModules.has(summaryMatch[1])) {
      if (summaryCounts.has(summaryMatch[1])) {
        throw new Error(
          `Duplicate summary row for selected module '${summaryMatch[1]}'`,
        );
      }
      summaryCounts.set(summaryMatch[1], Number(summaryMatch[2]));
      continue;
    }

    const moduleMatch = line.match(/^## ([A-Za-z_][A-Za-z0-9_]*)$/);
    if (moduleMatch?.[1]) {
      currentModule = moduleMatch[1];
      currentClassification = undefined;
      if (selectedModules.has(currentModule)) {
        if (seenModules.has(currentModule)) {
          throw new Error(
            `Duplicate section for selected module '${currentModule}'`,
          );
        }
        seenModules.add(currentModule);
      }
      continue;
    }

    const headingMatch = line.match(/^### (.+) \(\d+\)$/);
    if (headingMatch?.[1]) {
      currentClassification = HEADING_CLASSIFICATIONS[headingMatch[1]];
      if (!currentClassification && currentModule && selectedModules.has(currentModule)) {
        throw new Error(
          `Unknown classification heading '${headingMatch[1]}' in module '${currentModule}'`,
        );
      }
      continue;
    }

    const symbolMatch = line.match(/^- `([^`]+)` — /);
    if (!symbolMatch?.[1] || !currentModule || !selectedModules.has(currentModule)) {
      continue;
    }
    if (!currentClassification) {
      throw new Error(
        `Symbol '${currentModule}.${symbolMatch[1]}' has no classification heading`,
      );
    }
    entries.push({
      qualifiedName: `${currentModule}.${symbolMatch[1]}`,
      classification: currentClassification,
    });
    parsedCounts.set(currentModule, (parsedCounts.get(currentModule) ?? 0) + 1);
  }

  for (const module of selectedModules) {
    const declaredCount = summaryCounts.get(module);
    if (declaredCount === undefined) {
      throw new Error(`Selected module '${module}' is absent from the baseline summary`);
    }
    const parsedCount = parsedCounts.get(module) ?? 0;
    if (parsedCount !== declaredCount) {
      throw new Error(
        `Baseline entry-count mismatch for '${module}': ` +
          `summary declares ${declaredCount}, parsed ${parsedCount}`,
      );
    }
  }

  return { entries, seenModules, summaryCounts };
}

function yamlScalar(value: string): string {
  return /^[A-Za-z_][A-Za-z0-9_.]*$/.test(value)
    ? value
    : JSON.stringify(value);
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const selectedModules = new Set(args.modules);
  const explicit = await loadExplicitClassifications(args.overrides);
  const baseline = await loadBaselineEntries(args.baseline, selectedModules);

  const missingModules = args.modules.filter(
    (module) => !baseline.seenModules.has(module),
  );
  if (missingModules.length > 0) {
    throw new Error(
      `Selected module(s) absent from baseline: ${missingModules.join(", ")}`,
    );
  }

  const additions = new Map<Classification, string[]>();
  for (const entry of baseline.entries) {
    const existing = explicit.get(entry.qualifiedName);
    if (existing && existing !== entry.classification) {
      throw new Error(
        `Classification mismatch for '${entry.qualifiedName}': ` +
          `baseline '${entry.classification}', ledger '${existing}'`,
      );
    }
    if (existing) continue;
    const list = additions.get(entry.classification) ?? [];
    list.push(entry.qualifiedName);
    additions.set(entry.classification, list);
  }

  const additionCount = [...additions.values()].reduce(
    (sum, entries) => sum + entries.length,
    0,
  );
  if (additionCount === 0) {
    console.error(
      `[materialize_override_entries] OK — ${baseline.entries.length} selected ` +
        "baseline entries are explicit.",
    );
    return;
  }

  if (args.check) {
    console.error(
      `[materialize_override_entries] ${additionCount} selected baseline ` +
        "entries are still implicit:",
    );
    for (const classification of CLASSIFICATION_ORDER) {
      for (const key of additions.get(classification) ?? []) {
        console.error(`  - ${classification}: ${key}`);
      }
    }
    process.exit(1);
  }

  for (const classification of CLASSIFICATION_ORDER) {
    const entries = additions.get(classification);
    if (!entries || entries.length === 0) continue;
    console.log(`${classification}:`);
    for (const key of entries) console.log(`  - ${yamlScalar(key)}`);
  }
  console.error(
    `[materialize_override_entries] Emitted ${additionCount} missing entries ` +
      `from ${baseline.entries.length} selected baseline entries.`,
  );
}

await main();
