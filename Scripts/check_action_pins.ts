import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parse } from "yaml";

export function unpinnedActions(document: unknown): string[] {
  const failures: string[] = [];
  function visit(value: unknown) {
    if (!value || typeof value !== "object") return;
    for (const [key, child] of Object.entries(value)) {
      if (key === "uses") {
        if (typeof child !== "string") failures.push(String(child));
        else if (!child.startsWith("actions/") && !child.startsWith("./") &&
                 !/^[\w.-]+\/[\w./-]+@[0-9a-f]{40}$/i.test(child)) failures.push(child);
      } else visit(child);
    }
  }
  visit(document);
  return failures;
}

if (import.meta.main) {
  const roots = process.argv.slice(2);
  if (!roots.length) roots.push(fileURLToPath(new URL("../.github", import.meta.url)));
  const failures: string[] = [];
  for (const root of roots) {
    for (const path of new Bun.Glob("**/*.{yml,yaml}").scanSync(root)) {
      for (const action of unpinnedActions(parse(readFileSync(resolve(root, path), "utf8")))) {
        failures.push(`${root}/${path}: third-party action must use a full commit SHA: ${action}`);
      }
    }
  }
  if (failures.length) {
    console.error(failures.join("\n"));
    process.exitCode = 1;
  } else console.log("[action_pins] third-party actions use immutable commit SHAs");
}
