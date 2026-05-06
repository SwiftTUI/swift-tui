---
title: "feat: text input model v1"
type: feature
status: shipped
date: 2026-05-06
depends_on:
  - "../proposals/TEXT_INPUT_MODEL.md"
  - "../proposals/ACCESSIBILITY.md"
  - "../decisions/0013-accessibility-runtime-policy.md"
---

# Text Input Model V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking. Keep commits scoped to stages that reach a green checkpoint. This
> plan touches shared input, styling, semantics, runtime paste dispatch, and
> accessibility cursor policy; finish with `bun run test --skip-bun-install`
> before calling the work complete.

**Goal:** Replace the current append-only text-entry path with a shared,
grapheme-safe text input value, reducer, layout map, presentation primitive,
and caret-anchor semantic foundation for `TextField`, `SecureField`, and
`TextEditor`.

**Architecture:** Keep the public authoring API as `Binding<String>` in V1,
but store package-private `TextInputValue` state inside each text control. All
key, paste, and caret operations flow through a pure reducer; rendering uses a
text-input content primitive that publishes a caret anchor; semantic extraction
hoists that anchor onto the focused accessibility node.

**Tech Stack:** Swift 6.3 strict concurrency, strict memory safety,
`SwiftTUIViews` input controls, `SwiftTUICore` runtime registries and semantic
extraction, `TextLayout`/cell-width helpers, Swift Testing, snapshot surface
tests, public API inventory tooling, and the repo-wide `bun run test` gate.

---

## Starting State Snapshot

This was the text input state before the V1 implementation. It is retained as
the baseline the plan replaced:

- `TextField` lives in `Sources/SwiftTUIViews/Controls/ValueControls.swift`.
  It registers `registerTextEntryBinding(...)`, renders `displayText`, and
  appends a synthetic trailing `_` while focused.
- `SecureField` lives in `Sources/SwiftTUIViews/Input/SecureField.swift`. It
  reuses the same binding mutation path and masks display text.
- `TextEditor` lives in `Sources/SwiftTUIViews/Input/TextEditor.swift`. It
  registers `registerMultilineTextEntryBinding(...)`, keeps a
  `ScrollPosition`, and renders the same synthetic trailing `_`.
- `mutateTextEntryBinding(...)` in
  `Sources/SwiftTUIViews/Controls/SelectionAndValueSupport.swift` appends
  character input, removes the last character on backspace, appends `\n` for
  multiline return, scrolls on up/down, and consumes left/right without moving
  a caret.
- `RunLoop.handlePaste(...)` in
  `Sources/SwiftTUI/RunLoop/RunLoop+EventDispatch.swift` falls through from
  non-drop paste into repeated character key events.
- `SemanticMetadata.accessibilityCursorAnchor` and
  `AccessibilityNode.cursorAnchor` already existed in `SwiftTUICore`, but text
  controls did not publish real caret anchors.
- `RuntimeConfiguration.cursorFollowsFocus` is default-off and currently moves
  the hardware cursor to the focused accessibility node's `cursorAnchor` when
  one exists.

## V1 Boundary

### In Scope

- Package-private text input value, selection, offset, traits, commands, and
  reducer.
- Grapheme-cluster-safe insertion, deletion, replacement, and caret movement.
- Collapsed and non-collapsed selection in the model, even if visible selection
  painting remains basic.
- Single-line `TextField` and `SecureField` caret movement, insertion at caret,
  backspace before caret, home/end, and paste as one reducer command.
- Multiline `TextEditor` newline insertion, vertical movement, preferred visual
  column, caret-visible scroll adjustment, and multiline paste as one reducer
  command.
- Source-range-aware layout mapping from text offsets to terminal cell points.
- A reusable text-input field-content view for `TextFieldStyleConfiguration`.
- Real caret anchors in accessibility semantics for all three text input
  surfaces.
- Synthetic caret suppression when `RuntimeConfiguration.cursorFollowsFocus`
  is active.
- Secure-value redaction in display, semantics, snapshots, and tests.

### Out of Scope

- Rich text.
- Syntax highlighting.
- Multiple selections or multiple cursors.
- Full IME/composition behavior.
- Rope or piece-tree storage.
- Native/web host value and selection transport beyond existing cursor-anchor
  semantics.
- Public custom text storage.

## V1 Decisions From The Proposal

1. **Internal offset metric:** Use grapheme-cluster offsets internally. Add
   UTF-16 conversion helpers only where host bridges need them.
2. **Storage:** Use `String` as the authoritative V1 storage behind a focused
   package-private helper. Do not introduce a public storage protocol.
3. **Selection:** Store anchor/head immediately. V1 rendering may only draw a
   collapsed caret, but the reducer and layout APIs must support ranges.
4. **Scroll state:** Keep `TextEditor` scroll position as companion `@State`
   in V1. The reducer owns text, selection, composing range, and preferred
   visual column; the control applies caret-visible scrolling after layout.
5. **Paste:** Add a focused paste-handler path so bracketed paste becomes one
   reducer command after drop destinations decline it. Keep repeated key-event
   fallback only for non-text focused handlers.
6. **Text field styles:** Add a `fieldContent` view to
   `TextFieldStyleConfiguration` and preserve `displayText` for compatibility.
   Built-in styles must render `fieldContent`. Custom styles that continue to
   render `displayText` keep visual compatibility but cannot provide precise
   caret anchors until they adopt `fieldContent`.
7. **Semantics:** Do not add public value/selection fields to
   `AccessibilityNode` in V1. Use package-private caret-anchor metadata and
   the existing public `cursorAnchor` output.

## File Map

### Create

- `Sources/SwiftTUIViews/Input/TextInputTypes.swift`
  - `TextOffset`, `TextRange`, `TextSelection`, `TextInputValue`,
    `TextInputTraits`, `TextInputCommand`, `TextMovement`,
    `TextGranularity`, and mutation result types.
- `Sources/SwiftTUIViews/Input/TextInputStringMetrics.swift`
  - Grapheme-index conversion, line-boundary lookup, line/column metrics, word
    movement helpers, and UTF-16 bridge helpers.
- `Sources/SwiftTUIViews/Input/TextInputReducer.swift`
  - Pure command reducer with no runtime registry dependency.
- `Sources/SwiftTUIViews/Input/TextInputLayoutMap.swift`
  - Source-range-aware terminal-cell layout map and hit-testing helpers.
- `Sources/SwiftTUIViews/Input/TextInputPresentation.swift`
  - Display projection, secure masking, prompt behavior, synthetic-caret
    decision, selection rectangles, and caret anchor calculation.
- `Sources/SwiftTUIViews/Input/TextInputContent.swift`
  - Package-owned view rendered by text field styles and `TextEditor`.
- `Sources/SwiftTUIViews/Input/TextInputControlSupport.swift`
  - Shared reducer-backed key dispatch adapter for text input controls.
- `Tests/SwiftTUIViewsTests/TextInputReducerTests.swift`
  - Pure reducer coverage.
- `Tests/SwiftTUIViewsTests/TextInputLayoutMapTests.swift`
  - Offset-to-cell, cell-to-offset, wrapping, wide grapheme, secure masking,
    and prompt/caret presentation coverage.
- `Tests/SwiftTUITests/TextInputRuntimeIntegrationTests.swift`
  - Real control rendering and input dispatch coverage through
    `DefaultRenderer` and `RunLoop`.

### Modify

- `Sources/SwiftTUIViews/Controls/ValueControls.swift`
  - Move `TextField` to `TextInputValue` state and reducer-backed handlers.
- `Sources/SwiftTUIViews/Input/SecureField.swift`
  - Move `SecureField` to the same model with secure display projection.
- `Sources/SwiftTUIViews/Input/TextEditor.swift`
  - Move `TextEditor` to multiline model, layout map, and caret-visible scroll.
- `Sources/SwiftTUIViews/Controls/SelectionAndValueSupport.swift`
  - Delete or narrow the old append-only text-entry helpers after all controls
    have moved.
- `Sources/SwiftTUIViews/Controls/TextFieldStyles.swift`
  - Add `TextFieldStyleConfiguration.FieldContent` and update built-in styles.
- `Sources/SwiftTUIViews/Environment/RuntimePolicyEnvironment.swift`
  - Add package `cursorFollowsFocus`.
- `Sources/SwiftTUI/RunLoop/RunLoop+Rendering.swift`
  - Inject `runtimeConfiguration.cursorFollowsFocus` into environment values.
- `Sources/SwiftTUI/RunLoop/RunLoop+EventDispatch.swift`
  - Route non-drop paste to the focused text-input paste handler before
    character-key fallback.
- `Sources/SwiftTUICore/Runtime/LocalKeyHandlerRegistry.swift`
  - Add focused paste-handler registration, dispatch, snapshot, restore, reset,
    and subtree-removal support.
- `Sources/SwiftTUICore/Resolve/NodeHandlers.swift`
  - Record paste-handler registrations.
- `Sources/SwiftTUICore/Resolve/ViewNode.swift`
  - Add `recordPasteHandlerRegistration(...)`.
- `Sources/SwiftTUICore/Runtime/RuntimeRegistrationSet.swift`
  - Restore paste-handler registrations during retained-frame reuse.
- `Sources/SwiftTUICore/Resolve/ResolvedNode.swift`
  - Add package-only text-input caret-anchor metadata.
- `Sources/SwiftTUICore/Semantics/Semantics.swift`
  - Hoist placed text-input caret anchors onto their owning accessibility node.
- `docs/SOURCE_LAYOUT.md`
  - Add the new `Sources/SwiftTUIViews/Input/` files to the ownership map.
- `docs/proposals/TEXT_INPUT_MODEL.md`
  - Mark V1 plan linkage and any decisions settled here.
- `docs/README.md`
  - Keep this plan discoverable while planned/active.
- `docs/PUBLIC_API_BASELINE.md`
  - Refresh only if the public `TextFieldStyleConfiguration.fieldContent`
    addition changes the public inventory.

## Stage 0: Baseline And Red Tests

- [x] Read `docs/proposals/TEXT_INPUT_MODEL.md` and this plan in the same
  checkout before changing source.
- [x] Run the current focused surface tests so failures caused by this work are
  distinguishable from pre-existing failures.

```bash
swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/textFieldHandlesPromptCursorAndKeyInput
swiftly run swift test --filter SwiftTUITests.SecureFieldSurfaceTests
swiftly run swift test --filter SwiftTUITests.TextEditorSurfaceTests
swiftly run swift test --filter SwiftTUITests.AccessibilityRuntimePolicyTests
```

- [x] Add reducer and layout-map test files with failing tests for the V1
  behaviors below. The first run should fail because the new types do not
  exist yet.

```bash
swiftly run swift test --filter SwiftTUIViewsTests.TextInputReducerTests
swiftly run swift test --filter SwiftTUIViewsTests.TextInputLayoutMapTests
```

Required reducer test names:

- `insertsTextAtCollapsedSelection`
- `replacesNonCollapsedSelection`
- `backspaceDeletesClusterBeforeCaret`
- `backspaceDeletesSelectedRange`
- `movesLeftAndRightByGraphemeCluster`
- `homeAndEndMoveWithinCurrentLine`
- `upAndDownPreservePreferredVisualColumn`
- `secureTraitsDoNotChangeStoredText`
- `externalBindingUpdateClampsSelection`

Required layout-map test names:

- `caretPointTracksSingleLineOffsets`
- `nearestOffsetUsesCellMidpoints`
- `wideGraphemeOccupiesTwoCells`
- `explicitNewlinesCreateNewLayoutLines`
- `wrappedTextRetainsSourceRanges`
- `secureProjectionMasksDisplayButKeepsSourceOffsets`
- `syntheticCaretIsSuppressedWhenCursorFollowsFocus`

Checkpoint:

```bash
git add Tests/SwiftTUIViewsTests/TextInputReducerTests.swift \
  Tests/SwiftTUIViewsTests/TextInputLayoutMapTests.swift
git commit -m "test: define text input model v1 behavior"
```

## Stage 1: Pure Model And Reducer

- [x] Create `TextInputTypes.swift`.
- [x] Create `TextInputStringMetrics.swift`.
- [x] Create `TextInputReducer.swift`.
- [x] Implement `TextInputValue.synchronized(with:)` so external binding
  changes update text, clamp selection, clear composing range, and keep
  preferred visual column only when the caret remains on the same visual line.
- [x] Implement reducer commands for insertion, replacement, backspace,
  forward deletion, left/right, home/end, document start/end, and up/down.
- [x] Keep modifier-specific runtime shortcuts out of the reducer. The reducer
  should only see `TextInputCommand`.
- [x] Run the pure focused tests.

```bash
swiftly run swift test --filter SwiftTUIViewsTests.TextInputReducerTests
```

Acceptance criteria:

- All reducer tests pass.
- No reducer code imports or references runtime registries.
- All selection movement is grapheme-cluster based.
- `String.Index` values are not stored across mutations.

Checkpoint:

```bash
git add Sources/SwiftTUIViews/Input/TextInputTypes.swift \
  Sources/SwiftTUIViews/Input/TextInputStringMetrics.swift \
  Sources/SwiftTUIViews/Input/TextInputReducer.swift \
  Tests/SwiftTUIViewsTests/TextInputReducerTests.swift
git commit -m "feat: add text input value reducer"
```

## Stage 2: Layout Map And Presentation

- [x] Create `TextInputLayoutMap.swift`.
- [x] Create `TextInputPresentation.swift`.
- [x] Build layout from grapheme clusters and source ranges. Do not derive
  caret positions by scanning the rendered display string after masking or
  appending a synthetic caret.
- [x] Reuse `cellWidth(of:)` for terminal width. Keep all terminal geometry in
  `CellPoint`, `CellRect`, and `CellSize`.
- [x] Preserve explicit newlines.
- [x] Preserve source ranges through wrapping.
- [x] For secure fields, mask each grapheme in display while keeping source
  ranges tied to the original text.
- [x] Return selection rectangles even if V1 only paints collapsed carets.
- [x] Run the layout and presentation tests.

```bash
swiftly run swift test --filter SwiftTUIViewsTests.TextInputLayoutMapTests
```

Acceptance criteria:

- Offset-to-cell and cell-to-offset mappings are round-trippable for ASCII,
  wide graphemes, combining marks, explicit newlines, and wrapped text.
- Secure presentation never exposes the secret in display text.
- Synthetic caret rendering is a projection decision, not model state.

Checkpoint:

```bash
git add Sources/SwiftTUIViews/Input/TextInputLayoutMap.swift \
  Sources/SwiftTUIViews/Input/TextInputPresentation.swift \
  Tests/SwiftTUIViewsTests/TextInputLayoutMapTests.swift
git commit -m "feat: map text input offsets to terminal cells"
```

## Stage 3: Field Content And Built-In Style Integration

- [x] Create `TextInputContent.swift`.
- [x] Add `TextFieldStyleConfiguration.FieldContent`.
- [x] Add `public var fieldContent: FieldContent` to
  `TextFieldStyleConfiguration`.
- [x] Keep `public var displayText: String` unchanged for source
  compatibility.
- [x] Update `PlainTextFieldStyleBody` and `RoundedBorderTextFieldStyleBody`
  to render `configuration.fieldContent` instead of
  `Text(configuration.displayText)`.
- [x] Ensure `fieldContent` accepts foreground style, opacity metadata, and
  layout constraints from the surrounding style exactly as `Text(...)` did.
- [x] Add style-surface tests proving built-in styles render the same visible
  chrome and that a custom style using `displayText` still compiles.
- [x] Run focused text field style tests.

```bash
swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/plainTextFieldStyleRemovesChrome
swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/roundedBorderTextFieldFillsFrameWidth
```

Acceptance criteria:

- Existing text field style call sites keep compiling.
- Built-in styles use the field-content primitive.
- `fieldContent` is the only built-in rendering path that publishes caret
  metadata.
- Public API baseline is refreshed if `fieldContent` appears in inventory.

Checkpoint:

```bash
swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/plainTextFieldStyleRemovesChrome
swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/roundedBorderTextFieldFillsFrameWidth
./Scripts/generate_public_api_inventory.sh --check
```

If the public inventory check fails only because `fieldContent` is new:

```bash
./Scripts/generate_public_api_inventory.sh
git add docs/PUBLIC_API_BASELINE.md docs/PUBLIC_API_INVENTORY.md
```

Then commit:

```bash
git add Sources/SwiftTUIViews/Input/TextInputContent.swift \
  Sources/SwiftTUIViews/Controls/TextFieldStyles.swift \
  Tests/SwiftTUITests/SwiftUISurfaceTests.swift
git commit -m "feat: add text field input content"
```

## Stage 4: TextField And SecureField Key Integration

- [x] Add `@State private var textInputValue` to `TextField`.
- [x] Wrap `TextField.resolveElements(...)` in
  `dynamicPropertyAuthoringContext(for:)`, matching the existing `TextEditor`
  dynamic-property pattern.
- [x] Synchronize `textInputValue` from `text.wrappedValue` during resolve.
- [x] Register focused key handlers that translate `KeyPress` into
  `TextInputCommand`.
- [x] Write reducer mutations back through the original `Binding<String>`
  inside the current imperative authoring context.
- [x] Repeat the same integration for `SecureField`.
- [x] Keep secure display masked and keep secure semantic value redacted.
- [x] Add surface tests for caret insertion in the middle of text, left/right
  movement, backspace before caret, home/end, and secure masking after caret
  movement.
- [x] Run the focused single-line tests.

```bash
swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/textFieldHandlesPromptCursorAndKeyInput
swiftly run swift test --filter SwiftTUITests.SecureFieldSurfaceTests
swiftly run swift test --filter SwiftTUITests.TextInputRuntimeIntegrationTests
```

Acceptance criteria:

- Arrow left/right move the caret instead of being no-ops.
- Insertion happens at the caret.
- Backspace removes the cluster before the caret or the selected range.
- `SecureField` snapshots never include the secret value.

Checkpoint:

```bash
git add Sources/SwiftTUIViews/Controls/ValueControls.swift \
  Sources/SwiftTUIViews/Input/SecureField.swift \
  Tests/SwiftTUITests/SwiftUISurfaceTests.swift \
  Tests/SwiftTUITests/SecureFieldSurfaceTests.swift \
  Tests/SwiftTUITests/TextInputRuntimeIntegrationTests.swift
git commit -m "feat: use text input model in single-line fields"
```

## Stage 5: Paste Dispatch Foundation

- [x] Extend `LocalKeyHandlerRegistry` with a package `PasteHandler` type:
  `@MainActor (String) -> Bool`.
- [x] Add paste-handler registration, dispatch, snapshot, restore, reset, and
  subtree-removal support.
- [x] Record paste-handler registrations in `NodeHandlers` and `ViewNode`.
- [x] Restore paste-handler registrations from `RuntimeRegistrationSet`.
- [x] Register `TextField` and `SecureField` paste handlers that translate the
  whole pasted string into `.insertText(content)`.
- [x] Update `RunLoop.handlePaste(...)` so the order is:
  1. Try path-shaped drop dispatch.
  2. If the focused identity has a paste handler, dispatch the whole content.
  3. Fall back to the existing character-key fanout.
- [x] Preserve current drop-destination behavior for path-like paste.
- [x] Add single-line paste integration tests proving paste mutates the text
  binding once, not once per scalar.
- [x] Add runtime tests proving paste mutates the dispatching graph when the
  same text input view instance is hosted twice.
- [x] Run paste and imperative-context tests.

```bash
swiftly run swift test --filter SwiftTUITests.DropDestinationDispatchTests
swiftly run swift test --filter SwiftTUITests.ImperativeAuthoringContextDispatchTests
swiftly run swift test --filter SwiftTUITests.TextInputRuntimeIntegrationTests
```

Acceptance criteria:

- Drop destinations still receive path-shaped paste before text inputs.
- Non-path paste reaches a focused text input as one string.
- Non-text focused handlers still receive fallback character key events.
- Imperative authoring context remains scoped to the graph that received input.

Checkpoint:

```bash
git add Sources/SwiftTUICore/Runtime/LocalKeyHandlerRegistry.swift \
  Sources/SwiftTUICore/Resolve/NodeHandlers.swift \
  Sources/SwiftTUICore/Resolve/ViewNode.swift \
  Sources/SwiftTUICore/Runtime/RuntimeRegistrationSet.swift \
  Sources/SwiftTUIViews/Controls/ValueControls.swift \
  Sources/SwiftTUIViews/Input/SecureField.swift \
  Sources/SwiftTUI/RunLoop/RunLoop+EventDispatch.swift \
  Tests/SwiftTUITests/DropDestinationDispatchTests.swift \
  Tests/SwiftTUITests/ImperativeAuthoringContextDispatchTests.swift \
  Tests/SwiftTUITests/TextInputRuntimeIntegrationTests.swift
git commit -m "feat: route paste to focused text inputs"
```

## Stage 6: TextEditor Runtime Integration

- [x] Add `@State private var textInputValue` to `TextEditor`.
- [x] Keep the existing `@State private var scrollPosition` as companion state.
- [x] Build multiline presentation and layout map during resolve.
- [x] Translate key events through the same reducer with `isMultiline == true`.
- [x] Make return insert `\n`.
- [x] Make up/down move caret through the layout map and preferred visual
  column.
- [x] Apply caret-visible scroll adjustment after reducer mutations. Clamp
  scroll so the caret remains inside the visible editor content rect when the
  content is taller than the viewport.
- [x] Make bracketed paste insert the whole pasted string, preserving newlines.
- [x] Update `TextEditorSurfaceTests` for caret movement and add runtime
  coverage for caret-visible scrolling.
- [x] Run focused multiline tests.

```bash
swiftly run swift test --filter SwiftTUITests.TextEditorSurfaceTests
swiftly run swift test --filter SwiftTUITests.AppRuntimeTests/appLauncherPersistsStatefulTextEditorBindings
swiftly run swift test --filter SwiftTUITests.TextInputRuntimeIntegrationTests
```

Acceptance criteria:

- `TextEditor` no longer treats arrow up/down as scroll-only commands.
- Multiline insertion and paste preserve line breaks.
- The caret remains visible after vertical movement and insertion.
- Existing `ScrollView` chrome and indicators remain stable.

Checkpoint:

```bash
git add Sources/SwiftTUIViews/Input/TextEditor.swift \
  Sources/SwiftTUIViews/Controls/SelectionAndValueSupport.swift \
  Tests/SwiftTUITests/TextEditorSurfaceTests.swift \
  Tests/SwiftTUITests/AppRuntimeTests.swift \
  Tests/SwiftTUITests/TextInputRuntimeIntegrationTests.swift
git commit -m "feat: use text input model in text editor"
```

## Stage 7: Caret Semantics And Cursor-Follows-Focus

- [x] Add package `cursorFollowsFocus` to
  `EnvironmentValues` in `RuntimePolicyEnvironment.swift`.
- [x] Set `effectiveEnvironmentValues.cursorFollowsFocus` from
  `runtimeConfiguration.cursorFollowsFocus` in `RunLoop+Rendering.swift`.
- [x] Add package-only text-input caret-anchor metadata to `SemanticMetadata`.
  The metadata must include the owning text-control identity and a local
  caret point inside the placed `TextInputContent` node.
- [x] Update semantic extraction to hoist the placed text-input caret anchor
  onto the owner's `AccessibilityNode.cursorAnchor`.
- [x] Keep explicit `accessibilityCursorAnchor` behavior intact for non-text
  custom focus targets.
- [x] Suppress synthetic caret drawing when `cursorFollowsFocus` is true and a
  text input has a real caret anchor.
- [x] Add tests proving `AccessibilityRuntimePolicy` places the hardware
  cursor at the text caret for `TextField`, `SecureField`, and `TextEditor`.
- [x] Add tests proving secure field accessibility nodes do not expose the
  secret value while still publishing a caret anchor.

```bash
swiftly run swift test --filter SwiftTUITests.AccessibilityRuntimePolicyTests
swiftly run swift test --filter SwiftTUICoreTests.AccessibilityNodeExtractionTests
swiftly run swift test --filter SwiftTUITests.TextInputRuntimeIntegrationTests
```

Acceptance criteria:

- Cursor-following remains default-off.
- When enabled, the hardware cursor follows the text caret, not just the
  control origin.
- Synthetic `_` caret is not rendered for text inputs while hardware
  cursor-following is active.
- Secure fields publish caret location without exposing value text.

Checkpoint:

```bash
git add Sources/SwiftTUIViews/Environment/RuntimePolicyEnvironment.swift \
  Sources/SwiftTUI/RunLoop/RunLoop+Rendering.swift \
  Sources/SwiftTUICore/Resolve/ResolvedNode.swift \
  Sources/SwiftTUICore/Semantics/Semantics.swift \
  Tests/SwiftTUICoreTests/AccessibilityNodeExtractionTests.swift \
  Tests/SwiftTUITests/AccessibilityRuntimePolicyTests.swift \
  Tests/SwiftTUITests/TextInputRuntimeIntegrationTests.swift
git commit -m "feat: anchor accessibility cursor to text carets"
```

## Stage 8: Cleanup, Docs, And Public Surface

- [x] Remove obsolete text-entry mutation helpers after all call sites move to
  the reducer. If any helper remains, rename it so it is clearly a reducer
  adapter rather than the model owner.
- [x] Update `docs/SOURCE_LAYOUT.md` with the new input-model files.
- [x] Update `docs/proposals/TEXT_INPUT_MODEL.md` with a V1 implementation
  status note and decisions settled by this plan.
- [x] Update this plan's frontmatter `status:` to `active` when execution
  begins and to `shipped` only after the final repo-wide gate passes.
- [x] Run formatting on touched Swift files.

```bash
swift format format -i --configuration .swift-format.json Sources/ Tests/
```

- [x] Run focused tests one final time.

```bash
swiftly run swift test --filter SwiftTUIViewsTests.TextInputReducerTests
swiftly run swift test --filter SwiftTUIViewsTests.TextInputLayoutMapTests
swiftly run swift test --filter SwiftTUITests.TextInputRuntimeIntegrationTests
swiftly run swift test --filter SwiftTUITests.TextEditorSurfaceTests
swiftly run swift test --filter SwiftTUITests.SecureFieldSurfaceTests
swiftly run swift test --filter SwiftTUITests.AccessibilityRuntimePolicyTests
```

- [x] Run public-surface and repo-wide gates.

```bash
./Scripts/generate_public_api_inventory.sh --check
bun run test --skip-bun-install
```

Acceptance criteria:

- The new files are documented in the source layout.
- The proposal links to this implementation plan.
- Public API baseline is current.
- Repo-wide gate passes.
- No secure-value regression appears in snapshots, semantics, or transport
  fixtures.

Final checkpoint:

```bash
git add Sources Tests docs
git commit -m "docs: mark text input model v1 shipped"
```

Verification result on 2026-05-06:

- Focused text input, accessibility runtime, and semantic extraction tests
  passed.
- `./Scripts/generate_public_api_inventory.sh --check` passed.
- `bun run test --skip-bun-install` passed after clearing stale SwiftPM build
  products from the public struct-layout change.
- Full log: `/tmp/swift-tui-test-all-20260506-010612-10943.log`.

## Follow-Up Work Outside V1

- Public custom text-input storage.
- Rope or piece-tree storage for large `TextEditor` documents.
- Rich selection rendering.
- IME/composition support in native and web hosts.
- Web/WASI and SwiftUI-host value/selection transport.
- Copy/cut/select-all command handling.
- Word movement and deletion shortcuts once modifier-bearing text-editing
  input is normalized across terminal, web, and SwiftUI hosts.
