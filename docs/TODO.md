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

- Decide whether command collisions across different scope kinds need a
  precedence rule beyond the current shallowest-wins focus-chain dispatch. See
  [proposals/ACTION_SCOPES_AND_COMMANDS.md](proposals/ACTION_SCOPES_AND_COMMANDS.md).
- Decide whether state-predicate command scopes need first-class authoring DSL
  surface or should remain implicit through their anchor nodes. See
  [proposals/ACTION_SCOPES_AND_COMMANDS.md](proposals/ACTION_SCOPES_AND_COMMANDS.md).

## Planned Work

- Retire the CI-only Swift test quarantine in
  [.github/workflows/run-tests-linux.yml](../.github/workflows/run-tests-linux.yml)
  by stabilizing the named flaky runtime, socket readiness, terminal latency,
  WebHost byte-sink, and gallery terminal-host tests that currently require
  `STUI_SWIFT_TEST_SKIP_REGEX` in the external repo gates.
- Scope the host-native text input contract for value/selection transport and
  IME/composition before promoting those behaviors beyond current terminal and
  browser clipboard support. See
  [proposals/TEXT_INPUT_MODEL.md](proposals/TEXT_INPUT_MODEL.md).
- Define the restart/reattach contract for `SwiftTUITerminalWorkspace` before
  adding persisted child-process reattachment.
