import { Glob } from "bun";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

type Fragment = { spelling: string; preciseIdentifier?: string };
type Symbol = {
  identifier: { precise: string };
  pathComponents: string[];
  accessLevel: string;
  declarationFragments?: Fragment[];
  swiftGenerics?: unknown;
  swiftExtension?: unknown;
  spi?: boolean;
  location?: { uri: string; position: { line: number } };
};
type Relationship = { kind: string; source: string; target: string; swiftConstraints?: unknown };
export type ContractGraph = {
  module: { name: string };
  symbols: Symbol[];
  relationships?: Relationship[];
};

export function inventory(
  graphs: ContractGraph[],
  classify: (qualifiedOwner: string, module: string) => string,
  groups: Map<string, string[]> = new Map(),
): string {
  const symbols = new Map<string, { symbol: Symbol; module: string }>();
  const relationships = new Map<string, Relationship>();
  for (const graph of graphs) {
    for (const symbol of graph.symbols) {
      const id = symbol.identifier.precise;
      if (id.includes("::SYNTHESIZED::") || !["public", "open"].includes(symbol.accessLevel)) continue;
      symbols.set(id, { symbol, module: graph.module.name });
    }
    for (const relation of graph.relationships ?? []) {
      if (relation.source.includes("::SYNTHESIZED::")) continue;
      const value = { kind: relation.kind, source: relation.source, target: relation.target,
        ...(relation.swiftConstraints ? { swiftConstraints: relation.swiftConstraints } : {}) };
      relationships.set(JSON.stringify(value), value);
    }
  }
  const bySource = new Map<string, Relationship[]>();
  for (const relation of relationships.values()) {
    const list = bySource.get(relation.source) ?? [];
    list.push(relation);
    bySource.set(relation.source, list);
  }
  const inheritedGroups = (id: string, seen = new Set<string>()): string[] => {
    if (seen.has(id)) return [];
    seen.add(id);
    const own = groups.get(id) ?? [];
    if (own.length) return own;
    const parents = bySource.get(id)?.filter(r =>
      ["memberOf", "requirementOf", "optionalRequirementOf", "defaultImplementationOf"].includes(r.kind)) ?? [];
    return [...new Set(parents.flatMap(parent => inheritedGroups(parent.target, new Set(seen))))];
  };
  const rows = [...symbols].map(([id, { symbol, module }]) => {
    const spiGroups = inheritedGroups(id).sort();
    const classification = symbol.spi
      ? spiGroups.includes("Host") ? "host-spi"
        : spiGroups.includes("Testing") ? "test-support"
        : spiGroups.includes("StyleFixtures") ? "style-fixtures"
        : "internal-or-legacy-spi"
      : classify(`${module}.${symbol.pathComponents[0]}`, module);
    return { id, name: `${module}.${symbol.pathComponents.join(".")}`, classification, spiGroups,
      declaration: (symbol.declarationFragments ?? []).map(f => f.spelling).join(""),
      references: [...new Set((symbol.declarationFragments ?? []).flatMap(f =>
        f.preciseIdentifier && f.preciseIdentifier !== id ? [f.preciseIdentifier] : []))].sort(),
      ...(symbol.swiftGenerics ? { generics: symbol.swiftGenerics } : {}),
      ...(symbol.swiftExtension ? { extension: symbol.swiftExtension } : {}),
      relationships: (bySource.get(id) ?? []).map(({ source: _, ...r }) => r)
        .sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b))),
    };
  });
  // Mark every locally declared type that is reachable through a supported
  // signature, including generic constraints, conformances and default witnesses.
  const byID = new Map(rows.map(r => [r.id, r]));
  const reachable = new Set<string>();
  const work = rows.filter(r => ["canonical", "host-spi", "test-support", "style-fixtures"].includes(r.classification)).map(r => r.id);
  while (work.length) {
    const id = work.pop()!;
    if (reachable.has(id)) continue;
    reachable.add(id);
    const row = byID.get(id);
    if (!row) continue;
    work.push(...row.references, ...row.relationships.map(r => r.target));
    // Constraint operands contain compiler identifiers as well as spellings.
    const visit = (value: unknown) => {
      if (typeof value === "string" && byID.has(value)) work.push(value);
      else if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === "object") Object.values(value).forEach(visit);
    };
    visit(row.generics);
    visit(row.extension);
  }
  return rows.sort((a, b) => a.name.localeCompare(b.name) || a.id.localeCompare(b.id)).map(row =>
    JSON.stringify({ ...row, signatureReachable: reachable.has(row.id),
      disposition: reachable.has(row.id) && ["package-only-seam", "implementation-support"].includes(row.classification)
        ? "signature-only; no supported direct module import" : row.classification,
    })).join("\n") + "\n";
}

export async function renderSwiftContractInventory(
  directory: string,
  classify: (qualifiedOwner: string, module: string) => string,
): Promise<string> {
  const graphs: ContractGraph[] = [];
  const groups = new Map<string, string[]>();
  const sources = new Map<string, string[]>();
  const files = [...new Glob("*.symbols.json").scanSync(directory)].sort();
  for (const file of files) {
    const graph = await Bun.file(join(directory, file)).json() as ContractGraph;
    if (!graph.module.name.startsWith("SwiftTUI")) continue;
    graphs.push(graph);
    for (const symbol of graph.symbols) {
      if (!symbol.spi || !symbol.location) continue;
      const path = fileURLToPath(symbol.location.uri);
      let lines = sources.get(path);
      if (!lines) {
        lines = (await Bun.file(path).text()).split("\n");
        sources.set(path, lines);
      }
      // Swift's graph marks SPI but omits its group names. Read only the
      // declaration's attached attribute lines; never scan a previous body.
      const line = symbol.location.position.line;
      const attributes = [lines[line] ?? ""];
      for (let index = line - 1; index >= 0; index--) {
        const preceding = lines[index]!.trim();
        if (!preceding.startsWith("@") || /\b(public|func|var|let|class|struct|enum|protocol)\b/.test(preceding)) break;
        attributes.unshift(preceding);
      }
      const found = [...attributes.join("\n").matchAll(/@_spi\(([^)]+)\)/g)].map(m => m[1]!);
      if (found.length) groups.set(symbol.identifier.precise, found);
    }
  }
  return inventory(graphs, classify, groups);
}
