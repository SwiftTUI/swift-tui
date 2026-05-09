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

- [ ] Continue the `TextEditor` V2 plan after the shipped shortcut foundation.
  Next slices are visible selection rendering, clipboard command routing, host
  value/selection transport, IME/composition, and large-document storage.
  Supporting docs:
  [plans/2026-05-09-002-text-editor-v2-plan.md](plans/2026-05-09-002-text-editor-v2-plan.md),
  [plans/2026-05-06-001-text-input-model-v1-plan.md](plans/2026-05-06-001-text-input-model-v1-plan.md),
  [proposals/TEXT_INPUT_MODEL.md](proposals/TEXT_INPUT_MODEL.md).
- [ ] Design the `NavigationStack` / route surface. `TabView` has shipped and
  ActionScope is ready to treat destinations as scopes, but there is no
  `NavigationStack`, `NavigationLink`, or route-driven selection model. Start
  with a terminal-native route design before adding API: destination identity,
  back-stack rendering, focus restoration, command scope activation, and how
  list selection differs when it drives navigation. Supporting docs:
  [VISION.md](VISION.md),
  [FOCUS.md](FOCUS.md),
  [proposals/ACTION_SCOPES_AND_COMMANDS.md](proposals/ACTION_SCOPES_AND_COMMANDS.md).
- [ ] Design popover-style presentation. The shipped presentation surface covers
  `alert`, `confirmationDialog`, `sheet`, `paletteSheet`, `toast`, and `Menu`,
  but there is no public popover API. Work should first decide whether popovers
  are anchored non-modal overlays, menu-like intrinsic surfaces, sheet chrome
  variants, or an explicit non-goal; then pin focus/action-scope behavior,
  dismissal, anchor placement, and terminal fallback layout. Supporting docs:
  [VISION.md](VISION.md),
  [proposals/ACTION_SCOPES_AND_COMMANDS.md](proposals/ACTION_SCOPES_AND_COMMANDS.md).
- [ ] Define the first-class terminal workspace surface. The repo has `TabView`,
  custom layouts, multi-scene manifests, terminal embedding, and examples that
  can compose workspace-like UIs, but there is no explicit workspace/pane/session
  authoring API. Decide whether the next step is docs and examples, split-pane
  primitives, host shell chrome, session persistence, or a smaller scoped subset.
  Supporting docs: [TERMINAL_NATIVE_DOCTRINE.md](TERMINAL_NATIVE_DOCTRINE.md),
  [TERMINAL_NATIVE_UX_RESEARCH.md](TERMINAL_NATIVE_UX_RESEARCH.md),
  [proposals/TERMINAL_EMBEDDING.md](proposals/TERMINAL_EMBEDDING.md).
- [ ] Scope deeper scroll control. `ScrollView` has public `ScrollPosition`,
  binding-backed offsets, indicators, keyboard scrolling, pointer scrolling, and
  caret/focus reveal, but it lacks a higher-level scroll reader/proxy model.
  Decide which controls matter next: scroll-to-identity, anchor-based scrolling,
  page/home/end policy, scrollback and preview conventions, or host transport
  hooks. Supporting docs: [SOURCE_LAYOUT.md](SOURCE_LAYOUT.md),
  [TERMINAL_NATIVE_DOCTRINE.md](TERMINAL_NATIVE_DOCTRINE.md).
- [ ] Reconcile navigation-surface taxonomy. The repo now has focus traversal,
  list/table selection, `TabView`, command scopes, scene attachment, and semantic
  navigation-route placeholders, but no single document says which navigation
  concepts are first-class and which are composed patterns. Produce a short plan
  that separates route navigation, mode/tab switching, pane/workspace switching,
  command-palette discovery, and ordinary focus movement before implementing more
  public navigation API. Supporting docs: [VISION.md](VISION.md),
  [FOCUS.md](FOCUS.md),
  [TERMINAL_NATIVE_DOCTRINE.md](TERMINAL_NATIVE_DOCTRINE.md).
