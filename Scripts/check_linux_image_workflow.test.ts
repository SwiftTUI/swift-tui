import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { parse } from "yaml";
import { validateLinuxImageWorkflow } from "./check_linux_image_workflow.ts";
const workflow = () => parse(readFileSync(new URL("../.github/workflows/build-linux-image.yml", import.meta.url), "utf8"));

test("main-only image publication covers pushes, dispatch inputs, branches and tags", () => {
  expect(validateLinuxImageWorkflow(workflow())).toEqual([]);
});
test("rejects a dispatch that can publish from a feature branch", () => {
  const doc = workflow();
  doc.jobs.build.steps.find((s: any) => s.id === "push_decision").run =
    'printf "push=%s\\n" "$OVERRIDE" >> "$GITHUB_OUTPUT"';
  expect(validateLinuxImageWorkflow(doc).some((s) => s.includes("workflow_dispatch/refs/heads/feature/true"))).toBe(true);
});
test("rejects unguarded stable manifest and registry cache writes", () => {
  const doc = workflow();
  doc.jobs.merge.if = "needs.build.result == 'success'";
  doc.jobs.build.steps.find((s: any) => s.with?.["cache-to"]).if = "always()";
  expect(validateLinuxImageWorkflow(doc)).toHaveLength(2);
});

test("rejects loss of weekly rebuilding or base/package refresh", () => {
  const doc = workflow();
  delete doc.on.schedule;
  const steps = doc.jobs.build.steps.filter((s: any) => s.uses?.startsWith("docker/build-push-action@"));
  delete steps[0].with.pull;
  steps[1].with["no-cache"] = false;
  expect(validateLinuxImageWorkflow(doc)).toHaveLength(3);
});
