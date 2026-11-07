import { expect, test } from "bun:test";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

function fixture() {
  const root = mkdtempSync(join(tmpdir(), "swift-tui-import-state-"));
  mkdirSync(join(root, "Scripts/data/public-import-consumers"), { recursive: true });
  cpSync(join(import.meta.dir, "check_public_import_consumers.sh"), join(root, "Scripts/check_public_import_consumers.sh"));
  for (const product of ["SwiftTUIViews", "SwiftTUIRuntime"]) {
    writeFileSync(join(root, `Scripts/data/public-import-consumers/${product}.swift`), `import ${product}\n`);
  }
  mkdirSync(join(root, "bin"));
  writeFileSync(join(root, "bin/swiftly"), `#!/bin/sh
set -eu
consumer=$5
printf '%s\\n' "$consumer" >> "$IMPORT_TEST_CALLS"
test ! -e "$consumer/.build/seen"
mkdir -p "$consumer/.build"
touch "$consumer/.build/seen"
exit "$IMPORT_TEST_EXIT"
`, { mode: 0o755 });
  const calls = join(root, "calls");
  return {
    root,
    calls,
    run: (exit = "0") => Bun.spawnSync(["bash", join(root, "Scripts/check_public_import_consumers.sh")], {
      env: { ...process.env, PATH: `${join(root, "bin")}:${process.env.PATH}`, IMPORT_TEST_CALLS: calls, IMPORT_TEST_EXIT: exit },
      stdout: "pipe", stderr: "pipe",
    }),
  };
}

test("consumer checks never reuse another invocation's incremental state", () => {
  const f = fixture();
  try {
    for (let i = 0; i < 2; i++) expect(f.run().exitCode).toBe(0);
    const paths = readFileSync(f.calls, "utf8").trim().split("\n");
    expect(paths).toHaveLength(4);
    expect(new Set(paths).size).toBe(4);
    expect(new Set(paths.map(dirname)).size).toBe(2);
    for (const path of paths) expect(existsSync(path)).toBe(false);
  } finally {
    rmSync(f.root, { recursive: true, force: true });
  }
});

test("a failed consumer preserves its build state and original failure", () => {
  const f = fixture();
  try {
    const result = f.run("23");
    expect(result.exitCode).toBe(23);
    const path = readFileSync(f.calls, "utf8").trim();
    expect(existsSync(join(path, ".build/seen"))).toBe(true);
    expect(result.stderr.toString()).toContain(dirname(path));
    expect(result.stderr.toString()).toContain("Failed consumer state retained");
    expect(f.run().exitCode).toBe(0);
    expect(existsSync(join(path, ".build/seen"))).toBe(true);
  } finally {
    rmSync(f.root, { recursive: true, force: true });
  }
});
