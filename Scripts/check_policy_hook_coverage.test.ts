import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { standalonePolicyCommands, uncoveredPolicyHooks } from "./check_policy_hook_coverage.ts";
const config = () => Bun.TOML.parse(readFileSync(new URL("../prek.toml", import.meta.url), "utf8")) as any;
const commands = () => standalonePolicyCommands(fileURLToPath(new URL("lib/repo_policy_checks.sh", import.meta.url)));

test("every configured system policy hook runs without prek", () => {
  expect(uncoveredPolicyHooks(config(), commands())).toEqual([]);
});
test("removing a standalone step leaves its hook uncovered", () => {
  for (const hook of config().repos.flatMap((r: any) => r.hooks)) {
    if (hook.language !== "system" || hook.id === "swift-format") continue;
    expect(uncoveredPolicyHooks(config(), commands().filter((command) => command !== hook.entry))).toContain(hook.id);
  }
});
test("a new system hook or repurposed format exception must be covered", () => {
  const value = config();
  value.repos.push({ repo: "local", hooks: [{ id: "new-policy", language: "system", entry: "sh Scripts/new_policy.sh" }] });
  const formatter = value.repos.flatMap((r: any) => r.hooks).find((h: any) => h.id === "swift-format");
  formatter.entry = "sh Scripts/different_policy.sh";
  expect(uncoveredPolicyHooks(value, commands())).toEqual(["swift-format", "new-policy"]);
});
