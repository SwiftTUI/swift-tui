# Text Input Model

**Status:** Active implementation. Stages 0-7 of the linked V1 plan have
landed: the package-private value model, reducer, layout map, presentation
projection, field-content view, reducer-backed `TextField` / `SecureField`,
focused paste dispatch, reducer-backed `TextEditor`, caret-visible runtime
scrolling, and text-input caret anchors in accessibility semantics are in
place. Cleanup, source-layout/docs finalization, and the final repo-wide gate
remain open.

**Owner:** unassigned.

**Related docs:**

- [ACCESSIBILITY.md](./ACCESSIBILITY.md) - cursor-following and deferred caret tracking
- [2026-05-06-001-text-input-model-v1-plan.md](../plans/2026-05-06-001-text-input-model-v1-plan.md)
  - staged V1 implementation plan
- [0013-accessibility-runtime-policy.md](../decisions/0013-accessibility-runtime-policy.md)
  - runtime cursor policy
- [FOCUS.md](../FOCUS.md) - focus traversal and focused values
- [RUNTIME.md](../RUNTIME.md) - graph-scoped state and render-loop behavior

---

## Problem

SwiftTUI currently has enough text input to support simple demos, but not
enough model structure to make text editing, accessibility caret tracking, or
cross-host behavior dependable.

The current implementation is intentionally small:

- `TextField` and `SecureField` register a key handler for a `Binding<String>`
  and render a synthetic trailing `_` while focused.
- `TextEditor` uses the same text mutation path plus a `ScrollPosition`.
- The text mutation function appends printable input, removes the last
  character on backspace, appends `\n` for multiline return, scrolls
  `TextEditor` on up/down, and consumes left/right without moving anything.
- Accessibility nodes can carry `cursorAnchor`, and built-in text inputs now
  publish real caret anchors for cursor-following and caret-visible scroll sync.

That is not a stable foundation for the next tranche. A proper text model
needs to distinguish text storage, editing state, command reduction, layout,
presentation, semantics, and host bridging.

## Goals

1. Build one internal text input model for `TextField`, `SecureField`, and
   `TextEditor`.
2. Keep the public authoring API SwiftUI-shaped: bindings remain
   `Binding<String>` in v1.
3. Represent caret and selection explicitly instead of deriving them from a
   synthetic rendered underscore.
4. Make editing operations pure and testable before runtime integration.
5. Make caret-to-cell mapping a layout product, not a guess.
6. Publish text-input semantics from the shared `semantics` phase so terminal,
   web, and SwiftUI hosts consume the same state.
7. Preserve secure-entry privacy: never leak secret values through display,
   accessibility labels, logs, snapshots, or host wire formats.
8. Leave storage extensible for larger editors without forcing a rope or piece
   tree into the first implementation.

## Non-Goals

- Rich text editing.
- Syntax highlighting, code folding, multiple cursors, or collaborative editing.
- Public custom text-input storage.
- Replacing the existing `Text` layout system wholesale.
- Recreating platform IME behavior inside the terminal runtime. Terminal raw
  input can only model what the terminal sends; native/web hosts may later map
  platform composition into the same value model.

## Research Summary

### Cocoa and TextKit

Apple's Cocoa text system separates storage, layout geometry, layout control,
and view presentation. `NSTextStorage` holds attributed text, `NSTextContainer`
models the layout region, `NSTextView` displays, and `NSLayoutManager`
coordinates storage-to-glyph-to-layout state. TextKit 2 keeps the same
separation with newer content-storage and layout-manager types.

Useful lessons for SwiftTUI:

- Storage and layout should not be the same object.
- Geometry belongs in a layout/container layer, not in the editing reducer.
- A single storage object may be rendered differently in different layout
  contexts.
- Character ranges and glyph/layout ranges must remain convertible but are not
  the same concept.

### Flutter

Flutter's low-level `EditableText` is a building block for higher-level text
fields. Its value object, `TextEditingValue`, contains the current text,
selection, and composing range. `EditableText` explicitly owns scrolling,
selection, cursor movement, text-editing intents, shortcuts, and keeping the
caret visible.

Useful lessons for SwiftTUI:

- The minimal useful value is `text + selection + composing`, not just text.
- Editing should flow through explicit commands or intents.
- Shortcut/key-command dispatch can accidentally prevent text input, so text
  input and command routing need a clear ordering contract.
- "Keep caret visible" is part of text input, not a separate ScrollView concern.

### CodeMirror

CodeMirror 6 models editor state as persistent immutable state. The core state
contains a document and selection; updates happen through transactions. Its
`Text` document type is an immutable tree-shaped representation with efficient
indexing by offset and line number, structure-sharing updates, and iteration
without flattening large strings.

Useful lessons for SwiftTUI:

- State updates should be transaction-like and testable.
- Direct mutation of editor state is an anti-pattern.
- Selections are first-class ranges with anchor/head, mapping through changes,
  and a stored goal column for vertical movement.
- Documents need multiple metrics: offsets, line numbers, grapheme movement,
  and rendering columns.

### ProseMirror

ProseMirror is a rich-text framework, so its document model is larger than
SwiftTUI needs. Still, its state shape is relevant: editor state is persistent,
documents and selections are updated by applying transactions, and document
steps can be mapped through changes.

Useful lessons for SwiftTUI:

- Keep document changes and selection changes together in one update.
- Keep extension state out of the raw document string.
- Avoid view-owned mutation that cannot be replayed, tested, or mapped.

### Emacs Gap Buffer

Emacs buffers use a gap buffer. Insertions and deletions near the gap are fast;
editing far from the current gap may require moving it first.

Useful lessons for SwiftTUI:

- A gap buffer is simple and fast for local editing.
- It is a poor match for value-style transactions and immutable snapshots.
- It optimizes one caret locality. That is less useful once selections,
  host synchronization, undo, or external binding updates enter the picture.

### VS Code Piece Tree

VS Code moved from a line-array model to a piece-tree model: append-only buffers
plus a red-black-tree piece table optimized for line lookup. The migration notes
are especially useful because they are grounded in real editor workloads.

Useful lessons for SwiftTUI:

- "One string per line" is attractive for small files and bad for large ones.
- Line-break caches and offset conversion matter as much as insert/delete
  complexity.
- Real profiling beats theoretical hot-path guesses.
- CRLF and mixed line endings are correctness hazards, not polish.
- Crossing abstraction/runtime boundaries can erase data-structure wins.

### Ropes, Xi, and Ropey

Rope-backed editors store text as a tree and cache metrics in the tree. Xi's
"rope science" material calls out UTF-8/UTF-16 conversions, line-ending metrics,
grapheme boundaries, difficulty flags such as non-ASCII/bidi/tabs, and
incremental invalidation. Ropey exposes a UTF-8 rope whose operations are in
Unicode scalar indices to avoid invalid UTF-8 slicing.

Useful lessons for SwiftTUI:

- A scalable text system needs cached metrics, not repeated whole-string scans.
- Different consumers need different coordinate systems: UTF-8 bytes, UTF-16
  code units, Unicode scalars, grapheme clusters, lines, and terminal cells.
- Cursor movement should be based on user-perceived characters, not bytes.
- Incremental invalidation is valuable, but only after correctness is pinned.

## Comparative Model Table

| Model | Strengths | Weaknesses | SwiftTUI stance |
|---|---|---|---|
| Plain `String` plus selection | Simple, matches current public binding, easy to test | Middle edits and repeated offset conversion can become O(n); invalidated indices after mutation | Use for v1 behind a proper reducer and metrics helpers |
| Gap buffer | Fast local insertion/deletion near one caret, simple implementation | Poor fit for immutable snapshots, transactions, multiple selections, and external binding sync | Do not use as the architectural model |
| Line array | Easy line lookup, easy viewport rendering for small documents | Memory blow-up on many lines; costly insertion/removal in large documents; line ending edge cases | Use only as derived layout/cache data |
| Piece table / piece tree | Memory efficient for file-backed editing; good undo shape; stable large-document edits with tree metrics | More complex; line lookup still needs cached metrics; overkill for small fields | Keep as a future `TextEditor` storage candidate |
| Rope | Scales to large text; can cache multiple metrics; cheap snapshots in some designs | Complex Unicode boundary and metric implementation; API can leak storage concerns | Keep as future storage candidate, not v1 requirement |
| Immutable editor state + transactions | Predictable, testable, maps selection through edits, host-friendly | Requires discipline; more boilerplate than direct mutation | Adopt for text input value/reducer shape |
| Platform text system | Strong native accessibility, IME, selection, layout | Not available in terminal Core; platform-specific offsets and lifecycles | Bridge to it in hosts, but keep SwiftTUI model independent |

## Design Principles

1. **The model owns editing state.** Text inputs cannot infer caret state from
   rendered text. Caret, selection, composing range, scroll position, and
   preferred visual column are state.

2. **Editing is command reduction.** Keyboard input, paste, pointer placement,
   and host edits become `TextInputCommand` values. A reducer applies a command
   to a value and returns a new value plus a small edit summary.

3. **Layout maps text positions to cells.** The hardware cursor and pointer
   hit-testing use layout products. They do not recompute coordinates from a
   display string.

4. **Display is a projection.** `SecureField` uses the same editing model as
   `TextField`, but its display projection masks the value and its semantics
   avoid exposing the secret.

5. **Terminal cells are first-class.** SwiftTUI does not render pixels. The
   layout map must know terminal cell widths, wrapping, explicit newlines,
   viewport offsets, and wide grapheme clusters.

6. **Start simple, keep storage swappable.** The first implementation should
   use a `String`-backed internal buffer with explicit indices and metrics.
   The API boundary should not prevent moving `TextEditor` to a rope or piece
   table if real workloads demand it.

7. **No line-array editor core.** Line arrays are acceptable as a derived
   layout cache. They should not become the authoritative text store.

8. **One semantic truth.** Terminal cursor-following, web ARIA, SwiftUI host
   accessibility, and linear accessible output read from the same semantic
   payload.

## Proposed Model

### TextInputValue

`TextInputValue` is the central value passed through the reducer.

```swift
package struct TextInputValue: Equatable, Sendable {
  package var text: String
  package var selection: TextSelection
  package var composingRange: TextRange?
  package var preferredVisualColumn: Int?
}
```

The `Binding<String>` remains the public API. Internally, controls retain a
`TextInputValue` in graph-scoped state and synchronize it with the binding:

- If the binding changes externally, update `value.text`, clamp selection, and
  clear composing state unless the host explicitly supplies composition.
- If the reducer changes `value.text`, write the new string back through the
  binding in the focused graph's imperative authoring context.

### TextOffset and TextRange

Offsets should be grapheme-cluster offsets for internal editing commands.
Terminal editing and caret movement are user-perceived-character operations.

```swift
package struct TextOffset: Equatable, Comparable, Hashable, Sendable {
  package var rawValue: Int
}

package struct TextRange: Equatable, Hashable, Sendable {
  package var lowerBound: TextOffset
  package var upperBound: TextOffset
}
```

The model also needs conversion helpers:

- grapheme offset -> `String.Index`
- `String.Index` -> grapheme offset
- grapheme offset -> UTF-16 offset for web/native host bridges
- UTF-16 offset -> nearest valid grapheme offset

This keeps terminal editing cluster-safe while still acknowledging that DOM,
TextKit, and many platform APIs use UTF-16 positions.

### TextSelection

Selection stores anchor/head instead of only a normalized range.

```swift
package struct TextSelection: Equatable, Hashable, Sendable {
  package var anchor: TextOffset
  package var head: TextOffset

  package var range: TextRange { get }
  package var isCollapsed: Bool { get }
}
```

V1 can render only collapsed selections if necessary, but the model should
start with anchor/head. Retrofitting selection later would force changes into
every reducer and layout API.

### TextInputTraits

Traits describe the control, not the current value.

```swift
package struct TextInputTraits: Equatable, Sendable {
  package var isMultiline: Bool
  package var isSecure: Bool
  package var acceptsTab: Bool
  package var submitBehavior: TextInputSubmitBehavior
  package var lineLimit: Int?
}
```

`TextField` and `SecureField` use `isMultiline == false`.
`TextEditor` uses `isMultiline == true`.
`SecureField` uses `isSecure == true`.

### TextInputCommand

Commands are the reducer input. The exact spelling can change, but the shape
should preserve the distinction between text insertion, movement, deletion, and
selection.

```swift
package enum TextInputCommand: Equatable, Sendable {
  case insertText(String)
  case deleteBackward(granularity: TextGranularity)
  case deleteForward(granularity: TextGranularity)
  case move(TextMovement, selecting: Bool)
  case replaceSelection(String)
  case setSelection(TextSelection)
}
```

Proposed movement and granularity:

```swift
package enum TextGranularity: Equatable, Sendable {
  case character
  case word
  case line
}

package enum TextMovement: Equatable, Sendable {
  case left
  case right
  case up
  case down
  case lineStart
  case lineEnd
  case documentStart
  case documentEnd
  case wordBackward
  case wordForward
}
```

### TextInputReducer

The reducer is pure and has no dependency on runtime registries.

```swift
package struct TextInputReducer: Sendable {
  package func reduce(
    _ value: TextInputValue,
    command: TextInputCommand,
    traits: TextInputTraits,
    layout: TextInputLayoutMap?
  ) -> TextInputMutation
}
```

`layout` is optional because many commands do not need visual information.
Vertical movement, line start/end in wrapped text, and hit-testing do.

```swift
package struct TextInputMutation: Equatable, Sendable {
  package var value: TextInputValue
  package var changedRange: TextRange?
  package var insertedText: String
  package var shouldWriteBinding: Bool
  package var shouldRequestFrame: Bool
}
```

### TextInputLayoutMap

The layout map is the bridge from text offsets to terminal cells.

```swift
package struct TextInputLayoutMap: Equatable, Sendable {
  package var lines: [TextInputLayoutLine]
  package var contentSize: CellSize
  package var viewport: CellRect

  package func caretPoint(for offset: TextOffset) -> CellPoint
  package func nearestOffset(to point: CellPoint) -> TextOffset
}

package struct TextInputLayoutLine: Equatable, Sendable {
  package var sourceRange: TextRange
  package var clusters: [TextInputLayoutCluster]
  package var origin: CellPoint
  package var cellWidth: Int
}

package struct TextInputLayoutCluster: Equatable, Sendable {
  package var textRange: TextRange
  package var display: Character
  package var cellWidth: Int
  package var originX: Int
}
```

For secure text, `display` is the masking character and `textRange` points to
the original grapheme cluster. Caret movement remains based on the secret
string; display remains masked.

The existing `TextLayoutResult` can either be extended with source ranges or
wrapped by a text-input-specific layout builder. The important constraint is
that source offsets survive wrapping and masking.

### TextInputPresentation

Presentation is the derived view-facing data.

```swift
package struct TextInputPresentation: Equatable, Sendable {
  package var displayText: String
  package var isShowingPrompt: Bool
  package var layoutMap: TextInputLayoutMap
  package var caretAnchor: CellPoint
  package var selectionRects: [CellRect]
  package var shouldDrawSyntheticCaret: Bool
}
```

`shouldDrawSyntheticCaret` is true for normal TUI output when the hardware
cursor-following policy is disabled. It is false when
`RuntimeConfiguration.cursorFollowsFocus` is enabled and the runtime can place
the hardware cursor at `caretAnchor`.

### TextInputSemantics

The semantic payload should be package-level at first.

```swift
package struct TextInputSemantics: Equatable, Sendable {
  package var value: String?
  package var isSecure: Bool
  package var isMultiline: Bool
  package var selection: TextSelection
  package var caretAnchor: CellPoint
}
```

For secure text, `value == nil`. The role remains `.secureField`.

Longer term, this may become public or SPI if host packages need richer
bridging. The first implementation should keep it package-level until the
shape is proven.

## Rendering and Style Integration

The current `TextFieldStyleConfiguration` exposes `displayText` but not the
editable surface. That is too weak for caret anchoring because a custom style
can render the display text anywhere.

The proposed direction is:

1. Introduce a package-private `TextInputContent` view that owns text display,
   source ranges, selection rectangles, and caret anchor metadata.
2. Add a field-content member to `TextFieldStyleConfiguration` while keeping
   `displayText` for source compatibility.
3. Update built-in styles to render `configuration.fieldContent` instead of
   `Text(configuration.displayText)`.
4. Treat styles that ignore the field content as supported but degraded:
   semantic role and label remain correct, but caret anchoring falls back to
   the text input node origin.

This preserves style customization while keeping the editable text placement
inside the control's ownership.

## Runtime Integration

### Keyboard

Current text inputs register a `KeyEvent` handler. The replacement should
register a `KeyPress` handler so modifier-bearing editing commands can be
recognized.

Initial terminal key mapping:

| Key | Command |
|---|---|
| character / space | `.insertText(...)` |
| return in `TextEditor` | `.insertText("\n")` |
| return in `TextField` / `SecureField` | submit or ignore per traits |
| backspace | `.deleteBackward(.character)` |
| delete, when parsed | `.deleteForward(.character)` |
| left/right | `.move(.left/.right, selecting: shift)` |
| up/down | `.move(.up/.down, selecting: shift)` in multiline |
| home/end | `.move(.lineStart/.lineEnd, selecting: shift)` |
| ctrl/alt variants | word or document movement where terminals report them |

Framework-level exit bindings and app key commands currently run before
focused text handlers for modifier-bearing keys. That is a deliberate runtime
policy, but it means copy/cut/paste shortcuts should be added only with an
explicit command-routing decision.

### Paste

Bracketed paste should not be decomposed into scalar keypresses for focused
text inputs. After the drop-destination path declines a paste, the runtime
should dispatch one `.insertText(paste.content)` command to the focused text
input when it has text-input semantics.

This preserves grapheme clusters and lets the reducer apply multiline rules in
one place.

### Pointer

Click-to-focus already exists. Click-to-caret should be added once the layout
map exists:

1. Hit-test the text input.
2. Convert the pointer cell into text-input-local coordinates.
3. Ask `TextInputLayoutMap.nearestOffset(to:)`.
4. Dispatch `.setSelection(.collapsed(offset))`.

Drag selection can build on the same path later.

### Scroll

`TextEditor` scroll position should become part of text input state or a
closely owned companion. Vertical movement and text insertion must call a
single "ensure caret visible" helper that updates scroll only when necessary.

This avoids the current split where up/down scrolls the editor but does not
move a caret.

## Accessibility and Host Bridging

Text-input semantics should flow through the existing semantic snapshot.

Terminal TUI:

- When cursor-following is disabled, render a synthetic caret and keep current
  visual behavior.
- When cursor-following is enabled, suppress the synthetic caret and publish
  the real `caretAnchor`.
- If no caret anchor is available, fall back to the node origin and record a
  test gap.

Accessible linear output:

- Text fields should include role and label.
- Non-secure values may be included when useful.
- Secure values must never be included.

Web/WASI:

- The web accessibility tree currently maps text input roles to `textbox`.
- Add text-input state to the wire format only after secure-value redaction is
  guaranteed.
- Future web-host controls can map `value`, `selectionStart`,
  `selectionEnd`, `aria-multiline`, and password/secure traits from the same
  semantic payload.

SwiftUI host:

- Existing mappings already classify `.textField`, `.secureField`, and
  `.textEditor` as text input.
- Add value/selection/caret metadata only after the semantic payload is stable.

## Storage Decision

Use a `String`-backed internal storage for v1, but do not expose that as the
permanent design.

Why not rope first:

- SwiftTUI's public text-input API is currently `Binding<String>`.
- The immediate gaps are correctness gaps: caret, selection, layout mapping,
  labels, secure redaction, paste, and cursor anchors.
- A rope would add complexity before those contracts are pinned.

Why not a gap buffer:

- Gap buffers optimize local mutable editing.
- SwiftTUI needs graph-scoped state snapshots, transactions, host bridging,
  and binding synchronization.
- Moving a gap is invisible to users but visible to implementation complexity.

Why keep a storage seam:

- `TextEditor` may eventually host large documents.
- Efficient line lookup, viewport rendering, and random edits are real future
  concerns.
- A future rope or piece tree should be able to sit behind the reducer without
  changing control semantics.

V1 should introduce a small package-private storage wrapper only if it keeps
index conversion and metrics centralized. It should not expose a public storage
protocol until there is more than one real implementation.

## Anti-Patterns to Avoid

1. **Synthetic caret as state.** A trailing `_` is a rendering fallback, not
   the source of truth.
2. **Byte or scalar cursor movement.** Users move across grapheme clusters.
3. **Line arrays as authoritative storage.** Derived line caches are fine;
   primary storage should not be split into mutable line strings.
4. **Style-owned editable text placement.** Styles can decorate, but the
   control must own the editable content primitive if we want real anchors.
5. **Secure text in semantic labels.** Passwords must not leak into labels,
   snapshots, web transport, or native accessibility values.
6. **Paste as repeated keypresses.** Paste is an insertion command.
7. **Layout-free vertical movement.** Up/down needs visual layout and preferred
   column, especially with wrapping and wide graphemes.
8. **Runtime-only fixes.** Cursor anchors, accessibility values, and host
   selection metadata belong in semantics, not terminal-specific patches.

## Suggested Implementation Phases

### Phase 1: Pure Model and Reducer

Files likely touched:

- Create `Sources/SwiftTUIViews/Input/TextInputValue.swift`
- Create `Sources/SwiftTUIViews/Input/TextInputReducer.swift`
- Add tests under `Tests/SwiftTUIViewsTests/`

Deliverables:

- `TextOffset`, `TextRange`, `TextSelection`, `TextInputValue`,
  `TextInputTraits`, `TextInputCommand`, and `TextInputReducer`.
- Tests for insertion, replacement, backspace, delete-forward, line boundaries,
  collapsed vs non-collapsed selection, secure traits not affecting model text,
  and grapheme-cluster movement.

### Phase 2: Layout Map

Files likely touched:

- Create `Sources/SwiftTUIViews/Input/TextInputLayoutMap.swift`
- Extend or wrap `Sources/SwiftTUICore/Content/TextLayout.swift`
- Add tests under `Tests/SwiftTUITests/` or `Tests/SwiftTUIViewsTests/`

Deliverables:

- Offset-to-cell and cell-to-offset mapping.
- Wrapped-line caret placement.
- Wide grapheme and zero-width-combining coverage.
- Secure display projection with original offset mapping.

### Phase 3: Single-Line Control Integration

Files likely touched:

- `Sources/SwiftTUIViews/Controls/ValueControls.swift`
- `Sources/SwiftTUIViews/Input/SecureField.swift`
- `Sources/SwiftTUIViews/Controls/TextFieldStyles.swift`
- `Tests/SwiftTUITests/SwiftUISurfaceTests.swift`
- `Tests/SwiftTUITests/SecureFieldSurfaceTests.swift`

Deliverables:

- `TextField` and `SecureField` use `TextInputValue`.
- Left/right/home/end and insertion at caret work.
- Backspace deletes before caret.
- Secure display remains masked.
- Existing visual snapshots remain intentionally updated.

### Phase 4: TextEditor Integration

Files likely touched:

- `Sources/SwiftTUIViews/Input/TextEditor.swift`
- `Sources/SwiftTUIViews/Controls/SelectionAndValueSupport.swift`
- `Tests/SwiftTUITests/TextEditorSurfaceTests.swift`
- `Tests/SwiftTUITests/AppRuntimeTests.swift`

Deliverables:

- Multiline caret movement.
- Preferred visual column for up/down.
- Caret-visible scrolling.
- Newline insertion and multiline paste as reducer commands.

### Phase 5: Semantics and Cursor Anchors

Files likely touched:

- `Sources/SwiftTUICore/Resolve/ResolvedNode.swift`
- `Sources/SwiftTUICore/Semantics/SemanticSnapshot.swift`
- `Sources/SwiftTUICore/Semantics/Semantics.swift`
- `Sources/SwiftTUI/Accessibility/AccessibilityRuntimePolicy.swift`
- `Tests/SwiftTUICoreTests/AccessibilityNodeExtractionTests.swift`
- `Tests/SwiftTUITests/AccessibilityRuntimePolicyTests.swift`

Deliverables:

- Text input semantic payload.
- Real caret anchor for text inputs.
- Cursor-following uses the caret anchor.
- Synthetic caret is suppressed when hardware cursor-following is active.
- Secure value redaction is tested.

### Phase 6: Host Bridging

Files likely touched:

- `Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift`
- `Platforms/Web/src/AccessibilityTree.ts`
- `Platforms/SwiftUI/Sources/SwiftUIHost/AccessibilityNodeMapping.swift`
- Platform tests under `Platforms/WASI/Tests/` and `Platforms/SwiftUI/Tests/`

Deliverables:

- Web and SwiftUI hosts receive enough text-input state for native
  accessibility affordances.
- Secure values remain redacted on every transport.
- Host tests cover focused text input, multiline state, and secure state.

## Open Questions

1. Should internal offsets be grapheme offsets, UTF-16 offsets, or a dual
   metric? This proposal recommends grapheme offsets internally plus UTF-16
   conversion at host boundaries.
2. Should `TextInputValue` include scroll position directly, or should
   `TextEditor` own scroll as a companion state? The reducer needs access to
   it for caret-visible behavior either way.
3. How much of selection rendering should ship in v1? The model should support
   ranges immediately, but visible range highlighting can be staged.
4. Should `TextFieldStyleConfiguration` gain public field-content API, or
   should it remain package-only until the style story is proven?
5. How should framework exit bindings interact with text editing shortcuts
   such as copy/cut/paste? Current runtime policy gives exit bindings priority.
6. Which line-ending policy should text inputs use? Current SwiftTUI text
   layout normalizes around `\n`; future file-backed editors may need CRLF
   preservation.
7. Should IME/composition be supported only in web/native hosts at first, or
   should terminal input expose a limited composing model for paste and
   dead-key terminals?

## Sources

- Apple, [Text System Organization](https://developer.apple.com/library/archive/documentation/TextFonts/Conceptual/CocoaTextArchitecture/TextSystemArchitecture/ArchitectureOverview.html)
- Apple, [The Layout Manager](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/TextLayout/Concepts/LayoutManager.html)
- Apple, [TextKit](https://developer.apple.com/documentation/uikit/textkit)
- Apple, [NSTextStorage](https://developer.apple.com/documentation/uikit/nstextstorage)
- Flutter, [TextEditingValue](https://api.flutter.dev/flutter/flutter_test/TextEditingValue-class.html)
- Flutter, [EditableText](https://api.flutter.dev/flutter/widgets/EditableText-class.html)
- CodeMirror, [Reference Manual](https://codemirror.net/docs/ref/)
- ProseMirror, [Guide](https://prosemirror.net/docs/guide/)
- Microsoft VS Code, [Text Buffer Reimplementation](https://code.visualstudio.com/blogs/2018/03/23/text-buffer-reimplementation)
- GNU Emacs, [The Buffer Gap](https://www.gnu.org/software/emacs/manual/html_node/elisp/Buffer-Gap.html)
- Ropey, [Crate documentation](https://docs.rs/ropey/latest/ropey/)
- Xi Editor, [Rope science - Introduction](https://xi-editor.io/docs/rope_science_00.html)
- Xi Editor, [Rope science, part 2 - metrics](https://xi-editor.io/docs/rope_science_02.html)
- Xi Editor, [Rope science, part 12 - minimal invalidation](https://xi-editor.io/docs/rope_science_12.html)

## Changelog

- 2026-05-06: Initial draft proposal.
