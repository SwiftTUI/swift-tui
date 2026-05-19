#!/usr/bin/env bun
//
// generate_public_api_inventory.ts
//
// Reads the symbol-graph JSON files emitted by `swift package
// dump-symbol-graph` and produces two committed artefacts:
//
//   docs/PUBLIC_API_BASELINE.md    — curated, classification-grouped list of
//                                    every public top-level symbol per module.
//                                    Reviewers read this.
//   docs/.public-api-baseline.txt  — flat sorted list of every public symbol
//                                    path (top-level + members). Reviewers
//                                    git-diff this.
//
// Classifications come from docs/public_api_overrides.yml. Symbols not in
// that file fall into the `pending-review` bucket.
//
// `--check` also runs a report-only doc-comment ratchet over `canonical`
// symbols (see ENFORCE_DOC_COMMENTS).
//
// Run via `Scripts/generate_public_api_inventory.sh`. The shell wrapper
// handles the swift toolchain invocation; this file is pure parse + emit.

import { Glob } from "bun";
import { dirname, join, resolve } from "node:path";
import { existsSync } from "node:fs";
import { mkdir } from "node:fs/promises";
import { parse as parseYaml } from "yaml";

// ---------------------------------------------------------------------------
// CLI args

interface Args {
  symbolgraphDir: string;
  overrides: string;
  baselineMd: string;
  baselineFlat: string;
  check: boolean;
  allowMissingModules: string[];
}

function parseArgs(argv: readonly string[]): Args {
  const get = (flag: string): string | undefined => {
    const i = argv.indexOf(flag);
    return i >= 0 ? argv[i + 1] : undefined;
  };
  const required = (flag: string): string => {
    const v = get(flag);
    if (!v) {
      throw new Error(`Missing required argument: ${flag}`);
    }
    return v;
  };
  return {
    symbolgraphDir: required("--symbolgraph-dir"),
    overrides: required("--overrides"),
    baselineMd: required("--baseline-md"),
    baselineFlat: required("--baseline-flat"),
    check: argv.includes("--check"),
    allowMissingModules: values(argv, "--allow-missing-module"),
  };
}

function values(argv: readonly string[], flag: string): string[] {
  const result: string[] = [];
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === flag && argv[i + 1]) {
      result.push(argv[i + 1]!);
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Symbol graph types
//
// We use a permissive interface — the symbol graph schema has many fields
// we don't care about, so we narrow only what we read.

interface SymbolGraphSymbol {
  identifier: { precise: string };
  pathComponents: string[];
  kind: { identifier: string; displayName: string };
  accessLevel: string;
  names: { title: string };
  declarationFragments?: ReadonlyArray<{ kind: string; spelling: string }>;
  /** Present when the declaration carries a `///` documentation comment. */
  docComment?: { lines: ReadonlyArray<{ text: string }> };
}

interface SymbolGraph {
  module: { name: string };
  symbols: SymbolGraphSymbol[];
}

// ---------------------------------------------------------------------------
// Module configuration
//
// Library products live in PRIMARY_MODULES. PACKAGE_ONLY_MODULES are emitted
// as a separate section because they aren't shipped as library products even
// though their symbols carry `public` access (they're re-exported by other
// targets).

const PRIMARY_MODULES = [
  "SwiftTUI",
  "SwiftTUIRuntime",
  "SwiftTUIViews",
  "SwiftTUIAnimatedImage",
  "SwiftTUICharts",
  "SwiftTUIArguments",
  "SwiftTUIPTYPrimitives",
  "SwiftTUITerminal",
  "SwiftTUITerminalWorkspace",
  "SwiftTUICLI",
  "SwiftTUIWASI",
  "SwiftTUIWebHost",
  "SwiftTUIWebHostCLI",
  "SwiftUIHost",
] as const;
const PACKAGE_ONLY_MODULES = ["SwiftTUICore", "SwiftTUIPTYCPrimitives"] as const;
const ALL_MODULES = [...PRIMARY_MODULES, ...PACKAGE_ONLY_MODULES] as const;

type ModuleName = (typeof ALL_MODULES)[number];

// ---------------------------------------------------------------------------
// Classification

type Classification =
  | "canonical"
  | "package-only-seam"
  | "test-support"
  | "deprecated"
  | "removed"
  | "pending-review";

const CLASSIFICATION_ORDER: readonly Classification[] = [
  "canonical",
  "package-only-seam",
  "test-support",
  "deprecated",
  "pending-review",
  "removed",
];

const CLASSIFICATION_HEADINGS: Record<Classification, string> = {
  canonical: "Canonical surface",
  "package-only-seam": "Package-only seams",
  "test-support": "Test-support",
  deprecated: "Deprecated",
  removed: "Removed (must not appear)",
  "pending-review": "Pending review ⚠",
};

// Doc-comment coverage gate.
//
// `--check` reports how many `canonical`-classified top-level symbols carry no
// `///` summary. The consumer-facing surface is not yet fully documented, so
// this is a report-only ratchet: the count is printed but does not fail the
// gate. Flip ENFORCE_DOC_COMMENTS to `true` once the count reaches zero — that
// turns it into a hard gate that locks the canonical surface documented.
const ENFORCE_DOC_COMMENTS = false;

interface OverrideFile {
  classifications?: Partial<Record<Classification, string[]>>;
  /** Module-level fallback. Applied before the global `default`. */
  module_defaults?: Partial<Record<string, Classification>>;
  /** Global fallback for any symbol not otherwise classified. */
  default?: Classification;
  notes?: Record<string, string>;
}

// ---------------------------------------------------------------------------
// Data model

const TYPE_KIND_IDS = new Set([
  "swift.struct",
  "swift.class",
  "swift.enum",
  "swift.protocol",
  "swift.typealias",
  "swift.actor",
]);

const KIND_LABELS: Record<string, string> = {
  "swift.struct": "struct",
  "swift.class": "class",
  "swift.enum": "enum",
  "swift.protocol": "protocol",
  "swift.typealias": "typealias",
  "swift.actor": "actor",
  "swift.func": "func",
  "swift.func.op": "operator",
  "swift.method": "method",
  "swift.init": "init",
  "swift.deinit": "deinit",
  "swift.property": "property",
  "swift.type.property": "static property",
  "swift.type.method": "static method",
  "swift.subscript": "subscript",
  "swift.enum.case": "case",
  "swift.var": "var",
  "swift.let": "let",
  "swift.associatedtype": "associatedtype",
};

interface TopLevelEntry {
  /** "SwiftTUI.RunLoop" */
  qualifiedName: string;
  /** "RunLoop" */
  name: string;
  /** "class" / "struct" / etc. */
  kindLabel: string;
  /** raw kind id from the symbol graph */
  kindId: string;
  /** members nested inside this top-level type */
  members: MemberEntry[];
  classification: Classification;
  /** whether the declaration carries a `///` documentation comment */
  hasDoc: boolean;
}

interface MemberEntry {
  /** "RunLoop.run()" */
  pathInModule: string;
  kindLabel: string;
}

interface ModuleReport {
  module: ModuleName;
  topLevel: TopLevelEntry[];
}

// ---------------------------------------------------------------------------
// Loading

async function loadOverrides(path: string): Promise<{
  classification: Map<string, Classification>;
  moduleDefaults: Map<string, Classification>;
  defaultClassification: Classification;
  notes: Map<string, string>;
}> {
  const file = Bun.file(path);
  if (!(await file.exists())) {
    return {
      classification: new Map(),
      moduleDefaults: new Map(),
      defaultClassification: "pending-review",
      notes: new Map(),
    };
  }
  const raw = await file.text();
  const parsed = (parseYaml(raw) ?? {}) as OverrideFile;
  const classification = new Map<string, Classification>();
  for (const cls of CLASSIFICATION_ORDER) {
    const list = parsed.classifications?.[cls] ?? [];
    for (const sym of list) {
      classification.set(sym, cls);
    }
  }
  const moduleDefaults = new Map<string, Classification>(
    Object.entries(parsed.module_defaults ?? {}) as [string, Classification][],
  );
  const notes = new Map(Object.entries(parsed.notes ?? {}));
  return {
    classification,
    moduleDefaults,
    defaultClassification: parsed.default ?? "pending-review",
    notes,
  };
}

async function loadSymbolGraph(
  symbolgraphDir: string,
  module: ModuleName,
): Promise<SymbolGraph | undefined> {
  const path = join(symbolgraphDir, `${module}.symbols.json`);
  const file = Bun.file(path);
  if (!(await file.exists())) {
    return undefined;
  }
  return (await file.json()) as SymbolGraph;
}

// ---------------------------------------------------------------------------
// Build the report

function buildModuleReport(
  graph: SymbolGraph,
  module: ModuleName,
  classifications: ReadonlyMap<string, Classification>,
  moduleDefaults: ReadonlyMap<string, Classification>,
  defaultClassification: Classification,
): ModuleReport {
  const moduleDefault =
    moduleDefaults.get(module) ?? defaultClassification;
  const topLevelByName = new Map<string, TopLevelEntry>();
  const orphanMembers: SymbolGraphSymbol[] = [];

  // First pass: top-level types.
  for (const sym of graph.symbols) {
    if (isSynthesizedSymbol(sym)) continue;
    if (sym.accessLevel !== "public" && sym.accessLevel !== "open") continue;
    if (sym.pathComponents.length !== 1) continue;
    if (!TYPE_KIND_IDS.has(sym.kind.identifier)) {
      // top-level functions / properties / operators get their own bucket
      const qualifiedName = `${module}.${sym.pathComponents.join(".")}`;
      topLevelByName.set(sym.pathComponents[0]!, {
        qualifiedName,
        name: sym.pathComponents[0]!,
        kindLabel: KIND_LABELS[sym.kind.identifier] ?? sym.kind.identifier,
        kindId: sym.kind.identifier,
        members: [],
        classification: classifications.get(qualifiedName) ?? moduleDefault,
        hasDoc: hasDocComment(sym),
      });
      continue;
    }
    const qualifiedName = `${module}.${sym.pathComponents[0]!}`;
    topLevelByName.set(sym.pathComponents[0]!, {
      qualifiedName,
      name: sym.pathComponents[0]!,
      kindLabel: KIND_LABELS[sym.kind.identifier] ?? sym.kind.identifier,
      kindId: sym.kind.identifier,
      members: [],
      classification: classifications.get(qualifiedName) ?? moduleDefault,
      hasDoc: hasDocComment(sym),
    });
  }

  // Second pass: members.
  for (const sym of graph.symbols) {
    if (isSynthesizedSymbol(sym)) continue;
    if (sym.accessLevel !== "public" && sym.accessLevel !== "open") continue;
    if (sym.pathComponents.length < 2) continue;
    const ownerName = sym.pathComponents[0]!;
    const owner = topLevelByName.get(ownerName);
    if (!owner) {
      orphanMembers.push(sym);
      continue;
    }
    owner.members.push({
      pathInModule: sym.pathComponents.join("."),
      kindLabel: KIND_LABELS[sym.kind.identifier] ?? sym.kind.identifier,
    });
  }

  // Sort members for stable output.
  for (const entry of topLevelByName.values()) {
    entry.members.sort((a, b) => a.pathInModule.localeCompare(b.pathInModule));
  }

  const topLevel = Array.from(topLevelByName.values()).sort((a, b) =>
    a.name.localeCompare(b.name),
  );

  return { module, topLevel };
}

function isSynthesizedSymbol(sym: SymbolGraphSymbol): boolean {
  return sym.identifier.precise.includes("::SYNTHESIZED::");
}

function hasDocComment(sym: SymbolGraphSymbol): boolean {
  return (sym.docComment?.lines ?? []).some(
    (line) => line.text.trim().length > 0,
  );
}

// ---------------------------------------------------------------------------
// Render outputs

function renderBaselineMarkdown(
  reports: ReadonlyArray<ModuleReport>,
  notes: ReadonlyMap<string, string>,
  generatedAt: string,
): string {
  const lines: string[] = [];
  lines.push("# Public API Baseline");
  lines.push("");
  lines.push(
    "<!-- DO NOT EDIT — regenerated by Scripts/generate_public_api_inventory.sh -->",
  );
  lines.push(`<!-- Generated: ${generatedAt} -->`);
  lines.push("");
  lines.push(
    "This file is the authoritative enumeration of every public Swift symbol",
  );
  lines.push(
    "in the package, derived from `swift package dump-symbol-graph` and",
  );
  lines.push(
    "classified through [`docs/public_api_overrides.yml`](public_api_overrides.yml).",
  );
  lines.push("");
  lines.push(
    "PRs that add or remove a public symbol see the change show up here. The",
  );
  lines.push(
    "companion flat list at [`.public-api-baseline.txt`](.public-api-baseline.txt)",
  );
  lines.push(
    "is the machine-grep target; this file is grouped for human review.",
  );
  lines.push("");
  lines.push("For prose context, see [PUBLIC_API_INVENTORY.md](PUBLIC_API_INVENTORY.md).");
  lines.push("");

  // Summary table
  lines.push("## Summary");
  lines.push("");
  lines.push("| Module | Top-level | All public |");
  lines.push("|---|---:|---:|");
  for (const report of reports) {
    const topLevel = report.topLevel.length;
    const allPublic =
      topLevel +
      report.topLevel.reduce((sum, t) => sum + t.members.length, 0);
    lines.push(`| \`${report.module}\` | ${topLevel} | ${allPublic} |`);
  }
  lines.push("");

  // Per-module sections
  for (const report of reports) {
    const isPackageOnly = (PACKAGE_ONLY_MODULES as readonly string[]).includes(
      report.module,
    );
    lines.push(`## ${report.module}`);
    lines.push("");
    if (isPackageOnly) {
      lines.push(
        `> \`${report.module}\` is not shipped as a library product. Symbols here`,
      );
      lines.push(
        `> are package-internal but carry \`public\` access for re-export through`,
      );
      lines.push(`> other targets.`);
      lines.push("");
    }

    const grouped = new Map<Classification, TopLevelEntry[]>();
    for (const entry of report.topLevel) {
      const list = grouped.get(entry.classification) ?? [];
      list.push(entry);
      grouped.set(entry.classification, list);
    }

    for (const cls of CLASSIFICATION_ORDER) {
      const list = grouped.get(cls);
      if (!list || list.length === 0) continue;

      lines.push(`### ${CLASSIFICATION_HEADINGS[cls]} (${list.length})`);
      lines.push("");
      for (const entry of list) {
        const memberSummary = entry.members.length > 0
          ? ` — ${entry.members.length} member${entry.members.length === 1 ? "" : "s"}`
          : "";
        const note = notes.get(entry.qualifiedName);
        const noteSuffix = note ? ` _(${note})_` : "";
        lines.push(
          `- \`${entry.name}\` — ${entry.kindLabel}${memberSummary}${noteSuffix}`,
        );
      }
      lines.push("");
    }
  }

  return lines.join("\n");
}

function renderFlatBaseline(reports: ReadonlyArray<ModuleReport>): string {
  const lines: string[] = [];
  for (const report of reports) {
    for (const entry of report.topLevel) {
      lines.push(`${report.module}.${entry.name}`);
      for (const m of entry.members) {
        lines.push(`${report.module}.${m.pathInModule}`);
      }
    }
  }
  lines.sort();
  return lines.join("\n") + "\n";
}

// ---------------------------------------------------------------------------
// Drift detection

interface DriftReport {
  pendingReview: ReadonlyArray<{ module: ModuleName; qualifiedName: string }>;
  removedButPresent: ReadonlyArray<{ module: ModuleName; qualifiedName: string }>;
  /** `canonical`-classified top-level symbols with no `///` doc comment. */
  undocumentedCanonical: ReadonlyArray<{
    module: ModuleName;
    qualifiedName: string;
  }>;
  baselineStale: boolean;
  partialBaseline: boolean;
}

async function checkDrift(
  reports: ReadonlyArray<ModuleReport>,
  paths: { baselineMd: string; baselineFlat: string },
  rendered: { md: string; flat: string },
  options: { partialBaseline: boolean },
): Promise<DriftReport> {
  const pendingReview: { module: ModuleName; qualifiedName: string }[] = [];
  const removedButPresent: { module: ModuleName; qualifiedName: string }[] = [];
  const undocumentedCanonical: {
    module: ModuleName;
    qualifiedName: string;
  }[] = [];

  for (const report of reports) {
    for (const entry of report.topLevel) {
      if (entry.classification === "pending-review") {
        pendingReview.push({
          module: report.module,
          qualifiedName: entry.qualifiedName,
        });
      } else if (entry.classification === "removed") {
        removedButPresent.push({
          module: report.module,
          qualifiedName: entry.qualifiedName,
        });
      } else if (entry.classification === "canonical" && !entry.hasDoc) {
        undocumentedCanonical.push({
          module: report.module,
          qualifiedName: entry.qualifiedName,
        });
      }
    }
  }

  const existingMd = await readFileIfExists(paths.baselineMd);
  const existingFlat = await readFileIfExists(paths.baselineFlat);
  const baselineStale = options.partialBaseline
    ? false
    : existingMd !== rendered.md || existingFlat !== rendered.flat;

  return {
    pendingReview,
    removedButPresent,
    undocumentedCanonical,
    baselineStale,
    partialBaseline: options.partialBaseline,
  };
}

async function readFileIfExists(path: string): Promise<string | undefined> {
  const f = Bun.file(path);
  if (!(await f.exists())) return undefined;
  return await f.text();
}

function extractGeneratedAt(contents: string | undefined): string | undefined {
  return contents?.match(
    /<!-- Generated: ([0-9]{4}-[0-9]{2}-[0-9]{2}) -->/,
  )?.[1];
}

// ---------------------------------------------------------------------------
// Output

async function writeFileEnsuringDir(path: string, contents: string): Promise<void> {
  const dir = dirname(resolve(path));
  if (!existsSync(dir)) {
    await mkdir(dir, { recursive: true });
  }
  await Bun.write(path, contents);
}

// ---------------------------------------------------------------------------
// Main

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const overrides = await loadOverrides(args.overrides);
  const existingBaselineMd = await readFileIfExists(args.baselineMd);
  const generatedAt = args.check
    ? extractGeneratedAt(existingBaselineMd) ??
      new Date().toISOString().slice(0, 10)
    : new Date().toISOString().slice(0, 10);

  const reports: ModuleReport[] = [];
  const missingModules: ModuleName[] = [];
  for (const module of ALL_MODULES) {
    const graph = await loadSymbolGraph(args.symbolgraphDir, module);
    if (!graph) {
      console.error(
        `[generate_public_api_inventory] WARN: no symbol graph for ${module}`,
      );
      missingModules.push(module);
      continue;
    }
    reports.push(
      buildModuleReport(
        graph,
        module,
        overrides.classification,
        overrides.moduleDefaults,
        overrides.defaultClassification,
      ),
    );
  }

  if (missingModules.length > 0) {
    const allowedMissing = new Set(args.allowMissingModules);
    const unexpectedMissing = missingModules.filter(
      (module) => !allowedMissing.has(module),
    );
    if (!args.check) {
      console.error(
        "[generate_public_api_inventory] Refusing to regenerate a partial public API baseline.",
      );
      console.error(
        `[generate_public_api_inventory] Missing module(s): ${missingModules.join(", ")}`,
      );
      process.exit(1);
    }
    if (unexpectedMissing.length > 0) {
      console.error(
        "[generate_public_api_inventory] Missing required module symbol graph(s): " +
          unexpectedMissing.join(", "),
      );
      process.exit(1);
    }
    console.error(
      `[generate_public_api_inventory] Performing partial check without allowed missing module(s): ${missingModules.join(", ")}`,
    );
    console.error(
      "[generate_public_api_inventory] Skipping exact baseline comparison; " +
        "it requires a symbol graph for every public module.",
    );
  }

  const renderedMd = renderBaselineMarkdown(reports, overrides.notes, generatedAt);
  const renderedFlat = renderFlatBaseline(reports);
  const drift = await checkDrift(
    reports,
    args,
    {
      md: renderedMd,
      flat: renderedFlat,
    },
    {
      partialBaseline: missingModules.length > 0,
    },
  );

  if (args.check) {
    const failures: string[] = [];
    if (drift.baselineStale) {
      const message = drift.partialBaseline
        ? "Public API baseline is stale for modules emitted on this platform. " +
          "Regenerate on a platform that emits every public module."
        : "Public API baseline is stale. " +
          "Run Scripts/generate_public_api_inventory.sh to regenerate.";
      failures.push(message);
    }
    if (drift.pendingReview.length > 0) {
      failures.push(
        `${drift.pendingReview.length} top-level symbol(s) are unclassified:`,
      );
      for (const p of drift.pendingReview.slice(0, 10)) {
        failures.push(`  - ${p.qualifiedName}`);
      }
      if (drift.pendingReview.length > 10) {
        failures.push(`  - ...and ${drift.pendingReview.length - 10} more.`);
      }
      failures.push(
        "Add them to docs/public_api_overrides.yml under the appropriate classification.",
      );
    }
    if (drift.removedButPresent.length > 0) {
      failures.push(
        `${drift.removedButPresent.length} symbol(s) are classified "removed" but still present:`,
      );
      for (const p of drift.removedButPresent) {
        failures.push(`  - ${p.qualifiedName}`);
      }
    }
    if (drift.undocumentedCanonical.length > 0) {
      const summary =
        `${drift.undocumentedCanonical.length} canonical public ` +
        "symbol(s) have no doc comment";
      if (ENFORCE_DOC_COMMENTS) {
        failures.push(`${summary}:`);
        for (const p of drift.undocumentedCanonical.slice(0, 10)) {
          failures.push(`  - ${p.qualifiedName}`);
        }
        if (drift.undocumentedCanonical.length > 10) {
          failures.push(
            `  - ...and ${drift.undocumentedCanonical.length - 10} more.`,
          );
        }
        failures.push(
          "Add a /// summary to each, or reclassify it in " +
            "docs/public_api_overrides.yml if it is not consumer-facing.",
        );
      } else {
        console.error(
          `[generate_public_api_inventory] NOTE: ${summary} — ` +
            "report-only ratchet, not failing the gate. Add `///` summaries " +
            "to drive this to zero, then set ENFORCE_DOC_COMMENTS = true.",
        );
      }
    }
    if (failures.length > 0) {
      for (const f of failures) console.error(f);
      process.exit(1);
    }
    console.log(
      `[generate_public_api_inventory] OK — baseline current; ${reports.reduce((s, r) => s + r.topLevel.length, 0)} top-level public symbols.`,
    );
    return;
  }

  await writeFileEnsuringDir(args.baselineMd, renderedMd);
  await writeFileEnsuringDir(args.baselineFlat, renderedFlat);
  console.log(
    `[generate_public_api_inventory] Wrote ${args.baselineMd} and ${args.baselineFlat}.`,
  );
  if (drift.pendingReview.length > 0) {
    console.log(
      `[generate_public_api_inventory] NOTE: ${drift.pendingReview.length} top-level symbol(s) classified as "pending-review". See ${args.baselineMd}.`,
    );
  }
  if (drift.removedButPresent.length > 0) {
    console.error(
      `[generate_public_api_inventory] WARN: ${drift.removedButPresent.length} "removed" symbol(s) are still present in the source.`,
    );
  }
  if (drift.undocumentedCanonical.length > 0) {
    console.log(
      `[generate_public_api_inventory] NOTE: ${drift.undocumentedCanonical.length} canonical symbol(s) have no doc comment. See --check output.`,
    );
  }
}

await main();
