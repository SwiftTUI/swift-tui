import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// The runtime half of the `Transition` surface (STUI-1543): a transition's
/// own animation on the effect channel, and a custom body in its identity
/// phase. Run-loop tests step an injected frame clock; nothing waits.
@MainActor
@Suite("Transition surface runtime", .serialized)
struct TransitionSurfaceRuntimeTests {
  private static let transactionAnimation = Animation.linear(duration: .milliseconds(800))
  private static let ownAnimation = Animation.linear(duration: .milliseconds(400))

  // MARK: - A transition's own animation

  @Test("without an own animation an insertion still runs for the transaction's 800 ms")
  func inheritedInsertionKeepsTheTransactionCurve() throws {
    let probe = try TransitionProbe(named: "inherit-insert", shown: false, transition: .opacity)
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.toggle(animation: Self.transactionAnimation)
      #expect(probe.opacityAnimationCount == 1)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.opacityAnimationCount == 1)
      #expect(probe.log.completions == 0)
      try probe.advance(to: start.advanced(by: .milliseconds(799)))
      #expect(probe.opacityAnimationCount == 1)
      try probe.advance(to: start.advanced(by: .milliseconds(800)))
      #expect(probe.opacityAnimationCount == 0)
      #expect(probe.log.completions == 1)
    }
  }

  @Test("an own 400 ms animation ends an insertion at 400 ms inside an 800 ms transaction")
  func ownAnimationReplacesTheTransactionOnInsertion() throws {
    let probe = try TransitionProbe(
      named: "own-insert", shown: false,
      transition: AnyTransition.opacity.animation(Self.ownAnimation))
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.toggle(animation: Self.transactionAnimation)
      // The first frame shows the start of the fade: opacity 0.
      #expect(!probe.frame.contains("PRESENT"))
      #expect(probe.opacityAnimationCount == 1)
      #expect(probe.activeAnimationBoxes == [Self.ownAnimation.animationBox])
      try probe.advance(to: start.advanced(by: .milliseconds(399)))
      #expect(probe.opacityAnimationCount == 1)
      #expect(probe.log.completions == 0)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.opacityAnimationCount == 0)
      // The transaction's completion batch was retained by the transition's
      // animation, so it fires when that animation ends.
      #expect(probe.log.completions == 1)
      #expect(probe.frame.contains("PRESENT"))
      try probe.settle()
      #expect(probe.log.completions == 1)
    }
  }

  @Test("an own 400 ms animation ends a removal at 400 ms inside an 800 ms transaction")
  func ownAnimationReplacesTheTransactionOnRemoval() throws {
    let probe = try TransitionProbe(
      named: "own-remove", shown: true,
      transition: AnyTransition.opacity.animation(Self.ownAnimation))
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.toggle(animation: Self.transactionAnimation)
      #expect(probe.removingCount == 1)
      #expect(probe.removalAnimationBoxes == [Self.ownAnimation.animationBox])
      try probe.advance(to: start.advanced(by: .milliseconds(399)))
      #expect(probe.removingCount == 1)
      #expect(probe.log.completions == 0)
      // The curve ends on the 400 ms frame: the overlay is logically
      // complete there, and the next head tick purges it.
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.log.completions == 1)
      try probe.settle()
      #expect(probe.removingCount == 0)
      #expect(!probe.frame.contains("PRESENT"))
      #expect(probe.log.completions == 1)
    }
  }

  @Test("without an own animation a removal is still in flight at 400 ms")
  func inheritedRemovalKeepsTheTransactionCurve() throws {
    let probe = try TransitionProbe(named: "inherit-remove", shown: true, transition: .opacity)
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.toggle(animation: Self.transactionAnimation)
      #expect(probe.removingCount == 1)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.removingCount == 1)
      #expect(probe.log.completions == 0)
      try probe.advance(to: start.advanced(by: .milliseconds(799)))
      #expect(probe.log.completions == 0)
      try probe.advance(to: start.advanced(by: .milliseconds(800)))
      #expect(probe.log.completions == 1)
    }
  }

  @Test("animation(nil) snaps an insertion and a removal inside an animated transaction")
  func nilAnimationSnapsBothWays() throws {
    let probe = try TransitionProbe(
      named: "nil", shown: false, transition: AnyTransition.opacity.animation(nil))
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.toggle(animation: Self.transactionAnimation)
      #expect(probe.frame.contains("PRESENT"))
      #expect(probe.activeAnimationCount == 0)
      // Nothing retains the transaction's completion batch, so it drains at
      // the transaction's own 800 ms, as it does for an identity transition.
      try probe.advance(to: start.advanced(by: .milliseconds(799)))
      #expect(probe.log.completions == 0)
      try probe.advance(to: start.advanced(by: .milliseconds(800)))
      #expect(probe.log.completions == 1)
      try probe.settle()

      let removalStart = probe.clock.now
      try probe.toggle(animation: Self.transactionAnimation)
      #expect(!probe.frame.contains("PRESENT"))
      #expect(probe.removingCount == 0)
      #expect(probe.activeAnimationCount == 0)
      try probe.advance(to: removalStart.advanced(by: .milliseconds(800)))
      #expect(probe.log.completions == 2)
    }
  }

  @Test("an own animation plays when the state change carries no animation")
  func ownAnimationPlaysWithoutAnAnimatedTransaction() throws {
    let probe = try TransitionProbe(
      named: "own-unanimated", shown: false,
      transition: AnyTransition.opacity.animation(Self.ownAnimation))
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.toggle(animation: nil, disabling: false)
      #expect(probe.opacityAnimationCount == 1)
      try probe.advance(to: start.advanced(by: .milliseconds(399)))
      #expect(probe.opacityAnimationCount == 1)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.opacityAnimationCount == 0)
      try probe.settle()

      let removalStart = probe.clock.now
      try probe.toggle(animation: nil, disabling: false)
      #expect(probe.removingCount == 1)
      #expect(probe.frame.contains("PRESENT"))
      try probe.advance(to: removalStart.advanced(by: .milliseconds(399)))
      #expect(probe.removingCount == 1)
      // The curve ends on the 400 ms frame; the next head tick purges the
      // overlay.
      try probe.advance(to: removalStart.advanced(by: .milliseconds(400)))
      try probe.advance(to: removalStart.advanced(by: .milliseconds(433)))
      #expect(probe.removingCount == 0)
      #expect(!probe.frame.contains("PRESENT"))
    }
  }

  @Test("withAnimation(nil) disables a transition that carries its own animation")
  func disabledTransactionWinsOverTheOwnAnimation() throws {
    let probe = try TransitionProbe(
      named: "own-disabled", shown: false,
      transition: AnyTransition.opacity.animation(Self.ownAnimation))
    defer { probe.shutdown() }
    try probe.run { _ in
      try probe.toggle(animation: nil, disabling: true)
      #expect(probe.frame.contains("PRESENT"))
      #expect(probe.activeAnimationCount == 0)
      try probe.settle()
      try probe.toggle(animation: nil, disabling: true)
      try probe.settle()
      #expect(!probe.frame.contains("PRESENT"))
      #expect(probe.removingCount == 0)
    }
  }

  @Test("each side of an asymmetric transition plays its own animation")
  func asymmetricSidesKeepTheirOwnAnimations() throws {
    let probe = try TransitionProbe(
      named: "asymmetric", shown: false,
      transition: .asymmetric(
        insertion: AnyTransition.opacity.animation(Self.ownAnimation),
        removal: .opacity))
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.toggle(animation: Self.transactionAnimation)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.opacityAnimationCount == 0)
      try probe.settle()

      let removalStart = probe.clock.now
      try probe.toggle(animation: Self.transactionAnimation)
      try probe.advance(to: removalStart.advanced(by: .milliseconds(400)))
      #expect(probe.removingCount == 1)
      #expect(probe.removalAnimationBoxes == [Self.transactionAnimation.animationBox])
    }
  }

  @Test("the sampled opacity follows the transition's own curve")
  func sampledOpacityFollowsTheOwnCurve() throws {
    // 200 ms is a quarter of the 800 ms transaction and half of the 400 ms
    // own animation.
    let inherited = try Self.insertionOpacity(at: 200, transition: .opacity)
    #expect(abs(inherited - 0.25) < 1e-9)
    let own = try Self.insertionOpacity(
      at: 200, transition: AnyTransition.opacity.animation(Self.ownAnimation))
    #expect(abs(own - 0.5) < 1e-9)
    let ownThroughType = try Self.insertionOpacity(
      at: 200, transition: OpacityTransition().animation(Self.ownAnimation))
    #expect(ownThroughType == own)
    let inheritedThroughType = try Self.insertionOpacity(at: 200, transition: OpacityTransition())
    #expect(inheritedThroughType == inherited)
  }

  // MARK: - One engine path for built-in types

  @Test("a built-in transition type resolves to the same tree as its AnyTransition static")
  func builtInTypeTakesTheStaticPath() throws {
    let proposal = ProposedSize(width: .finite(20), height: .finite(3))
    let root = testIdentity("transition-surface", "parity")
    let viaStatic = DefaultRenderer().render(
      PresenceHost(visible: true) { Text("PRESENT").transition(.opacity) },
      context: .init(identity: root), proposal: proposal)
    let viaType = DefaultRenderer().render(
      PresenceHost(visible: true) { Text("PRESENT").transition(OpacityTransition()) },
      context: .init(identity: root), proposal: proposal)
    let unmarked = DefaultRenderer().render(
      PresenceHost(visible: true) { Text("PRESENT") },
      context: .init(identity: root), proposal: proposal)
    #expect(Self.shape(of: viaType.resolvedTree) == Self.shape(of: viaStatic.resolvedTree))
    #expect(Self.shape(of: viaType.resolvedTree) == Self.shape(of: unmarked.resolvedTree))
    #expect(!Self.kinds(in: viaType.resolvedTree).contains(.view(.transitionContent)))
    #expect(viaType.rasterSurface.lines == viaStatic.rasterSurface.lines)
  }

  // MARK: - Custom bodies

  @Test("a custom transition renders its identity body at rest")
  func customBodyRendersItsIdentityPhase() throws {
    let result = DefaultRenderer().render(
      PresenceHost(visible: true) { Text("PRESENT").transition(Bracket()) },
      context: .init(identity: testIdentity("transition-surface", "body-rest")),
      proposal: .init(width: .finite(20), height: .finite(3)))
    #expect(result.rasterSurface.lines.contains { $0.contains("[PRESENT]") })
    #expect(!result.rasterSurface.lines.contains { $0.contains("<") })

    // The content sits behind exactly one boundary node with one child.
    let boundaries = Self.nodes(in: result.resolvedTree) { $0.kind == .view(.transitionContent) }
    #expect(boundaries.count == 1)
    let boundary = try #require(boundaries.first)
    #expect(boundary.children.count == 1)
    #expect(boundary.children.first?.kind == .view(.text))
    #expect(boundary.children.first?.identity == boundary.identity.child(.named("content")))
  }

  @Test("the boundary node passes layout, drawing and interaction through")
  func boundaryIsTransparent() throws {
    let log = TransitionProbeLog()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("transition-surface", "boundary"),
      size: .init(width: 24, height: 4)
    ) {
      VStack(alignment: .leading, spacing: 0) {
        Text("above")
        Button("Press") { log.completions += 1 }.transition(Passthrough())
        Text("below")
      }
    }
    defer { harness.shutdown() }
    let plain = try StressRuntimeHarness(
      rootIdentity: testIdentity("transition-surface", "boundary-plain"),
      size: .init(width: 24, height: 4)
    ) {
      VStack(alignment: .leading, spacing: 0) {
        Text("above")
        Button("Press") {}
        Text("below")
      }
    }
    defer { plain.shutdown() }
    #expect(harness.frame == plain.frame)
    #expect(harness.focusRegionCount == plain.focusRegionCount)
    try harness.clickText("Press")
    #expect(log.completions == 1)
  }

  @Test("a modifier a body applies to its content lands on the boundary node")
  func bodyModifiersLandOnTheBoundary() throws {
    let result = DefaultRenderer().render(
      PresenceHost(visible: true) { Text("PRESENT").opacity(0.5).transition(Veil()) },
      context: .init(identity: testIdentity("transition-surface", "stamp")),
      proposal: .init(width: .finite(20), height: .finite(3)))
    let boundary = try #require(
      Self.nodes(in: result.resolvedTree) { $0.kind == .view(.transitionContent) }.first)
    #expect(boundary.drawMetadata.baseStyle.explicitOpacity == 1)
    #expect(boundary.children.first?.drawMetadata.baseStyle.explicitOpacity == 0.5)
  }

  @Test("a body that places its content twice resolves it at two identities")
  func contentPlacedTwiceResolvesTwice() throws {
    let result = DefaultRenderer().render(
      PresenceHost(visible: true) { Text("PRESENT").transition(Twice()) },
      context: .init(identity: testIdentity("transition-surface", "twice")),
      proposal: .init(width: .finite(20), height: .finite(4)))
    let boundaries = Self.nodes(in: result.resolvedTree) { $0.kind == .view(.transitionContent) }
    #expect(boundaries.count == 2)
    #expect(Set(boundaries.map(\.identity)).count == 2)
    #expect(Set(boundaries.compactMap { $0.children.first?.identity }).count == 2)
    #expect(result.rasterSurface.lines.filter { $0.contains("PRESENT") }.count == 2)
  }

  @Test("a custom body snaps on insertion and on removal and takes no default fade")
  func customBodySnaps() throws {
    let probe = try TransitionProbe(
      named: "body-snap", shown: false, transition: AnyTransition(Bracket()))
    defer { probe.shutdown() }
    try probe.run { _ in
      try probe.toggle(animation: Self.transactionAnimation)
      #expect(probe.frame.contains("[PRESENT]"))
      #expect(probe.activeAnimationCount == 0)
      try probe.settle()

      try probe.toggle(animation: Self.transactionAnimation)
      #expect(!probe.frame.contains("PRESENT"))
      #expect(probe.removingCount == 0)
      #expect(probe.activeAnimationCount == 0)
    }
  }

  @Test("the effect channel of a mixed transition animates around the body")
  func mixedTransitionAnimatesItsEffects() throws {
    let probe = try TransitionProbe(
      named: "mixed", shown: false, transition: AnyTransition(Bracket().combined(with: .opacity)))
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.toggle(animation: Self.transactionAnimation)
      #expect(probe.opacityAnimationCount == 1)
      try probe.advance(to: start.advanced(by: .milliseconds(800)))
      #expect(probe.opacityAnimationCount == 0)
      #expect(probe.frame.contains("[PRESENT]"))
      try probe.settle()

      try probe.toggle(animation: Self.transactionAnimation)
      #expect(probe.removingCount == 1)
      #expect(probe.frame.contains("[PRESENT]"))
      try probe.settle()
      #expect(probe.removingCount == 0)
      #expect(!probe.frame.contains("PRESENT"))
    }
  }

  @Test("combined and asymmetric bodies nest, each in its own phase")
  func bodiesCompose() throws {
    #expect(try Self.line(of: Bracket().combined(with: Braces())) == "{[PRESENT]}")
    #expect(try Self.line(of: Braces().combined(with: Bracket())) == "[{PRESENT}]")
    #expect(
      try Self.line(of: AsymmetricTransition(insertion: Bracket(), removal: Braces()))
        == "{[PRESENT]}")
    #expect(
      try Self.line(
        of: AnyTransition.asymmetric(
          insertion: AnyTransition(Bracket()), removal: AnyTransition(Braces())))
        == "{[PRESENT]}")
    #expect(
      try Self.line(
        of: AnyTransition(Bracket()).combined(with: .opacity).combined(
          with: AnyTransition(Braces())))
        == "{[PRESENT]}")
    #expect(
      try Self.line(
        of: AnyTransition.modifier(active: Suffix(text: "?"), identity: Suffix(text: "!")))
        == "PRESENT!")

    // `apply` evaluates any phase. Each side of an asymmetric pair is active
    // in its own direction only.
    let pair = AsymmetricTransition(insertion: Bracket(), removal: Braces())
    #expect(try Self.line(applying: pair, phase: .identity) == "{[PRESENT]}")
    #expect(try Self.line(applying: pair, phase: .willAppear) == "{<PRESENT>}")
    #expect(try Self.line(applying: pair, phase: .didDisappear) == "([PRESENT])")
    #expect(
      try Self.line(applying: Bracket().combined(with: Braces()), phase: .willAppear)
        == "(<PRESENT>)")
    #expect(try Self.line(applying: Bracket().animation(nil), phase: .didDisappear) == "<PRESENT>")
  }

  @Test("a built-in transition applied inside a body stamps exact opacity in every phase")
  func builtInBodyOpacityIsExact() throws {
    for (phase, expected) in [
      (TransitionPhase.willAppear, 0.0), (.identity, 1.0), (.didDisappear, 0.0),
    ] {
      let result = DefaultRenderer().render(
        OpacityTransition().apply(content: Text("PRESENT"), phase: phase),
        context: .init(identity: testIdentity("transition-surface", "builtin-body")),
        proposal: .init(width: .finite(20), height: .finite(1)))
      let boundary = try #require(
        Self.nodes(in: result.resolvedTree) { $0.kind == .view(.transitionContent) }.first)
      #expect(boundary.drawMetadata.baseStyle.explicitOpacity == expected)
    }
    // A built-in without an opacity channel stamps none, and its identity
    // phase is the content unchanged.
    let moved = DefaultRenderer().render(
      MoveTransition(edge: .leading).apply(content: Text("PRESENT"), phase: .identity),
      context: .init(identity: testIdentity("transition-surface", "builtin-move")),
      proposal: .init(width: .finite(20), height: .finite(1)))
    let boundary = try #require(
      Self.nodes(in: moved.resolvedTree) { $0.kind == .view(.transitionContent) }.first)
    #expect(boundary.drawMetadata.baseStyle.explicitOpacity == nil)
    #expect(moved.rasterSurface.lines.first?.hasPrefix("PRESENT") == true)
  }

  // MARK: - Helpers

  /// Inserts under an 800 ms transaction and returns the opacity sampled
  /// `milliseconds` later.
  private static func insertionOpacity<T: Transition>(
    at milliseconds: Int, transition: T
  ) throws -> Double {
    try insertionOpacity(at: milliseconds, transition: AnyTransition(transition))
  }

  private static func insertionOpacity(
    at milliseconds: Int, transition: AnyTransition
  ) throws -> Double {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let root = testIdentity("transition-surface", "sampled")
    let proposal = ProposedSize(width: .finite(20), height: .finite(3))
    let start = MonotonicInstant(offset: .seconds(100))
    var animated = TransactionSnapshot()
    animated.animationRequest = .animate(transactionAnimation.animationBox)
    return try withAnimationSinks(controller) {
      controller.register(transactionAnimation)
      _ = renderer.render(
        PresenceHost(visible: false) { Text("PRESENT").transition(transition) },
        context: .init(identity: root), proposal: proposal, frameInstant: start)
      _ = renderer.render(
        PresenceHost(visible: true) { Text("PRESENT").transition(transition) },
        context: .init(identity: root, transaction: animated),
        proposal: proposal, frameInstant: start)
      let frame = renderer.render(
        PresenceHost(visible: true) { Text("PRESENT").transition(transition) },
        context: .init(identity: root),
        proposal: proposal, frameInstant: start.advanced(by: .milliseconds(milliseconds)))
      let key = try #require(
        controller.debugStateSnapshot().activeAnimationKeys.first {
          $0.scope == .property(.opacity)
        })
      let node = try #require(
        AnimationTreeQueries.findResolvedSubtree(in: frame.resolvedTree, identity: key.identity))
      return try #require(node.drawMetadata.baseStyle.explicitOpacity)
    }
  }

  private static func line<T: Transition>(of transition: T) throws -> String {
    try line(of: AnyTransition(transition))
  }

  private static func line(of transition: AnyTransition) throws -> String {
    try firstLine(Text("PRESENT").transition(transition))
  }

  private static func line<T: Transition>(
    applying transition: T, phase: TransitionPhase
  ) throws -> String {
    try firstLine(transition.apply(content: Text("PRESENT"), phase: phase))
  }

  private static func firstLine<V: View>(_ view: V) throws -> String {
    let result = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("transition-surface", "line")),
      proposal: .init(width: .finite(20), height: .finite(1)))
    let line = try #require(result.rasterSurface.lines.first)
    return String(line.reversed().drop { $0 == " " }.reversed())
  }

  private static func nodes(
    in node: ResolvedNode, where matches: (ResolvedNode) -> Bool
  ) -> [ResolvedNode] {
    (matches(node) ? [node] : []) + node.children.flatMap { nodes(in: $0, where: matches) }
  }

  private static func kinds(in node: ResolvedNode) -> Set<NodeKind> {
    Set(nodes(in: node) { _ in true }.map(\.kind))
  }

  /// Identity, kind and opacity of every node, in tree order.
  private static func shape(of node: ResolvedNode) -> [String] {
    nodes(in: node) { _ in true }.map {
      "\($0.identity.path) \($0.kind) \(String(describing: $0.drawMetadata.baseStyle.explicitOpacity))"
    }
  }
}

// MARK: - Fixtures

@MainActor
private final class TransitionProbeClock { var now = MonotonicInstant.now() }

@MainActor
private final class TransitionProbeLog {
  var shown: Binding<Bool>?
  var completions = 0
}

/// A run-loop harness around one conditional view with a transition, driven
/// on an injected frame clock.
@MainActor
private final class TransitionProbe {
  let harness: StressRuntimeHarness<TransitionProbeRoot>
  let clock: TransitionProbeClock
  let log: TransitionProbeLog

  init(named name: String, shown: Bool, transition: AnyTransition) throws {
    let log = TransitionProbeLog()
    self.log = log
    harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("transition-surface", name),
      size: .init(width: 24, height: 4)
    ) { TransitionProbeRoot(initiallyShown: shown, transition: transition, log: log) }
    // The clock starts after the mount frame: a frame never runs earlier than
    // the frame before it, so an earlier start would be pinned to the mount
    // frame's wall-clock instant and every offset below would be short.
    let clock = TransitionProbeClock()
    self.clock = clock
    harness.runLoop.frameClock = { clock.now }
  }

  private var controller: AnimationController {
    harness.runLoop.renderer.internalAnimationController
  }

  var frame: String { harness.frame }

  var activeAnimationCount: Int { controller.activeAnimationCount }

  var opacityAnimationCount: Int {
    controller.debugStateSnapshot().activeAnimationKeys.filter { $0.scope == .property(.opacity) }
      .count
  }

  var activeAnimationBoxes: Set<AnimationBox> {
    Set(controller.debugStateSnapshot().activeAnimationBoxesByKey.values)
  }

  var removingCount: Int { controller.debugStateSnapshot().removingNodeIDs.count }

  var removalAnimationBoxes: [AnimationBox?] {
    Array(controller.debugStateSnapshot().removalAnimationBoxesByNodeID.values)
  }

  func shutdown() { harness.shutdown() }

  /// Runs `body` with the animation sinks bound, passing the start instant.
  func run(_ body: (MonotonicInstant) throws -> Void) throws {
    try withAnimationSinks(controller) { try body(clock.now) }
  }

  /// Flips presence and renders the frame of the change. `animation: nil`
  /// with `disabling: false` is a plain state write.
  func toggle(animation: Animation?, disabling: Bool = false) throws {
    let shown = try #require(log.shown)
    let log = log
    if let animation {
      withAnimation(animation) {
        shown.wrappedValue.toggle()
      } completion: {
        log.completions += 1
      }
    } else if disabling {
      withAnimation(nil) { shown.wrappedValue.toggle() }
    } else {
      shown.wrappedValue.toggle()
    }
    _ = try harness.render()
  }

  /// Renders every armed turn before `target`, then one frame exactly at it.
  func advance(to target: MonotonicInstant) throws {
    var turns = 0
    while let wake = harness.runLoop.scheduler.nextWakeInstant(after: clock.now), wake < target,
      turns < 256
    {
      clock.now = wake
      _ = try harness.render()
      turns += 1
    }
    #expect(turns < 256, "the scheduler must reach the target within the turn budget")
    clock.now = target
    harness.runLoop.scheduler.requestDeadline(clock.now)
    _ = try harness.render()
  }

  /// Runs two seconds of armed turns, which is longer than any animation
  /// here. A registered transition keeps a frame deadline armed while its
  /// view is present, so there is no quiescent scheduler to wait for.
  func settle() throws {
    try advance(to: clock.now.advanced(by: .seconds(2)))
  }
}

private struct TransitionProbeRoot: View {
  @State private var shown: Bool
  let transition: AnyTransition
  let log: TransitionProbeLog

  init(initiallyShown: Bool, transition: AnyTransition, log: TransitionProbeLog) {
    _shown = State(initialValue: initiallyShown)
    self.transition = transition
    self.log = log
  }

  var body: some View {
    let _ = capture()
    VStack(alignment: .leading, spacing: 0) {
      Text("host")
      if shown { Text("PRESENT").transition(transition) }
    }
  }

  private func capture() {
    log.shown = $shown
  }
}

private struct PresenceHost<Content: View>: View {
  var visible: Bool
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("STAYS")
      if visible { content() }
    }
  }
}

/// Brackets the content; the brackets differ outside the identity phase.
private struct Bracket: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    HStack(spacing: 0) {
      Text(phase.isIdentity ? "[" : "<")
      content
      Text(phase.isIdentity ? "]" : ">")
    }
  }
}

private struct Braces: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    HStack(spacing: 0) {
      Text(phase.isIdentity ? "{" : "(")
      content
      Text(phase.isIdentity ? "}" : ")")
    }
  }
}

private struct Twice: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      content
      content
    }
  }
}

private struct Passthrough: Transition {
  func body(content: Content, phase: TransitionPhase) -> Content {
    content
  }
}

private struct Veil: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.opacity(phase.isIdentity ? 1 : 0)
  }
}

private struct Suffix: ViewModifier {
  var text: String

  func body(content: Content) -> some View {
    HStack(spacing: 0) {
      content
      Text(text)
    }
  }
}
