# TODO

## Rules

- Keep this document up to date whenever planned work or unresolved decisions
  are added, completed, or re-scoped.
- Include only planned work and unresolved decisions. Do not include completed,
  explicitly deferred, or rejected items.
- Use concise task descriptions with links to supporting docs, plans, source
  files, or tests.
- Remove completed work from this document entirely.
- When removing completed work, add a concise self-standing entry to
  [CHANGELOG.md](CHANGELOG.md). Keep long-form details in the supporting docs,
  plans, source, or tests.
- Changelog entries may link to long-lived repo documentation, but every link
  must be prefixed with the short git hash that anchors the referenced material,
  for example: `4ee7a8f9 [STATUS.md](STATUS.md)`.
- Treat this file as additive to the repo documentation structure. It does not
  replace durable docs, proposals, ADRs, plans, or tests.
- Use this file as the first place to check what is next.
- `STATUS.md` may summarize goals, shipped surface, constraints, and
  deferred-by-design areas. Any gap or goal in `STATUS.md` that is
  planned, actively investigated, or awaiting a decision must have a
  corresponding item here. If there is no item here, the status text should make
  clear that the topic is shipped, contextual, or explicitly deferred.

## Active Investigations

- Decide which local-browser WebHost polish should follow v1, using
  [proposals/LOCAL_BROWSER_HOST_LEARNINGS.md](proposals/LOCAL_BROWSER_HOST_LEARNINGS.md)
  as the investigation record.
- Decide whether to split `Platforms/Web` into consumable browser/runtime and
  build packages such as `@swifttui/web` and `@swifttui/build`, using
  [proposals/PLATFORMS_WEB_CONSUMABLE_PACKAGES.md](proposals/PLATFORMS_WEB_CONSUMABLE_PACKAGES.md)
  as the investigation record.
