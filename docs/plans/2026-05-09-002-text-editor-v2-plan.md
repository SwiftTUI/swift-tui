---
title: "feat: text editor v2"
type: feature
status: active
date: 2026-05-09
depends_on:
  - "../proposals/TEXT_INPUT_MODEL.md"
  - "2026-05-06-001-text-input-model-v1-plan.md"
---

# TextEditor V2 Plan

**Goal:** Turn the V1 text-input model into a more complete editing substrate
for `TextEditor` without prematurely publicizing storage or host-transport
APIs. V2 should proceed in slices that keep `TextField`, `SecureField`, and
`TextEditor` sharing the same package-private reducer wherever behavior
overlaps.

**Current status:** The first V2 slice is shipped in this branch: word
movement/deletion and select-all now flow through shared text-input commands and
the composed `TextEditor` key-handler path.

## Boundaries

- Keep public text controls on `Binding<String>` until storage, host transport,
  and composition behavior have enough implementation evidence.
- Keep editor commands package-private unless a host or authoring API needs a
  public contract.
- Preserve grapheme-cluster offsets internally. Add UTF-16 or platform-specific
  conversion only at host boundaries.
- Do not treat terminal raw-key support as proof of native/web host behavior.
  IME and value/selection transport need host-specific design.
- Keep secure input privacy intact: selection, clipboard, semantics, logs, and
  host transport must not leak secure values.

## Stages

- [x] **Shortcut foundation.** Add shared word-boundary movement, word
  deletion, and select-all commands. Map alt/ctrl left/right to word movement,
  alt/ctrl backspace to word deletion, and ctrl-a to select-all where the
  focused text input receives those key presses. Cover the pure reducer and the
  composed `TextEditor` runtime path.
- [ ] **Visible range selection.** Render non-collapsed selections in
  `TextInputContent` using the existing `TextInputLayoutMap`. Pin multiline
  selections, wrapped lines, secure redaction, focused/unfocused rendering, and
  accessibility caret behavior with focused tests.
- [ ] **Clipboard command routing.** Decide copy/cut/select-all routing against
  the runtime's exit-binding precedence. Add explicit command routing only after
  the policy says when text inputs may consume ctrl-c, ctrl-x, ctrl-a, and
  paste-like shortcuts.
- [ ] **Host value and selection transport.** Define the selection wire model
  for Web/WASI and SwiftUI hosts, including grapheme-to-host offset conversion,
  secure-field suppression, host-originated edits, and synchronization with
  graph-scoped `TextInputValue`.
- [ ] **Composition and IME.** Use `composingRange` as the shared model point,
  but design per-host input events before adding public API. Terminal support
  should document raw-input limits instead of pretending to reproduce platform
  IME.
- [ ] **Large-document storage.** Evaluate rope or piece-tree storage behind
  the reducer after selection rendering and host transport define the required
  access patterns. Public custom storage should come after the internal storage
  seam has real performance and host evidence.

## Validation

- Red checkpoint: `swiftly run swift test --filter SwiftTUIViewsTests.TextInputReducerTests`
  failed before implementation because `TextInputCommand.selectAll` did not
  exist.
- Green checkpoint: `swiftly run swift test --filter SwiftTUIViewsTests.TextInputReducerTests`
  passes the shared reducer shortcut coverage.
- Green checkpoint: `swiftly run swift test --filter SwiftTUITests.TextEditorSurfaceTests/textEditorHandlesWordShortcutsAndSelectAll`
  passes the composed `TextEditor` shortcut path.
- Final gate: `bun run test` passes all policy checks, root SwiftPM tests,
  platform package tests, example package tests, and perf-tool tests.
