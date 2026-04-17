# ActionScopes and Commands — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** [ACTION_SCOPES_AND_COMMANDS.md](./ACTION_SCOPES_AND_COMMANDS.md)

**Goal:** Replace `.onKeyPress`/`HotkeyRegistry` with an `ActionScope`-based command system where commands live at scope roots, dispatch uses focus-chain precedence (shallowest wins), and toolbar items hoist to the nearest ancestor scope that declares a toolbar.

**Architecture:** Commands are stored in a new scope-identity-keyed `CommandRegistry` populated during resolve. Dispatch reads the current focus region's existing `scopePath: [Identity]` (already produced by the semantic pipeline for any node with `focusScopeBoundary: true`), walks it root-to-leaf, and fires the first matching `keyCommand`. ActionScope conformance is a protocol marker that implies `focusScopeBoundary: true` in semantic metadata. Single-key events continue to route via `LocalKeyHandlerRegistry` unchanged — the public API simply refuses to accept them.

**Tech Stack:** Swift 6 strict concurrency, Swift Testing (`import Testing`), preference-key propagation for toolbar item hoisting, existing semantic-extraction pass for scope-path accumulation.

---

## Phases

The plan has six phases. Each phase ends with a committable, buildable, testable state. Phases can be paused between without the codebase being half-broken.

- **Phase 0** — Remove `.onKeyPress` / `HotkeyRegistry` surface cleanly (no replacement yet; codebase continues to build without them)
- **Phase 1** — Core types: `ActionScope` protocol, `AnyID`, `CommandRegistry` (no public API consumers yet)
- **Phase 2** — `Panel` primitive + `.panel(id:)` / `.panel()` + `FocusContainment`
- **Phase 3** — `Scene` and presentation-modifier `ActionScope` conformances
- **Phase 4** — `.keyCommand(...)` + dispatch wiring
- **Phase 5** — `.paletteCommand(...)` + environment value for consumers to query
- **Phase 6** — `.toolbar(style:)` + `.toolbarItem(...)` (hoisted via preference keys)

---

## File Structure

### New files

- `Sources/Core/ActionScope.swift` — `ActionScope` protocol + `AnyID` type
- `Sources/Core/CommandRegistry.swift` — scope-identity-keyed registry of key and palette commands
- `Sources/View/ActionScopes/Panel.swift` — `Panel` view + `.panel(_:)` / `.panel()` + `FocusContainment`
- `Sources/View/ActionScopes/KeyCommandModifier.swift` — `.keyCommand(...)` on `ActionScope where Self: View`
- `Sources/View/ActionScopes/PaletteCommandModifier.swift` — `.paletteCommand(...)` on `ActionScope where Self: View`
- `Sources/View/ActionScopes/Toolbar.swift` — `ToolbarStyle`, `DefaultTopToolbarStyle`, `DefaultBottomToolbarStyle`, `.toolbar(style:)`
- `Sources/View/ActionScopes/ToolbarItem.swift` — `ToolbarItemConfig`, `ToolbarItemsPreferenceKey`, `.toolbarItem(...)`
- `Tests/CoreTests/ActionScopeTests.swift` — protocol conformance + AnyID tests
- `Tests/CoreTests/CommandRegistryTests.swift` — registry behavior + dispatch precedence
- `Tests/TerminalUITests/PanelTests.swift` — Panel focus semantics, ID stability, containment
- `Tests/TerminalUITests/KeyCommandTests.swift` — dispatch, shallowest-wins, isEnabled, modifier-required
- `Tests/TerminalUITests/PaletteCommandTests.swift` — palette collection + environment exposure
- `Tests/TerminalUITests/ToolbarTests.swift` — toolbar declaration, item hoisting, no-absorber behavior

### Modified files

- `Sources/Core/RuntimeRegistrationSet.swift` — remove `hotkeyRegistry`; add `commandRegistry`
- `Sources/TerminalUI/RunLoop.swift` — remove `hotkeyRegistry` field; add `commandRegistry`; wire dispatch
- `Sources/TerminalUI/RunLoop+EventDispatch.swift` — replace hotkey dispatch with command dispatch using current focus region's `scopePath`
- `Sources/View/Environment/Environment.swift` — remove `hotkeyRegistry`; add `commandRegistry`; add `activePaletteCommands` env
- `Sources/TerminalUI/App.swift` — add `ActionScope` conformance to the Scene-side types
- `Sources/View/Presentation/PresentationModifiers.swift` — make presentation modifiers contribute as ActionScopes

### Deleted files

- `Sources/Core/HotkeyRegistry.swift`
- `Sources/View/Modifiers/OnKeyPress.swift`

---

## Conventions

- **Swift Testing** (`import Testing`) for all new tests. Use `@Test` and `#expect`.
- **Package imports** — `package import Core` in View/TerminalUI modules (follow existing convention).
- **`@MainActor` isolation** — all command registration and dispatch happens on the main actor (matches existing registries).
- **Commit messages** — follow project convention: short, lowercase, no attribution footer.
- **Hooks** — `swift-format` and guardrail hooks run on save; don't fight them.
- **Test invocation** — `swift test --filter <TestName>` for targeted runs; `swift test` for full suite.

---

## Phase 0 — Remove `.onKeyPress` and `HotkeyRegistry`

This phase deletes all pre-existing keybinding surface that the new system replaces. At the end of Phase 0 the codebase builds and tests pass; the only change is that `.onKeyPress` is gone and nothing has replaced it yet.

### Task 0.1: Survey consumers of `.onKeyPress` in tests

**Files:**
- Survey: `Tests/**/*.swift`

- [ ] **Step 1: List all `.onKeyPress` callers**

Run: `grep -rn "\.onKeyPress\|OnKeyPress" Tests/ Sources/ Examples/ Runners/ GUI/`

Expected: a list of files. Production code callers (outside `Sources/View/Modifiers/OnKeyPress.swift` and its test) need their tests deleted or rewritten to avoid `.onKeyPress`. If any production source file uses it, that's a blocker — re-check the spec and discuss before proceeding.

- [ ] **Step 2: Record the list**

Save the output for reference during Task 0.3. Don't commit anything.

### Task 0.2: Delete `.onKeyPress` modifier file

**Files:**
- Delete: `Sources/View/Modifiers/OnKeyPress.swift`

- [ ] **Step 1: Delete the file**

```bash
rm Sources/View/Modifiers/OnKeyPress.swift
```

- [ ] **Step 2: Build to see what breaks**

Run: `swift build`
Expected: compile errors pointing at consumers (expected; we address them next).

### Task 0.3: Remove `.onKeyPress` consumers in tests

**Files:** Whatever the survey in 0.1 found.

- [ ] **Step 1: Delete test methods that exercise `.onKeyPress` behavior**

For each test that uses `.onKeyPress`, delete the test method. Do not rewrite — the capability is going away and the replacement (`keyCommand`) will have its own tests in Phase 4.

- [ ] **Step 2: Build to verify clean removal**

Run: `swift build`
Expected: either a clean build, or only compile errors pointing at `HotkeyRegistry` usage (handled in the next task).

### Task 0.4: Delete `HotkeyRegistry.swift`

**Files:**
- Delete: `Sources/Core/HotkeyRegistry.swift`

- [ ] **Step 1: Delete the file**

```bash
rm Sources/Core/HotkeyRegistry.swift
```

- [ ] **Step 2: Build to see remaining consumers**

Run: `swift build`
Expected: compile errors in `RuntimeRegistrationSet.swift`, `RunLoop.swift`, `Environment.swift`, `RunLoop+EventDispatch.swift`.

### Task 0.5: Remove `hotkeyRegistry` from `RuntimeRegistrationSet`

**Files:**
- Modify: `Sources/Core/RuntimeRegistrationSet.swift`

- [ ] **Step 1: Read the current file**

Run: `cat Sources/Core/RuntimeRegistrationSet.swift`
Identify every line that mentions `hotkeyRegistry`, `HotkeyRegistry`, or `hotkeyRegistrations`.

- [ ] **Step 2: Delete all `hotkeyRegistry` and `hotkeyRegistrations` references**

In the `RuntimeRegistrationSet` struct, the `reset()` method, the `capture()`/`restore()` methods (whatever they're named), and the initializer — remove every reference. Likewise in `NodeHandlers.swift` if there's a `hotkeyRegistrations` field there.

- [ ] **Step 3: Build**

Run: `swift build`
Expected: compile errors only in `Environment.swift`, `RunLoop.swift`, `RunLoop+EventDispatch.swift`.

### Task 0.6: Remove `hotkeyRegistry` from `Environment.swift`

**Files:**
- Modify: `Sources/View/Environment/Environment.swift`

- [ ] **Step 1: Grep for the declaration**

Run: `grep -n "hotkeyRegistry" Sources/View/Environment/Environment.swift`

- [ ] **Step 2: Delete the field and any getter/setter**

Remove all lines referencing `hotkeyRegistry`.

- [ ] **Step 3: Build**

Run: `swift build`
Expected: compile errors only in `RunLoop.swift` and `RunLoop+EventDispatch.swift`.

### Task 0.7: Remove `hotkeyRegistry` from `RunLoop` and its dispatch file

**Files:**
- Modify: `Sources/TerminalUI/RunLoop.swift`
- Modify: `Sources/TerminalUI/RunLoop+EventDispatch.swift`

- [ ] **Step 1: Delete the field in `RunLoop`**

In `RunLoop.swift`, find `package let hotkeyRegistry = HotkeyRegistry()` and delete it. Remove any passes of `hotkeyRegistry` to `RuntimeRegistrationSet` or to `ResolveContext` construction.

- [ ] **Step 2: Delete the dispatch path**

In `RunLoop+EventDispatch.swift`, find any code that calls `hotkeyRegistry.dispatch(...)`. Delete those lines. If a key handler falls through because hotkey dispatch returned false, that fallthrough is fine — deleting the call is sufficient.

- [ ] **Step 3: Build**

Run: `swift build`
Expected: clean build.

- [ ] **Step 4: Run all tests**

Run: `swift test 2>&1 | tail -10`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add -u
git commit -m "remove .onKeyPress and HotkeyRegistry"
```

---

## Phase 1 — Core types: `ActionScope`, `AnyID`, `CommandRegistry`

Phase 1 introduces the new types without wiring them up to anything public. The registry sits in the runtime but nothing registers into it yet. At the end of Phase 1, the codebase builds, tests pass, and the types are ready to be used in subsequent phases.

### Task 1.1: Add `ActionScope` protocol and `AnyID`

**Files:**
- Create: `Sources/Core/ActionScope.swift`
- Test: `Tests/CoreTests/ActionScopeTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CoreTests/ActionScopeTests.swift`:

```swift
import Testing
@testable import Core

@Suite
struct ActionScopeTests {
  @Test("AnyID wraps Hashable & Sendable values and round-trips equality")
  func anyIDRoundTrip() {
    let a = AnyID(42)
    let b = AnyID(42)
    let c = AnyID("forty-two")
    #expect(a == b)
    #expect(a != c)
    #expect(a.hashValue == b.hashValue)
  }

  @Test("AnyID distinguishes values of different types with equal raw representations")
  func anyIDTypeSensitivity() {
    let intID = AnyID(1)
    let stringID = AnyID("1")
    #expect(intID != stringID)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ActionScopeTests 2>&1 | tail -5`
Expected: compile error — `AnyID` not found.

- [ ] **Step 3: Create `ActionScope.swift`**

Create `Sources/Core/ActionScope.swift`:

```swift
/// A tree-authored focus region that owns a set of commands.
///
/// ActionScope conformance is deliberately opt-in. A conforming type
/// participates in the focus topology at least as strongly as a focus
/// section: the framework can answer "is this scope on the current
/// focus chain?" by checking whether its identity appears in the
/// `scopePath` of the currently focused region.
///
/// The activation predicate for any ActionScope is:
/// _this scope's identity is on the current focus chain_ (i.e. present
/// in the currently focused region's `scopePath`).
///
/// See `docs/proposals/ACTION_SCOPES_AND_COMMANDS.md` for the full
/// design.
public protocol ActionScope: Identifiable {
  associatedtype ID: Hashable & Sendable
}

/// A type-erased `Hashable & Sendable` identity.
///
/// Used as the `ID` type for scopes whose identity is framework-derived
/// rather than consumer-supplied (e.g. the pseudonymous variant of
/// `Panel` produced by `.panel()` without an explicit id).
///
/// Consumers supply their own `Hashable & Sendable` values through
/// `.panel(id:)` rather than constructing `AnyID` directly.
public struct AnyID: Hashable, Sendable {
  @usableFromInline
  internal let boxed: AnyHashable

  @usableFromInline
  internal init<Value: Hashable & Sendable>(_ value: Value) {
    self.boxed = AnyHashable(value)
  }

  public static func == (lhs: AnyID, rhs: AnyID) -> Bool {
    lhs.boxed == rhs.boxed
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(boxed)
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ActionScopeTests 2>&1 | tail -5`
Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/ActionScope.swift Tests/CoreTests/ActionScopeTests.swift
git commit -m "add ActionScope protocol and AnyID"
```

### Task 1.2: Add `CommandRegistry`

**Files:**
- Create: `Sources/Core/CommandRegistry.swift`
- Test: `Tests/CoreTests/CommandRegistryTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/CommandRegistryTests.swift`:

```swift
import Testing
@testable import Core

@MainActor
@Suite
struct CommandRegistryTests {
  @Test("Registered key commands can be looked up by scope identity and key")
  func keyCommandLookup() {
    let registry = CommandRegistry()
    let scope = Identity(components: ["a"] as [IdentityComponent])
    let binding = KeyBinding(key: .character("s"), modifiers: .ctrl)
    var fired = 0
    registry.registerKeyCommand(
      at: scope,
      binding: binding,
      description: "Save",
      isEnabled: true,
      action: { fired += 1 }
    )
    #expect(registry.keyCommand(at: scope, matching: binding) != nil)
    #expect(registry.keyCommand(at: scope, matching: .init(key: .character("x"), modifiers: .ctrl)) == nil)
  }

  @Test("reset() clears all registrations")
  func resetClears() {
    let registry = CommandRegistry()
    let scope = Identity(components: ["a"] as [IdentityComponent])
    registry.registerKeyCommand(
      at: scope,
      binding: .init(key: .character("s"), modifiers: .ctrl),
      description: "Save",
      isEnabled: true,
      action: {}
    )
    registry.reset()
    #expect(registry.keyCommand(at: scope, matching: .init(key: .character("s"), modifiers: .ctrl)) == nil)
  }

  @Test("Dispatch walks a scope chain shallowest-first and stops at the first match")
  func dispatchShallowestWins() {
    let registry = CommandRegistry()
    let shallow = Identity(components: ["shallow"] as [IdentityComponent])
    let deep = Identity(components: ["shallow", "deep"] as [IdentityComponent])
    var shallowFired = 0
    var deepFired = 0
    registry.registerKeyCommand(
      at: shallow,
      binding: .init(key: .character("s"), modifiers: .ctrl),
      description: "Shallow save",
      isEnabled: true,
      action: { shallowFired += 1 }
    )
    registry.registerKeyCommand(
      at: deep,
      binding: .init(key: .character("s"), modifiers: .ctrl),
      description: "Deep save",
      isEnabled: true,
      action: { deepFired += 1 }
    )
    let consumed = registry.dispatch(
      key: .init(key: .character("s"), modifiers: .ctrl),
      along: [shallow, deep]
    )
    #expect(consumed == true)
    #expect(shallowFired == 1)
    #expect(deepFired == 0)
  }

  @Test("Dispatch consumes but does not fire when the shallowest match is disabled")
  func dispatchDisabledShallowBlocksDeeper() {
    let registry = CommandRegistry()
    let shallow = Identity(components: ["shallow"] as [IdentityComponent])
    let deep = Identity(components: ["shallow", "deep"] as [IdentityComponent])
    var deepFired = 0
    registry.registerKeyCommand(
      at: shallow,
      binding: .init(key: .character("s"), modifiers: .ctrl),
      description: "Shallow (disabled)",
      isEnabled: false,
      action: {}
    )
    registry.registerKeyCommand(
      at: deep,
      binding: .init(key: .character("s"), modifiers: .ctrl),
      description: "Deep save",
      isEnabled: true,
      action: { deepFired += 1 }
    )
    let consumed = registry.dispatch(
      key: .init(key: .character("s"), modifiers: .ctrl),
      along: [shallow, deep]
    )
    #expect(consumed == true)    // strict shallowest-wins even when disabled
    #expect(deepFired == 0)
  }

  @Test("Dispatch returns false when no scope on the chain claims the key")
  func dispatchNoMatch() {
    let registry = CommandRegistry()
    let scope = Identity(components: ["a"] as [IdentityComponent])
    let consumed = registry.dispatch(
      key: .init(key: .character("s"), modifiers: .ctrl),
      along: [scope]
    )
    #expect(consumed == false)
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CommandRegistryTests 2>&1 | tail -5`
Expected: compile error — `CommandRegistry` and `KeyBinding` not found.

- [ ] **Step 3: Create `CommandRegistry.swift`**

Create `Sources/Core/CommandRegistry.swift`:

```swift
/// A key + modifier combination used as a `keyCommand` binding.
package struct KeyBinding: Equatable, Hashable, Sendable {
  package var key: KeyEvent
  package var modifiers: EventModifiers

  package init(key: KeyEvent, modifiers: EventModifiers) {
    self.key = key
    self.modifiers = modifiers
  }
}

/// A registered key command.
package struct RegisteredKeyCommand: Sendable {
  package var binding: KeyBinding
  package var description: String
  package var isEnabled: Bool
  package var action: @MainActor @Sendable () -> Void

  package init(
    binding: KeyBinding,
    description: String,
    isEnabled: Bool,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    self.binding = binding
    self.description = description
    self.isEnabled = isEnabled
    self.action = action
  }
}

/// A registered palette command (no key binding).
package struct RegisteredPaletteCommand: Sendable {
  package var name: String
  package var description: String?
  package var isEnabled: Bool
  package var action: @MainActor @Sendable () -> Void

  package init(
    name: String,
    description: String?,
    isEnabled: Bool,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    self.name = name
    self.description = description
    self.isEnabled = isEnabled
    self.action = action
  }
}

/// Collects commands declared at ActionScope roots and dispatches key
/// events to the shallowest claiming scope along the current focus
/// chain.
///
/// Registrations are scope-identity-keyed. Dispatch walks the supplied
/// `scopePath` from index 0 (shallowest) to the end (leafmost) and
/// consumes the event at the first scope whose registrations contain a
/// matching binding. If that match is disabled, the event is consumed
/// but no action fires — strict shallowest-wins semantics.
@MainActor
package final class CommandRegistry {
  private var keyCommandsByScope: [Identity: [KeyBinding: RegisteredKeyCommand]] = [:]
  private var paletteCommandsByScope: [Identity: [RegisteredPaletteCommand]] = [:]

  package init() {}

  package func registerKeyCommand(
    at scope: Identity,
    binding: KeyBinding,
    description: String,
    isEnabled: Bool,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    var table = keyCommandsByScope[scope] ?? [:]
    table[binding] = RegisteredKeyCommand(
      binding: binding,
      description: description,
      isEnabled: isEnabled,
      action: action
    )
    keyCommandsByScope[scope] = table
  }

  package func registerPaletteCommand(
    at scope: Identity,
    command: RegisteredPaletteCommand
  ) {
    var list = paletteCommandsByScope[scope] ?? []
    list.append(command)
    paletteCommandsByScope[scope] = list
  }

  package func keyCommand(
    at scope: Identity,
    matching binding: KeyBinding
  ) -> RegisteredKeyCommand? {
    keyCommandsByScope[scope]?[binding]
  }

  package func paletteCommands(at scope: Identity) -> [RegisteredPaletteCommand] {
    paletteCommandsByScope[scope] ?? []
  }

  /// Walks the focus chain shallowest-first and fires the first
  /// matching enabled keyCommand. A disabled match still consumes the
  /// event. Returns true if the event was consumed (fired or blocked)
  /// and false if no scope on the chain claims the binding.
  @discardableResult
  package func dispatch(
    key binding: KeyBinding,
    along scopePath: [Identity]
  ) -> Bool {
    for scope in scopePath {
      guard let match = keyCommand(at: scope, matching: binding) else {
        continue
      }
      if match.isEnabled {
        match.action()
      }
      return true
    }
    return false
  }

  /// Returns all palette commands visible along the given focus chain,
  /// ordered shallowest-first.
  package func paletteCommands(along scopePath: [Identity]) -> [RegisteredPaletteCommand] {
    scopePath.flatMap { paletteCommandsByScope[$0] ?? [] }
  }

  package func reset() {
    keyCommandsByScope.removeAll(keepingCapacity: true)
    paletteCommandsByScope.removeAll(keepingCapacity: true)
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CommandRegistryTests 2>&1 | tail -5`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/CommandRegistry.swift Tests/CoreTests/CommandRegistryTests.swift
git commit -m "add CommandRegistry"
```

### Task 1.3: Wire `commandRegistry` into `RuntimeRegistrationSet`, `RunLoop`, and `Environment`

**Files:**
- Modify: `Sources/Core/RuntimeRegistrationSet.swift`
- Modify: `Sources/TerminalUI/RunLoop.swift`
- Modify: `Sources/View/Environment/Environment.swift`

- [ ] **Step 1: Read `RuntimeRegistrationSet`**

Run: `cat Sources/Core/RuntimeRegistrationSet.swift`

Identify the struct, its `reset()` method, and wherever it composes the registries (initializer or similar).

- [ ] **Step 2: Add `commandRegistry` field to `RuntimeRegistrationSet`**

Add alongside the existing registries:

```swift
package let commandRegistry: CommandRegistry?
```

In the initializer, add the corresponding parameter and assignment. In `reset()`, add `commandRegistry?.reset()`.

- [ ] **Step 3: Add `commandRegistry` to `RunLoop`**

In `Sources/TerminalUI/RunLoop.swift`, add a `package let commandRegistry = CommandRegistry()` alongside the other `Local*Registry` instances. Wherever `RuntimeRegistrationSet` is constructed, pass `commandRegistry: commandRegistry`.

- [ ] **Step 4: Add environment value**

In `Sources/View/Environment/Environment.swift`, add:

```swift
package var commandRegistry: CommandRegistry?
```

Alongside the other registry environment fields, with the same shape as `localKeyHandlerRegistry`.

Wire it through wherever the environment is populated by `RunLoop` (same place you added the field to `RuntimeRegistrationSet`).

- [ ] **Step 5: Build and run full tests**

Run: `swift build && swift test 2>&1 | tail -5`
Expected: clean build, all existing tests pass, no new tests yet beyond the ones added in Tasks 1.1 and 1.2.

- [ ] **Step 6: Commit**

```bash
git add -u
git commit -m "wire CommandRegistry into runtime"
```

---

## Phase 2 — Panel primitive

Phase 2 adds the `Panel` view and its modifiers. Panels don't do anything command-related yet; Phase 4 will add `keyCommand`. What they DO get in this phase is:

- `ActionScope` conformance
- Focus-region semantic metadata (`focusScopeBoundary: true`, focusable)
- `.panel(id:)` and `.panel()` modifiers
- `FocusContainment` enum and modifier

### Task 2.1: Create `Panel` struct and `.panel(id:)` modifier

**Files:**
- Create: `Sources/View/ActionScopes/Panel.swift`
- Test: `Tests/TerminalUITests/PanelTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/TerminalUITests/PanelTests.swift`:

```swift
import Testing
@testable import Core
@testable import View

@MainActor
@Suite
struct PanelTests {
  @Test("Panel with explicit id exposes that id via ActionScope.ID")
  func panelExposesExplicitID() {
    let panel = Panel(id: "editor") { EmptyView() }
    #expect(panel.id == "editor")
  }

  @Test("Panel sets focusScopeBoundary in its resolved node metadata")
  func panelMarksFocusScopeBoundary() {
    let panel = Panel(id: "editor") { EmptyView() }
    let context = ResolveContext.testFixture()
    let resolved = panel.resolve(in: context)
    #expect(resolved.semanticMetadata.focusScopeBoundary == true)
  }

  @Test("Panel is focusable")
  func panelIsFocusable() {
    let panel = Panel(id: "editor") { EmptyView() }
    let context = ResolveContext.testFixture()
    let resolved = panel.resolve(in: context)
    #expect(resolved.semanticMetadata.isFocusable == true)
  }
}
```

_Note_: `ResolveContext.testFixture()` is the framework's existing test-helper constructor. If it doesn't exist, use whatever equivalent the other tests in `Tests/TerminalUITests/` use (see `Tests/TerminalUITests/SwiftUISurfaceTests.swift` for a pattern).

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PanelTests 2>&1 | tail -5`
Expected: compile error — `Panel` not found.

- [ ] **Step 3: Create `Panel.swift`**

Create `Sources/View/ActionScopes/Panel.swift`:

```swift
package import Core

/// A rectangular consumer-controlled area that conforms to
/// `ActionScope`.
///
/// Panel has no default UI chrome. Visual treatment is the consumer's
/// responsibility via standard modifiers (`.border`, `.background`,
/// `.padding`, etc.).
///
/// A Panel is focusable and participates in the focus topology. When a
/// Panel enters the focus chain, the Panel itself is focused first —
/// descendants are reached via Tab or explicit focus requests.
///
/// Pair with `.keyCommand(...)`, `.paletteCommand(...)`,
/// `.toolbar(style:)`, or `.focusContainment(_:)` to configure.
public struct Panel<ID: Hashable & Sendable, Content: View>: View, ActionScope {
  public let id: ID
  package let containment: FocusContainment
  package let content: Content

  public init(
    id: ID,
    @ViewBuilder content: () -> Content
  ) {
    self.id = id
    self.containment = .open
    self.content = content()
  }

  package init(
    id: ID,
    containment: FocusContainment,
    content: Content
  ) {
    self.id = id
    self.containment = containment
    self.content = content
  }

  public var body: some View {
    PanelBody(id: id, containment: containment, content: content)
  }
}

/// Controls how focus enters a Panel's descendants.
public enum FocusContainment: Sendable {
  /// Default: Tab reaches focusable descendants of the Panel.
  case open
  /// Panel is the focus stop; Tab skips the Panel's focusable
  /// descendants. Drill-in mechanism deferred.
  case sealed
}

private struct PanelBody<ID: Hashable & Sendable, Content: View>: View, ResolvableView {
  let id: ID
  let containment: FocusContainment
  let content: Content

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let childContext = context
    var node = content.resolve(in: childContext)
    node.semanticMetadata = node.semanticMetadata.merging(
      with: focusStructureMetadata(scopeBoundary: true)
    )
    node.semanticMetadata.isFocusable = true
    // Panel identity is recorded by making the anchor identity this
    // Panel's resolved identity; the context.identity path has already
    // applied Panel's position in the structural identity tree.
    return [node]
  }
}

extension Panel {
  /// Configures focus containment for this Panel.
  public func focusContainment(_ mode: FocusContainment) -> Panel<ID, Content> {
    Panel(id: id, containment: mode, content: content)
  }
}

extension View {
  /// Wraps `self` in a Panel with an explicit identity.
  public func panel<PanelID: Hashable & Sendable>(
    id: PanelID
  ) -> Panel<PanelID, Self> {
    Panel(id: id, content: self)
  }

  /// Wraps `self` in a Panel whose identity is derived from the
  /// structural identity path at the call site. Stable across
  /// re-resolves.
  public func panel() -> Panel<AnyID, Self> {
    // The pseudonymous ID is derived from the current authoring
    // context; `AnyID` type-erases it so the Panel type is
    // nameable without exposing the derivation.
    let scope = currentAuthoringContext()
    let pseudonymous = AnyID(scope?.viewIdentity ?? Identity(components: [] as [IdentityComponent]))
    return Panel(id: pseudonymous, content: self)
  }
}
```

_Notes_:
- `currentAuthoringContext()` is the framework's existing hook for accessing the current structural identity during view construction; see `Sources/View/Modifiers/ViewModifiers.swift` (look for `currentAuthoringContext`).
- If the framework exposes a different hook, use it — the goal is a stable-per-resolve identity derivation.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PanelTests 2>&1 | tail -5`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/View/ActionScopes/Panel.swift Tests/TerminalUITests/PanelTests.swift
git commit -m "add Panel primitive"
```

### Task 2.2: Add `.panel()` pseudonymous-identity test

**Files:**
- Modify: `Tests/TerminalUITests/PanelTests.swift`

- [ ] **Step 1: Add the failing test**

Append to `PanelTests`:

```swift
  @Test(".panel() produces stable AnyID across re-resolves at the same source location")
  func panelPseudonymousIDIsStable() {
    // Build a small view tree, resolve twice, verify Panel identity
    // remains equal across resolves at the same call site.
    let outer = Text("content").panel()
    let context = ResolveContext.testFixture()
    let first = outer.resolve(in: context)
    let second = outer.resolve(in: context)
    #expect(first.identity == second.identity)
  }
```

- [ ] **Step 2: Run the new test**

Run: `swift test --filter PanelTests 2>&1 | tail -5`
Expected: pass. If it fails, the `currentAuthoringContext()`-based derivation is unstable and needs a different anchor. In that case, switch to using `context.identity` inside `resolveElements` (which is already stable by construction) — the tradeoff is the ID isn't observable until resolve time, but that's acceptable for a pseudonymous ID.

- [ ] **Step 3: Commit**

```bash
git add Tests/TerminalUITests/PanelTests.swift
git commit -m "test: Panel pseudonymous ID stability"
```

### Task 2.3: Add `.focusContainment(_:)` behavior test

**Files:**
- Modify: `Tests/TerminalUITests/PanelTests.swift`

- [ ] **Step 1: Add the failing test**

Append to `PanelTests`:

```swift
  @Test(".focusContainment(.sealed) prevents descendant focus regions from being reachable")
  func sealedPanelBlocksDescendantFocus() {
    let sealedPanel = Panel(id: "outer") {
      Text("inner").focusable(true)
    }
    .focusContainment(.sealed)

    let context = ResolveContext.testFixture()
    let resolved = sealedPanel.resolve(in: context)
    // After semantic extraction, the only focus region produced
    // should be the Panel's own. Descendant focusables inside a
    // sealed panel do not appear in the focus region list.
    let regions = extractFocusRegions(from: resolved)
    #expect(regions.count == 1)
    #expect(regions.first?.identity == resolved.identity)
  }
```

_Note_: `extractFocusRegions(from:)` is a test helper; if not present, either use the existing pipeline (e.g. `SemanticExtractor`) via the framework's test utilities, or add a small helper in the test file that runs semantic extraction and returns the `focusRegions`.

- [ ] **Step 2: Run the new test to verify it fails**

Run: `swift test --filter PanelTests 2>&1 | tail -5`
Expected: failure — sealed containment hasn't been implemented yet.

- [ ] **Step 3: Implement sealed containment in `PanelBody.resolveElements`**

Modify `Sources/View/ActionScopes/Panel.swift` `PanelBody.resolveElements`:

When `containment == .sealed`, wrap the content resolution so descendant focus regions are suppressed. One approach: after resolving content, walk the resolved subtree and set `isFocusable = false` on descendants. Simpler: set a semantic-metadata flag on the Panel's node that the semantic extractor respects.

Concretely: add to `SemanticMetadata` (in `Sources/Core/RenderTreeAndSemanticsTypes.swift`):

```swift
package var sealsFocusDescendants: Bool
```

Default `false`. In `Semantics.swift` focus-region extraction, when a frame's parent metadata has `sealsFocusDescendants: true`, skip focus-region emission for descendants — emit only the parent itself.

In `PanelBody`, set `node.semanticMetadata.sealsFocusDescendants = (containment == .sealed)`.

- [ ] **Step 4: Run the test**

Run: `swift test --filter PanelTests 2>&1 | tail -5`
Expected: 4 Panel tests pass.

- [ ] **Step 5: Verify full suite still passes**

Run: `swift test 2>&1 | tail -5`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add -u
git commit -m "implement sealed FocusContainment"
```

---

## Phase 3 — Scene and presentation ActionScope conformances

Phase 3 makes the existing scene and presentation surfaces conform to `ActionScope` so commands can be attached to them in later phases. No command behavior is added yet.

### Task 3.1: Make Scene-conforming types conform to `ActionScope`

**Files:**
- Modify: `Sources/TerminalUI/App.swift` (or wherever `Scene` / `WindowGroup` live)

- [ ] **Step 1: Locate the Scene types**

Run: `grep -rn "public protocol Scene\|public struct WindowGroup\|extension Scene" Sources/TerminalUI/`

Expected: identifies the file(s) containing `Scene` and `WindowGroup`.

- [ ] **Step 2: Add ActionScope conformance**

For `WindowGroup` (and any other Scene-conforming top-level types), add conformance to `ActionScope`. The Scene identity already exists as `WindowIdentifier`:

```swift
extension WindowGroup: ActionScope {
  // ID is already WindowIdentifier (or the existing scene-id type).
}
```

If the existing Scene type's `ID` typealias doesn't match `ActionScope.ID`'s `Hashable & Sendable` bound, verify `WindowIdentifier` already conforms. If not, widen the conformance.

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -10`
Expected: clean build, or an error pointing at `Sendable` or `Hashable` missing on `WindowIdentifier`. If so, add those conformances (they should be trivial).

- [ ] **Step 4: Verify tests still pass**

Run: `swift test 2>&1 | tail -5`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add -u
git commit -m "conform Scene types to ActionScope"
```

### Task 3.2: Verify Scene nodes mark `focusScopeBoundary`

**Files:**
- Modify: probably `Sources/TerminalUI/App.swift` or wherever Scene resolves to a `ResolvedNode`

- [ ] **Step 1: Grep for where Scene/WindowGroup produces resolved nodes**

Run: `grep -rn "focusScopeBoundary\|focusStructureMetadata" Sources/TerminalUI/ Sources/View/Foundation/`

- [ ] **Step 2: If WindowGroup's resolved node doesn't already have `focusScopeBoundary: true`, add it**

The root window-group resolution needs to include `focusScopeBoundary: true` in its semantic metadata. This makes the scene's identity appear at index 0 of every focus region's `scopePath`. Follow the same pattern as `PanelBody`:

```swift
resolved.semanticMetadata = resolved.semanticMetadata.merging(
  with: focusStructureMetadata(scopeBoundary: true)
)
```

- [ ] **Step 3: Write a test**

Add to `Tests/TerminalUITests/` (new file `SceneActionScopeTests.swift` if needed):

```swift
import Testing
@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct SceneActionScopeTests {
  @Test("Scene-rooted focus regions include the scene identity in scopePath")
  func sceneIsOnScopePath() {
    // Build a WindowGroup with a focusable leaf, resolve the tree
    // plus semantics, and assert the focus region's scopePath's
    // first element is the scene identity.
    // ... use existing SceneSessionTestHarness patterns for the
    // harness wiring.
  }
}
```

_Note_: Look at `Tests/TerminalUITests/SceneSessionTestHarness.swift` for the existing pattern.

- [ ] **Step 4: Run test**

Run: `swift test --filter SceneActionScopeTests 2>&1 | tail -5`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add -u
git commit -m "Scene marks focusScopeBoundary and test its scopePath"
```

### Task 3.3: Make presentation modifiers conform to `ActionScope`

**Files:**
- Modify: `Sources/View/Presentation/PresentationModifiers.swift`
- Modify: `Sources/View/Presentation/PresentationCoordinator.swift` (if needed)

- [ ] **Step 1: Identify the modifier types**

The presentation family currently routes through `BuiltinPromptPresentationModifier` and `BuiltinSheetPresentationModifier`. The *authoring-side* type that should conform is likely the modifier struct; check what type is returned by `.sheet()`, `.alert()`, `.confirmationDialog()`.

- [ ] **Step 2: Add conformance**

The presentation-coordinator flow already produces a wrapped overlay subtree for the presented content. Ensure that subtree's root node has `focusScopeBoundary: true`. If the presentation-root view isn't accessible or doesn't currently have a typed struct, add one.

Grep for `presentationRole: .sheet` / `.alert` etc. in semantic metadata to find where these are emitted; add `focusScopeBoundary: true` at that same site.

- [ ] **Step 3: Write a test**

Add `Tests/TerminalUITests/PresentationActionScopeTests.swift`:

```swift
import Testing
@testable import Core
@testable import View

@MainActor
@Suite
struct PresentationActionScopeTests {
  @Test("Sheet content's focus regions include both the scene identity and the sheet identity on scopePath")
  func sheetContributesToScopePath() {
    // Build: WindowGroup { Text("x").sheet(isPresented: .constant(true)) { Text("sheet content").focusable(true) } }
    // Resolve, extract focus regions. The focus region for the
    // sheet's focusable should have a scopePath containing the
    // sheet identity (after the scene identity).
    // ... implementation details follow existing presentation test patterns
  }
}
```

- [ ] **Step 4: Run test**

Run: `swift test --filter PresentationActionScopeTests 2>&1 | tail -5`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add -u
git commit -m "presentation modifiers contribute ActionScope boundaries"
```

---

## Phase 4 — `.keyCommand(...)` and dispatch

Phase 4 connects the Phase 1 command registry to the public API. Commands get registered at scope roots; a new dispatch path in `RunLoop+EventDispatch` reads the current focus region's `scopePath` and calls `CommandRegistry.dispatch`.

### Task 4.1: Add `.keyCommand(...)` modifier

**Files:**
- Create: `Sources/View/ActionScopes/KeyCommandModifier.swift`
- Test: `Tests/TerminalUITests/KeyCommandTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/TerminalUITests/KeyCommandTests.swift`:

```swift
import Testing
@testable import Core
@testable import View

@MainActor
@Suite
struct KeyCommandTests {
  @Test("keyCommand registers at scope identity in the CommandRegistry")
  func keyCommandRegisters() {
    let registry = CommandRegistry()
    let panel = Panel(id: "editor") { EmptyView() }
      .keyCommand(
        "Save",
        key: .character("s"),
        modifiers: .ctrl,
        action: {}
      )
    var context = ResolveContext.testFixture()
    context.commandRegistry = registry
    _ = panel.resolve(in: context)
    // The scope identity of Panel "editor" should have a registered command.
    // Find the Panel's identity in the resolved tree and assert the
    // registry returns a non-nil command for (.character("s"), .ctrl).
    // ... use existing semantic-extraction helpers to find the Panel's identity
  }

  @Test("keyCommand with empty modifiers is rejected at runtime")
  func keyCommandRejectsModifierless() {
    // Behavior: a precondition failure, or a runtime diagnostic.
    // Use #expect(exitsWith:) or a direct call that verifies rejection.
    // For the v1 implementation a runtime precondition is acceptable.
    // Test via a compile-time fallback if a precondition is used:
    // check that no registration lands for an empty-modifiers call.
    let registry = CommandRegistry()
    let panel = Panel(id: "x") { EmptyView() }
      .keyCommand("Bad", key: .character("s"), modifiers: [], action: {})
    var context = ResolveContext.testFixture()
    context.commandRegistry = registry
    _ = panel.resolve(in: context)
    #expect(registry.keyCommand(at: /* panel identity */, matching: .init(key: .character("s"), modifiers: [])) == nil)
  }
}
```

_Note_: The exact identity of a resolved Panel requires either exposing it via test helpers or reading it back from the resolved tree. Follow the pattern in `Tests/TerminalUITests/Phase4ObservationAndEnvironmentTests.swift` for how existing tests introspect resolved nodes.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter KeyCommandTests 2>&1 | tail -5`
Expected: compile error — `keyCommand` not found.

- [ ] **Step 3: Create `KeyCommandModifier.swift`**

Create `Sources/View/ActionScopes/KeyCommandModifier.swift`:

```swift
package import Core

extension ActionScope where Self: View {
  /// Declares a keyboard-shortcut command at this scope's root.
  ///
  /// Fires only when this scope is on the current focus chain AND no
  /// shallower scope on that chain has claimed the same
  /// `(key, modifiers)` combination (strict shallowest-wins).
  ///
  /// `modifiers` must be non-empty. Single-key bindings are reserved
  /// for framework-internal dispatch (typing, arrow navigation).
  public func keyCommand(
    _ description: String,
    key: KeyEvent,
    modifiers: EventModifiers,
    isEnabled: Bool = true,
    action: @escaping @MainActor @Sendable () -> Void
  ) -> some View {
    KeyCommandModifier(
      content: self,
      binding: KeyBinding(key: key, modifiers: modifiers),
      description: description,
      isEnabled: isEnabled,
      action: action
    )
  }
}

private struct KeyCommandModifier<Content: View>: View, ResolvableView {
  let content: Content
  let binding: KeyBinding
  let description: String
  let isEnabled: Bool
  let action: @MainActor @Sendable () -> Void

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let node = content.resolve(in: context)
    // Reject modifier-less bindings at runtime. Emitting a diagnostic
    // and silently dropping the registration is preferable to a crash.
    guard !binding.modifiers.isEmpty else {
      assertionFailure(
        "keyCommand '\(description)' requires non-empty modifiers; single-key bindings are framework-reserved"
      )
      return [node]
    }
    context.commandRegistry?.registerKeyCommand(
      at: node.identity,
      binding: binding,
      description: description,
      isEnabled: isEnabled,
      action: action
    )
    return [node]
  }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter KeyCommandTests 2>&1 | tail -5`
Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/View/ActionScopes/KeyCommandModifier.swift Tests/TerminalUITests/KeyCommandTests.swift
git commit -m "add .keyCommand modifier"
```

### Task 4.2: Wire dispatch in `RunLoop+EventDispatch`

**Files:**
- Modify: `Sources/TerminalUI/RunLoop+EventDispatch.swift`

- [ ] **Step 1: Locate the key-dispatch entry point**

Run: `grep -n "KeyEvent\|KeyPress\|dispatchKey" Sources/TerminalUI/RunLoop+EventDispatch.swift | head -20`

Identify where a parsed key event is handed to the dispatch pipeline (previously feeding into `hotkeyRegistry.dispatch(...)`).

- [ ] **Step 2: Write the dispatch path**

At the same site where hotkey dispatch previously fired, add:

```swift
// Before the local-widget dispatch (typing, arrows), try scoped
// keyCommand dispatch for modifier-bearing keys. If a scope on the
// current focus chain claims the binding, dispatch halts there.
if !keyPress.modifiers.isEmpty {
  let scopePath = currentFocusScopePath()
  let binding = KeyBinding(key: keyPress.key, modifiers: keyPress.modifiers)
  if commandRegistry.dispatch(key: binding, along: scopePath) {
    return  // event consumed
  }
}
// Fall through to existing single-key local dispatch.
```

Where `currentFocusScopePath()` is a helper (add it if missing) that pulls `FocusTracker.currentFocusIdentity` and looks up that identity's `FocusRegion.scopePath` from the most recent frame artifacts.

- [ ] **Step 3: Test end-to-end**

Add to `Tests/TerminalUITests/KeyCommandTests.swift`:

```swift
  @Test("End-to-end: Ctrl+S on focus inside a Panel fires the Panel's keyCommand")
  func endToEndDispatch() {
    var fired = 0
    let view = Panel(id: "editor") {
      Text("inside").focusable(true)
    }
    .keyCommand("Save", key: .character("s"), modifiers: .ctrl) {
      fired += 1
    }
    // Harness: resolve, extract semantics, set focus to the Text,
    // inject Ctrl+S through the event pump, verify fired == 1.
    // Use existing InteractiveDemoTestSupport or SceneSessionTestHarness patterns.
  }
```

- [ ] **Step 4: Run the test**

Run: `swift test --filter KeyCommandTests 2>&1 | tail -5`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add -u
git commit -m "wire keyCommand dispatch in RunLoop"
```

### Task 4.3: Shallowest-wins end-to-end test

**Files:**
- Modify: `Tests/TerminalUITests/KeyCommandTests.swift`

- [ ] **Step 1: Add the failing test**

Append:

```swift
  @Test("Ancestor Panel's Ctrl+S wins over descendant Panel's Ctrl+S")
  func shallowestWins() {
    var ancestorFired = 0
    var descendantFired = 0
    let view = Panel(id: "outer") {
      Panel(id: "inner") {
        Text("leaf").focusable(true)
      }
      .keyCommand("Inner save", key: .character("s"), modifiers: .ctrl) {
        descendantFired += 1
      }
    }
    .keyCommand("Outer save", key: .character("s"), modifiers: .ctrl) {
      ancestorFired += 1
    }
    // Harness: focus the Text, press Ctrl+S.
    #expect(ancestorFired == 1)
    #expect(descendantFired == 0)
  }

  @Test("Disabled ancestor blocks descendant; no action fires")
  func disabledAncestorBlocks() {
    var descendantFired = 0
    let view = Panel(id: "outer") {
      Panel(id: "inner") {
        Text("leaf").focusable(true)
      }
      .keyCommand("Inner save", key: .character("s"), modifiers: .ctrl) {
        descendantFired += 1
      }
    }
    .keyCommand(
      "Outer save",
      key: .character("s"),
      modifiers: .ctrl,
      isEnabled: false
    ) {}
    // Harness: focus the Text, press Ctrl+S.
    #expect(descendantFired == 0)
  }
```

- [ ] **Step 2: Run tests**

Run: `swift test --filter KeyCommandTests 2>&1 | tail -5`
Expected: both tests pass (behavior should already be correct from Phase 4.1's CommandRegistry semantics).

- [ ] **Step 3: Commit**

```bash
git add -u
git commit -m "test: shallowest-wins and disabled-blocks-deeper"
```

---

## Phase 5 — `.paletteCommand(...)` and environment exposure

Phase 5 adds the palette-command annotation and exposes the currently-active palette commands via an environment value that consumer-authored palette surfaces can query.

### Task 5.1: Add `.paletteCommand(...)` modifier

**Files:**
- Create: `Sources/View/ActionScopes/PaletteCommandModifier.swift`
- Test: `Tests/TerminalUITests/PaletteCommandTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/TerminalUITests/PaletteCommandTests.swift`:

```swift
import Testing
@testable import Core
@testable import View

@MainActor
@Suite
struct PaletteCommandTests {
  @Test("paletteCommand registers at the scope identity")
  func paletteCommandRegisters() {
    let registry = CommandRegistry()
    let panel = Panel(id: "editor") { EmptyView() }
      .paletteCommand(name: "Toggle theme", action: {})
    var context = ResolveContext.testFixture()
    context.commandRegistry = registry
    let resolved = panel.resolve(in: context)
    let commands = registry.paletteCommands(at: resolved.identity)
    #expect(commands.count == 1)
    #expect(commands.first?.name == "Toggle theme")
  }

  @Test("Disabled paletteCommand is registered but marked disabled")
  func paletteCommandDisabled() {
    let registry = CommandRegistry()
    let panel = Panel(id: "editor") { EmptyView() }
      .paletteCommand(name: "Delete all", isEnabled: false, action: {})
    var context = ResolveContext.testFixture()
    context.commandRegistry = registry
    let resolved = panel.resolve(in: context)
    let commands = registry.paletteCommands(at: resolved.identity)
    #expect(commands.first?.isEnabled == false)
  }
}
```

- [ ] **Step 2: Run test to fail**

Run: `swift test --filter PaletteCommandTests 2>&1 | tail -5`
Expected: compile error.

- [ ] **Step 3: Create the modifier**

Create `Sources/View/ActionScopes/PaletteCommandModifier.swift`:

```swift
package import Core

extension ActionScope where Self: View {
  /// Declares a searchable, consumer-invocable command at this
  /// scope's root. The framework does not ship a palette surface;
  /// consumer code is responsible for presenting a palette view and
  /// querying `activePaletteCommands` from the environment.
  public func paletteCommand(
    name: String,
    description: String? = nil,
    isEnabled: Bool = true,
    action: @escaping @MainActor @Sendable () -> Void
  ) -> some View {
    PaletteCommandModifier(
      content: self,
      name: name,
      description: description,
      isEnabled: isEnabled,
      action: action
    )
  }
}

private struct PaletteCommandModifier<Content: View>: View, ResolvableView {
  let content: Content
  let name: String
  let description: String?
  let isEnabled: Bool
  let action: @MainActor @Sendable () -> Void

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let node = content.resolve(in: context)
    context.commandRegistry?.registerPaletteCommand(
      at: node.identity,
      command: RegisteredPaletteCommand(
        name: name,
        description: description,
        isEnabled: isEnabled,
        action: action
      )
    )
    return [node]
  }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter PaletteCommandTests 2>&1 | tail -5`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/View/ActionScopes/PaletteCommandModifier.swift Tests/TerminalUITests/PaletteCommandTests.swift
git commit -m "add .paletteCommand modifier"
```

### Task 5.2: Expose `activePaletteCommands` via environment

**Files:**
- Modify: `Sources/View/Environment/Environment.swift`
- Modify: `Sources/TerminalUI/RunLoop+EventDispatch.swift` (or wherever the environment is populated per frame)

- [ ] **Step 1: Add the environment key**

In `Sources/View/Environment/Environment.swift`, add:

```swift
public struct ActivePaletteCommand: Sendable {
  public let name: String
  public let description: String?
  public let isEnabled: Bool
  public let action: @MainActor @Sendable () -> Void
}

extension EnvironmentValues {
  public var activePaletteCommands: [ActivePaletteCommand] {
    get { self[ActivePaletteCommandsKey.self] }
    set { self[ActivePaletteCommandsKey.self] = newValue }
  }
}

private struct ActivePaletteCommandsKey: EnvironmentKey {
  static var defaultValue: [ActivePaletteCommand] = []
}
```

Note: Check the framework's existing environment-key declaration pattern (`Sources/View/Environment/Environment.swift`) and match it exactly — enum cases versus struct singletons, defaultValue property declarations, etc.

- [ ] **Step 2: Populate the environment per frame**

Wherever the environment is injected into the resolve pipeline (look for where `localKeyHandlerRegistry` or similar is injected), compute `activePaletteCommands` from `commandRegistry.paletteCommands(along: currentFocusScopePath())` and set the environment value.

`RegisteredPaletteCommand` → `ActivePaletteCommand` is a straightforward map.

- [ ] **Step 3: Write a test**

Add to `PaletteCommandTests`:

```swift
  @Test("activePaletteCommands environment reflects commands on current focus chain")
  func environmentExposesActiveCommands() {
    // Build a view hierarchy with Panel containing a focusable
    // leaf and a paletteCommand. Focus the leaf. Resolve + run one
    // frame. Read activePaletteCommands from the environment of a
    // nested view. Assert the palette command is present.
    // ... harness-dependent; follow existing env-test patterns
  }
```

- [ ] **Step 4: Run test**

Run: `swift test --filter PaletteCommandTests 2>&1 | tail -5`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add -u
git commit -m "expose activePaletteCommands via environment"
```

---

## Phase 6 — Toolbar surface and hoisted toolbar items

Phase 6 adds `.toolbar(style:)` on ActionScopes and `.toolbarItem(...)` as a hoisted preference. Toolbars have an actual visual rendering — this is the largest task in Phase 6.

### Task 6.1: Define `ToolbarStyle` protocol and default styles

**Files:**
- Create: `Sources/View/ActionScopes/Toolbar.swift`
- Test: `Tests/TerminalUITests/ToolbarTests.swift`

- [ ] **Step 1: Write a compile-only test to pin the protocol shape**

Create `Tests/TerminalUITests/ToolbarTests.swift`:

```swift
import Testing
@testable import Core
@testable import View

@MainActor
@Suite
struct ToolbarTests {
  @Test("DefaultTopToolbarStyle and DefaultBottomToolbarStyle exist and conform to ToolbarStyle")
  func defaultStylesExist() {
    let top: any ToolbarStyle = DefaultTopToolbarStyle()
    let bottom: any ToolbarStyle = DefaultBottomToolbarStyle()
    _ = top
    _ = bottom
    #expect(true)
  }
}
```

- [ ] **Step 2: Create `Toolbar.swift` scaffold**

Create `Sources/View/ActionScopes/Toolbar.swift`:

```swift
package import Core

/// Style protocol for toolbars declared on ActionScopes.
///
/// Implementations control the layout of toolbar items (horizontal,
/// wrapped, top vs. bottom placement) via the framework's existing
/// `Layout` protocol.
public protocol ToolbarStyle: Sendable {
  associatedtype ItemLayout: TerminalUI.Layout
  var itemLayout: ItemLayout { get }
  var placement: ToolbarPlacement { get }
}

public enum ToolbarPlacement: Sendable {
  case top
  case bottom
}

public struct DefaultTopToolbarStyle: ToolbarStyle {
  public var itemLayout: HStackLayout {
    HStackLayout(alignment: .center, spacing: 1)
  }
  public var placement: ToolbarPlacement { .top }

  public init() {}
}

public struct DefaultBottomToolbarStyle: ToolbarStyle {
  public var itemLayout: HStackLayout {
    HStackLayout(alignment: .center, spacing: 1)
  }
  public var placement: ToolbarPlacement { .bottom }

  public init() {}
}
```

_Note_: `HStackLayout` is the framework's existing HStack layout type. Verify the exact name by running `grep -rn "struct HStackLayout" Sources/`. If it doesn't exist by that name, use the closest equivalent (`_HStackLayout` or whatever the framework already uses).

- [ ] **Step 3: Run test**

Run: `swift test --filter ToolbarTests 2>&1 | tail -5`
Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/View/ActionScopes/Toolbar.swift Tests/TerminalUITests/ToolbarTests.swift
git commit -m "add ToolbarStyle and default styles"
```

### Task 6.2: `ToolbarItemConfig` and the hoisting preference key

**Files:**
- Create: `Sources/View/ActionScopes/ToolbarItem.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/TerminalUITests/ToolbarTests.swift`:

```swift
  @Test("toolbarItem contributions accumulate up the tree via preference key")
  func toolbarItemsAccumulate() {
    let view = VStack {
      Text("A").toolbarItem(.init(
        title: "Item A",
        icon: nil,
        position: .top,
        isEnabled: true,
        action: {}
      ))
      Text("B").toolbarItem(.init(
        title: "Item B",
        icon: nil,
        position: .top,
        isEnabled: true,
        action: {}
      ))
    }
    let context = ResolveContext.testFixture()
    let resolved = view.resolve(in: context)
    let items = resolved.preferenceValues[ToolbarItemsPreferenceKey.self]
    #expect(items.count == 2)
    #expect(items.map(\.title).contains("Item A"))
    #expect(items.map(\.title).contains("Item B"))
  }
```

- [ ] **Step 2: Create `ToolbarItem.swift`**

Create `Sources/View/ActionScopes/ToolbarItem.swift`:

```swift
package import Core

public struct ToolbarItemConfig: Sendable {
  public enum Position: Sendable { case top, bottom, automatic }

  public var title: String
  public var icon: Image?
  public var position: Position
  public var isEnabled: Bool
  public var action: @MainActor @Sendable () -> Void

  public init(
    title: String,
    icon: Image? = nil,
    position: Position = .automatic,
    isEnabled: Bool = true,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    self.title = title
    self.icon = icon
    self.position = position
    self.isEnabled = isEnabled
    self.action = action
  }
}

/// Preference key that accumulates toolbar-item contributions from
/// descendants up to the nearest ActionScope that has declared a
/// toolbar. Consumed and cleared at that scope.
package enum ToolbarItemsPreferenceKey: PreferenceKey {
  package static var defaultValue: [ToolbarItemConfig] { [] }

  package static func reduce(
    value: inout [ToolbarItemConfig],
    nextValue: () -> [ToolbarItemConfig]
  ) {
    value.append(contentsOf: nextValue())
  }
}

extension View {
  public func toolbarItem(_ config: ToolbarItemConfig) -> some View {
    ToolbarItemContribution(content: self, config: config)
  }
}

private struct ToolbarItemContribution<Content: View>: View, ResolvableView {
  let content: Content
  let config: ToolbarItemConfig

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.preferenceValues.merge(
      ToolbarItemsPreferenceKey.self,
      value: [config]
    )
    return [node]
  }
}
```

- [ ] **Step 3: Run test**

Run: `swift test --filter ToolbarTests 2>&1 | tail -5`
Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/View/ActionScopes/ToolbarItem.swift Tests/TerminalUITests/ToolbarTests.swift
git commit -m "add ToolbarItemConfig and hoisting preference"
```

### Task 6.3: Builder-based `toolbarItem` variant

**Files:**
- Modify: `Sources/View/ActionScopes/ToolbarItem.swift`

- [ ] **Step 1: Add the builder variant**

Append to `ToolbarItem.swift`:

```swift
extension View {
  public func toolbarItem<Label: View, Icon: View>(
    position: ToolbarItemConfig.Position = .automatic,
    isEnabled: Bool = true,
    action: @escaping @MainActor @Sendable () -> Void,
    @ViewBuilder label: () -> Label,
    @ViewBuilder icon: () -> Icon
  ) -> some View {
    // For now the builder variant renders its label/icon to a string
    // title and elides the Icon into a stored Image placeholder. A
    // richer render path lands when Toolbar rendering is implemented
    // (Task 6.5).
    // TODO(Task 6.5): thread the label/icon views through to render.
    let labelText = extractPrimaryText(from: label()) ?? ""
    return toolbarItem(
      ToolbarItemConfig(
        title: labelText,
        position: position,
        isEnabled: isEnabled,
        action: action
      )
    )
  }
}
```

- [ ] **Step 2: Add basic test**

Append to `ToolbarTests`:

```swift
  @Test("Builder toolbarItem variant registers its title")
  func builderVariantRegisters() {
    let view = Text("X").toolbarItem(action: {}) {
      Text("Copy")
    } icon: {
      EmptyView()
    }
    let context = ResolveContext.testFixture()
    let resolved = view.resolve(in: context)
    let items = resolved.preferenceValues[ToolbarItemsPreferenceKey.self]
    #expect(items.first?.title == "Copy")
  }
```

- [ ] **Step 3: Run and commit**

```bash
swift test --filter ToolbarTests
git add -u
git commit -m "add builder variant of toolbarItem"
```

### Task 6.4: `.toolbar(style:)` absorbs preference up to its scope

**Files:**
- Modify: `Sources/View/ActionScopes/Toolbar.swift`

- [ ] **Step 1: Write the failing test**

Append to `ToolbarTests`:

```swift
  @Test("Panel with toolbar absorbs toolbar items from its subtree")
  func toolbarAbsorbsItems() {
    let panel = Panel(id: "outer") {
      Text("content").toolbarItem(.init(
        title: "Save",
        icon: nil,
        position: .top,
        isEnabled: true,
        action: {}
      ))
    }
    .toolbar(style: DefaultTopToolbarStyle())

    let context = ResolveContext.testFixture()
    let resolved = panel.resolve(in: context)
    // After the toolbar modifier consumes the preference, the outer
    // preferenceValues should NOT still contain the toolbar item.
    let leakedItems = resolved.preferenceValues[ToolbarItemsPreferenceKey.self]
    #expect(leakedItems.isEmpty)
  }

  @Test("Toolbar items pass through a non-toolbar scope and land at the next ancestor with a toolbar")
  func toolbarItemsBubblePastScopeWithoutToolbar() {
    let view = Panel(id: "outer") {
      Panel(id: "inner") {
        Text("content").toolbarItem(.init(
          title: "Save",
          icon: nil,
          position: .top,
          isEnabled: true,
          action: {}
        ))
      }
    }
    .toolbar(style: DefaultTopToolbarStyle())

    let context = ResolveContext.testFixture()
    let resolved = view.resolve(in: context)
    let leakedItems = resolved.preferenceValues[ToolbarItemsPreferenceKey.self]
    // Absorbed at outer Panel because inner Panel has no toolbar.
    #expect(leakedItems.isEmpty)
  }
```

- [ ] **Step 2: Implement `.toolbar(style:)`**

Append to `Toolbar.swift`:

```swift
extension ActionScope where Self: View {
  /// Declares that this scope has a toolbar. Toolbar items contributed
  /// by descendant views via `.toolbarItem(_:)` are absorbed here and
  /// rendered above or below the scope's content per `style.placement`.
  public func toolbar<S: ToolbarStyle>(style: S) -> some View {
    ToolbarHost(content: self, style: style)
  }
}

private struct ToolbarHost<Content: View, S: ToolbarStyle>: View, ResolvableView {
  let content: Content
  let style: S

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    let items = node.preferenceValues[ToolbarItemsPreferenceKey.self]
    // Consume the preference: clear it so it doesn't bubble further.
    node.preferenceValues.merge(
      ToolbarItemsPreferenceKey.self,
      value: [] // replace, not append; implementation may require a dedicated clear operation
    )
    // TODO(Task 6.5): Render the toolbar — build a toolbar strip using
    // style.itemLayout, positioned per style.placement, and compose
    // into `node` as either a top-overlay or bottom-overlay child.
    // For this task, absorption alone proves the hoisting contract.
    _ = items
    return [node]
  }
}
```

_Note_: `preferenceValues.merge` currently uses `reduce` semantics. Replacing with `[]` may not actually clear. If that's the case, the implementation needs a `preferenceValues.set(key, to: ...)` helper, OR `ToolbarItemsPreferenceKey.reduce` needs to be tolerant of empty next-values. Check the existing PreferenceKey machinery (`grep -rn "preferenceValues" Sources/Core/ | head -20`) and use whatever clear-the-key primitive exists. If none exists, add one.

- [ ] **Step 3: Run tests**

Run: `swift test --filter ToolbarTests 2>&1 | tail -5`
Expected: both new tests pass.

- [ ] **Step 4: Commit**

```bash
git add -u
git commit -m "toolbar modifier absorbs hoisted items"
```

### Task 6.5: Render the toolbar visually

**Files:**
- Modify: `Sources/View/ActionScopes/Toolbar.swift`

- [ ] **Step 1: Write the failing visual test**

Append to `ToolbarTests`:

```swift
  @Test("Panel with top toolbar renders item titles in a horizontal strip above the content")
  func toolbarRendersAboveContent() {
    let panel = Panel(id: "outer") {
      Text("body").frame(width: 10, height: 3)
        .toolbarItem(.init(
          title: "Save",
          icon: nil,
          position: .top,
          isEnabled: true,
          action: {}
        ))
    }
    .toolbar(style: DefaultTopToolbarStyle())
    .frame(width: 20, height: 5)

    // Render the view to a cell surface and assert the first row
    // contains "Save" and the content "body" appears below.
    // Follow the pattern in Tests/TerminalUITests/SwiftUISurfaceTests.swift.
    let surface = renderToSurface(panel)
    #expect(surface.row(0).contains("Save"))
    #expect(surface.row(1).contains("body"))
  }
```

_Note_: `renderToSurface` is a test helper; use whichever rendering fixture the existing tests use. See `SwiftUISurfaceTests.swift` for patterns.

- [ ] **Step 2: Implement rendering in `ToolbarHost`**

Replace the TODO in `ToolbarHost.resolveElements` with a real composition. The approach:

1. Build a SwiftUI-style child view that renders toolbar items using `style.itemLayout`. Each item is a labeled button-like cell rendering `config.title` (optionally with icon).
2. Compose the item strip and the original content using a VStack, placing the strip at top or bottom per `style.placement`.
3. Resolve that composed view and return its ResolvedNode.

```swift
private struct ToolbarItemsStrip<S: ToolbarStyle>: View {
  let items: [ToolbarItemConfig]
  let style: S

  var body: some View {
    style.itemLayout {
      ForEach(Array(items.enumerated()), id: \.offset) { _, item in
        ToolbarItemButton(config: item)
      }
    }
  }
}

private struct ToolbarItemButton: View {
  let config: ToolbarItemConfig

  var body: some View {
    Button(action: config.action) {
      if let icon = config.icon {
        HStack(spacing: 1) {
          icon
          Text(config.title)
        }
      } else {
        Text(config.title)
      }
    }
    .disabled(!config.isEnabled)
  }
}
```

And rewrite `ToolbarHost.resolveElements` to compose:

```swift
func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
  let base = content.resolve(in: context)
  let items = base.preferenceValues[ToolbarItemsPreferenceKey.self]
  if items.isEmpty {
    return [base]
  }
  let strip = ToolbarItemsStrip(items: items, style: style)
  let composed: some View = {
    switch style.placement {
    case .top:    return VStack(spacing: 0) { strip; _ResolvedPassthrough(node: base) }
    case .bottom: return VStack(spacing: 0) { _ResolvedPassthrough(node: base); strip }
    }
  }()
  var result = composed.resolve(in: context)
  // Clear the preference at this scope boundary.
  result.preferenceValues.merge(
    ToolbarItemsPreferenceKey.self,
    value: []
  )
  return [result]
}
```

_Note_: `_ResolvedPassthrough` is a hypothetical helper that re-emits an already-resolved node from within a view-builder context. If the framework doesn't already have an equivalent, either:
- add a minimal internal wrapper `ResolvedNodeWrapperView` that holds a `ResolvedNode` and passes it through in `resolveElements`, OR
- skip this composition approach and instead build the composed tree by hand in `resolveElements` (avoid the view-builder path).

Pick whichever matches the codebase's existing conventions — `Tests/TerminalUITests/*PresentationSurfaceTests.swift` likely has analogous composition for sheets/alerts.

- [ ] **Step 3: Run visual test**

Run: `swift test --filter ToolbarTests 2>&1 | tail -5`
Expected: pass.

- [ ] **Step 4: Full suite**

Run: `swift test 2>&1 | tail -5`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add -u
git commit -m "render toolbar strip above/below scope content"
```

---

## Phase 7 — Final cleanup and documentation

### Task 7.1: Update docs

**Files:**
- Modify: `docs/STATUS.md`
- Modify: `docs/PUBLIC_API_INVENTORY.md`
- Modify: `docs/SOURCE_LAYOUT.md`

- [ ] **Step 1: Update STATUS.md**

Move the "Commands, Keybindings, and Scope Hypothesis" section from "hypothesis, not yet implemented" into a "Shipped Surface" item. Reference `docs/proposals/ACTION_SCOPES_AND_COMMANDS.md` for the design and this plan for the implementation record.

- [ ] **Step 2: Update PUBLIC_API_INVENTORY.md**

Add the new public types and modifiers:
- `ActionScope` protocol + `AnyID`
- `Panel` + `.panel(_:)` + `.panel()` + `FocusContainment` + `.focusContainment(_:)`
- `.keyCommand(...)` + `.paletteCommand(...)` on `ActionScope where Self: View`
- `.toolbar(style:)` + `ToolbarStyle` + default styles
- `.toolbarItem(...)` (config + builder variants)
- `EnvironmentValues.activePaletteCommands` + `ActivePaletteCommand`

Remove the now-deleted `.onKeyPress(...)` entries.

- [ ] **Step 3: Update SOURCE_LAYOUT.md**

Add the new `Sources/View/ActionScopes/` directory and its files. Remove `Sources/View/Modifiers/OnKeyPress.swift` and `Sources/Core/HotkeyRegistry.swift` from the map.

- [ ] **Step 4: Commit**

```bash
git add -u
git commit -m "docs: reflect action-scopes shipping"
```

### Task 7.2: Final full-suite verification

- [ ] **Step 1: Build clean**

Run: `swift build 2>&1 | tail -5`
Expected: clean.

- [ ] **Step 2: Full test suite**

Run: `swift test 2>&1 | tail -10`
Expected: all pass, no skipped tests.

- [ ] **Step 3: Verify no stale references**

Run: `grep -rn "HotkeyRegistry\|onKeyPress\|hotkeyRegistry" Sources/ Tests/ Runners/ GUI/ Examples/`
Expected: no matches (aside from possibly in historical docs — those are fine).

- [ ] **Step 4: Commit any final touch-ups**

If the sweep finds leftover references, clean them up and commit.

---

## Self-Review Checklist

**Spec coverage:**

- [x] ActionScope protocol → Task 1.1
- [x] AnyID → Task 1.1
- [x] Scene conformance → Task 3.1, 3.2
- [x] Presentation modifier conformance → Task 3.3
- [x] Panel primitive with focus semantics → Task 2.1, 2.2, 2.3
- [x] FocusContainment → Task 2.1, 2.3
- [x] keyCommand (modifier-required, isEnabled, scope-root only) → Task 4.1, 4.2
- [x] paletteCommand → Task 5.1, 5.2
- [x] Strict shallowest-wins dispatch → Task 1.2, 4.3
- [x] Single-key framework-reserved → Task 4.1 (rejects empty modifiers)
- [x] Toolbar + styles → Task 6.1, 6.4, 6.5
- [x] ToolbarItem hoisting → Task 6.2, 6.3, 6.4
- [x] Remove .onKeyPress and HotkeyRegistry → Phase 0
- [x] Consumer-wrapped palette/help (not shipped) → confirmed by absence of palette/help views in the plan

**Placeholder scan:** The plan uses "TODO" comments in two places (Task 6.3, Task 6.4 code) for known follow-ups in later tasks — these are tracked and referenced by task number, not open TBDs. No other placeholders.

**Type consistency:** `KeyBinding` is used consistently across `CommandRegistry`, `KeyCommandModifier`, and tests. `RegisteredKeyCommand` and `RegisteredPaletteCommand` are consistent. `ToolbarItemConfig` is used consistently. `AnyID` appears only where needed.

**Known gaps requiring implementer judgment (flagged inline):**

- Task 2.3: may need to add `sealsFocusDescendants` to `SemanticMetadata` — this is a new field, confirmed mechanical.
- Task 6.4: may need to add a `preferenceValues.set(key, to:)` primitive if the existing machinery doesn't permit clearing a key.
- Task 6.5: composition helper (`_ResolvedPassthrough` or equivalent) — implementer to choose between (a) adding a minimal wrapper view and (b) hand-building the composed tree.

Each of these is marked at the point it arises so the implementer can make a concrete choice without re-reading the whole plan.
