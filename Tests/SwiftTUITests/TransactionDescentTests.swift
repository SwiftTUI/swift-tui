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
    "w4fn03: .animation(_:value:) in a body-root conditional animates the first change",
    arguments: BodyRootEntry.allCases)
  func w4fn03ValueAnimationInBodyRootConditionalAnimatesFirstChange(entry: BodyRootEntry) throws {
    let log = BodyRootLog()
    let view = BodyRootView(log: log) { v in
      if v > -1 { BodyRoot.glyph(v).animation(bodyRootOneSecond, value: v) }
    }
    let after = try BodyRoot.run(
      "w4fn03-\(entry)", entry: entry, log: log, view, writes: [(1, nil), (0.5, nil)])
    #expect(after[0][.offset] == bodyRootOneSecond, "first write: \(after[0])")
    #expect(after[1][.offset] == bodyRootOneSecond, "second write: \(after[1])")
  }

  @Test(
    "w4fn04: .transaction(value:_:) at a body root animates the first change",
    arguments: BodyRootEntry.allCases)
  func w4fn04ValueTransactionAtBodyRootAnimatesFirstChange(entry: BodyRootEntry) throws {
    let conditionalLog = BodyRootLog()
    let conditional = try BodyRoot.run(
      "w4fn04-if-\(entry)", entry: entry, log: conditionalLog,
      BodyRootView(log: conditionalLog) { v in
        if v > -1 {
          BodyRoot.glyph(v).transaction(value: v) { $0.animation = bodyRootOneSecond }
        }
      }, writes: [(1, nil)])
    #expect(conditional[0][.offset] == bodyRootOneSecond, "if: \(conditional[0])")
    let groupLog = BodyRootLog()
    let group = try BodyRoot.run(
      "w4fn04-group-\(entry)", entry: entry, log: groupLog,
      BodyRootView(log: groupLog) { v in
        Group { BodyRoot.glyph(v).transaction(value: v) { $0.animation = bodyRootOneSecond } }
      }, writes: [(1, nil)])
    #expect(group[0][.offset] == bodyRootOneSecond, "Group: \(group[0])")
  }

  @Test("w4fn05: value gates at a navigation destination root fire on every change")
  func w4fn05ValueGatesAtNavigationDestinationFire() throws {
    let animationLog = BodyRootLog()
    let animation = try BodyRoot.run(
      "w4fn05-animation", entry: .navigation, log: animationLog,
      BodyRootView(log: animationLog) { v in
        BodyRoot.glyph(v).animation(bodyRootOneSecond, value: v)
      }, writes: [(1, nil), (0.5, nil)])
    #expect(
      animation.map { $0[.offset] } == [bodyRootOneSecond, bodyRootOneSecond], "\(animation)")
    let transactionLog = BodyRootLog()
    let transaction = try BodyRoot.run(
      "w4fn05-transaction", entry: .navigation, log: transactionLog,
      BodyRootView(log: transactionLog) { v in
        BodyRoot.glyph(v).transaction(value: v) { $0.animation = bodyRootOneSecond }
      }, writes: [(1, nil), (0.5, nil)])
    #expect(
      transaction.map { $0[.offset] } == [bodyRootOneSecond, bodyRootOneSecond], "\(transaction)")
  }

  @Test("w4fn06: a branch flip between value gates of different types keeps separate values")
  func w4fn06BranchFlipBetweenDifferentlyTypedGates() throws {
    // The view is the run loop's root view, then one container down.
    let rootLog = BodyRootTypedFlipLog()
    let rootView = BodyRootTypedFlip(log: rootLog)
    let root = try StressRuntimeHarness(
      rootIdentity: testIdentity("BodyRoot", "w4fn06-root"), size: .init(width: 20, height: 3)
    ) { rootView }
    defer { root.shutdown() }
    let rootCurves = try flipCurves(rootLog, root.runLoop.renderer.internalAnimationController) {
      _ = try root.render()
    }
    let stackLog = BodyRootTypedFlipLog()
    let stackView = BodyRootTypedFlip(log: stackLog)
    let stack = try StressRuntimeHarness(
      rootIdentity: testIdentity("BodyRoot", "w4fn06-stack"), size: .init(width: 20, height: 3)
    ) { VStack { stackView } }
    defer { stack.shutdown() }
    let stackCurves = try flipCurves(stackLog, stack.runLoop.renderer.internalAnimationController) {
      _ = try stack.render()
    }
    // The Int gate fires; the String branch appears without firing, then
    // fires on its own change; the Int branch reappears, then fires again.
    let expected: [AnimatableSlot?] = [.offset, nil, .offset, nil, .offset]
    #expect(rootCurves == expected, "root: \(rootCurves)")
    #expect(stackCurves == expected, "stack child: \(stackCurves)")
  }

  private func flipCurves(
    _ log: BodyRootTypedFlipLog, _ controller: AnimationController, render: () throws -> Void
  ) throws -> [AnimatableSlot?] {
    let flag = try #require(log.flag)
    let count = try #require(log.count)
    let writes: [() -> Void] = [
      { count.wrappedValue += 1 }, { flag.wrappedValue = false }, { count.wrappedValue += 1 },
      { flag.wrappedValue = true }, { count.wrappedValue += 1 },
    ]
    return try withAnimationSinks(controller) {
      try writes.map { write -> AnimatableSlot? in
        write()
        try render()
        return BodyRoot.curves(controller).keys.first
      }
    }
  }

  @Test("w4fn07: a one-shot root whose body is a conditional animates its first changed render")
  func w4fn07OneShotConditionalRootAnimatesFirstChange() {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let identity = testIdentity("BodyRoot", "w4fn07")
    let proposal = ProposedSize(width: 20, height: 3)
    _ = renderer.render(
      BodyRootOneShot(value: 0.25), context: .init(identity: identity), proposal: proposal)
    withAnimationSinks(controller) {
      _ = renderer.render(
        BodyRootOneShot(value: 1), context: .init(identity: identity), proposal: proposal)
    }
    #expect(
      BodyRoot.curves(controller)[.offset] == bodyRootOneSecond, "\(BodyRoot.curves(controller))")
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

  @Test("w4fn10: a value gate whose value did not change stays silent on a plain write")
  func w4fn10UnchangedGateStaysSilent() throws {
    let log = BodyRootLog()
    let view = BodyRootView(log: log) { v in
      if v > -1 { BodyRoot.glyph(v).animation(bodyRootOneSecond, value: v > 2) }
    }
    let after = try BodyRoot.run(
      "w4fn10", entry: .runLoopRoot, log: log, view, writes: [(1, nil), (0.5, nil)])
    #expect(after.allSatisfy { $0.isEmpty }, "\(after)")
  }

  @Test("w4fn11: reduce motion snaps a value gate and a withAnimation write in a body-root branch")
  func w4fn11ReducedMotionSnapsBodyRootBranch() throws {
    let log = BodyRootLog()
    let view = BodyRootView(log: log) { v in
      if v > -1 { BodyRoot.glyph(v).animation(bodyRootOneSecond, value: v) }
    }
    .environment(\.accessibilityReduceMotion, true)
    let after = try BodyRoot.run(
      "w4fn11", entry: .stackChild, log: log, view, writes: [(1, nil), (0.5, bodyRootFourSeconds)])
    #expect(after.allSatisfy { $0.isEmpty }, "\(after)")
  }

  @Test("w4fn12: stacked value gates in one branch keep separate values")
  func w4fn12StackedGatesKeepSeparateValues() throws {
    let log = BodyRootLog()
    let view = BodyRootView(log: log) { v in
      if v > -1 {
        BodyRoot.glyph(v)
          .animation(bodyRootOneSecond, value: v)
          .animation(bodyRootFourSeconds, value: v > 0.75)
      }
    }
    // 0.25 -> 1 changes both watched values: the outer gate's curve reaches
    // the content first and the inner one wins below it. 1 -> 0.9 changes
    // only the inner value; 0.9 -> 0.5 changes both again.
    let after = try BodyRoot.run(
      "w4fn12", entry: .runLoopRoot, log: log, view, writes: [(1, nil), (0.9, nil), (0.5, nil)])
    #expect(after.map { $0[.offset] } == [bodyRootOneSecond, bodyRootOneSecond, bodyRootOneSecond])
    let outerOnlyLog = BodyRootLog()
    let outerOnly = try BodyRoot.run(
      "w4fn12-outer", entry: .runLoopRoot, log: outerOnlyLog,
      BodyRootView(log: outerOnlyLog) { v in
        if v > -1 {
          BodyRoot.glyph(v)
            .animation(nil, value: 0)
            .animation(bodyRootFourSeconds, value: v)
        }
      }, writes: [(1, nil)])
    #expect(outerOnly[0][.offset] == bodyRootFourSeconds, "\(outerOnly[0])")
  }
}

extension BodyRootTransactionTests {
  @Test("w4fn13: a value gate inside an explicit .id in a conditionally hosted view animates")
  func w4fn13ValueGateInsideExplicitIDInConditionallyHostedView() throws {
    let log = BodyRootLog()
    let view = BodyRootView(log: log) { v in
      BodyRoot.glyph(v).animation(bodyRootOneSecond, value: v).id("k")
    }
    let after = try BodyRoot.run(
      "w4fn13", entry: .conditionalHost, log: log, view, writes: [(1, nil), (0.5, nil)])
    #expect(after.map { $0[.offset] } == [bodyRootOneSecond, bodyRootOneSecond], "\(after)")
  }
}

@MainActor
private final class BodyRootTypedFlipLog {
  var flag: Binding<Bool>?
  var count: Binding<Int>?
}

private struct BodyRootTypedFlip: View {
  @State private var flag = true
  @State private var count = 1
  let log: BodyRootTypedFlipLog
  var body: some View {
    let _ = capture()
    if flag {
      Text("#").offset(x: count, y: 0).animation(bodyRootOneSecond, value: count)
    } else {
      Text("#").offset(x: count, y: 0).animation(bodyRootOneSecond, value: "s\(count)")
    }
  }
  private func capture() {
    log.flag = $flag
    log.count = $count
  }
}

private struct BodyRootOneShot: View {
  let value: Double
  var body: some View {
    if value > -1 { BodyRoot.glyph(value).animation(bodyRootOneSecond, value: value) }
  }
}
