import { expect, test } from "bun:test";
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

test("standalone Foundation ban covers convenience imports, attributes and submodules", () => {
  const root = mkdtempSync(join(tmpdir(), "foundation-policy-"));
  try {
    for (const path of ["Scripts", ...["SwiftTUIPrimitives", "SwiftTUIGraph", "SwiftTUICore", "SwiftTUIViews", "SwiftTUI"].map((s) => `Sources/${s}`), "Vendor/swift-figlet/Sources/EmbeddedFonts", "Vendor/swift-figlet/Sources/SwiftFiglet"]) {
      mkdirSync(join(root, path), { recursive: true });
    }
    const script = join(root, "Scripts/check_foundation_imports.sh");
    copyFileSync(new URL("check_foundation_imports.sh", import.meta.url), script);
    const source = join(root, "Sources/SwiftTUI/Fixture.swift");
    for (const text of ["import Foundation", "@_exported import Foundation", "public import Foundation // comment", "import struct Foundation.Date", "import Foundation; let value = 1"]) {
      writeFileSync(source, text + "\n");
      expect(Bun.spawnSync(["sh", script]).exitCode).toBe(1);
    }
    writeFileSync(source, "// import Foundation\nimport SwiftTUIRuntime\n");
    expect(Bun.spawnSync(["sh", script]).exitCode).toBe(0);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
