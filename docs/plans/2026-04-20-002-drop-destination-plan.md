---
title: "feat: drop destinations scoped to ActionScopes"
type: feature
status: active
date: 2026-04-20
---

# Drop Destination Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a `.dropDestination { paths in ... }` modifier that is a type-level error anywhere except on an `ActionScope`. File paths dropped on (or pasted into) the terminal are parsed from a bracketed-paste burst, dispatched leafmost-first along the current focus chain via a new scope-identity-keyed `DropDestinationRegistry`, and bubble outward when a handler returns `false`. Non-path pastes fall through unchanged so existing text-input behavior is preserved.

**Architecture:** Mirror the existing key-command machinery. `CommandRegistry` + `KeyCommandModifier` are the prototypes: a `Core` registry indexed by scope `Identity`, a `View`-layer modifier that extends `ActionScope where Self: View & Sendable`, registration at `resolveElements` time via `ResolveContext`, and dispatch from `RunLoop+EventDispatch`. The one inversion: key-command dispatch is shallowest-first (broad shortcuts win); drop dispatch is **leafmost-first** (narrow attention wins).

**Tech Stack:** Swift 6.3 strict concurrency, Swift Testing (`@Test` / `#expect`), `@MainActor`-isolated view and runtime tests, `@testable import Core / View / TerminalUI`, package-layered with `Core`, `View`, and `TerminalUI`. No `import Foundation` in those layers.

**Design context from conversation (not a separate spec):** drop targets only receive file paths, not arbitrary Transferable types; location/isTargeted are deliberately omitted; `.dropDestination` is intentionally **not** hoistable onto arbitrary `View`s — it is only valid on `ActionScope` conformers because in a terminal there is no pointer to disambiguate multiple view-level drop targets.

---

## Overview

The implementation is three cleanly separable slices:

1. **Core value types + registry** — `DroppedPath`, shell/URL path parser, `DropDestinationRegistry` (parallel to `CommandRegistry`).
2. **Input pipeline** — new `InputEvent.paste(PasteEvent)` case, bracketed-paste envelope parser, raw-mode enable/disable for `\e[?2004h` / `\e[?2004l`.
3. **Public API + dispatch** — the `.dropDestination` modifier on `ActionScope`, `ResolveContext` wiring, and the `RunLoop` paste handler that tries drop dispatch first and falls back to re-emitting characters so `TextEditor`/`SecureField` paste keeps working.

Each slice has its own tests. The last slice has the integration test that proves the whole pipeline works.

## Scope Boundaries (Non-goals)

- **No location parameter** on the drop closure. Terminals don't report where the drop landed.
- **No `isTargeted` binding.** Without a pointer there is no hover truth to mirror.
- **No cross-app `Transferable` payload types** beyond file paths. `for: URL.self`-shaped generics are out of scope.
- **No multiple `.dropDestination` per scope.** The modifier is defined on `ActionScope` only; two destinations at the same scope identity is a registration-overwrite, documented as undefined.
- **No spatial dispatch**, ever. Dispatch is focus-chain-driven.
- **No new sheet/alert parameter** for inline drop destinations. Consumers scope drops inside a presentation by wrapping the sheet body in a `Panel` and attaching `.dropDestination` there (same pattern as `.keyCommand`).
- **No Image/clipboard-image support.** Dropping an image from Finder delivers a path (handled); dropping raw image bytes via terminal clipboard extensions is out of scope.
- **No typed `Transferable` machinery.** We ship one closure signature: `([DroppedPath]) -> Bool`.

## File Structure

### New files

| File | Responsibility |
|------|----------------|
| `Sources/Core/DroppedPath.swift` | Foundation-free `DroppedPath` value type (wraps a `String`; one line of doc-comment purpose). |
| `Sources/Core/DroppedPathParsing.swift` | `parseDroppedPaths(_ pasted: String) -> [DroppedPath]` — handles backslash escapes, single-quoted segments, and `file://` URL decoding. |
| `Sources/Core/DropDestinationRegistry.swift` | `@MainActor` class; identity-keyed; `register`, `handler(at:)`, `dispatch(paths:along:)`, `reset`, `removeSubtrees`. |
| `Sources/View/ActionScopes/DropDestinationModifier.swift` | `DropDestinationModifier<Content>` struct + the `extension ActionScope where Self: View & Sendable` method. |
| `Tests/CoreTests/DroppedPathTests.swift` | Value-type equality, debug description, literal initialization. |
| `Tests/CoreTests/DroppedPathParsingTests.swift` | Shell-unescape, single-quote, `file://`, multi-path, empty input. |
| `Tests/CoreTests/DropDestinationRegistryTests.swift` | Register/lookup, leafmost-first dispatch with `Bool` bubble, disabled-no-op absent here (no `isEnabled`), reset, subtree removal. |
| `Tests/TerminalUITests/BracketedPasteParserTests.swift` | `TerminalInputParser` emits `.paste(PasteEvent)` for `\e[200~...\e[201~`, and does not for unterminated envelopes. |
| `Tests/TerminalUITests/DropDestinationTests.swift` | `.dropDestination` on `Panel` registers at the panel's identity; forwards `ActionScope` conformance; chains with `.keyCommand`. |
| `Tests/TerminalUITests/DropDestinationDispatchTests.swift` | End-to-end: synthesized paste → RunLoop dispatch → nested scope priority → `Bool` bubbling → non-path fallback to character events. |

### Modified files

| File | What changes |
|------|--------------|
| `Sources/Core/RuntimeRegistrationSet.swift` | Add `dropDestinationRegistry` property; include in `resetAll`/`removeSubtrees`/init. |
| `Sources/View/Environment/Environment.swift` | Add `dropDestinationRegistry` to `ResolveContext`; include in `runtimeRegistrations`. |
| `Sources/TerminalUI/InputReader.swift` | Add `PasteEvent` struct + `InputEvent.paste` case; bracketed-paste parsing; coalescing passthrough. |
| `Sources/TerminalUI/StreamingTerminalHost.swift` | Emit `\e[?2004h` on `enableRawMode`, `\e[?2004l` on `disableRawMode`. |
| `Sources/TerminalUI/TerminalHost.swift` | Same pair of writes at the two existing setup/teardown sites (lines ~1356/1568 and their matching teardown blocks). |
| `Sources/TerminalUI/RunLoop.swift` | Instantiate `dropDestinationRegistry`; pass into `ResolveContext`. |
| `Sources/TerminalUI/RunLoop+EventDispatch.swift` | Handle `.paste` case in `handle(_:)`; add `handlePaste` method; add focus-chain leafmost-first walk helper. |

---

## Task 1: `DroppedPath` value type

**Files:**
- Create: `Sources/Core/DroppedPath.swift`
- Test: `Tests/CoreTests/DroppedPathTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/CoreTests/DroppedPathTests.swift
import Testing

@testable import Core

@Suite
struct DroppedPathTests {
  @Test("DroppedPath preserves its raw string and compares by value")
  func rawValueAndEquality() {
    let a = DroppedPath("/Users/me/file.txt")
    let b = DroppedPath("/Users/me/file.txt")
    let c = DroppedPath("/Users/me/other.txt")
    #expect(a.rawValue == "/Users/me/file.txt")
    #expect(a == b)
    #expect(a != c)
  }

  @Test("DroppedPath is string-literal expressible for ergonomics in tests")
  func stringLiteral() {
    let path: DroppedPath = "/tmp/x"
    #expect(path.rawValue == "/tmp/x")
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swiftly run swift test --filter CoreTests.DroppedPathTests`
Expected: FAIL with "cannot find 'DroppedPath' in scope".

- [ ] **Step 3: Write the implementation**

```swift
// Sources/Core/DroppedPath.swift

/// A single path that arrived via a drop or paste of file-shaped
/// content. Kept as a raw string so the `Core` layer — which may not
/// `import Foundation` — can represent paths without pulling in `URL`.
/// Consumers convert to `URL` or `FilePath` at their own layer.
public struct DroppedPath: Equatable, Hashable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible, ExpressibleByStringLiteral
{
  public var rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: String) {
    rawValue = value
  }

  public var description: String { rawValue }
  public var debugDescription: String { "DroppedPath(\(rawValue))" }
  public var isEmpty: Bool { rawValue.isEmpty }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swiftly run swift test --filter CoreTests.DroppedPathTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/DroppedPath.swift Tests/CoreTests/DroppedPathTests.swift
git commit -m "feat(core): add DroppedPath value type"
```

---

## Task 2: Path parser (shell unescape + file:// decode)

**Files:**
- Create: `Sources/Core/DroppedPathParsing.swift`
- Test: `Tests/CoreTests/DroppedPathParsingTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/CoreTests/DroppedPathParsingTests.swift
import Testing

@testable import Core

@Suite
struct DroppedPathParsingTests {
  @Test("Backslash-escaped spaces are unescaped")
  func backslashEscape() {
    let paths = parseDroppedPaths(#"/Users/me/my\ file.png"#)
    #expect(paths == [DroppedPath("/Users/me/my file.png")])
  }

  @Test("Single-quoted segments preserve spaces and are unwrapped")
  func singleQuoted() {
    let paths = parseDroppedPaths("'/Users/me/my file.png'")
    #expect(paths == [DroppedPath("/Users/me/my file.png")])
  }

  @Test("Multiple unquoted paths separated by whitespace parse in order")
  func multiUnquoted() {
    let paths = parseDroppedPaths("/a /b/c /d")
    #expect(
      paths == [
        DroppedPath("/a"),
        DroppedPath("/b/c"),
        DroppedPath("/d"),
      ]
    )
  }

  @Test("Mixed quoted and backslash-escaped paths keep relative order")
  func mixed() {
    let paths = parseDroppedPaths(#"'/one file' /two\ file"#)
    #expect(
      paths == [
        DroppedPath("/one file"),
        DroppedPath("/two file"),
      ]
    )
  }

  @Test("file:// URLs are decoded to POSIX paths")
  func fileURL() {
    let paths = parseDroppedPaths("file:///Users/me/my%20photo.png")
    #expect(paths == [DroppedPath("/Users/me/my photo.png")])
  }

  @Test("Empty input returns no paths")
  func empty() {
    #expect(parseDroppedPaths("").isEmpty)
    #expect(parseDroppedPaths("   ").isEmpty)
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swiftly run swift test --filter CoreTests.DroppedPathParsingTests`
Expected: FAIL with "cannot find 'parseDroppedPaths' in scope".

- [ ] **Step 3: Write the implementation**

```swift
// Sources/Core/DroppedPathParsing.swift

/// Parses a bracketed-paste burst into an ordered list of dropped
/// paths. Accepts the three forms macOS terminals emit when a file is
/// dragged into them: backslash-escaped POSIX paths, single-quoted
/// POSIX paths, and `file://`-prefixed URLs with percent-encoding.
///
/// Returns an empty list for input that contains no path-shaped
/// tokens; callers treat empty as "not a drop, fall through to text
/// paste".
public func parseDroppedPaths(_ pasted: String) -> [DroppedPath] {
  var results: [DroppedPath] = []
  var current = ""
  var index = pasted.startIndex
  let end = pasted.endIndex

  func flushCurrent() {
    guard !current.isEmpty else { return }
    results.append(DroppedPath(decodeFileURLIfNeeded(current)))
    current.removeAll(keepingCapacity: true)
  }

  while index < end {
    let character = pasted[index]
    switch character {
    case " ", "\t", "\n", "\r":
      flushCurrent()
      index = pasted.index(after: index)
    case "\\":
      let next = pasted.index(after: index)
      if next < end {
        current.append(pasted[next])
        index = pasted.index(after: next)
      } else {
        index = pasted.index(after: index)
      }
    case "'":
      var inside = pasted.index(after: index)
      while inside < end, pasted[inside] != "'" {
        current.append(pasted[inside])
        inside = pasted.index(after: inside)
      }
      index = inside < end ? pasted.index(after: inside) : inside
    default:
      current.append(character)
      index = pasted.index(after: index)
    }
  }
  flushCurrent()
  return results
}

private func decodeFileURLIfNeeded(_ token: String) -> String {
  guard token.hasPrefix("file://") else { return token }
  let pathPart = String(token.dropFirst("file://".count))
  return percentDecode(pathPart)
}

private func percentDecode(_ input: String) -> String {
  var output = ""
  output.reserveCapacity(input.count)
  var scalars = input.unicodeScalars.makeIterator()
  while let scalar = scalars.next() {
    guard scalar == "%" else {
      output.unicodeScalars.append(scalar)
      continue
    }
    guard
      let hi = scalars.next(), let lo = scalars.next(),
      let hiValue = hexValue(hi), let loValue = hexValue(lo)
    else {
      output.append("%")
      continue
    }
    let byte = UInt8(hiValue << 4 | loValue)
    if let decoded = UnicodeScalar(UInt32(byte)) {
      output.unicodeScalars.append(decoded)
    }
  }
  return output
}

private func hexValue(_ scalar: UnicodeScalar) -> UInt8? {
  switch scalar {
  case "0"..."9": return UInt8(scalar.value - UnicodeScalar("0").value)
  case "a"..."f": return UInt8(scalar.value - UnicodeScalar("a").value + 10)
  case "A"..."F": return UInt8(scalar.value - UnicodeScalar("A").value + 10)
  default: return nil
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swiftly run swift test --filter CoreTests.DroppedPathParsingTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/DroppedPathParsing.swift Tests/CoreTests/DroppedPathParsingTests.swift
git commit -m "feat(core): add parseDroppedPaths with shell + file-URL handling"
```

---

## Task 3: `DropDestinationRegistry`

**Files:**
- Create: `Sources/Core/DropDestinationRegistry.swift`
- Test: `Tests/CoreTests/DropDestinationRegistryTests.swift`

Reference pattern: `Sources/Core/CommandRegistry.swift`. This task mirrors it, with two intentional differences — dispatch walks the focus chain **leafmost-first**, and consumption is driven by the handler's `Bool` return.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/CoreTests/DropDestinationRegistryTests.swift
import Testing

@testable import Core

@MainActor
@Suite
struct DropDestinationRegistryTests {
  @Test("Registered handlers can be looked up by scope identity")
  func lookup() {
    let registry = DropDestinationRegistry()
    let scope = Identity(components: ["panel"])
    registry.register(at: scope) { _ in true }
    #expect(registry.handler(at: scope) != nil)
    #expect(registry.handler(at: Identity(components: ["other"])) == nil)
  }

  @Test("Dispatch walks leafmost-first and stops when a handler returns true")
  func leafmostFirstConsumes() {
    let registry = DropDestinationRegistry()
    let shallow = Identity(components: ["app"])
    let deep = Identity(components: ["app", "panel"])
    let shallowFired = Counter()
    let deepFired = Counter()
    registry.register(at: shallow) { _ in shallowFired.increment(); return true }
    registry.register(at: deep) { _ in deepFired.increment(); return true }
    let consumed = registry.dispatch(
      paths: [DroppedPath("/a")],
      along: [shallow, deep]  // shallowest-first input; registry walks reversed
    )
    #expect(consumed == true)
    #expect(deepFired.count == 1)
    #expect(shallowFired.count == 0)
  }

  @Test("Handler returning false bubbles to the next outer scope")
  func bubbleOnFalse() {
    let registry = DropDestinationRegistry()
    let shallow = Identity(components: ["app"])
    let deep = Identity(components: ["app", "panel"])
    let shallowFired = Counter()
    let deepFired = Counter()
    registry.register(at: shallow) { _ in shallowFired.increment(); return true }
    registry.register(at: deep) { _ in deepFired.increment(); return false }
    let consumed = registry.dispatch(
      paths: [DroppedPath("/a")],
      along: [shallow, deep]
    )
    #expect(consumed == true)
    #expect(deepFired.count == 1)
    #expect(shallowFired.count == 1)
  }

  @Test("Dispatch returns false when no scope on the chain has a destination")
  func noMatch() {
    let registry = DropDestinationRegistry()
    let consumed = registry.dispatch(
      paths: [DroppedPath("/a")],
      along: [Identity(components: ["app"])]
    )
    #expect(consumed == false)
  }

  @Test("reset clears all registrations")
  func resetClears() {
    let registry = DropDestinationRegistry()
    let scope = Identity(components: ["panel"])
    registry.register(at: scope) { _ in true }
    registry.reset()
    #expect(registry.handler(at: scope) == nil)
  }

  @Test("removeSubtrees drops registrations under given roots")
  func subtreeRemoval() {
    let registry = DropDestinationRegistry()
    let kept = Identity(components: ["app"])
    let removed = Identity(components: ["app", "panel"])
    registry.register(at: kept) { _ in true }
    registry.register(at: removed) { _ in true }
    registry.removeSubtrees(rootedAt: [Identity(components: ["app", "panel"])])
    #expect(registry.handler(at: kept) != nil)
    #expect(registry.handler(at: removed) == nil)
  }
}

private final class Counter: @unchecked Sendable {
  private(set) var count = 0
  func increment() { count += 1 }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swiftly run swift test --filter CoreTests.DropDestinationRegistryTests`
Expected: FAIL with "cannot find 'DropDestinationRegistry' in scope".

- [ ] **Step 3: Write the implementation**

```swift
// Sources/Core/DropDestinationRegistry.swift

/// A registered file-drop handler. Returning `true` marks the drop
/// consumed; returning `false` bubbles to the next outer scope on the
/// focus chain. The final outer scope that returns `false` yields
/// overall consumption=false, and the runtime falls back to re-emitting
/// the paste as ordinary characters.
package typealias DropDestinationHandler =
  @MainActor @Sendable ([DroppedPath]) -> Bool

/// Stores file-drop destinations keyed by scope `Identity` and
/// dispatches a single drop event leafmost-first along the current
/// focus chain. Mirrors `CommandRegistry` in lifetime and lifecycle;
/// the direction reversal is intentional — drop dispatch favors the
/// innermost attention target, the inverse of broad-shortcut routing.
@MainActor
package final class DropDestinationRegistry: Equatable {
  private var handlersByScope: [Identity: DropDestinationHandler] = [:]

  package init() {}

  nonisolated package static func == (
    lhs: DropDestinationRegistry,
    rhs: DropDestinationRegistry
  ) -> Bool {
    lhs === rhs
  }

  /// Registers (or replaces) the drop handler at `scope`. A second
  /// registration at the same identity is undefined at the public API
  /// level — the `.dropDestination` modifier is only valid on
  /// `ActionScope` conformers, so two registrations at one scope
  /// identity imply two `.dropDestination` modifiers on the same scope,
  /// which is a programming error; last-write-wins here.
  package func register(
    at scope: Identity,
    handler: @escaping DropDestinationHandler
  ) {
    handlersByScope[scope] = handler
  }

  /// Returns the registered handler at `scope`, if any.
  package func handler(at scope: Identity) -> DropDestinationHandler? {
    handlersByScope[scope]
  }

  /// Walks `scopePath` from leaf to root, invoking the first registered
  /// handler. If the handler returns `true`, dispatch stops. If it
  /// returns `false`, dispatch continues outward looking for another
  /// handler. Returns `true` if any handler consumed; `false` if every
  /// handler (or none) declined.
  ///
  /// `scopePath` is provided shallowest-first by the runtime, matching
  /// `CommandRegistry.dispatch(key:along:)`. This method reverses it
  /// internally so callers don't need to know the registry's direction.
  @discardableResult
  package func dispatch(
    paths: [DroppedPath],
    along scopePath: [Identity]
  ) -> Bool {
    for scope in scopePath.reversed() {
      guard let handler = handlersByScope[scope] else { continue }
      if handler(paths) {
        return true
      }
    }
    return false
  }

  /// Clears every registration.
  package func reset() {
    handlersByScope.removeAll(keepingCapacity: true)
  }

  /// Removes every registration whose identity sits under any of
  /// `roots`. Called by `RuntimeRegistrationSet.removeSubtrees` during
  /// partial re-resolves so stale handlers don't linger.
  package func removeSubtrees(rootedAt roots: [Identity]) {
    guard !roots.isEmpty else { return }
    for identity in handlersByScope.keys
    where dropDestinationIdentityMatchesAnySubtreeRoot(identity, roots: roots) {
      handlersByScope.removeValue(forKey: identity)
    }
  }
}

private func dropDestinationIdentityMatchesAnySubtreeRoot(
  _ identity: Identity,
  roots: [Identity]
) -> Bool {
  roots.contains { root in
    identity == root || identity.isDescendant(of: root)
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swiftly run swift test --filter CoreTests.DropDestinationRegistryTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/DropDestinationRegistry.swift \
  Tests/CoreTests/DropDestinationRegistryTests.swift
git commit -m "feat(core): add DropDestinationRegistry mirroring CommandRegistry"
```

---

## Task 4: Wire registry into `RuntimeRegistrationSet`

**Files:**
- Modify: `Sources/Core/RuntimeRegistrationSet.swift`

- [ ] **Step 1: Add the property, init param, and lifecycle hooks**

Add a field after `commandRegistry`, add the init parameter, extend `resetAll`, and extend `removeSubtrees`. The additions (inserted into the existing struct) are:

```swift
  package let dropDestinationRegistry: DropDestinationRegistry?
```

Extend the designated initializer to accept and store it (default `nil`). Extend `resetAll()` with:

```swift
    dropDestinationRegistry?.reset()
```

Extend `removeSubtrees(rootedAt:)` with:

```swift
    dropDestinationRegistry?.removeSubtrees(rootedAt: roots)
```

- [ ] **Step 2: Build to confirm the addition is clean**

Run: `swiftly run swift build`
Expected: succeeds; nothing else depends on `RuntimeRegistrationSet`'s field set yet.

- [ ] **Step 3: Commit**

```bash
git add Sources/Core/RuntimeRegistrationSet.swift
git commit -m "feat(core): thread DropDestinationRegistry through RuntimeRegistrationSet"
```

---

## Task 5: Expose the registry on `ResolveContext`

**Files:**
- Modify: `Sources/View/Environment/Environment.swift` (add a field near `commandRegistry`, line 220)

- [ ] **Step 1: Add the property and the bridge to `runtimeRegistrations`**

Add alongside `commandRegistry`:

```swift
  package var dropDestinationRegistry: DropDestinationRegistry?
```

In the `runtimeRegistrations` computed property, pass it through:

```swift
      dropDestinationRegistry: dropDestinationRegistry
```

- [ ] **Step 2: Build to confirm the addition compiles**

Run: `swiftly run swift build`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/View/Environment/Environment.swift
git commit -m "feat(view): expose DropDestinationRegistry on ResolveContext"
```

---

## Task 6: `.dropDestination` modifier — compile and register

**Files:**
- Create: `Sources/View/ActionScopes/DropDestinationModifier.swift`
- Test: `Tests/TerminalUITests/DropDestinationTests.swift`

Reference pattern: `Sources/View/ActionScopes/KeyCommandModifier.swift` (copy structure; adjust payload; no `isEnabled` flag).

- [ ] **Step 1: Write the failing test**

```swift
// Tests/TerminalUITests/DropDestinationTests.swift
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct DropDestinationTests {
  @Test("dropDestination registers a handler at the Panel's scope identity")
  func registersAtScopeIdentity() {
    let registry = DropDestinationRegistry()
    let panel =
      Panel(id: "inbox") { EmptyView() }
      .dropDestination { _ in true }

    var context = ResolveContext(identity: testIdentity("drop-root"))
    context.dropDestinationRegistry = registry
    let resolved = Resolver().resolve(AnyView(panel), in: context)

    let panelNode = findPanelNode(in: resolved)
    #expect(panelNode != nil)
    #expect(panelNode.flatMap { registry.handler(at: $0.identity) } != nil)
  }

  @Test("dropDestination forwards ActionScope conformance so keyCommand still compiles")
  func conformanceIsForwarded() {
    // If this compiles, the assertion holds; kept as an explicit test
    // so a later refactor that breaks the forwarding is caught here.
    _ =
      Panel(id: "inbox") { EmptyView() }
      .dropDestination { _ in true }
      .keyCommand("Save", key: .character("s"), modifiers: .ctrl, action: {})
  }
}

@MainActor
private func findPanelNode(in root: ResolvedNode) -> ResolvedNode? {
  var stack: [ResolvedNode] = [root]
  while let node = stack.popLast() {
    if case .view("Panel") = node.kind { return node }
    stack.append(contentsOf: node.children)
  }
  return nil
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swiftly run swift test --filter TerminalUITests.DropDestinationTests`
Expected: FAIL with "value of type '...' has no member 'dropDestination'".

- [ ] **Step 3: Write the implementation**

```swift
// Sources/View/ActionScopes/DropDestinationModifier.swift
public import Core

extension ActionScope where Self: View & Sendable {
  /// Declares this scope as a file-drop destination.
  ///
  /// The closure fires when a file is dropped on the terminal (or a
  /// file-path-shaped payload is pasted) while this scope is on the
  /// current focus chain. Dispatch is leafmost-first: inner scopes see
  /// the drop before outer ones. Returning `true` consumes the drop;
  /// returning `false` bubbles it to the next outer scope, ultimately
  /// falling through to ordinary text paste if no scope claims it.
  ///
  /// `.dropDestination` is intentionally available only on
  /// `ActionScope` conformers — attaching it to an arbitrary `View`
  /// would introduce a spatial-dispatch ambiguity a terminal cannot
  /// resolve.
  @MainActor
  public func dropDestination(
    action: @escaping @MainActor @Sendable ([DroppedPath]) -> Bool
  ) -> DropDestinationModifier<Self> {
    DropDestinationModifier(content: self, action: action)
  }
}

public struct DropDestinationModifier<Content: View & Sendable>: View, ResolvableView {
  nonisolated let content: Content
  let action: @MainActor @Sendable ([DroppedPath]) -> Bool

  init(
    content: Content,
    action: @escaping @MainActor @Sendable ([DroppedPath]) -> Bool
  ) {
    self.content = content
    self.action = action
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let node = content.resolve(in: context)
    context.dropDestinationRegistry?.register(at: node.identity, handler: action)
    return [node]
  }
}

// Forward the inner scope's identity so chained `.dropDestination`,
// `.keyCommand`, and `.paletteCommand` keep compiling: after the
// modifier, the wrapped view is still an ActionScope whose id equals
// the content's.
extension DropDestinationModifier: Identifiable where Content: ActionScope {
  public typealias ID = Content.ID
  nonisolated public var id: Content.ID { content.id }
}

extension DropDestinationModifier: ActionScope where Content: ActionScope {}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swiftly run swift test --filter TerminalUITests.DropDestinationTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/View/ActionScopes/DropDestinationModifier.swift \
  Tests/TerminalUITests/DropDestinationTests.swift
git commit -m "feat(view): add .dropDestination modifier on ActionScope"
```

---

## Task 7: `PasteEvent` + `InputEvent.paste` case

**Files:**
- Modify: `Sources/TerminalUI/InputReader.swift`

- [ ] **Step 1: Add the event types next to `MouseEvent` (around line 85)**

```swift
/// A bracketed-paste burst emitted by the terminal between
/// `ESC[200~` and `ESC[201~`. The `content` is the raw payload with
/// no terminal framing — callers decide whether the bytes represent a
/// file drop (routed to `.dropDestination` destinations) or ordinary
/// pasted text (routed back as character `KeyPress` events).
public struct PasteEvent: Equatable, Sendable {
  public var content: String

  public init(content: String) {
    self.content = content
  }
}
```

Extend `InputEvent` to add a third case:

```swift
public enum InputEvent: Equatable, Sendable {
  case key(KeyPress)
  case mouse(MouseEvent)
  case paste(PasteEvent)

  public static func key(
    _ keyEvent: KeyEvent,
    modifiers: EventModifiers = []
  ) -> Self {
    .key(KeyPress(keyEvent, modifiers: modifiers))
  }
}
```

Extend `coalescedInputEvents` to flush pending mouse and append paste events verbatim (paste events never merge). Edit the `switch event` body in that function:

```swift
    switch event {
    case .key:
      flushPendingMouseEvent()
      coalesced.append(event)
    case .paste:
      flushPendingMouseEvent()
      coalesced.append(event)
    case .mouse(let mouseEvent):
      // (existing code unchanged)
```

- [ ] **Step 2: Build to confirm adding the case hasn't broken exhaustivity checks**

Run: `swiftly run swift build`
Expected: may emit warnings for exhaustive switches elsewhere; fix any that surface (most consumers should already switch only on `.key` vs `.mouse` in the reader). Verify no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/TerminalUI/InputReader.swift
git commit -m "feat(input): add PasteEvent and InputEvent.paste"
```

---

## Task 8: Bracketed-paste envelope parser

**Files:**
- Modify: `Sources/TerminalUI/InputReader.swift`
- Test: `Tests/TerminalUITests/BracketedPasteParserTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/TerminalUITests/BracketedPasteParserTests.swift
import Testing

@testable import TerminalUI

@Suite
struct BracketedPasteParserTests {
  @Test("A complete bracketed-paste envelope emits a single PasteEvent")
  func completeEnvelope() {
    var parser = TerminalInputParser()
    let bytes = Array("\u{1B}[200~/Users/me/file.txt\u{1B}[201~".utf8)
    let events = parser.feed(bytes)
    #expect(events == [.paste(PasteEvent(content: "/Users/me/file.txt"))])
  }

  @Test("An unterminated envelope yields no events and preserves bytes for more input")
  func unterminatedEnvelope() {
    var parser = TerminalInputParser()
    let first = parser.feed(Array("\u{1B}[200~/Users/me/fil".utf8))
    #expect(first.isEmpty)
    let second = parser.feed(Array("e.txt\u{1B}[201~".utf8))
    #expect(second == [.paste(PasteEvent(content: "/Users/me/file.txt"))])
  }

  @Test("Paste envelopes tolerate embedded newlines")
  func embeddedNewlines() {
    var parser = TerminalInputParser()
    let bytes = Array("\u{1B}[200~/a\n/b\u{1B}[201~".utf8)
    let events = parser.feed(bytes)
    #expect(events == [.paste(PasteEvent(content: "/a\n/b"))])
  }

  @Test("Non-paste escape sequences are unaffected")
  func nonPasteEscape() {
    var parser = TerminalInputParser()
    // A bare ESC-key press
    let events = parser.feed([0x1B])
    #expect(events.count == 1)
    if case .key(let keyPress) = events[0] {
      #expect(keyPress.key == .escape)
    } else {
      Issue.record("expected .key(.escape)")
    }
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swiftly run swift test --filter TerminalUITests.BracketedPasteParserTests`
Expected: FAIL (parser does not yet recognize `\e[200~`).

- [ ] **Step 3: Teach `parseEscapeSequence` to detect bracketed paste**

In `Sources/TerminalUI/InputReader.swift`, inside `parseEscapeSequence()` (currently begins around line 281), add a branch that dispatches to a new `parseBracketedPaste` when the buffer begins with `ESC [ 2 0 0 ~`. Place this branch before the existing SGR-mouse check (byte `0x3C`) and before `parseCSIModifierSequence`:

```swift
    // Bracketed-paste start: ESC [ 2 0 0 ~ ... ESC [ 2 0 1 ~
    if matchesBracketedPasteStart(bufferedBytes) {
      return parseBracketedPaste()
    }
```

Add the helpers at the bottom of the same `extension TerminalInputParser` block (or a new private extension — match whichever style sibling helpers use):

```swift
extension TerminalInputParser {
  fileprivate mutating func parseBracketedPaste() -> InputEvent? {
    // Buffer layout at entry: ESC [ 2 0 0 ~ <payload> ESC [ 2 0 1 ~
    let startMarker: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E]
    let endMarker: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E]
    guard bufferedBytes.count >= startMarker.count else { return nil }
    // Look for the end marker anywhere after the start marker.
    let payloadStart = startMarker.count
    var searchIndex = payloadStart
    let totalCount = bufferedBytes.count
    while searchIndex + endMarker.count <= totalCount {
      var matches = true
      for offset in 0..<endMarker.count where bufferedBytes[searchIndex + offset] != endMarker[offset] {
        matches = false
        break
      }
      if matches {
        let payloadBytes = Array(bufferedBytes[payloadStart..<searchIndex])
        bufferedBytes.removeFirst(searchIndex + endMarker.count)
        let content = String(decoding: payloadBytes, as: UTF8.self)
        return .paste(PasteEvent(content: content))
      }
      searchIndex += 1
    }
    // End marker not yet seen — keep buffering.
    return nil
  }
}

private func matchesBracketedPasteStart(_ buffer: [UInt8]) -> Bool {
  let marker: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E]
  guard buffer.count >= marker.count else { return false }
  for index in 0..<marker.count where buffer[index] != marker[index] {
    return false
  }
  return true
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swiftly run swift test --filter TerminalUITests.BracketedPasteParserTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TerminalUI/InputReader.swift \
  Tests/TerminalUITests/BracketedPasteParserTests.swift
git commit -m "feat(input): parse bracketed-paste envelopes into PasteEvent"
```

---

## Task 9: Enable/disable bracketed paste mode

**Files:**
- Modify: `Sources/TerminalUI/StreamingTerminalHost.swift` (around lines 108–126 — `enableRawMode`/`disableRawMode`)
- Modify: `Sources/TerminalUI/TerminalHost.swift` (the two existing raw-mode transition sites near lines 1356/1360 and 1568/1572)

- [ ] **Step 1: Add the enable/disable writes**

In `StreamingTerminalHost.enableRawMode`, append a line after the mouse-tracking block:

```swift
    setup += "\u{001B}[?2004h"  // enable bracketed paste
```

In `disableRawMode`, append (before the existing alt-screen teardown):

```swift
    teardown += "\u{001B}[?2004l"  // disable bracketed paste
```

In `TerminalHost.swift`, at each of the two sites that write `"\u{001B}[?1002h\u{001B}[?1006h"`, append `\u{001B}[?2004h`. At each matching teardown site that writes `"\u{001B}[?1002l\u{001B}[?1006l"`, append `\u{001B}[?2004l`.

- [ ] **Step 2: Build to confirm no regressions**

Run: `swiftly run swift build`
Expected: succeeds.

- [ ] **Step 3: Run the full TerminalUI suite (no new test yet — this is terminal I/O plumbing)**

Run: `swiftly run swift test --filter TerminalUITests`
Expected: all existing tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/TerminalUI/StreamingTerminalHost.swift Sources/TerminalUI/TerminalHost.swift
git commit -m "feat(runtime): enable bracketed paste mode in raw-mode setup"
```

---

## Task 10: Instantiate `DropDestinationRegistry` in `RunLoop`

**Files:**
- Modify: `Sources/TerminalUI/RunLoop.swift` (the `commandRegistry` line is at 120)

- [ ] **Step 1: Add the registry instance and wire it into the resolve context**

Near the existing `package let commandRegistry = CommandRegistry()` (line 120), add:

```swift
  package let dropDestinationRegistry = DropDestinationRegistry()
```

In the init that constructs the `ResolveContext` (line 136 area where `commandRegistry:` is passed), set:

```swift
      context.dropDestinationRegistry = dropDestinationRegistry
```

(Match the exact plumbing style used next to `commandRegistry:` — whichever helper line 136 lives inside.)

- [ ] **Step 2: Build to confirm wiring**

Run: `swiftly run swift build`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/TerminalUI/RunLoop.swift
git commit -m "feat(runtime): instantiate DropDestinationRegistry on RunLoop"
```

---

## Task 11: Dispatch paste events to drop destinations

**Files:**
- Modify: `Sources/TerminalUI/RunLoop+EventDispatch.swift`
- Test: `Tests/TerminalUITests/DropDestinationDispatchTests.swift`

- [ ] **Step 1: Write the failing integration test**

```swift
// Tests/TerminalUITests/DropDestinationDispatchTests.swift
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct DropDestinationDispatchTests {
  @Test("A paste of a single path routes to a Panel's dropDestination")
  func singlePathDispatched() async throws {
    let received = Box<[DroppedPath]>([])
    let harness = try await DropDispatchHarness.make {
      Panel(id: "inbox") {
        Text("body").focusable(true)
      }
      .dropDestination { paths in
        received.value = paths
        return true
      }
    }
    harness.feedBracketedPaste("/Users/me/file.txt")
    await harness.drain()
    #expect(received.value == [DroppedPath("/Users/me/file.txt")])
  }

  @Test("Inner scope consumes before outer scope (leafmost-first)")
  func leafmostWins() async throws {
    let outerFired = Box(0)
    let innerFired = Box(0)
    let harness = try await DropDispatchHarness.make {
      Panel(id: "outer") {
        Panel(id: "inner") {
          Text("body").focusable(true)
        }
        .dropDestination { _ in
          innerFired.value += 1
          return true
        }
      }
      .dropDestination { _ in
        outerFired.value += 1
        return true
      }
    }
    harness.feedBracketedPaste("/a")
    await harness.drain()
    #expect(innerFired.value == 1)
    #expect(outerFired.value == 0)
  }

  @Test("Inner handler returning false bubbles the drop to the outer scope")
  func bubblesOnFalse() async throws {
    let outerFired = Box(0)
    let innerFired = Box(0)
    let harness = try await DropDispatchHarness.make {
      Panel(id: "outer") {
        Panel(id: "inner") {
          Text("body").focusable(true)
        }
        .dropDestination { _ in
          innerFired.value += 1
          return false
        }
      }
      .dropDestination { _ in
        outerFired.value += 1
        return true
      }
    }
    harness.feedBracketedPaste("/a")
    await harness.drain()
    #expect(innerFired.value == 1)
    #expect(outerFired.value == 1)
  }

  @Test("Non-path paste is not delivered to the drop destination")
  func nonPathIsNotDelivered() async throws {
    let fired = Box(0)
    let harness = try await DropDispatchHarness.make {
      Panel(id: "editor") {
        TextEditor(text: .constant("")).focusable(true)
      }
      .dropDestination { _ in
        fired.value += 1
        return true
      }
    }
    harness.feedBracketedPaste("plain typed text, not a path")
    await harness.drain()
    #expect(fired.value == 0)
  }
}

private final class Box<Value>: @unchecked Sendable {
  var value: Value
  init(_ initial: Value) { value = initial }
}
```

The `DropDispatchHarness` test helper belongs beside this test file. Model it on existing runtime harness patterns already present in `Tests/TerminalUITests/` (e.g. the `AppRuntimeTests` fixtures). It must:

- Build a `RunLoop` around the supplied root view.
- Expose `feedBracketedPaste(_:)` that injects `"\u{1B}[200~\(payload)\u{1B}[201~"` through the same input channel `InjectedTerminalInputReader` uses.
- Expose `drain() async` that yields the runloop one frame so the paste is processed.

Copy the fixture shape from whichever existing test spins up a RunLoop with injected input — do not invent a new harness style.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swiftly run swift test --filter TerminalUITests.DropDestinationDispatchTests`
Expected: FAIL — `handle(_:)` does not yet understand `.paste`.

- [ ] **Step 3: Handle `.paste` in `RunLoop.handle(_:)`**

In `Sources/TerminalUI/RunLoop+EventDispatch.swift`, extend the `case .input(let inputEvent)` switch:

```swift
      case .input(let inputEvent):
        switch inputEvent {
        case .key(let keyPress):
          scheduler.requestInput()
          return handleKeyPress(keyPress)
        case .mouse(let mouseEvent):
          if shouldScheduleFrame(for: mouseEvent) {
            scheduler.requestInput()
          }
          handleMouseEvent(mouseEvent)
          return nil
        case .paste(let pasteEvent):
          scheduler.requestInput()
          handlePaste(pasteEvent)
          return nil
        }
```

Add the `handlePaste` method inside the same `extension RunLoop`:

```swift
  package func handlePaste(_ pasteEvent: PasteEvent) {
    let paths = parseDroppedPaths(pasteEvent.content)
    if !paths.isEmpty {
      let consumed = dropDestinationRegistry.dispatch(
        paths: paths,
        along: currentFocusScopePath()
      )
      if consumed { return }
    }
    // Fall through: re-emit the paste content as a sequence of
    // character key events so text-input views (TextEditor, SecureField,
    // REPL-style consumers) continue to see pasted text. This preserves
    // pre-bracketed-paste behavior for the non-drop case.
    for scalar in pasteEvent.content.unicodeScalars {
      guard let character = Character(UnicodeScalar(scalar.value)!) as Character?,
        scalar.value >= 0x20 || scalar == "\n" || scalar == "\t"
      else { continue }
      let key: KeyEvent
      switch scalar {
      case "\n", "\r": key = .return
      case "\t": key = .tab
      case " ": key = .space
      default: key = .character(character)
      }
      _ = handleKeyPress(KeyPress(key, modifiers: []))
    }
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swiftly run swift test --filter TerminalUITests.DropDestinationDispatchTests`
Expected: PASS.

- [ ] **Step 5: Run the full repo test surface**

Run: `bun run test`
Expected: PASS (no regressions in existing key / mouse / presentation tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/TerminalUI/RunLoop+EventDispatch.swift \
  Tests/TerminalUITests/DropDestinationDispatchTests.swift
git commit -m "feat(runtime): dispatch paste events to drop destinations leafmost-first"
```

---

## Task 12: Gallery example

**Files:**
- Modify: `Examples/gallery/Sources/GalleryDemoViews/GalleryView.swift` (or whichever example screen best demonstrates a single scope with file-drop handling — match the convention of sibling demos).

- [ ] **Step 1: Add a demo screen that uses `.dropDestination`**

Add a small demo view that declares a `Panel(id: "drop-demo")` with a `.dropDestination { paths in ... }` that appends path `rawValue`s to a `@State` list and renders them. Mount it under the gallery's screen registry alongside existing demos.

- [ ] **Step 2: Manually verify in a terminal**

Run: `swift run gallery`
Drag a file from Finder onto the demo screen. Expected: the path renders as a new line. Paste plain text elsewhere: TextEditor still receives it.

- [ ] **Step 3: Commit**

```bash
git add Examples/gallery
git commit -m "docs(gallery): add file drop demo using .dropDestination"
```

---

## Self-Review

**Spec coverage.** The conversation-level requirements are:

- `.dropDestination` exists and compiles → Task 6
- Only valid on `ActionScope` → Task 6 (extension is on `ActionScope where Self: View & Sendable`; any `View` without that conformance fails to compile)
- No hoisting / no multi-handler resolution → Task 3 (registry is a dictionary keyed by identity; last-write-wins is documented, and since the modifier is `ActionScope`-only, sibling registrations cannot share an identity)
- Paths receivable from actual terminal drops → Tasks 2 (parser), 8 (bracketed-paste parse), 9 (enable mode)
- Leafmost-first dispatch → Task 3 (registry walks `scopePath.reversed()`), Task 11 (runtime call site)
- `Bool` consumed/bubble semantics → Task 3 (tested), Task 11 (wired into dispatch)
- Non-path paste falls through to ordinary text input → Task 11 (`handlePaste` re-emits characters on no-consume)
- App/Screen/Presentation scopes supported; Input/Selection scopes excluded → covered implicitly: `WindowGroup`, `Panel`, and `PromptPresentationSurface` are the `ActionScope` conformers; `TextEditor`/`SecureField` are not, so the modifier simply does not exist on them
- No `location` or `isTargeted` parameter → Task 6 (closure signature is `([DroppedPath]) -> Bool` only)

No gaps.

**Placeholder scan.** No `TBD`, `TODO`, or "similar to Task N" forward-references. Every code-bearing step carries a complete snippet.

**Type consistency.**

- `DroppedPath` used uniformly in `parseDroppedPaths`, the registry, the handler typealias, the modifier closure, and tests.
- `DropDestinationRegistry` used uniformly in `RuntimeRegistrationSet`, `ResolveContext`, `RunLoop`, and the modifier's resolve hook.
- Closure signature `@MainActor @Sendable ([DroppedPath]) -> Bool` is identical across the public API (Task 6), the typealias (Task 3), and the test harness (Task 11).
- `PasteEvent` used consistently in the parser (Task 8) and the dispatch site (Task 11).
- `InputEvent.paste` added in Task 7 is the one the parser emits (Task 8) and the runtime consumes (Task 11).

**Known risks the engineer should flag, not fix.**

- `TerminalInputParser` is `public`. Adding a case to a public enum is source-breaking for any external consumer that exhaustively switches on it. If this matters for API stability, the engineer should surface a governance question before Task 7 rather than widening scope.
- The non-consumed-paste fallback in Task 11 re-emits only printable characters plus `\n`/`\t`/space. If the pasted content contains control bytes, they are dropped. This mirrors what typed input would look like; if a future requirement needs full-fidelity text paste, that's a separate feature.
