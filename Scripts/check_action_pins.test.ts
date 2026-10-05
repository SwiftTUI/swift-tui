import { expect, test } from "bun:test";
import { parse } from "yaml";
import { unpinnedActions } from "./check_action_pins.ts";

test("accepts local actions, first-party actions, and third-party commit pins", () => {
  expect(unpinnedActions({ jobs: { test: { steps: [
    { uses: "./.github/actions/local" }, { uses: "actions/checkout@v7" },
    { uses: `owner/repo/subpath@${"a".repeat(40)}` },
  ] } } })).toEqual([]);
});
test("rejects tags and short SHAs in steps, reusable workflows and composites", () => {
  const doc = parse(`jobs:
  reuse:
    uses: owner/repo/.github/workflows/ci.yml@main
  build:
    steps:
      - uses: oven-sh/setup-bun@v2
runs:
  steps:
    - uses: owner/repo@abcdef0
`);
  expect(unpinnedActions(doc)).toEqual([
    "owner/repo/.github/workflows/ci.yml@main", "oven-sh/setup-bun@v2", "owner/repo@abcdef0",
  ]);
});
