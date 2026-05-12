# Palette Sheet Subtree Absorption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the focus-chain-derived palette-command mechanism with subtree absorption that mirrors `.toolbar(style:)`, removing the proxy holder pattern entirely.

**Architecture:** `.paletteCommand(...)` becomes a contributor that merges into a new `PaletteCommandsPreferenceKey`. `.paletteSheet(...)` becomes an `ActionScope`-bound absorber that reads the preference at its host scope and passes the snapshot into the sheet content closure as a parameter. The current pathway (registry storage → focus-chain projection → environment value) is removed completely. No external consumers — internal callers are migrated in lockstep.

**Tech Stack:** Swift 6, SwiftTUI `PrimitiveViewModifier` + `PreferenceKey` + `ResolveContext` machinery (no new dependencies).

**Phase ordering (six tasks, six commits):**

1. Build new mechanism (additive — dual-write keeps old paths alive)
2. Migrate gallery + drop old `View.paletteSheet`
3. Port framework tests off registry/env palette APIs
4. Strip env key + RunLoop projection
5. Strip palette code from `CommandRegistry` + `NodeHandlers`
6. Final verification

Each commit must leave the build green. The destructive phase (Tasks 4–5) runs only after all consumers and tests are off the old APIs.

---

## Task 1: Build the new mechanism

Adds `PaletteCommandsPreferenceKey`, the new `BuiltinPaletteSheetPresentationModifier`, the `ActionScope`-bound `paletteSheet` extension, and the dual-write in `PaletteCommandRegistrationModifier` (preserves the existing registry write so this commit doesn't break any current test). Includes a new test suite that pins the absorption contract.

**Files:**
- Modify: `Sources/SwiftTUIViews/ActionScopes/PaletteCommandModifier.swift`
- Modify: `Sources/SwiftTUIViews/Presentation/PresentationModifiers.swift`
- Create: `Tests/SwiftTUITests/PaletteSheetAbsorptionTests.swift`

- [ ] **Step 1: Add the preference key**

In `PaletteCommandModifier.swift`, immediately after the `extension EnvironmentValues { ... }` block (around line 42), add:

```swift
/// Preference key that accumulates `paletteCommand` contributions from
/// every descendant in a scope's subtree. Consumed and cleared at the
/// nearest `.paletteSheet(...)` host (an `ActionScope`), which passes
/// the absorbed snapshot into the sheet content closure. Mirrors
/// `ToolbarItemsPreferenceKey`.
package enum PaletteCommandsPreferenceKey: PreferenceKey {
  package static var defaultValue: [ActivePaletteCommand] { [] }

  package static func reduce(
    value: inout [ActivePaletteCommand],
    nextValue: () -> [ActivePaletteCommand]
  ) {
    value.append(contentsOf: nextValue())
  }
}
```

- [ ] **Step 2: Make `PaletteCommandRegistrationModifier` dual-write**

Replace the body of `PaletteCommandRegistrationModifier.resolve` in the same file:

```swift
  package func resolve<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    let dynamicPropertyScope = currentImperativeAuthoringContextSnapshot() ?? authoringContext
    let contribution = ActivePaletteCommand(
      name: name,
      description: description,
      isEnabled: isEnabled,
      action: {
        withImperativeAuthoringContext(dynamicPropertyScope) {
          action()
        }
      }
    )
    node.preferenceValues.merge(
      PaletteCommandsPreferenceKey.self,
      value: [contribution]
    )
    context.commandRegistry?.registerPaletteCommand(
      at: node.identity,
      command: RegisteredPaletteCommand(
        name: name,
        description: description,
        isEnabled: isEnabled,
        action: contribution.action
      )
    )
    return [node]
  }
```

- [ ] **Step 3: Add the new modifier struct + `paletteSheet` extension**

In `PresentationModifiers.swift`, immediately after the closing brace of `BuiltinSheetPresentationModifier` (around line 437), append:

```swift
/// Sheet variant that absorbs `paletteCommand` contributions from the
/// enclosing scope's subtree via `PaletteCommandsPreferenceKey` and
/// passes the snapshot into the sheet content closure. Mirrors the
/// `.toolbar(style:)` absorption pattern.
public struct BuiltinPaletteSheetPresentationModifier<SheetContent: View>: PrimitiveViewModifier {
  package let title: String
  package let isPresented: Binding<Bool>
  package let sheetContentBuilder: ([ActivePaletteCommand]) -> SheetContent
  package let sheetContentAuthoringContext: AuthoringContext?
  package let dismissAuthoringContext: AuthoringContext?

  package init(
    title: String,
    isPresented: Binding<Bool>,
    sheetContentBuilder: @escaping ([ActivePaletteCommand]) -> SheetContent,
    sheetContentAuthoringContext: AuthoringContext?,
    dismissAuthoringContext: AuthoringContext?
  ) {
    self.title = title
    self.isPresented = isPresented
    self.sheetContentBuilder = sheetContentBuilder
    self.sheetContentAuthoringContext = sheetContentAuthoringContext
    self.dismissAuthoringContext = dismissAuthoringContext
  }

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)

    let absorbed = node.preferenceValues[PaletteCommandsPreferenceKey.self]
    node.preferenceValues[PaletteCommandsPreferenceKey.self] = []

    guard isPresented.wrappedValue else {
      return [node]
    }

    let sheetContent = withAuthoringContext(sheetContentAuthoringContext) {
      sheetContentBuilder(absorbed)
    }

    let sourceIdentity = node.identity
    let dismissInvalidator = context.invalidationProxy?.invalidator
    let spec = sheetPromptPresentationSpec(chrome: .dropdown)
    let item = PromptPresentationItem(
      id: presentationAttachmentID(
        for: sourceIdentity,
        token: spec.token
      ),
      title: title,
      descriptor: spec.descriptor,
      actionPayloads: [],
      messagePayloads: [],
      contentPayloads: withAuthoringContext(sheetContentAuthoringContext) {
        portalDeclaredBuilderChildren(from: sheetContent)
      },
      dismiss: { [isPresented, dismissAuthoringContext, dismissInvalidator, sourceIdentity] in
        withAuthoringContext(dismissAuthoringContext) {
          isPresented.wrappedValue = false
        }
        dismissInvalidator?.requestInvalidation(of: [sourceIdentity])
      }
    )

    node.preferenceValues.merge(
      PresentationCoordinatorDeclarationPreferenceKey.self,
      value: .init(
        declarations: [
          .init(sourceIdentity: sourceIdentity) { registry in
            spec.reconcile(
              registry,
              sourceIdentity,
              item
            )
          }
        ]
      )
    )
    return [node]
  }
}

extension ActionScope where Self: View {
  /// Presents a palette sheet whose content closure receives all
  /// `paletteCommand(...)` contributions absorbed from this scope's
  /// subtree. The snapshot is recomputed each resolve, so an open
  /// palette stays in sync with subtree changes.
  ///
  /// Mirrors `.toolbar(style:)` ↔ `.toolbarItem(...)`.
  @MainActor
  public func paletteSheet<S: StringProtocol, SheetContent: View>(
    _ title: S,
    isPresented: Binding<Bool>,
    @ViewBuilder content: @escaping @MainActor ([ActivePaletteCommand]) -> SheetContent
  ) -> some View & ActionScope {
    modifier(
      BuiltinPaletteSheetPresentationModifier(
        title: String(title),
        isPresented: isPresented,
        sheetContentBuilder: content,
        sheetContentAuthoringContext: makeDeferredAuthoringContext(),
        dismissAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }
}
```

- [ ] **Step 4: Add the absorption test suite**

Create `Tests/SwiftTUITests/PaletteSheetAbsorptionTests.swift`:

```swift
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite
struct PaletteSheetAbsorptionTests {
  @Test("paletteSheet content receives palette commands contributed by its subtree")
  func paletteSheetReceivesSubtreeContributions() {
    let capture = PaletteSheetCaptureBox()

    let view =
      EmptyView()
      .paletteCommand(name: "Alpha", action: {})
      .paletteCommand(name: "Beta", action: {})
      .panel(id: "host")
      .paletteSheet("Palette", isPresented: .constant(true)) { commands in
        capture.commandNames = commands.map(\.name)
        return Text("placeholder")
      }

    let context = ResolveContext(identity: testIdentity("absorption-root"))
    _ = Resolver().resolve(AnyView(view), in: context)

    #expect(capture.commandNames == ["Alpha", "Beta"])
  }

  @Test("paletteSheet clears absorbed commands so they do not re-bubble")
  func paletteSheetClearsAbsorbedCommands() {
    let view =
      EmptyView()
      .paletteCommand(name: "Inner", action: {})
      .panel(id: "inner")
      .paletteSheet("Inner", isPresented: .constant(true)) { _ in Text("") }

    let context = ResolveContext(identity: testIdentity("clear-root"))
    let resolved = Resolver().resolve(AnyView(view), in: context)
    let leftover = resolved.preferenceValues[PaletteCommandsPreferenceKey.self]
    #expect(leftover.isEmpty)
  }

  @Test("paletteSheet content builder is not invoked when isPresented is false")
  func paletteSheetSkipsBuilderWhenNotPresented() {
    let capture = PaletteSheetCaptureBox()

    let view =
      EmptyView()
      .paletteCommand(name: "Alpha", action: {})
      .panel(id: "host")
      .paletteSheet("Palette", isPresented: .constant(false)) { commands in
        capture.commandNames = commands.map(\.name)
        return Text("placeholder")
      }

    let context = ResolveContext(identity: testIdentity("absent-root"))
    _ = Resolver().resolve(AnyView(view), in: context)

    #expect(capture.commandNames.isEmpty)
  }
}

@MainActor
final class PaletteSheetCaptureBox {
  var commandNames: [String] = []
}
```

- [ ] **Step 5: Build and test**

Run: `swift build && swift test`
Expected: all tests pass — new tests included, no existing tests broken.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftTUIViews/ActionScopes/PaletteCommandModifier.swift Sources/SwiftTUIViews/Presentation/PresentationModifiers.swift Tests/SwiftTUITests/PaletteSheetAbsorptionTests.swift
git commit -m "feat(palette): add ActionScope-bound paletteSheet with subtree absorption

PaletteCommand contributions now bubble through a new
PaletteCommandsPreferenceKey in addition to (for now) the existing
CommandRegistry path. The new paletteSheet overload, scoped to
ActionScope, absorbs that preference at its host scope and passes the
snapshot into its content closure. Mirrors .toolbar(style:) +
.toolbarItem(...)."
```

---

## Task 2: Migrate the gallery + delete old `View.paletteSheet`

Switch `GalleryView.swift` and `GalleryTabSwitchTests.swift` to the new API, then remove the old `extension View` `paletteSheet` since nothing else uses it. This is one coherent change: production swaps onto the new API, the test harness drops its proxy, the old API disappears.

**Files:**
- Modify: `Examples/gallery/Sources/GalleryDemoViews/GalleryView.swift:110`
- Modify: `Examples/gallery/Sources/GalleryDemoViews/CommandPalette.swift` (file-level doc only)
- Modify: `Examples/gallery/Tests/GalleryDemoViewsTests/GalleryTabSwitchTests.swift:737-768, :863-868`
- Modify: `Sources/SwiftTUIViews/Presentation/PresentationModifiers.swift:277-300`

- [ ] **Step 1: Switch the gallery to the new paletteSheet**

In `GalleryView.swift`, replace line 110:

```swift
    .paletteSheet("Open...", isPresented: $showPalette, content: { Text("...") })
```

with:

```swift
    .paletteSheet("Command palette", isPresented: $showPalette) { commands in
      CommandPaletteList(
        commands: commands,
        dismiss: { showPalette = false }
      )
    }
```

- [ ] **Step 2: Update the `CommandPalette.swift` doc block**

Replace the file-level doc at the top of `CommandPalette.swift` (lines 3–17 today, ending just before `struct CommandPaletteList: View`):

```swift
/// A fuzzy-filterable command-palette list used inside the Gallery's
/// palette sheet. The outer wrapper intentionally returns a
/// single-child `Group` so the stateful body becomes a DECLARED child
/// instead of the deferred payload's root view. In the graph-backed
/// runtime path, declared children are resolved through `resolveView`,
/// which gives the child its own `viewNode` and therefore safe local
/// `@State` / `@FocusState` storage.
///
/// Commands are passed in by the framework — `.paletteSheet`'s content
/// closure receives the snapshot of `paletteCommand` contributions
/// absorbed from the host scope's subtree (mirroring how
/// `.toolbar(style:)` absorbs toolbar items).
```

- [ ] **Step 3: Strip the proxy from `GalleryTabSwitchTests`**

In `GalleryTabSwitchTests.swift`:

**Delete** the `TestPaletteCommandHolder` class (lines 737–740):

```swift
@MainActor
private final class TestPaletteCommandHolder {
  var commands: [ActivePaletteCommand] = []
}
```

**Replace** the entire `GallerySelectionSeedHarness` struct (lines 742–758) with:

```swift
private struct GallerySelectionSeedHarness: View {
  @State private var selection: GalleryView.GalleryTab
  @State private var isPaletteOpen = false

  init(initialSelection: GalleryView.GalleryTab) {
    _selection = State(initialValue: initialSelection)
  }

  var body: some View {
    GallerySelectionRuntimeBridge(
      selection: $selection,
      isPaletteOpen: $isPaletteOpen
    )
  }
}
```

**Replace** the head of `GallerySelectionRuntimeBridge` (lines 760–772) with:

```swift
private struct GallerySelectionRuntimeBridge: View {
  @Binding var selection: GalleryView.GalleryTab
  @Binding var isPaletteOpen: Bool

  var body: some View {
    galleryBody()
  }
```

(Keep the existing `private func galleryBody() -> some View { ... }` method definition that follows — only the wrapper goes away.)

**Replace** the `.paletteSheet` block at lines 863–868:

```swift
    .paletteSheet("Command palette", isPresented: $isPaletteOpen) {
      CommandPaletteList(
        commands: paletteHolder.commands,
        dismiss: { isPaletteOpen = false }
      )
    }
```

with:

```swift
    .paletteSheet("Command palette", isPresented: $isPaletteOpen) { commands in
      CommandPaletteList(
        commands: commands,
        dismiss: { isPaletteOpen = false }
      )
    }
```

- [ ] **Step 4: Delete the old `View.paletteSheet` extension**

In `Sources/SwiftTUIViews/Presentation/PresentationModifiers.swift`, delete lines 277–300 — the doc comment (`/// Presents content as a full-width…`) through the closing brace of the method body. Leave the surrounding `extension View { ... }` block intact (it still hosts `sheet`, `confirmationDialog`, etc.).

- [ ] **Step 5: Verify with grep**

Run:
```bash
grep -rn "paletteSheet" Sources Tests Examples 2>/dev/null | grep -v ".build" | grep -v "/reference/"
```
Expected: every hit either declares or invokes the new `ActionScope`-bound overload. Search for any caller still using the trailing-closure form without a `commands` parameter (`paletteSheet(…) { Text(…) }` rather than `paletteSheet(…) { commands in … }`); there should be none.

- [ ] **Step 6: Build and test (framework + gallery)**

Run: `swift build && swift test`
Then: `cd Examples/gallery && swift build && swift test && cd -`
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Examples/gallery/Sources/GalleryDemoViews/GalleryView.swift Examples/gallery/Sources/GalleryDemoViews/CommandPalette.swift Examples/gallery/Tests/GalleryDemoViewsTests/GalleryTabSwitchTests.swift Sources/SwiftTUIViews/Presentation/PresentationModifiers.swift
git commit -m "refactor(palette): migrate gallery to ActionScope-bound paletteSheet, drop old API

Gallery now wires CommandPaletteList through the new paletteSheet
closure parameter; the test harness no longer needs
TestPaletteCommandHolder + EnvironmentReader to snapshot commands
across the sheet boundary. The old View-scoped paletteSheet is
deleted in the same commit since nothing else used it."
```

---

## Task 3: Port framework tests off registry + env palette APIs

All framework tests that read palette commands via `commandRegistry.paletteCommands(...)` or `EnvironmentValues.activePaletteCommands` are migrated to the preference-key path (via `.paletteSheet` capture or direct preference read). Tests that exclusively exercise the registry-projection-into-environment mechanism are deleted (those behaviors are gone in the new design; equivalent regressions are covered by `PaletteSheetAbsorptionTests`).

**Files:**
- Modify: `Tests/SwiftTUITests/PaletteCommandTests.swift`
- Modify: `Tests/SwiftTUICoreTests/CommandRegistryTests.swift`
- Modify: `Tests/SwiftTUICoreTests/Graph/ViewGraphTests.swift`
- Modify: `Tests/SwiftTUITests/ImperativeAuthoringContextDispatchTests.swift`
- Modify: `Tests/SwiftTUITests/GalleryStyleDispatchTests.swift`

### The shared port pattern

Every test that captures palette commands via the env path uses this pattern:

```swift
EnvironmentReader(\.activePaletteCommands) { commands in
  capture(commands)
  return innerView
}
```

The replacement is to attach a `.paletteSheet` to the absorbing scope (a Panel) with a builder that captures into a holder. The sheet's `isPresented` is `.constant(true)` so the builder fires each resolve:

```swift
innerView
  .paletteSheet("__capture", isPresented: .constant(true)) { commands in
    capture(commands)
    return EmptyView()
  }
```

For tests that need to fire a specific palette command's action (e.g. `ImperativeAuthoringContextDispatchTests` and `paletteCommandActionMutatesState` in `GalleryStyleDispatchTests`), the absorbed snapshot held by a capture box is the input — call `box.commands.first(where: { $0.name == "X" })?.action()`.

- [ ] **Step 1: Rewrite `PaletteCommandTests.swift`**

Overwrite `Tests/SwiftTUITests/PaletteCommandTests.swift` with:

```swift
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct PaletteCommandTests {
  @Test("paletteCommand contributes a value to PaletteCommandsPreferenceKey")
  func paletteCommandContributes() {
    let view = Panel(id: "editor") { EmptyView() }
      .paletteCommand(name: "Toggle theme", action: {})

    let resolved = Resolver().resolve(
      AnyView(view),
      in: ResolveContext(identity: testIdentity("palette-root"))
    )

    let commands = resolved.preferenceValues[PaletteCommandsPreferenceKey.self]
    #expect(commands.count == 1)
    #expect(commands.first?.name == "Toggle theme")
    #expect(commands.first?.isEnabled == true)
    #expect(commands.first?.description == nil)
  }

  @Test("paletteCommand description survives the contribution")
  func paletteCommandPreservesDescription() {
    let view = Panel(id: "editor") { EmptyView() }
      .paletteCommand(
        name: "Toggle theme",
        description: "Switch between light and dark",
        action: {}
      )

    let resolved = Resolver().resolve(
      AnyView(view),
      in: ResolveContext(identity: testIdentity("palette-root"))
    )

    let commands = resolved.preferenceValues[PaletteCommandsPreferenceKey.self]
    #expect(commands.first?.description == "Switch between light and dark")
  }

  @Test("Disabled paletteCommand is contributed but marked disabled")
  func paletteCommandDisabled() {
    let view = Panel(id: "editor") { EmptyView() }
      .paletteCommand(
        name: "Delete all",
        isEnabled: false,
        action: {}
      )

    let resolved = Resolver().resolve(
      AnyView(view),
      in: ResolveContext(identity: testIdentity("palette-root"))
    )

    let commands = resolved.preferenceValues[PaletteCommandsPreferenceKey.self]
    #expect(commands.first?.isEnabled == false)
  }

  @Test("Multiple paletteCommands accumulate in declaration order")
  func paletteCommandsAccumulate() {
    let view = Panel(id: "editor") { EmptyView() }
      .paletteCommand(name: "Command A", action: {})
      .paletteCommand(name: "Command B", action: {})

    let resolved = Resolver().resolve(
      AnyView(view),
      in: ResolveContext(identity: testIdentity("palette-root"))
    )

    let names = resolved
      .preferenceValues[PaletteCommandsPreferenceKey.self]
      .map(\.name)
    #expect(names == ["Command A", "Command B"])
  }

  @Test("paletteCommand action survives wrapping; invoking it fires the user action")
  func paletteCommandActionWrappedSafely() {
    let fired = PaletteActionFiredBox()
    let view = Panel(id: "editor") { EmptyView() }
      .paletteCommand(name: "Trigger", action: { fired.value = true })

    let resolved = Resolver().resolve(
      AnyView(view),
      in: ResolveContext(identity: testIdentity("palette-root"))
    )
    let commands = resolved.preferenceValues[PaletteCommandsPreferenceKey.self]
    commands.first?.action()
    #expect(fired.value == true)
  }
}

@MainActor
private final class PaletteActionFiredBox {
  var value: Bool = false
}
```

- [ ] **Step 2: Drop palette test from `CommandRegistryTests.swift`**

Delete the `paletteCommandsRegisterAndAccumulate` function in its entirety (from the `@Test("Palette commands register, read back, and accumulate shallowest-first along a chain")` attribute at line 176 through the closing brace at roughly line 207). Leave every other test in the file untouched.

- [ ] **Step 3: Drop palette assertions from `ViewGraphTests.swift`**

In the test around lines 350–427:

Remove the `paletteCommandsByScope:` argument and its value (lines 366–375) from the `CommandRegistrySnapshot(...)` initializer call inside `recordCommandRegistration`. The initializer should now end after the `keyCommandsByScope: [...]` argument.

Delete this line (around line 417):

```swift
    #expect(commandRegistry.paletteCommands(at: childIdentity).map(\.name) == ["Save"])
```

- [ ] **Step 4: Port the palette test in `ImperativeAuthoringContextDispatchTests.swift`**

The test at line 28 (`paletteCommandTargetsDispatchingGraph`) reads:

```swift
    let command = try #require(
      primary.runLoop.commandRegistry.paletteCommands(
        along: primary.runLoop.currentFocusScopePath()
      ).first
    )
    command.action()
```

The fixture is `PaletteCommandScopeFixture` (referenced at line 32). Open `PaletteCommandScopeFixture` (search the file for `struct PaletteCommandScopeFixture`) and wrap its body in `.paletteSheet`, capturing absorbed commands into a static holder. Pattern:

```swift
// At the file scope (alongside other fixtures, search for `private struct PaletteCommandScopeFixture` and replace the struct):
@MainActor
private struct PaletteCommandScopeFixture: View {
  static let absorbed = PaletteCommandFixtureCaptureBox()

  var body: some View {
    // Keep the existing inner content (the paletteCommand chain + Panel that the
    // fixture already declares); only ADD the .paletteSheet capture below.
    existingContent
      .paletteSheet("__capture", isPresented: .constant(true)) { commands in
        Self.absorbed.commands = commands
        return EmptyView()
      }
  }
}

@MainActor
final class PaletteCommandFixtureCaptureBox {
  var commands: [ActivePaletteCommand] = []
}
```

(Where `existingContent` stands for whatever view chain the fixture currently builds. Do not change the chain; only wrap it.)

Then change the test body:

```swift
    let command = try #require(
      PaletteCommandScopeFixture.absorbed.commands.first(where: { $0.name == "Mutate" })
    )
    command.action()
```

(The original test used the first command in scope — match the same selection criterion the existing test asserts on. If the original test was firing the first command without filtering by name, use `.first` instead of `.first(where:)`.)

- [ ] **Step 5: Port `GalleryStyleDispatchTests.swift`**

Apply these per-test changes:

- `galleryKeyCommandDispatchesIntoTabbedContent` (line 15) — keep. If its fixture wraps content in `EnvironmentReader(\.activePaletteCommands) { _ in ... }` purely as scaffolding, drop the wrapper and inline the content.
- `galleryStyleMultipleCommandsDispatch` (line 50) — same: strip any `EnvironmentReader(\.activePaletteCommands)` scaffolding.
- `paletteCommandActionMutatesState` (line 86) — rewrite. The fixture is `GalleryStyleOuter` (line 411). Replace its body:

  ```swift
    var body: some View {
      TabView(selection: $selection) {
        Text("zero").focusable(true).tag(0)
        Text("one").focusable(true).tag(1)
      }
      .tabViewStyle(.literalTabs)
      .panel(id: "gallery")
      .paletteCommand(
        name: "Switch",
        action: {
          selection = 1
          Self.selectionSink.update { $0 = selection }
        }
      )
      .paletteSheet("__capture", isPresented: .constant(true)) { commands in
        Self.capturedCommands.update { $0 = commands }
        return EmptyView()
      }
    }
  ```

  The test body itself (`paletteCommandActionMutatesState`) does not need to change — it already reads `GalleryStyleOuter.capturedCommands.value`.

- `paletteCommandsDoNotAccumulate` (line 109) — rewrite. Replace the registry-count assertion:

  ```swift
    let counts = runLoop.commandRegistry.paletteCommandCountsByScope()
    #expect(counts.count == 1)
    #expect(counts.values.first == 3, "expected 3 palette commands per scope, got \(counts)")
  ```

  with a preference-key read off the fixture's capture box. First, update `PaletteDupProbeRoot` (line 389) to add a capture:

  ```swift
  @MainActor
  private struct PaletteDupProbeRoot: View {
    static let tickSource = LockedBoxLocal<Int>(initial: 0)
    static let absorbed = LockedBoxLocal<[ActivePaletteCommand]>(initial: [])

    @State private var tick: Int = 0

    var body: some View {
      TabView(selection: .constant(0)) {
        Text("tick=\(tick)").focusable(true).tag(0)
      }
      .tabViewStyle(.literalTabs)
      .panel(id: "gallery")
      .paletteCommand(name: "A", action: {})
      .paletteCommand(name: "B", action: {})
      .paletteCommand(name: "C", action: {})
      .paletteSheet("__capture", isPresented: .constant(true)) { commands in
        Self.absorbed.update { $0 = commands }
        return EmptyView()
      }
      .onAppear {
        tick = Self.tickSource.value
      }
    }
  }
  ```

  And replace the test assertion:

  ```swift
    #expect(
      PaletteDupProbeRoot.absorbed.value.count == 3,
      "expected exactly 3 palette commands after re-resolves, got \(PaletteDupProbeRoot.absorbed.value.count)"
    )
  ```

- `altDigitDispatches` (line 132) — keep unchanged (no palette involvement).
- `galleryExactFlowKeyCommandSnapshotsNonEmptyCommands` (line 155) — **delete** the entire test. Its purpose was to verify the env-snapshot capture closure path; that path no longer exists.
- `galleryExactFlowPresentsPaletteImmediatelyAfterRuntimeInput` (line 189) — keep, but adapt `GallerySimulator` (line 333). Replace `GallerySimulator.body`:

  ```swift
    var body: some View {
      galleryBody()
    }

    @ViewBuilder
    private func galleryBody() -> some View {
      TabView(selection: .constant(0)) {
        Text("body").focusable(true).tag(0)
      }
      .tabViewStyle(.literalTabs)
      .toolbarItem(.init(title: "⌃K Palette", action: {}))
      .panel(id: "gallery")
      .keyCommand(
        "Command palette",
        key: .character("k"),
        modifiers: .ctrl,
        action: {
          isPaletteOpen = true
        }
      )
      .paletteCommand(name: "A", action: {})
      .paletteCommand(name: "B", action: {})
      .paletteCommand(name: "C", action: {})
      .toolbar(style: DefaultBottomToolbarStyle())
      .paletteSheet("Command palette", isPresented: $isPaletteOpen) { commands in
        Self.snapshotAtKeyPress.update { $0 = commands }
        return Text("palette sheet")
      }
    }
  ```

  And drop `Self.lastSeenEnvCount` updates (the field is unused without the env reader; remove the `lastSeenEnvCount` static let entirely from `GallerySimulator` along with its initializer line in `reset()`).

- `wrapperHostedGalleryPresentsPaletteImmediatelyAfterRuntimeInput` (line 214) — keep; same `GallerySimulator` changes above apply.
- `toolbarWrappedPanelSurfacesActivePaletteCommandsViaEnv` (line 242) — **delete**. The semantically equivalent regression (Panel + toolbar + palette commands flow through subtree absorption) is covered by `PaletteSheetAbsorptionTests.paletteSheetReceivesSubtreeContributions`.
- `activePaletteCommandsFlowsIntoEnvironment` (line 284) — **delete**. The mechanism it tests is removed.

- [ ] **Step 6: Build and test**

Run: `swift build && swift test`
Then: `cd Examples/gallery && swift build && swift test && cd -`
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Tests/SwiftTUITests/PaletteCommandTests.swift Tests/SwiftTUICoreTests/CommandRegistryTests.swift Tests/SwiftTUICoreTests/Graph/ViewGraphTests.swift Tests/SwiftTUITests/ImperativeAuthoringContextDispatchTests.swift Tests/SwiftTUITests/GalleryStyleDispatchTests.swift
git commit -m "test(palette): port framework tests to PaletteCommandsPreferenceKey

Tests that captured palette commands via EnvironmentReader or read the
CommandRegistry directly are migrated to read absorbed contributions
through .paletteSheet's content closure (or to inspect the preference
key on the resolved root). Three tests whose entire subject was the
removed env-projection mechanism are deleted; their regression cover
is now provided by PaletteSheetAbsorptionTests."
```

---

## Task 4: Strip env key + RunLoop projection

Removes `EnvironmentValues.activePaletteCommands`, the `latestActivePaletteCommands` field, both projection blocks in `RunLoop+Rendering.swift`, and the env-write. These have to land together — deleting the env property without deleting the runtime assignment site breaks the build.

**Files:**
- Modify: `Sources/SwiftTUIViews/ActionScopes/PaletteCommandModifier.swift`
- Modify: `Sources/SwiftTUIRuntime/RunLoop/RunLoop.swift:217`
- Modify: `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift:166-176, 871-881, 1228`

- [ ] **Step 1: Delete the env key + accessor + update header doc**

In `PaletteCommandModifier.swift`, delete:

```swift
private enum ActivePaletteCommandsKey: EnvironmentKey {
  static let defaultValue: [ActivePaletteCommand] = []
}

extension EnvironmentValues {
  /// The palette commands active along the current focus chain,
  /// ordered shallowest-first. Consumer-authored palette views read
  /// this to discover what actions the user can invoke now.
  public var activePaletteCommands: [ActivePaletteCommand] {
    get { self[ActivePaletteCommandsKey.self] }
    set { self[ActivePaletteCommandsKey.self] = newValue }
  }
}
```

Replace the doc block above `ActivePaletteCommand` (currently references the env key):

```swift
/// A snapshot of a palette command visible from the current focus
/// chain, exposed via `EnvironmentValues.activePaletteCommands`.
///
/// Consumer-authored palette surfaces read this value to render and
/// dispatch the commands active at the current focus. The snapshot is
/// updated by the runtime after each frame, so a palette view that
/// reads it sees the commands authored by every scope on the current
/// focus chain — shallowest first.
```

with:

```swift
/// A palette-command contribution carried via
/// `PaletteCommandsPreferenceKey` and absorbed by `.paletteSheet(...)`
/// at the nearest enclosing `ActionScope`. The absorbing scope passes
/// the snapshot from its subtree into the sheet content closure.
```

Replace the doc above the `paletteCommand` extension method (currently references `EnvironmentValues.activePaletteCommands`) with:

```swift
  /// Declares a searchable, consumer-invocable command. Contributions
  /// bubble up to the nearest enclosing `.paletteSheet(...)` (an
  /// `ActionScope`), which absorbs them and passes the snapshot into
  /// its content closure. Mirrors `.toolbarItem(...)` ↔ `.toolbar(style:)`.
```

- [ ] **Step 2: Delete `latestActivePaletteCommands` from RunLoop**

In `RunLoop.swift`, delete line 217:

```swift
  package var latestActivePaletteCommands: [ActivePaletteCommand] = []
```

- [ ] **Step 3: Delete both projection blocks + the env-write**

In `RunLoop+Rendering.swift`:

Delete the block at lines 166–176:

```swift
        latestActivePaletteCommands =
          commandRegistry
          .paletteCommands(along: currentFocusScopePath())
          .map { command in
            ActivePaletteCommand(
              name: command.name,
              description: command.description,
              isEnabled: command.isEnabled,
              action: command.action
            )
          }
```

Delete the identical block at lines 871–881.

Delete line 1228:

```swift
    effectiveEnvironmentValues.activePaletteCommands = latestActivePaletteCommands
```

- [ ] **Step 4: Build and test**

Run: `swift build && swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftTUIViews/ActionScopes/PaletteCommandModifier.swift Sources/SwiftTUIRuntime/RunLoop/RunLoop.swift Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift
git commit -m "refactor(palette): remove activePaletteCommands env + runtime projection

The environment key, the RunLoop's per-frame projection, and the
latestActivePaletteCommands field become dead code now that the
preference-key path is in place. Palette commands flow only through
PaletteCommandsPreferenceKey + .paletteSheet absorption."
```

---

## Task 5: Strip palette code from `CommandRegistry` + `NodeHandlers`

Removes the registry write from `PaletteCommandRegistrationModifier`, drops `RegisteredPaletteCommand`, `paletteCommandsByScope` storage, every `paletteCommand…` method on `CommandRegistry`, the palette field on `CommandRegistrySnapshot`, and the consumer branch in `NodeHandlers.swift`. These have to land together because `NodeHandlers.swift` reads `CommandRegistrySnapshot.paletteCommandsByScope`.

**Files:**
- Modify: `Sources/SwiftTUIViews/ActionScopes/PaletteCommandModifier.swift`
- Modify: `Sources/SwiftTUICore/Runtime/CommandRegistry.swift`
- Modify: `Sources/SwiftTUICore/Resolve/NodeHandlers.swift:225-226`

- [ ] **Step 1: Drop the registry write from `PaletteCommandRegistrationModifier`**

Replace the body of `resolve` (in `PaletteCommandModifier.swift`) with the registry-free version:

```swift
  package func resolve<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    let dynamicPropertyScope = currentImperativeAuthoringContextSnapshot() ?? authoringContext
    let contribution = ActivePaletteCommand(
      name: name,
      description: description,
      isEnabled: isEnabled,
      action: {
        withImperativeAuthoringContext(dynamicPropertyScope) {
          action()
        }
      }
    )
    node.preferenceValues.merge(
      PaletteCommandsPreferenceKey.self,
      value: [contribution]
    )
    return [node]
  }
```

- [ ] **Step 2: Strip palette from `CommandRegistry.swift`**

Apply these deletions in `Sources/SwiftTUICore/Runtime/CommandRegistry.swift`:

Delete the entire `RegisteredPaletteCommand` struct (lines 40–58).

Replace `CommandRegistrySnapshot` (lines 60–75) with the slimmed version:

```swift
package struct CommandRegistrySnapshot: Sendable {
  package var keyCommandsByScope: [Identity: [KeyBinding: RegisteredKeyCommand]]

  package init(
    keyCommandsByScope: [Identity: [KeyBinding: RegisteredKeyCommand]] = [:]
  ) {
    self.keyCommandsByScope = keyCommandsByScope
  }

  package var isEmpty: Bool {
    keyCommandsByScope.isEmpty
  }
}
```

Delete the `paletteCommandsByScope` stored property (line 89).

Delete the entire `registerPaletteCommand(at:command:)` method (lines 120–133).

Delete the entire `paletteCommands(at:)` method (lines 144–147).

Delete the entire `paletteCommands(along:)` method (lines 170–174).

Delete the entire `paletteCommandCountsByScope()` method (lines 182–187).

In `reset()` (lines 177–180), delete the line:

```swift
    paletteCommandsByScope.removeAll(keepingCapacity: true)
```

In `snapshot()` (lines 189–194), drop the `paletteCommandsByScope:` argument so the return becomes:

```swift
  package func snapshot() -> CommandRegistrySnapshot {
    CommandRegistrySnapshot(
      keyCommandsByScope: keyCommandsByScope
    )
  }
```

In `restore(_:)` (lines 196–207), delete the palette loop:

```swift
    for (identity, commands) in snapshot.paletteCommandsByScope {
      paletteCommandsByScope[identity] = commands
    }
```

In `removeSubtrees(rootedAt:)` (lines 214–224), delete the palette loop:

```swift
    for identity in paletteCommandsByScope.keys
    where commandRegistryIdentityMatchesAnySubtreeRoot(identity, roots: roots) {
      paletteCommandsByScope.removeValue(forKey: identity)
    }
```

- [ ] **Step 3: Strip palette from `NodeHandlers.swift`**

In `Sources/SwiftTUICore/Resolve/NodeHandlers.swift`, delete lines 225–226:

```swift
    for (identity, commands) in registration.paletteCommandsByScope {
      commandRegistrations.paletteCommandsByScope[identity] = commands
    }
```

If the file has any other references to `paletteCommandsByScope`, delete them too. Verify with:

```bash
grep -n "paletteCommandsByScope" Sources/SwiftTUICore/Resolve/NodeHandlers.swift
```

Expected after edit: no output.

- [ ] **Step 4: Build and test**

Run: `swift build && swift test`
Then: `cd Examples/gallery && swift build && swift test && cd -`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftTUIViews/ActionScopes/PaletteCommandModifier.swift Sources/SwiftTUICore/Runtime/CommandRegistry.swift Sources/SwiftTUICore/Resolve/NodeHandlers.swift
git commit -m "refactor(registry): remove palette state from CommandRegistry

PaletteCommandRegistrationModifier no longer writes to the registry;
RegisteredPaletteCommand, paletteCommandsByScope, registerPaletteCommand,
paletteCommands(at:), paletteCommands(along:), paletteCommandCountsByScope,
the snapshot field, and the NodeHandlers restore branch all go. The
registry now tracks only key commands."
```

---

## Task 6: Final verification

No code changes — confirm the migration is clean.

- [ ] **Step 1: Full build and test (framework + gallery)**

Run: `swift build && swift test`
Then: `cd Examples/gallery && swift build && swift test && cd -`
Expected: all tests pass.

- [ ] **Step 2: Verify removed symbols are gone**

Run:
```bash
for sym in activePaletteCommands RegisteredPaletteCommand registerPaletteCommand paletteCommandsByScope paletteCommandCountsByScope latestActivePaletteCommands; do
  echo "=== $sym ==="
  grep -rn "$sym" Sources Tests Examples 2>/dev/null | grep -v ".build" | grep -v "/reference/"
done
```
Expected: every block prints just the header and no matches.

- [ ] **Step 3: Verify new symbol is in place**

Run:
```bash
grep -rn "PaletteCommandsPreferenceKey" Sources Tests Examples 2>/dev/null | grep -v ".build"
grep -n "paletteSheet" Examples/gallery/Sources/GalleryDemoViews/GalleryView.swift
```
Expected: the first command lists hits across `PaletteCommandModifier.swift`, `PresentationModifiers.swift`, and the test files that port to it; the second prints exactly one line, using the `commands in` form.

---

## Self-Review Notes

- **Spec coverage:** Subtree absorption (Task 1), removal of old API (Tasks 2, 4, 5), no consumer left behind (Tasks 2, 3), final verification (Task 6).
- **Build-green invariant:** Tasks 4 and 5 are coordinated multi-file commits because their constituent changes mutually reference each other. Every other task is self-contained.
- **TDD overhead removed:** No "write failing test, observe failure, then implement" cycles. The new test suite lands with the new mechanism in Task 1; subsequent tasks rely on the existing + new suite to catch regressions.
- **Bisect resolution:** Six commits at phase boundaries — each commit is a coherent rollback point.
- **Acknowledged risk areas:**
  - Task 3 Step 4: `PaletteCommandScopeFixture`'s exact existing shape isn't quoted in this plan (only the change pattern). The engineer must read the fixture and apply the `.paletteSheet` wrap around its existing chain without altering the chain.
  - Task 3 Step 5: `GalleryStyleDispatchTests.swift`'s per-test instructions describe the change to make; some fixtures (`GalleryStyleOuter`, `PaletteDupProbeRoot`, `GallerySimulator`) get edited to add `.paletteSheet` capture wrappers. The pattern is consistent across them — if one works, the rest follow.
  - Both above are mechanical and any failure surfaces as either a compile error or a failing test inside Task 3, before any destructive change happens.
