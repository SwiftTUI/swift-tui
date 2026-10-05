import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

export function standalonePolicyCommands(script: string): string[] {
  // Observe the shared phase's actual dispatch without running its checks.
  const result = Bun.spawnSync(["sh", "-c", `
    . "$1"
    run_repo_policy_check() {
      shift 4
      printf 'POLICY_COMMAND:'
      printf '%s ' "$@"
      printf '\\n'
    }
    run_repo_policy_phase . direct
  `, "policy-coverage", script]);
  if (result.exitCode !== 0) throw new Error(result.stderr.toString());
  return result.stdout.toString().split("\n")
    .filter((line) => line.startsWith("POLICY_COMMAND:"))
    .map((line) => line.slice("POLICY_COMMAND:".length).trim());
}

export function uncoveredPolicyHooks(config: any, commands: string[]): string[] {
  const missing: string[] = [];
  for (const repo of config.repos ?? []) for (const hook of repo.hooks ?? []) {
    if (hook.language !== "system") continue;
    // Formatting is deliberately commit-time only: it rewrites staged files.
    // This exact exception cannot silently exempt a different formatter/check.
    if (hook.id === "swift-format" &&
        hook.entry === "swift format format -i --configuration .swift-format.json") continue;
    if (!commands.includes(hook.entry)) missing.push(hook.id);
  }
  return missing;
}

if (import.meta.main) {
  const config = Bun.TOML.parse(readFileSync(new URL("../prek.toml", import.meta.url), "utf8"));
  const commands = standalonePolicyCommands(fileURLToPath(new URL("lib/repo_policy_checks.sh", import.meta.url)));
  const missing = uncoveredPolicyHooks(config, commands);
  if (missing.length) {
    console.error(`System hooks missing standalone policy steps: ${missing.join(", ")}`);
    process.exitCode = 1;
  } else console.log("[policy_hook_coverage] every system policy hook is covered; formatting is commit-time only");
}
