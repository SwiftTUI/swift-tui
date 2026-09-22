# Test ownership and source observations

The root SwiftPM manifest owns target membership. Core tests cover rendering
phase products and commit contracts, including their Graph inputs. Views tests
cover authored views, controls, styles and gesture recognizers against Core.
Runtime tests cover composed renderer/run-loop/host behavior, source policies,
public import contracts and shared consumer fixtures used in runtime journeys.
Graph-only ownership is unchanged.

`Scripts/data/test-ownership.json` records the category and reason for each
test source containing `@Test`. This is a source-file census, not a replacement
for Swift Testing discovery: one file may contain multiple suites or parameterized
tests. New files without reviewed entries appear as **unclassified**. Review
their behavior and helper dependencies before assigning ownership; an import
alone is insufficient. The three consumer style-reuse files share the same
public-import fixtures as runtime interaction tests and intentionally remain
with those fixtures. Support synchronization tests remain with their consumers.

`DefaultRenderer` lives in `Sources/SwiftTUIRuntime/DefaultRenderer.swift`.
It composes runtime stages; the Core target owns their rendering products and
algorithms. The renderer's type and API were not changed by this file rename.

## Refresh and compare

Run `python3 Scripts/source_inventory.py` to refresh
[`source-structure.json`](source-structure.json) and its readable
[`source-structure.md`](source-structure.md). Review the diff, including newly
unclassified test sources, before committing it. There is no size ceiling or
automatic splitting requirement.

The census calls `swiftly run swift package describe --type json`, so custom
target paths and production support targets under `Tests/` are attributed by
SwiftPM, not directory assumptions. It counts physical source lines, including
comments and blanks, and includes all file types SwiftPM lists as sources.
Vendor paths/targets and files with a generated header in the first eight
lines are excluded with an explicit reason. Resources, build outputs and
dependency checkouts are not in the manifest's source lists. Conditional
targets follow the platform on which SwiftPM evaluates the manifest.

The source revision is the base checkout's HEAD; per-file SHA-256 values
identify the actual census, including edits made before the refresh commit.
No timestamps or absolute checkout paths enter the output.

To compare a saved base with the live head:

```sh
git show origin/main:docs/source-structure.json > /tmp/source-base.json
python3 Scripts/source_inventory.py --compare /tmp/source-base.json --output .build/source-head.json
```

The `.diff.json` and Markdown show additions, deletions, content changes,
same-path target moves and unique identical-content renames. A renamed **and
edited** file is conservatively an addition/deletion; inspect the accompanying
`git diff --find-renames`. Ambiguous identical files are not guessed as renames.
The pure comparison accepts any two saved censuses; it does not require a
particular Git branch or network access.

Linux core and macOS CI append these observations to their job summaries and
upload the JSON/Markdown artifacts. Findings are advisory; malformed manifests
or a broken reporting command remain ordinary infrastructure errors.
`python3 Scripts/test_source_inventory.py` verifies an independent manifest
census, custom production paths, exclusions, unknown classification, repeatable
output, additions/deletions/renames, edits and target moves. The policy lane
runs these checks without needing Swift.

For execution ownership, `swiftly run swift test list` is authoritative.
`Scripts/check_root_test_target_coverage.sh` checks every manifest test target
and the runtime shard partition. The runtime lane uses first-match filters and
explicit skips, so isolated suites execute in core and every other runtime
suite executes in exactly one shard.
