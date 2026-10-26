import Synchronization
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// F137 — authored transactions must survive descent. The frame-input
/// refresh (`applyingCurrentFrameResolveInputs`) stamped the frame-root
/// transaction over every nested `resolveView`, so a `.animation(_:value:)`
/// request reached only the subtree ROOTS (via a post-hoc re-stamp) and
/// grandchildren carried the inherited frame transaction.
@MainActor
@Suite
struct TransactionDescentTests {
  @Test("value animation request reaches grandchild snapshots")
  func valueAnimationRequestReachesGrandchildren() throws {
    let renderer = DefaultRenderer()
    let animation = Animation.linear(duration: .milliseconds(300))
    let rootIdentity = testIdentity("TransactionDescentRoot")

    func probe(shifted: Bool) -> some View {
      VStack {
        VStack {
          Text("Leaf")
        }
      }
      .animation(animation, value: shifted)
    }

    _ = renderer.render(
      probe(shifted: false),
      context: ResolveContext(identity: rootIdentity)
    )
    let second = renderer.render(
      probe(shifted: true),
      context: ResolveContext(identity: rootIdentity)
    )

    let leaf = try #require(second.resolvedTree.descendant(withText: "Leaf"))
    let request = leaf.transactionSnapshot.animationRequest
    guard case .animate = request else {
      Issue.record(
        "grandchild snapshot carries \(String(describing: request)) instead of the authored .animate request"
      )
      return
    }
  }

  @Test("an inner transaction edit wins below its own modifier")
  func innerTransactionEditWins() throws {
    let renderer = DefaultRenderer()
    let animation = Animation.linear(duration: .milliseconds(300))
    let rootIdentity = testIdentity("TransactionDescentInnerRoot")

    func probe(shifted: Bool) -> some View {
      VStack {
        VStack {
          Text("Still")
            .transaction { $0.disablesAnimations = true }
        }
      }
      .animation(animation, value: shifted)
    }

    _ = renderer.render(
      probe(shifted: false),
      context: ResolveContext(identity: rootIdentity)
    )
    let second = renderer.render(
      probe(shifted: true),
      context: ResolveContext(identity: rootIdentity)
    )

    let leaf = try #require(second.resolvedTree.descendant(withText: "Still"))
    #expect(leaf.transactionSnapshot.animationRequest == .disabled)
  }
}

extension ResolvedNode {
  fileprivate func descendant(withText text: String) -> ResolvedNode? {
    if drawPayload == .text(text) {
      return self
    }

    for child in children {
      if let match = child.descendant(withText: text) {
        return match
      }
    }

    return nil
  }
}

// MARK: - Wave 4 FN (STUI-1335): transactions at a view's body root

// A view whose body root is a conditional produces the branch as its output,
// so a state write's frame segment names the branch identity and the view's
// node absorbs that identity. Two mechanisms failed there: the branch kept
// its parent's transaction (a transform read no `withAnimation` curve), and a
// value gate lost its remembered value when the identity index moved to the
// absorber (the first change after appearance never animated), never fired
// at a navigation destination (a same-pass second resolve), and trapped on a
// branch flip between gates of different value types.

private final class BodyRootSeen: Sendable {
  private let storage = Mutex<[String]>([])
  var values: [String] { storage.withLock { $0 } }
  func record(_ value: String) { storage.withLock { $0.append(value) } }
  func reset() { storage.withLock { $0.removeAll() } }
}

@MainActor
private final class BodyRootLog { var value: Binding<Double>? }

/// Hosts `content(value)` as its whole body, so the body root is exactly the
/// shape under test.
private struct BodyRootView<Content: View>: View {
  @State private var value = 0.25
  let log: BodyRootLog
  @ViewBuilder let content: (Double) -> Content
  var body: some View {
    let _ = capture()
    content(value)
  }
  private func capture() { log.value = $value }
}

private struct BodyRootSheetHost<C: View>: View {
  @State private var shown = true
  let content: C
  var body: some View { Text("base").sheet(isPresented: $shown) { content } }
}

private struct BodyRootPopoverHost<C: View>: View {
  @State private var shown = true
  let content: C
  var body: some View { Text("base").popover(isPresented: $shown) { content } }
}

private struct BodyRootAlertHost<C: View>: View {
  @State private var shown = true
  let content: C
  var body: some View {
    Text("base").alert("Title", isPresented: $shown) {
      Button("OK") {}
    } message: {
      content
    }
  }
}

private struct BodyRootTabHost<C: View>: View {
  @State private var selection = 0
  let content: C
  var body: some View { TabView(selection: $selection) { Tab("A", value: 0) { content } } }
}

private struct BodyRootNavigationHost<C: View>: View {
  @State private var shown = true
  let content: C
  var body: some View {
    NavigationStack { Text("base").navigationDestination(isPresented: $shown) { content } }
  }
}

/// Hosts its content inside an `if` at its own body root, so the hosted view
/// is flattened onto this one.
private struct BodyRootConditionalHost<C: View>: View {
  @State private var on = true
  let content: C
  var body: some View { if on { content } }
}

/// Where the view under test is hosted.
enum BodyRootEntry: String, CaseIterable, Sendable {
  case runLoopRoot, stackChild, windowGroup, sheet, popover, alert, tab, navigation, conditionalHost
}

@MainActor
private enum BodyRoot {
  static func glyph(_ value: Double) -> some View { Text("#").offset(x: Int(value * 16), y: 0) }

  static func hosted(_ entry: BodyRootEntry, _ content: some View) -> AnyView {
    switch entry {
    case .runLoopRoot: AnyView(content)
    case .stackChild: AnyView(VStack { content })
    case .windowGroup: AnyView(WindowHostView(content: content))
    case .sheet: AnyView(BodyRootSheetHost(content: content))
    case .popover: AnyView(BodyRootPopoverHost(content: content))
    case .alert: AnyView(BodyRootAlertHost(content: content))
    case .tab: AnyView(BodyRootTabHost(content: content))
    case .navigation: AnyView(BodyRootNavigationHost(content: content))
    case .conditionalHost: AnyView(BodyRootConditionalHost(content: content))
    }
  }

  /// The property slots animating after one render, with their curves.
  static func curves(_ controller: AnimationController) -> [AnimatableSlot: Animation] {
    let snapshot = controller.debugStateSnapshot()
    var curves: [AnimatableSlot: Animation] = [:]
    for key in snapshot.activeAnimationKeys {
      guard case .property(let slot) = key.scope,
        let animation = snapshot.activeAnimationBoxesByKey[key]?.unwrap(as: Animation.self)
      else { continue }
      curves[slot] = animation
    }
    return curves
  }

  /// Hosts `view` (the run loop's root view itself for `.runLoopRoot`), lets
  /// it appear, then applies each write and renders, returning the curves
  /// animating after each write. A `nil` animation is a plain write.
  static func run<V: View>(
    _ name: String, entry: BodyRootEntry, log: BodyRootLog, _ view: V,
    writes: [(value: Double, animation: Animation?)], seen: BodyRootSeen? = nil
  ) throws -> [[AnimatableSlot: Animation]] {
    if entry == .runLoopRoot {
      let harness = try StressRuntimeHarness(
        rootIdentity: testIdentity("BodyRoot", name), size: .init(width: 40, height: 12)
      ) { view }
      defer { harness.shutdown() }
      return try drive(harness.runLoop.renderer.internalAnimationController, log, writes, seen) {
        _ = try harness.render()
      }
    }
    let hosted = Self.hosted(entry, view)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("BodyRoot", name), size: .init(width: 40, height: 12)
    ) { hosted }
    defer { harness.shutdown() }
    return try drive(harness.runLoop.renderer.internalAnimationController, log, writes, seen) {
      _ = try harness.render()
    }
  }

  private static func drive(
    _ controller: AnimationController, _ log: BodyRootLog,
    _ writes: [(value: Double, animation: Animation?)], _ seen: BodyRootSeen?,
    render: () throws -> Void
  ) throws -> [[AnimatableSlot: Animation]] {
    try render()
    let binding = try #require(log.value, "the view under test appeared")
    // Only what the transforms observe for the writes counts.
    seen?.reset()
    return try withAnimationSinks(controller) {
      try writes.map { write in
        if let animation = write.animation {
          withAnimation(animation) { binding.wrappedValue = write.value }
        } else {
          binding.wrappedValue = write.value
        }
        try render()
        return curves(controller)
      }
    }
  }
}

private let bodyRootOneSecond = Animation.linear(duration: .seconds(1))
private let bodyRootFourSeconds = Animation.linear(duration: .seconds(4))

@MainActor
@Suite("Wave 4 FN: transactions and value gates at a view's body root", .serialized)
struct BodyRootTransactionTests {
  @Test(
    "w4fn01: a transform in a body-root conditional sees withAnimation's curve",
    arguments: BodyRootEntry.allCases)
  func w4fn01TransformInBodyRootConditionalSeesWithAnimation(entry: BodyRootEntry) throws {
    let log = BodyRootLog()
    let seen = BodyRootSeen()
    let view = BodyRootView(log: log) { v in
      if v > -1 {
        BodyRoot.glyph(v).transaction { [seen] in
          seen.record($0.animation.map { "\($0)" } ?? "nil")
        }
      }
    }
    _ = try BodyRoot.run(
      "w4fn01-\(entry)", entry: entry, log: log, view, writes: [(1, bodyRootFourSeconds)],
      seen: seen)
    #expect(!seen.values.isEmpty)
    #expect(seen.values.allSatisfy { $0 == "\(bodyRootFourSeconds)" }, "\(seen.values)")
  }

  @Test("w4fn02: a filling transform keeps withAnimation's curve in every conditional form")
  func w4fn02FillingTransformKeepsWithAnimationInEveryConditionalForm() throws {
    func filling(_ v: Double) -> some View {
      BodyRoot.glyph(v).transaction {
        if $0.animation == nil { $0.animation = bodyRootOneSecond }
      }
    }
    var results: [String: [AnimatableSlot: Animation]] = [:]
    let ifElseLog = BodyRootLog()
    results["if-else"] = try BodyRoot.run(
      "w4fn02-ifelse", entry: .runLoopRoot, log: ifElseLog,
      BodyRootView(log: ifElseLog) { v in
        if v > -1 { filling(v) } else { Text("x") }
      }, writes: [(1, bodyRootFourSeconds)]
    ).first
    let switchLog = BodyRootLog()
    results["switch"] = try BodyRoot.run(
      "w4fn02-switch", entry: .runLoopRoot, log: switchLog,
      BodyRootView(log: switchLog) { v in
        switch v > -1 {
        case true: filling(v)
        case false: Text("x")
        }
      }, writes: [(1, bodyRootFourSeconds)]
    ).first
    let ifLetLog = BodyRootLog()
    results["if-let"] = try BodyRoot.run(
      "w4fn02-iflet", entry: .runLoopRoot, log: ifLetLog,
      BodyRootView(log: ifLetLog) { v in
        if let w = Optional(v) { filling(w) }
      }, writes: [(1, bodyRootFourSeconds)]
    ).first
    for (form, curves) in results {
      #expect(curves[.offset] == bodyRootFourSeconds, "\(form): \(curves)")
    }
  }

  @Test(
    "w4fn14: a transform in the branch a withAnimation write switches to sees the curve",
    arguments: BodyRootEntry.allCases.filter { $0 != .navigation })
  func w4fn14TransformInSwitchedBranchSeesWithAnimation(entry: BodyRootEntry) throws {
    // A navigation destination resolves twice in the write frame, and the
    // second resolve already sees the node re-keyed to the new branch; that
    // entry is recorded as residual in the W4-FN report, not pinned here.
    let log = BodyRootLog()
    let seen = BodyRootSeen()
    let view = BodyRootView(log: log) { v in
      if v > 0.5 {
        Text("on").transaction { [seen] in
          seen.record($0.animation.map { "\($0)" } ?? "nil")
        }
      } else {
        Text("off")
      }
    }
    _ = try BodyRoot.run(
      "w4fn14-\(entry)", entry: entry, log: log, view, writes: [(1, bodyRootFourSeconds)],
      seen: seen)
    #expect(!seen.values.isEmpty)
    #expect(seen.values.allSatisfy { $0 == "\(bodyRootFourSeconds)" }, "\(seen.values)")
  }

  // Neighbours: behaviour adjacent to the repairs that must not change.

  @Test("w4fn08: an authored transaction around the view still wins inside its body-root branch")
  func w4fn08AuthoredOuterTransactionWinsInsideBranch() throws {
    let log = BodyRootLog()
    let seen = BodyRootSeen()
    let inner = BodyRootView(log: log) { v in
      if v > -1 {
        BodyRoot.glyph(v).transaction { [seen] in
          seen.record($0.animation.map { "\($0)" } ?? "nil")
        }
      }
    }
    let after = try BodyRoot.run(
      "w4fn08", entry: .stackChild, log: log,
      inner.transaction { $0.animation = bodyRootOneSecond }, writes: [(1, bodyRootFourSeconds)],
      seen: seen)
    #expect(!seen.values.isEmpty)
    #expect(seen.values.allSatisfy { $0 == "\(bodyRootOneSecond)" }, "\(seen.values)")
    #expect(after[0][.offset] == bodyRootOneSecond, "\(after[0])")
  }

  @Test("w4fn09: a disabling transaction in a body-root branch still snaps under withAnimation")
  func w4fn09DisablingTransactionInBranchSnaps() throws {
    let log = BodyRootLog()
    let view = BodyRootView(log: log) { v in
      if v > -1 { BodyRoot.glyph(v).transaction { $0.disablesAnimations = true } }
    }
    let after = try BodyRoot.run(
      "w4fn09", entry: .runLoopRoot, log: log, view, writes: [(1, bodyRootFourSeconds)])
    #expect(after[0].isEmpty, "\(after[0])")
  }
}
