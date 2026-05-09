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

- [ ] Design popover-style presentation. The shipped presentation surface covers
  `alert`, `confirmationDialog`, `sheet`, `paletteSheet`, `toast`, and `Menu`,
  but there is no public popover API. Work should first decide whether popovers
  are anchored non-modal overlays, menu-like intrinsic surfaces, sheet chrome
  variants, or an explicit non-goal; then pin focus/action-scope behavior,
  dismissal, anchor placement, and terminal fallback layout. Supporting docs:
  [VISION.md](VISION.md),
  [proposals/ACTION_SCOPES_AND_COMMANDS.md](proposals/ACTION_SCOPES_AND_COMMANDS.md).
- [ ] Design the first-class terminal workspace surface. `TerminalView` already
  embeds one terminal program in one view, but there is no official
  Zellij-style workspace layer for tabs, split-pane identity, pane commands,
  session retention, persistence, or reattach semantics. Start from the scoped
  proposal and produce an evidence example before committing broad public API.
  Supporting docs: [proposals/TERMINAL_WORKSPACE.md](proposals/TERMINAL_WORKSPACE.md),
  [EMBEDDING.md](EMBEDDING.md),
  [TERMINAL_NATIVE_DOCTRINE.md](TERMINAL_NATIVE_DOCTRINE.md),
  [TERMINAL_NATIVE_UX_RESEARCH.md](TERMINAL_NATIVE_UX_RESEARCH.md).
- [ ] Implement deeper scroll control V1. The scope pass recommends starting
  with a `ScrollViewReader` / `ScrollViewProxy` model for identity and anchor
  based scrolling, plus home/end policy, while deferring semantic
  `ScrollPosition` binding, target behavior, scrollback conventions, and host
  observation hooks. Supporting docs:
  [plans/2026-05-09-003-deeper-scroll-control-scope.md](plans/2026-05-09-003-deeper-scroll-control-scope.md),
  [SOURCE_LAYOUT.md](SOURCE_LAYOUT.md),
  [TERMINAL_NATIVE_DOCTRINE.md](TERMINAL_NATIVE_DOCTRINE.md).
