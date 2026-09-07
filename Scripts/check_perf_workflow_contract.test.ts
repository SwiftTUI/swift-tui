import { expect, test } from "bun:test";
import { requiredPerfPaths, validatePerfWorkflow } from "./check_perf_workflow_contract.ts";

function workflow() {
  return {
    on: {
      push: { paths: [...requiredPerfPaths] as string[] },
      pull_request: { paths: [...requiredPerfPaths] as string[] },
    },
  };
}

test("accepts the full dependency closure and unfiltered triggers", () => {
  expect(validatePerfWorkflow(workflow())).toEqual([]);
  expect(validatePerfWorkflow({ on: { push: null, pull_request: {} } })).toEqual([]);
});

for (const event of ["push", "pull_request"] as const) {
  for (const path of ["Sources/**", "Platforms/**", "Tests/**", "Scripts/**"] as const) {
    test(`${event} cannot delegate tests while omitting ${path}`, () => {
      const value = workflow();
      value.on[event].paths = value.on[event].paths.filter((entry) => entry !== path);
      expect(validatePerfWorkflow(value)).toEqual([
        `${event}: missing dependency path ${path}`,
      ]);
    });
  }
}

test("rejects absent events and exclusions that hide source changes", () => {
  expect(validatePerfWorkflow({ on: { workflow_dispatch: null } })).toHaveLength(2);
  const value = workflow();
  value.on.push.paths.push("!Sources/SwiftTUIRuntime/**");
  expect(validatePerfWorkflow(value)).toContain(
    "push: negative path filters can exclude framework work",
  );
  expect(validatePerfWorkflow({ on: { push: { "paths-ignore": ["Sources/**"] }, pull_request: {} } }))
    .toContain("push: review exclusions before narrowing performance coverage");
});
