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

## Unresolved Decisions

- Decide whether historical plans and proposals may retain stale source paths as
  historical records, or whether all tracked docs must remain path-current. See
  [../Scripts/check_stable_doc_source_paths.sh](../Scripts/check_stable_doc_source_paths.sh).
- Decide whether current example surface and test-scope language is enough, or
  whether examples need formal support tiers such as flagship, regression,
  integration reference, and experimental. See
  [../Examples/README.md](../Examples/README.md).
- Decide whether the project name remains `SwiftTUI` despite ecosystem name
  collisions. If it stays, add a concise README distinction from similarly named
  Swift terminal UI projects. See [../README.md](../README.md).
- Decide whether to delete or move the historical `0.0.1` tag, or preserve it
  with the current release-policy warning. See [RELEASES.md](RELEASES.md).
- Decide whether command collisions across different scope kinds need a
  precedence rule beyond the current shallowest-wins focus-chain dispatch. See
  [proposals/ACTION_SCOPES_AND_COMMANDS.md](proposals/ACTION_SCOPES_AND_COMMANDS.md).
- Decide whether state-predicate command scopes need first-class authoring DSL
  surface or should remain implicit through their anchor nodes. See
  [proposals/ACTION_SCOPES_AND_COMMANDS.md](proposals/ACTION_SCOPES_AND_COMMANDS.md).

## Planned Work

- Re-enable `NeverUseForceTry` once the remaining call sites are audited. See
  [../.swift-format.json](../.swift-format.json).
- Continue reducing duplicated phase metadata between resolved and placed nodes
  after the synchronized-mirror policy is in place. Cover retained-layout and
  late-preference behavior before changing the shared structure. See
  [ARCHITECTURE.md](ARCHITECTURE.md).
- Apply the historical-doc path policy once decided: either archive historical
  plans clearly or keep the stable-doc source-path checker focused on current
  source-of-truth docs. See
  [../Scripts/check_stable_doc_source_paths.sh](../Scripts/check_stable_doc_source_paths.sh).
- If formal example support tiers are adopted, update the examples index with
  the agreed tier labels while keeping the current gate-vs-exhaustive test-scope
  caveat. See [../Examples/README.md](../Examples/README.md).
- Scope the host-native text input contract for value/selection transport and
  IME/composition before promoting those behaviors beyond current terminal and
  browser clipboard support. See
  [proposals/TEXT_INPUT_MODEL.md](proposals/TEXT_INPUT_MODEL.md).
- Define the restart/reattach contract for `SwiftTUITerminalWorkspace` before
  adding persisted child-process reattachment.
- [ ] BUG: the cursor is positioned off by a line in the gallery demo's Multiline editor
