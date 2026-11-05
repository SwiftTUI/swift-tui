import { expect, test } from "bun:test";
import { inventory, type ContractGraph } from "./swift_contract_inventory.ts";

const graph = (): ContractGraph => ({
  module: { name: "SwiftTUIRuntime" },
  symbols: [
    { identifier: { precise: "host" }, pathComponents: ["Host"], accessLevel: "public", spi: true,
      declarationFragments: [{ spelling: "@MainActor final class Host" }] },
    { identifier: { precise: "render" }, pathComponents: ["Host", "render(_:)"], accessLevel: "public", spi: true,
      declarationFragments: [{ spelling: "func render(_ value: " },
        { spelling: "Frame", preciseIdentifier: "frame" }, { spelling: ")" }] },
    { identifier: { precise: "frame" }, pathComponents: ["Frame"], accessLevel: "public",
      declarationFragments: [{ spelling: "struct Frame" }] },
  ],
  relationships: [{ kind: "memberOf", source: "render", target: "host" },
    { kind: "conformsTo", source: "frame", target: "sendable" },
    { kind: "defaultImplementationOf", source: "render", target: "requirement" }],
});
const render = (input: ContractGraph) => inventory([input], () => "package-only-seam", new Map([["host", ["Host"]]]));

test("signature dependencies retain a disposition and inherited SPI groups", () => {
  const rows = render(graph()).trim().split("\n").map(line => JSON.parse(line));
  expect(rows.find(row => row.id === "render").classification).toBe("host-spi");
  expect(rows.find(row => row.id === "frame").disposition).toBe("signature-only; no supported direct module import");
});

test("same-name parameter, actor, conformance and default-witness changes alter the ratchet", () => {
  const baseline = render(graph());
  for (const mutation of ["parameter", "actor", "conformance", "witness"]) {
    const changed = graph();
    if (mutation === "parameter") changed.symbols[1]!.declarationFragments![1]!.spelling = "Int";
    if (mutation === "actor") changed.symbols[0]!.declarationFragments![0]!.spelling = "final class Host";
    if (mutation === "conformance") changed.relationships!.splice(1, 1);
    if (mutation === "witness") changed.relationships!.splice(2, 1);
    expect(render(changed)).not.toBe(baseline);
  }
});

test("symbol extraction order does not affect the inventory", () => {
  const changed = graph();
  changed.symbols.reverse();
  changed.relationships!.reverse();
  expect(render(changed)).toBe(render(graph()));
});
