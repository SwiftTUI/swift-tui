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

## Runtime And Public Surface Gaps

- [ ] Turn the current constraints in `STATUS.md` into executable plans or
  explicitly defer them: default-focus scopes, `@FocusedObject`, richer
  `TextEditor`, `NavigationStack`, popover-style presentation, terminal
  workspaces, deeper scroll control, and navigation surfaces. Supporting docs:
  [STATUS.md](STATUS.md),
  [VISION.md](VISION.md),
  [FOCUS.md](FOCUS.md).
  Ambiguity note: park this for later investigation. Some listed constraints
  may already be obsolete, so this remains a prioritization pass rather than a
  single implementation task.
