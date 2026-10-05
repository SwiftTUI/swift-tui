import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { parse } from "yaml";

export function validateLinuxImageWorkflow(document: any): string[] {
  const failures: string[] = [];
  if (!document?.on?.schedule?.some((entry: any) => entry.cron === "23 7 * * 1")) {
    failures.push("Linux image must rebuild weekly on Monday at 07:23 UTC");
  }
  const build = document?.jobs?.build;
  const merge = document?.jobs?.merge;
  const steps = build?.steps ?? [];
  const decision = steps.find((step: any) => step.id === "push_decision");
  const pushGuard = "steps.push_decision.outputs.push == 'true'";
  const mergeGuard = "needs.build.result == 'success' && needs.build.outputs.push == 'true' && github.ref == 'refs/heads/main'";
  if (build?.outputs?.push !== "${{ steps.push_decision.outputs.push }}") {
    failures.push("build must export its guarded push decision");
  }
  if (merge?.if?.replace(/\s+/g, " ").trim() !== mergeGuard) {
    failures.push("manifest publication must require the main branch and the build push decision");
  }
  for (const step of steps) {
    if (step.uses?.startsWith("docker/build-push-action@") &&
        (step.with?.pull !== true || step.with?.["no-cache"] !== "${{ github.event_name == 'schedule' }}")) {
      failures.push(`${step.name}: scheduled builds must pull the base and bypass cached package layers`);
    }
    if (step.with?.["cache-to"] || step.with?.outputs?.includes("push=true") || step.with?.push === true) {
      if (step.if !== pushGuard) failures.push(`${step.name}: image/cache publication must use the push guard`);
    }
  }
  if (decision?.env?.EVENT_NAME !== "${{ github.event_name }}" ||
      decision?.env?.REF !== "${{ github.ref }}" ||
      decision?.env?.OVERRIDE !== "${{ inputs.push }}" || typeof decision?.run !== "string") {
    return [...failures, "push decision must read the event, full ref, and input through env"];
  }
  const scratch = mkdtempSync(join(tmpdir(), "linux-image-policy-"));
  try {
    for (const event of ["push", "pull_request", "workflow_dispatch", "schedule"])
      for (const ref of ["refs/heads/main", "refs/heads/feature", "refs/tags/main"])
        for (const override of ["true", "false", ""]) {
          const output = join(scratch, `${event}-${ref.replaceAll("/", "_")}-${override}`);
          const result = spawnSync("bash", ["-c", decision.run], {
            env: { PATH: process.env.PATH, EVENT_NAME: event, REF: ref, OVERRIDE: override, GITHUB_OUTPUT: output },
            encoding: "utf8",
          });
          const expected = ref === "refs/heads/main" &&
            (event === "push" || event === "schedule" || (event === "workflow_dispatch" && override === "true"));
          const actual = result.status === 0 ? readFileSync(output, "utf8").trim() : result.stderr;
          if (actual !== `push=${expected}`) failures.push(`${event}/${ref}/${override}: expected push=${expected}, got ${actual}`);
        }
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
  return failures;
}

if (import.meta.main) {
  const file = new URL("../.github/workflows/build-linux-image.yml", import.meta.url);
  const failures = validateLinuxImageWorkflow(parse(readFileSync(file, "utf8")));
  if (failures.length) {
    console.error(failures.join("\n"));
    process.exitCode = 1;
  } else console.log("[linux_image_workflow] publication is restricted to main");
}
