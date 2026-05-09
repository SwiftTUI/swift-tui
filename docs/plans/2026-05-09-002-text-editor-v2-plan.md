---
title: "feat: text editor v2"
type: feature
status: shipped
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

**Current status:** Shipped. `TextEditor` now uses the shared V2 shortcut
foundation and renders focused range selections through the shared text-input
presentation path. Clipboard copy/cut now writes through terminal, hosted,
SwiftUI, Web/WASI, and embedding host adapters. Host-native value/selection
transport, IME/composition, and large-document storage remain explicitly
deferred until the repo has the relevant host-event or performance evidence.

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
- [x] **Visible range selection.** Render non-collapsed selections in
  `TextInputContent` using the existing `TextInputLayoutMap`. Pin multiline
  selections, wrapped lines, secure redaction, focused/unfocused rendering, and
  accessibility caret behavior with focused tests.
- [x] **Clipboard command routing.** Decide copy/cut/select-all routing against
  the runtime's exit-binding precedence. Current policy: focused text inputs may
  consume `ctrl-a` for select-all; the default exit binding is `ctrl-d`;
  `ctrl-c` / `ctrl-x` perform host-backed copy/cut for focused text inputs; and
  secure fields suppress clipboard text.
- [x] **Host value and selection transport.** Define the selection wire model
  boundary for Web/WASI and SwiftUI hosts. Current decision: do not add public
  or wire-level value/selection fields in this V2 tranche. A future host plan
  must define grapheme-to-host offset conversion, secure-field suppression,
  host-originated edits, and graph-scoped synchronization before adding API.
- [x] **Composition and IME.** Use `composingRange` as the shared model point,
  but design per-host input events before adding public API. Terminal support
  documents the raw-input limit; native/web hosts need their own composition
  event contract before SwiftTUI exposes composition.
- [x] **Large-document storage.** Evaluate rope or piece-tree storage behind
  the reducer after selection rendering and host transport define the required
  access patterns. Current decision: keep `String` storage behind
  `Binding<String>` until real large-document workloads or host transport
  requirements justify a package-private rope/piece-tree seam.

## Validation

- Red checkpoint: `swiftly run swift test --filter SwiftTUIViewsTests.TextInputReducerTests`
  failed before implementation because `TextInputCommand.selectAll` did not
  exist.
- Green checkpoint: `swiftly run swift test --filter SwiftTUIViewsTests.TextInputReducerTests`
  passes the shared reducer shortcut coverage.
- Green checkpoint: `swiftly run swift test --filter SwiftTUITests.TextEditorSurfaceTests/textEditorHandlesWordShortcutsAndSelectAll`
  passes the composed `TextEditor` shortcut path.
- Red checkpoint: `swiftly run swift test --filter SwiftTUIViewsTests.TextInputLayoutMapTests`
  failed before implementation because `TextInputPresentation` did not expose
  styled display runs for selected ranges.
- Green checkpoint: `swiftly run swift test --filter SwiftTUIViewsTests.TextInputLayoutMapTests`
  passes selection rect coverage for multiline, wrapped, focused/unfocused, and
  secure-projected input.
- Green checkpoint: `swiftly run swift test --filter SwiftTUITests.TextEditorSurfaceTests`
  passes composed `TextEditor` range-selection rendering.
- Green checkpoint: `swiftly run swift test --filter SwiftTUITests.TextInputRuntimeIntegrationTests`
  pins `ctrl-a` select-all routing, host-backed copy/cut, secure-field
  suppression, and `ctrl-d` default-exit precedence for focused `TextEditor`.
- Final gate: `bun run test` passes all policy checks, root SwiftPM tests,
  platform package tests, example package tests, and perf-tool tests.
