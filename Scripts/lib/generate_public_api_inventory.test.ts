import { afterEach, expect, test } from "bun:test";
import { mkdtemp, mkdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import {
  ALL_MODULES,
  libraryProducts,
  loadReexports,
  parseReexports,
  reachableModules,
  type PackageDescription,
} from "./generate_public_api_inventory";

const scratch: string[] = [];
async function temporaryDirectory() {
  const path = await mkdtemp(join(tmpdir(), "swift-tui-module-map-"));
  scratch.push(path);
  return path;
}
afterEach(async () => {
  for (const path of scratch.splice(0)) await rm(path, { recursive: true, force: true });
});

test("products can have different names, several targets, and executable neighbors", () => {
  const manifest: PackageDescription = {
    products: [
      { name: "Authoring", targets: ["SwiftTUIViews", "SwiftTUICore"], type: { library: ["automatic"] } },
      { name: "Executable", targets: ["Main"], type: {} },
    ],
    targets: [],
  };
  expect(libraryProducts(manifest).map((product) => [product.name, product.targets])).toEqual([
    ["Authoring", ["SwiftTUIViews", "SwiftTUICore"]],
  ]);
});

test("re-exports retain nested branch conditions and SPI, ignoring ordinary public imports", () => {
  const edges = parseReexports(`
public import Ordinary
#if os(Windows)
@_exported import Portable
#elseif os(Linux)
#if canImport(Extra)
@_spi(Testing) @_exported public import Extra
#endif
#else
@_exported import Native
#endif
`, "Facade", "Facade.swift");
  expect(edges.map(({ to, condition, spi }) => ({ to, condition, spi }))).toEqual([
    { to: "Portable", condition: "(os(Windows))", spi: "none" },
    { to: "Extra", condition: "(!((os(Windows))) && (os(Linux))) && (canImport(Extra))", spi: "Testing" },
    { to: "Native", condition: "(!((os(Windows)) || (os(Linux))))", spi: "none" },
  ]);
});

test("comments and raw multiline literals cannot invent edges or conditions", () => {
  expect(parseReexports(`
/* outer /* nested */
@_exported import Comment
*/
let example = ##"""
#if os(Windows)
@_exported import StringLiteral
"""##
// @_exported import LineComment
@_exported import Actual /* trailing */
`, "Facade", "Facade.swift").map((edge) => edge.to)).toEqual(["Actual"]);
});

test("unsupported declarations fail instead of silently dropping an edge", () => {
  expect(() => parseReexports("@_exported\nimport Other", "Facade", "Facade.swift"))
    .toThrow("Unsupported re-export declaration");
});

test("reachability handles diamonds and cycles without changing ownership", () => {
  const edges = [
    ...parseReexports("@_exported import Core\n@_exported import Graph", "Views", "Views.swift"),
    ...parseReexports("@_exported import Graph", "Core", "Core.swift"),
    ...parseReexports("@_exported import Views\n@_exported import Primitives", "Graph", "Graph.swift"),
  ];
  expect(reachableModules("Views", edges)).toEqual(["Core", "Graph", "Primitives"]);
});

test("only SwiftPM-listed library sources contribute edges", async () => {
  const root = await temporaryDirectory();
  await Bun.write(join(root, "Included.swift"), "@_exported import Actual");
  await Bun.write(join(root, "Excluded.swift"), "@_exported import Excluded");
  const manifest: PackageDescription = {
    products: [],
    targets: [
      { name: "Facade", type: "library", path: ".", sources: ["Included.swift"] },
      { name: "Fixture", type: "executable", path: ".", sources: ["Excluded.swift"] },
    ],
  };
  expect((await loadReexports(manifest, root)).map((edge) => edge.to)).toEqual(["Actual"]);
});

test("CLI detects product and re-export drift even when the public symbol census is unchanged", async () => {
  const root = await temporaryDirectory();
  const graphs = join(root, "graphs");
  await mkdir(graphs);
  for (const module of ALL_MODULES) {
    await Bun.write(join(graphs, `${module}.symbols.json`), JSON.stringify({ module: { name: module }, symbols: [] }));
  }
  await Bun.write(join(graphs, "SwiftTUICore.symbols.json"), JSON.stringify({
    module: { name: "SwiftTUICore" },
    symbols: [{
      identifier: { precise: "s:Core5OwnedV" }, pathComponents: ["Owned"],
      kind: { identifier: "swift.struct", displayName: "Structure" },
      accessLevel: "public", names: { title: "Owned" },
    }],
  }));
  await Bun.write(join(root, "docs/overrides.yml"), "default: canonical\n");
  await Bun.write(join(root, "Sources/SwiftTUIViews/SwiftTUIViews.docc/Divergences-And-Gaps.md"), "# Divergences\n");
  await Bun.write(join(root, "Exports.swift"), "@_exported import SwiftTUICore\n");
  const manifest: PackageDescription = {
    products: [{ name: "Authoring", targets: ["SwiftTUIViews"], type: { library: ["automatic"] } }],
    targets: ALL_MODULES.map((name) => ({ name, type: "library", path: ".", sources: name === "SwiftTUIViews" ? ["Exports.swift"] : [] })),
  };
  const manifestPath = join(root, "manifest.json");
  await Bun.write(manifestPath, JSON.stringify(manifest));
  const args = [
    process.execPath, resolve(import.meta.dir, "generate_public_api_inventory.ts"),
    "--package-manifest", manifestPath, "--package-root", root,
    "--symbolgraph-dir", graphs, "--overrides", join(root, "docs/overrides.yml"),
    "--baseline-md", join(root, "docs/PUBLIC_API_BASELINE.md"),
    "--baseline-flat", join(root, "docs/.public-api-baseline.txt"),
    "--module-map", join(root, "docs/PUBLIC_MODULE_MAP.md"),
  ];
  const run = (check = false) => Bun.spawnSync([...args, ...(check ? ["--check"] : [])]);
  expect(run().exitCode).toBe(0);
  expect(run(true).exitCode).toBe(0);
  const baseline = await Bun.file(join(root, "docs/PUBLIC_API_BASELINE.md")).text();
  expect(baseline).toContain("`SwiftTUITerminalCLI` is not shipped as a library product");
  const map = await Bun.file(join(root, "docs/PUBLIC_MODULE_MAP.md")).text();
  expect(map).toContain("| `Authoring` | `SwiftTUIViews` |");
  expect(map).toContain("| [`SwiftTUICore`](PUBLIC_API_BASELINE.md#swifttuicore) | None (non-product support target) | 1 | 1 |");
  expect(map).toContain("| [`SwiftTUIViews`](PUBLIC_API_BASELINE.md#swifttuiviews) | `Authoring` | 0 | 0 |");

  manifest.products[0]!.name = "RenamedAuthoring";
  await Bun.write(manifestPath, JSON.stringify(manifest));
  let check = run(true);
  expect(check.exitCode).toBe(1);
  expect(check.stderr.toString()).toContain("Public module map is stale");
  expect(run().exitCode).toBe(0);
  await Bun.write(join(root, "Exports.swift"), "#if !os(Windows)\n@_exported import SwiftTUICore\n#endif\n");
  check = run(true);
  expect(check.exitCode).toBe(1);
  expect(check.stderr.toString()).toContain("Public module map is stale");
  expect(await Bun.file(join(root, "docs/.public-api-baseline.txt")).text()).toBe("SwiftTUICore.Owned\n");
});
