import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Insertion of a custom `Transition` body (STUI-1544): the content appears
/// through the body of the `.willAppear` phase and moves to the body of the
/// `.identity` phase.
///
/// Frame tests render one renderer at fixed instants. Run-loop tests step an
/// injected frame clock to each scheduler wake. Nothing waits.
@MainActor
@Suite("Transition body insertion", .serialized)
struct TransitionBodyInsertionTests {
  private static let letters = "ABCDEFGHIJKLMNOPQRST"
  /// The start, the three quarters and the end of the 800 ms transaction.
  private static let instants = [0, 200, 400, 600, 800]
  private static let progress = [0.0, 0.25, 0.5, 0.75, 1.0]
  private static let transactionAnimation = TransitionBodyFrames.transactionAnimation
  private static let ownAnimation = Animation.linear(duration: .milliseconds(400))

  // MARK: - Frames at fixed instants

  @Test("an interpolable body animates its clip path and its opacity from the willAppear phase")
  func interpolableBodyFrames() throws {
    let frames = try TransitionBodyFrames.insertion(
      of: Text(Self.letters).foregroundStyle(Color.white).transition(Reveal()),
      at: Self.instants)
    for (frame, progress) in zip(frames, Self.progress) {
      let label = "\(frame.milliseconds) ms"
      // Coverage: the clip path has grown to `progress` of the width, so
      // that many columns of the text are painted.
      let columns = Int((Double(Self.letters.count) * progress).rounded())
      #expect(frame.lines[1] == String(Self.letters.prefix(columns)), "\(label)")
      // Opacity: the boundary the body's modifiers land on carries the
      // interpolated value.
      let boundary = try #require(frame.boundaries.first, "\(label)")
      let opacity = try #require(boundary.drawMetadata.baseStyle.explicitOpacity, "\(label)")
      #expect(abs(opacity - (0.2 + 0.8 * progress)) < 1e-9, "\(label): \(opacity)")
      // The cells are those of the same body held at that progress.
      let held = try TransitionBodyFrames.atRest(
        Text(Self.letters).foregroundStyle(Color.white).transition(RevealAt(progress: progress)))
      #expect(frame.row(1, matches: held), "\(label)")
    }
    // The opacity is visible in the cells: the first painted letter gets
    // brighter from one sample to the next.
    let brightness = frames.dropFirst().map { $0.foreground(row: 1, column: 0)?.red ?? -1 }
    #expect(brightness == brightness.sorted() && Set(brightness).count == brightness.count)
  }

  @Test("a value that cannot interpolate shows its identity value from the first frame")
  func nonInterpolableDifferenceTakesTheIdentityValueAtOnce() throws {
    let frames = try TransitionBodyFrames.insertion(
      of: Text("PRESENT").transition(BlendShift()), at: Self.instants)
    for (frame, progress) in zip(frames, Self.progress) {
      let label = "\(frame.milliseconds) ms"
      // `blendMode` is not a slot. The identity phase asks for `.normal` and
      // the willAppear phase for `.multiply`; `.multiply` never renders.
      let boundary = try #require(frame.boundaries.first, "\(label)")
      #expect(boundary.drawEffects.ordered == [.blendMode(.normal)], "\(label)")
      // The underline is not a slot either: the willAppear phase underlines
      // the text, and no sampled cell is underlined.
      #expect(
        frame.surface.cells[1].allSatisfy { $0.style?.underlineStyle == nil }, "\(label)")
      // The offset in the same body is a slot: the text is drawn at the
      // sampled offset.
      let column = try #require(frame.offsetColumns.first, "\(label)")
      #expect(
        frame.lines[1] == String(repeating: " ", count: column) + "PRESENT",
        "\(label): \(frame.lines[1])")
      #expect(abs(Double(column) - 8 * (1 - progress)) <= 1, "\(label): \(column)")
    }
    // It starts at the willAppear value, eight columns, and reaches zero.
    let columns = frames.compactMap(\.offsetColumns.first)
    #expect(columns.first == 8 && columns.last == 0, "\(columns)")
    #expect(columns == columns.sorted(by: >), "\(columns)")
  }

  @Test("a view the body adds is drawn in every frame of the insertion")
  func addedOverlayIsDrawnInEveryFrame() throws {
    let frames = try TransitionBodyFrames.insertion(
      of: Text("PRESENT").transition(Starred()), at: Self.instants)
    for frame in frames {
      // The star is part of the identity body, so it is there from the first
      // frame. The content fades in beside it from an opacity of zero.
      #expect(frame.lines[1].hasSuffix("*"), "\(frame.milliseconds) ms: \(frame.lines[1])")
      #expect(
        frame.lines[1].contains("PRESENT") == (frame.milliseconds > 0),
        "\(frame.milliseconds) ms: \(frame.lines[1])")
    }
    #expect(frames.last?.lines[1] == "PRESENT *")
  }

  @Test("a foreground style the body sets animates on the views of the content")
  func inheritedForegroundStyleAnimatesOnTheContent() throws {
    let content = VStack(alignment: .leading, spacing: 0) {
      Text("AB")
      Text("CD")
    }
    let frames = try TransitionBodyFrames.insertion(
      of: content.transition(Tinted()), at: Self.instants)
    let red = try TransitionBodyFrames.atRest(content.transition(TintedAt(color: .red)))
    let white = try TransitionBodyFrames.atRest(content.transition(TintedAt(color: .white)))
    // Both texts read the style from the environment the body wrote. Each
    // starts at the willAppear colour and ends at the identity colour.
    for row in [1, 2] {
      let first = try #require(frames.first)
      let last = try #require(frames.last)
      #expect(first.row(row, matches: red), "row \(row)")
      #expect(last.row(row, matches: white), "row \(row)")
      let middle = frames[2]
      #expect(!middle.row(row, matches: red) && !middle.row(row, matches: white), "row \(row)")
    }

    // A view of the content that sets its own style does not inherit the
    // body's, in either phase: it keeps its colour through the insertion.
    let mixed = VStack(alignment: .leading, spacing: 0) {
      Text("AB")
      Text("CD").foregroundStyle(Color.green)
    }
    let mixedFrames = try TransitionBodyFrames.insertion(
      of: mixed.transition(Tinted()), at: Self.instants)
    let mixedAtRest = try TransitionBodyFrames.atRest(mixed.transition(TintedAt(color: .white)))
    for frame in mixedFrames {
      #expect(frame.row(2, matches: mixedAtRest), "\(frame.milliseconds) ms")
    }
    #expect(try #require(mixedFrames.first).row(1, matches: red))
    // So does content whose root sets the style for all of it.
    let overridden = Text("AB").foregroundStyle(Color.green)
    for frame in try TransitionBodyFrames.insertion(
      of: overridden.transition(Tinted()), at: Self.instants)
    {
      #expect(
        frame.row(
          1, matches: try TransitionBodyFrames.atRest(overridden.transition(Tinted()))),
        "\(frame.milliseconds) ms")
    }
  }

  @Test("the abortable frame path, where the graph is suspended, shows the same frames")
  func interpolableBodyFramesOnTheAbortablePath() async throws {
    // The async renderer runs the abortable frame head: the prepared graph
    // is not live while the insertion is planned, and the frame tail runs
    // on its worker. The willAppear phase is evaluated without the graph, so
    // the frames are the ones the one-shot path produces.
    let view = Text(Self.letters).foregroundStyle(Color.white).transition(Reveal())
    let frames = await TransitionBodyFrames.asyncInsertion(of: view, at: Self.instants)
    let oneShot = try TransitionBodyFrames.insertion(of: view, at: Self.instants)
    for (frame, expected) in zip(frames, oneShot) {
      #expect(frame.lines == expected.lines, "\(frame.milliseconds) ms")
      #expect(frame.row(1, matches: expected), "\(frame.milliseconds) ms")
      #expect(frame.issues.isEmpty)
    }
    #expect(frames.map { $0.lines[1].count } == [0, 5, 10, 15, 20])
  }

  @Test("a run-loop insertion shows the same frames at the same instants")
  func runLoopFramesAtFixedInstants() throws {
    let probe = try TransitionBodyProbe(named: "run-loop-frames") {
      Text(Self.letters).transition(Reveal())
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.toggle(animation: Self.transactionAnimation)
      for (offset, progress) in zip(Self.instants, Self.progress) {
        if offset > 0 { try probe.advance(to: start.advanced(by: .milliseconds(offset))) }
        let columns = Int((Double(Self.letters.count) * progress).rounded())
        #expect(
          probe.line(1) == String(Self.letters.prefix(columns)), "\(offset) ms: \(probe.frame)")
      }
      // The clip path and the opacity each ran as one property animation.
      #expect(probe.activeAnimationCount == 0)
      #expect(probe.log.completions == 1)
    }
  }

  @Test("every interpolable modifier of a body animates from its willAppear value")
  func everyInterpolableModifierAnimates() throws {
    let probe = try TransitionBodyProbe(named: "every-slot") {
      Text("PRESENT").transition(EverySlot())
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      try probe.toggle(animation: Self.transactionAnimation)
      // One body with a modifier for each kind of slot. Each has a different
      // value in the willAppear phase, and each runs a property animation.
      let slots = probe.animationSlots
      for slot in [
        AnimatableSlot.opacity, .foregroundShapeStyle, .tintShapeStyle, .padding, .offset,
        .position, .frameWidth, .frameHeight, .borderForegroundStyle, .shapeFillStyle,
        .shapeStrokeStyle, .shapePath, .clipShapePaths, .strokeDashPhase, .shapeTrim,
        .textRoll,
      ] {
        #expect(slots.contains(slot), "\(slot)")
      }
      try probe.settle()
      #expect(probe.activeAnimationCount == 0)
      #expect(probe.log.issues.isEmpty, "\(probe.log.issues)")
    }
  }

  // MARK: - Structure that differs between phases

  @Test("a view only the willAppear phase has is reported once and never drawn")
  func willAppearOnlyViewIsReportedAndAbsent() throws {
    let probe = try TransitionBodyProbe(named: "will-appear-only") {
      Text("PRESENT").transition(GhostBefore())
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.toggle(animation: Self.transactionAnimation)
      for offset in Self.instants {
        if offset > 0 { try probe.advance(to: start.advanced(by: .milliseconds(offset))) }
        #expect(!probe.frame.contains("GHOST"), "\(offset) ms: \(probe.frame)")
      }
      #expect(probe.frame.contains("PRESENT"))
      try probe.settle()
      let issues = probe.log.issues.filter { $0.code == "transition.phaseOnlyView" }
      #expect(issues.count == 1)
      let issue = try #require(issues.first)
      // The issue names the transition type.
      #expect(issue.message.contains("GhostBefore"), "\(issue.message)")
      #expect(issue.severity == .warning)

      // A second insertion of the same view raises the same issue, which the
      // run loop reports once.
      try probe.toggle(animation: nil)
      try probe.toggle(animation: Self.transactionAnimation)
      try probe.settle()
      #expect(probe.log.issues.filter { $0.code == "transition.phaseOnlyView" }.count == 1)
    }
  }

  @Test("a view only the identity phase has is present at the first frame")
  func identityOnlyViewIsPresentAtOnce() throws {
    let probe = try TransitionBodyProbe(named: "identity-only") {
      Text("PRESENT").transition(BadgeAfter())
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.toggle(animation: Self.transactionAnimation)
      // The badge exists only in the identity body. It is there at once,
      // while the content is still at the willAppear opacity of zero.
      #expect(probe.frame.contains("BADGE"), "\(probe.frame)")
      #expect(!probe.frame.contains("PRESENT"), "\(probe.frame)")
      try probe.advance(to: start.advanced(by: .milliseconds(800)))
      #expect(probe.frame.contains("PRESENTBADGE"), "\(probe.frame)")
      try probe.settle()
      #expect(probe.log.issues.isEmpty, "\(probe.log.issues)")
    }
  }

  // MARK: - Views a body adds, and content placed twice

  @Test("a view the body adds mounts with the content, keeps its state and leaves with it")
  func addedViewLifecycle() throws {
    let log = TransitionBodyProbeLog()
    let probe = try TransitionBodyProbe(named: "added-view", log: log) {
      Text("PRESENT").transition(WithCounter(log: log))
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.toggle(animation: Self.transactionAnimation)
      // Mounted with the content, on the frame of the insertion, while the
      // insertion animates.
      #expect(probe.activeAnimationCount == 1)
      #expect(log.appears == 1)
      #expect(probe.frame.contains("taps 0"), "\(probe.frame)")
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(log.appears == 1)

      // Its state is ordinary state: it changes mid-insertion and persists
      // through the end of the insertion and an unrelated update.
      try probe.harness.clickText("taps 0")
      #expect(probe.frame.contains("taps 1"), "\(probe.frame)")
      try probe.settle()
      try probe.harness.clickText("host 0")
      #expect(probe.frame.contains("host 1"), "\(probe.frame)")
      #expect(probe.frame.contains("taps 1"), "\(probe.frame)")
      #expect(log.appears == 1)
      #expect(log.disappears == 0)

      // Torn down with the content, on the frame of the removal.
      try probe.toggle(animation: Self.transactionAnimation)
      #expect(log.disappears == 1)
      #expect(!probe.frame.contains("taps"), "\(probe.frame)")
      try probe.settle()

      // A new insertion is a new mount with new state.
      try probe.toggle(animation: nil)
      #expect(log.appears == 2)
      #expect(probe.frame.contains("taps 0"), "\(probe.frame)")
    }
  }

  @Test("content placed twice is two mounts with separate state")
  func contentPlacedTwiceHasSeparateState() throws {
    let probe = try TransitionBodyProbe(named: "twice") {
      TapCounter().transition(Doubled())
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      try probe.toggle(animation: Self.transactionAnimation)
      // Each placement has its own boundary, and each animates.
      #expect(probe.boundaryIdentities.count == 2)
      #expect(probe.animationIdentities(slot: .opacity) == Set(probe.boundaryIdentities))
      try probe.settle()
      #expect(probe.rows(containing: "count 0") == 2, "\(probe.frame)")

      // A write to the state of one mount leaves the other unchanged.
      try probe.harness.clickText("count 0")
      #expect(probe.rows(containing: "count 1") == 1, "\(probe.frame)")
      #expect(probe.rows(containing: "count 0") == 1, "\(probe.frame)")
      try probe.harness.clickText("count 1")
      #expect(probe.rows(containing: "count 2") == 1, "\(probe.frame)")
      #expect(probe.rows(containing: "count 0") == 1, "\(probe.frame)")
    }
  }

  @Test("a body with several root views animates each root once")
  func multiRootBodyAnimatesEachRoot() throws {
    let probe = try TransitionBodyProbe(named: "multi-root") {
      Text("PRESENT").transition(WithTail())
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.toggle(animation: Self.transactionAnimation)
      // The body returns the content and a second view side by side. Both
      // are inserted, and each runs its own opacity from zero: one willAppear
      // evaluation serves both.
      #expect(probe.animationIdentities(slot: .opacity).count == 2)
      #expect(probe.activeAnimationCount == 2)
      #expect(!probe.frame.contains("PRESENT") && !probe.frame.contains("TAIL"), "\(probe.frame)")
      try probe.advance(to: start.advanced(by: .milliseconds(800)))
      #expect(probe.frame.contains("PRESENT") && probe.frame.contains("TAIL"), "\(probe.frame)")
      #expect(probe.activeAnimationCount == 0)
      #expect(probe.log.completions == 1)
      try probe.settle()
      #expect(probe.log.issues.isEmpty, "\(probe.log.issues)")
    }
  }

  // MARK: - When nothing plays

  @Test("without an animated transaction the insertion snaps to the identity body")
  func unanimatedInsertionSnaps() throws {
    let probe = try TransitionBodyProbe(named: "unanimated") {
      Text(Self.letters).transition(Reveal())
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      try probe.toggle(animation: nil)
      #expect(probe.line(1) == Self.letters)
      #expect(probe.activeAnimationCount == 0)
      try probe.settle()
      #expect(probe.line(1) == Self.letters)
    }
  }

  @Test("withAnimation(nil) snaps a body that carries its own animation")
  func disabledTransactionSnaps() throws {
    let probe = try TransitionBodyProbe(named: "disabled") {
      Text(Self.letters).transition(Reveal().animation(Self.ownAnimation))
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      try probe.toggle(animation: nil, disabling: true)
      #expect(probe.line(1) == Self.letters)
      #expect(probe.activeAnimationCount == 0)
    }
  }

  @Test("a body transition inside a container that mounts with it does not play")
  func bulkMountPlaysNoBodyTransition() throws {
    let probe = try TransitionBodyProbe(named: "bulk") {
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        Text(Self.letters).transition(Reveal())
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      try probe.toggle(animation: Self.transactionAnimation)
      // The container appeared, so it takes the default fade. The transition
      // child appeared with its parent, which is not a change of its own
      // presence: nothing animates on its boundary.
      let boundary = try #require(probe.boundaryIdentities.first)
      #expect(!probe.animationIdentities.contains(boundary))
      #expect(probe.animationIdentities(slot: .clipShapePaths).isEmpty)
      try probe.settle()
      #expect(probe.line(2) == Self.letters, "\(probe.frame)")
    }
  }

  @Test(
    "reduced motion and stable output snap the insertion whatever hasMotion says",
    arguments: [TransitionBodyProbePolicy.reduceMotion, .stableOutput], [true, false])
  func motionPoliciesSnap(policy: TransitionBodyProbePolicy, hasMotion: Bool) throws {
    let probe = try TransitionBodyProbe(named: "policy-\(policy)-\(hasMotion)", policy: policy) {
      if hasMotion {
        Text(Self.letters).transition(Reveal())
      } else {
        Text(Self.letters).transition(StillReveal())
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      try probe.toggle(animation: Self.transactionAnimation)
      #expect(probe.line(1) == Self.letters, "\(probe.frame)")
      #expect(probe.activeAnimationCount == 0)
      try probe.settle()
      #expect(probe.line(1) == Self.letters)
    }
  }

  // MARK: - Curves, channels and completion

  @Test("the effect channel and the body channel of a mixed transition both animate")
  func mixedTransitionAnimatesBothChannels() throws {
    let probe = try TransitionBodyProbe(named: "mixed") {
      Text("PRESENT").transition(Shift().combined(with: .opacity))
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.toggle(animation: Self.transactionAnimation)
      // The effect channel fades the inserted view. The body channel moves
      // the offset the body wraps the content in.
      #expect(probe.animationIdentities(slot: .opacity).count == 1)
      #expect(probe.animationIdentities(slot: .offset).count == 1)
      #expect(!probe.frame.contains("PRESENT"), "\(probe.frame)")
      #expect(probe.indent(1) == nil)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      // Half way: the offset is at four of its eight columns, give or take
      // the cell an integer offset truncates to.
      #expect(abs((probe.indent(1) ?? -8) - 4) <= 1, "\(probe.frame)")
      #expect(probe.animationIdentities(slot: .opacity).count == 1)
      try probe.advance(to: start.advanced(by: .milliseconds(800)))
      #expect(probe.line(1) == "PRESENT", "\(probe.frame)")
      #expect(probe.activeAnimationCount == 0)
      #expect(probe.log.completions == 1)
    }
  }

  @Test("a transition's own animation drives the body channel")
  func ownAnimationDrivesTheBodyChannel() throws {
    let probe = try TransitionBodyProbe(named: "own") {
      Text("PRESENT").transition(Shift().combined(with: .opacity).animation(Self.ownAnimation))
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.toggle(animation: Self.transactionAnimation)
      #expect(probe.activeAnimationBoxes == [Self.ownAnimation.animationBox])
      // 200 ms is half of the transition's own 400 ms.
      try probe.advance(to: start.advanced(by: .milliseconds(200)))
      #expect(abs((probe.indent(1) ?? -8) - 4) <= 1, "\(probe.frame)")
      try probe.advance(to: start.advanced(by: .milliseconds(399)))
      #expect(probe.activeAnimationCount == 2)
      #expect(probe.log.completions == 0)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.activeAnimationCount == 0)
      #expect(probe.line(1) == "PRESENT", "\(probe.frame)")
      // Both channels retained the transaction's batch, so its completion
      // fires when they end, not at the transaction's 800 ms.
      #expect(probe.log.completions == 1)
    }
  }

  @Test("an own animation plays a body when the state change carries no animation")
  func ownAnimationPlaysWithoutAnAnimatedTransaction() throws {
    let probe = try TransitionBodyProbe(named: "own-unanimated") {
      Text("PRESENT").transition(Shift().animation(Self.ownAnimation))
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.toggle(animation: nil)
      #expect(probe.line(1) == "        PRESENT", "\(probe.frame)")
      try probe.advance(to: start.advanced(by: .milliseconds(200)))
      #expect(abs((probe.indent(1) ?? -8) - 4) <= 1, "\(probe.frame)")
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.line(1) == "PRESENT", "\(probe.frame)")
      #expect(probe.activeAnimationCount == 0)
    }
  }

  @Test("a logicallyComplete completion waits for the body insertion to finish")
  func completionWaitsForTheBodyInsertion() throws {
    // The body animates for 1200 ms inside an 800 ms transaction. A
    // completion that nothing retained would fire at 800 ms.
    let probe = try TransitionBodyProbe(named: "completion") {
      Text("PRESENT").transition(
        Shift().animation(.linear(duration: .milliseconds(1200))))
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.toggle(animation: Self.transactionAnimation)
      try probe.advance(to: start.advanced(by: .milliseconds(800)))
      #expect(probe.log.completions == 0)
      #expect(probe.activeAnimationCount == 1)
      try probe.advance(to: start.advanced(by: .milliseconds(1199)))
      #expect(probe.log.completions == 0)
      try probe.advance(to: start.advanced(by: .milliseconds(1200)))
      #expect(probe.log.completions == 1)
      #expect(probe.activeAnimationCount == 0)
      try probe.settle()
      #expect(probe.log.completions == 1)
    }
  }

  @Test("a body with nothing to interpolate plays nothing and keeps no curve")
  func bodyWithoutAnInterpolableDifference() throws {
    let probe = try TransitionBodyProbe(named: "nothing") {
      Text("PRESENT").transition(Brackets().animation(Self.ownAnimation))
    }
    defer { probe.shutdown() }
    try probe.run { start in
      let registered = probe.registeredAnimationCount
      try probe.toggle(animation: Self.transactionAnimation)
      // The brackets are text, which is not a slot: the identity strings show
      // at once and no animation starts.
      #expect(probe.line(1) == "[PRESENT]", "\(probe.frame)")
      #expect(probe.activeAnimationCount == 0)
      // The transition's own curve was never registered, since nothing plays
      // it. The transaction's curve is the only addition.
      #expect(probe.registeredAnimationCount == registered + 1)
      // Nothing retained the batch, so the completion drains at the
      // transaction's own 800 ms.
      try probe.advance(to: start.advanced(by: .milliseconds(799)))
      #expect(probe.log.completions == 0)
      try probe.advance(to: start.advanced(by: .milliseconds(800)))
      #expect(probe.log.completions == 1)
    }
  }

  @Test("removal of a custom body still snaps")
  func removalStillSnaps() throws {
    let probe = try TransitionBodyProbe(named: "removal", shown: true) {
      Text(Self.letters).transition(Reveal())
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      try probe.toggle(animation: Self.transactionAnimation)
      #expect(!probe.frame.contains(Self.letters), "\(probe.frame)")
      #expect(probe.removingCount == 0)
      #expect(probe.activeAnimationCount == 0)
    }
  }

  @Test("a removal during an insertion ends the insertion at once")
  func removalDuringInsertionEndsIt() throws {
    let probe = try TransitionBodyProbe(named: "removal-mid-insertion") {
      Text(Self.letters).transition(Reveal())
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.toggle(animation: Self.transactionAnimation)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      // The clip path and the opacity are half way.
      #expect(probe.activeAnimationCount == 2)
      #expect(probe.line(1) == String(Self.letters.prefix(10)), "\(probe.frame)")
      #expect(probe.log.completions == 0)
      try probe.toggle(animation: Self.transactionAnimation)
      // The view is gone, with no overlay, and its animations went with it.
      #expect(!probe.frame.contains("A"), "\(probe.frame)")
      #expect(probe.removingCount == 0)
      #expect(probe.activeAnimationCount == 0)
      // The insertion's completion fires when the removal ends it. The
      // removal's own completion follows at the end of its transaction.
      #expect(probe.log.completions == 1)
      try probe.settle()
      #expect(probe.activeAnimationCount == 0)
      #expect(probe.log.completions == 2)
    }
  }

  // MARK: - Built-in transitions applied inside a body

  @Test("a fixed offset transition applied inside a body renders its offset in every phase")
  func builtInOffsetBodyIsExact() throws {
    let transition = OffsetTransition(CellSize(width: 4, height: 1))
    for (phase, lines) in [
      (TransitionPhase.willAppear, ["", "    PRESENT"]),
      (.identity, ["PRESENT", ""]),
      (.didDisappear, ["", "    PRESENT"]),
    ] {
      let artifacts = DefaultRenderer().renderArtifacts(
        transition.apply(content: Text("PRESENT"), phase: phase),
        context: .init(identity: testIdentity("transition-body", "offset-static")),
        proposal: .init(width: .finite(20), height: .finite(2)))
      #expect(Array(artifacts.rasterSurface.lines.prefix(2)) == lines, "\(phase)")
      #expect(artifacts.diagnostics.runtime.issues.isEmpty, "\(phase)")
    }
  }

  @Test("a fixed offset transition applied inside a body animates on insertion")
  func builtInOffsetBodyAnimates() throws {
    let frames = try TransitionBodyFrames.insertion(
      of: Text("PRESENT").transition(Nudge()), at: Self.instants)
    for (frame, progress) in zip(frames, Self.progress) {
      let column = try #require(frame.offsetColumns.first)
      #expect(
        frame.lines[1] == String(repeating: " ", count: column) + "PRESENT",
        "\(frame.milliseconds) ms: \(frame.lines[1])")
      #expect(abs(Double(column) - 8 * (1 - progress)) <= 1, "\(frame.milliseconds) ms")
      #expect(frame.issues.isEmpty)
    }
    let columns = frames.compactMap(\.offsetColumns.first)
    #expect(columns.first == 8 && columns.last == 0, "\(columns)")
    #expect(columns == columns.sorted(by: >), "\(columns)")
  }

  @Test("a move or a scale transition applied inside a body reports a runtime issue")
  func builtInMoveAndScaleBodiesReport() throws {
    func render<V: View>(_ view: V) -> FrameArtifacts {
      DefaultRenderer().renderArtifacts(
        view,
        context: .init(identity: testIdentity("transition-body", "placed-static")),
        proposal: .init(width: .finite(20), height: .finite(2)))
    }
    func issues(_ artifacts: FrameArtifacts) -> [RuntimeIssue] {
      artifacts.diagnostics.runtime.issues.filter {
        $0.code == "transition.unsupportedBuiltInBody"
      }
    }
    // Each built-in whose active phase moves relative to an edge or scales.
    let moved = render(MoveTransition(edge: .leading).apply(content: Text("X"), phase: .willAppear))
    let scaled = render(ScaleTransition(0.5).apply(content: Text("X"), phase: .didDisappear))
    let pushed = render(PushTransition(edge: .top).apply(content: Text("X"), phase: .willAppear))
    let slid = render(SlideTransition().apply(content: Text("X"), phase: .didDisappear))
    for (name, artifacts) in [
      ("MoveTransition", moved), ("ScaleTransition", scaled), ("PushTransition", pushed),
      ("SlideTransition", slid),
    ] {
      let reported = issues(artifacts)
      #expect(reported.count == 1, "\(name)")
      // The issue names the type and the alternative that works.
      #expect(reported.first?.message.contains(name) == true, "\(name)")
      #expect(reported.first?.message.contains("combined(with:") == true, "\(name)")
    }
    // The content renders in place, without the effect. The push still
    // applies the opacity it can render.
    #expect(moved.rasterSurface.lines.first == "X")
    #expect(scaled.rasterSurface.lines.first == "X")
    #expect(pushed.rasterSurface.lines.first == "")

    // The identity phase has nothing a body cannot render.
    for artifacts in [
      render(MoveTransition(edge: .leading).apply(content: Text("X"), phase: .identity)),
      render(ScaleTransition(0.5).apply(content: Text("X"), phase: .identity)),
      render(OpacityTransition().apply(content: Text("X"), phase: .willAppear)),
    ] {
      #expect(issues(artifacts).isEmpty)
    }
  }

  @Test("a move applied inside a body is reported when the engine evaluates the willAppear phase")
  func builtInMoveBodyReportsFromAnInsertion() throws {
    let probe = try TransitionBodyProbe(named: "move-in-body") {
      Text("PRESENT").transition(MovedAndFaded())
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      // At rest the identity phase has no move: nothing is reported.
      try probe.toggle(animation: nil)
      try probe.settle()
      #expect(probe.log.issues.isEmpty, "\(probe.log.issues)")
      try probe.toggle(animation: nil)

      // An animated insertion evaluates the willAppear phase, where the move
      // has a value the body cannot render.
      try probe.toggle(animation: Self.transactionAnimation)
      // The opacity of the same body still animates.
      #expect(probe.animationIdentities(slot: .opacity).count == 1)
      try probe.settle()
      let issues = probe.log.issues.filter { $0.code == "transition.unsupportedBuiltInBody" }
      #expect(issues.count == 1)
      #expect(issues.first?.message.contains("MoveTransition") == true)
    }
  }
}

// MARK: - Transitions

/// A rectangle covering `fraction` of the width. Every fraction has the same
/// element topology, so two of them interpolate.
private struct RevealShape: Shape {
  var fraction: Double

  func path(in rect: Rect) -> Path {
    var path = Path()
    let right = rect.origin.x + rect.size.width * fraction
    let bottom = rect.origin.y + rect.size.height
    path.move(to: Point(x: rect.origin.x, y: rect.origin.y))
    path.addLine(to: Point(x: right, y: rect.origin.y))
    path.addLine(to: Point(x: right, y: bottom))
    path.addLine(to: Point(x: rect.origin.x, y: bottom))
    path.closeSubpath()
    return path
  }
}

/// An interpolable body: a clip path that grows from nothing to the whole
/// view, and an opacity.
private struct Reveal: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .clipShape(RevealShape(fraction: phase.isIdentity ? 1 : 0))
      .opacity(phase.isIdentity ? 1 : 0.2)
  }
}

/// `Reveal` declaring that it has no motion.
private struct StillReveal: Transition {
  static let properties = TransitionProperties(hasMotion: false)

  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .clipShape(RevealShape(fraction: phase.isIdentity ? 1 : 0))
      .opacity(phase.isIdentity ? 1 : 0.2)
  }
}

/// The body of `Reveal` held at one progress in every phase.
private struct RevealAt: Transition {
  var progress: Double

  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .clipShape(RevealShape(fraction: progress))
      .opacity(0.2 + 0.8 * progress)
  }
}

/// A modifier for each kind of slot the engine interpolates.
private struct EverySlot: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    let active = !phase.isIdentity
    content
      .foregroundStyle(active ? Color.red : Color.white)
      .tint(active ? Color.green : Color.blue)
      .padding(active ? 2 : 1)
      .frame(width: active ? 22 : 18, height: active ? 7 : 5)
      .border(active ? Color.red : Color.white)
      .background(active ? Color.gray : Color.blue)
      .overlay {
        RevealShape(fraction: active ? 0.5 : 1)
          .trim(from: 0, to: active ? 0.5 : 1)
          .stroke(
            active ? Color.red : Color.white,
            style: StrokeStyle(dash: [2, 1], dashPhase: active ? 3 : 0))
      }
      .clipShape(RevealShape(fraction: active ? 0.5 : 1))
      .overlay(alignment: .bottom) {
        Text(active ? "10" : "42").contentTransition(.numericText())
      }
      .offset(x: active ? 2 : 0, y: 0)
      .position(x: active ? 14 : 12, y: 3)
      .opacity(active ? 0.5 : 1)
  }
}

/// Two values that cannot interpolate, a blend mode and an underline, beside
/// one that can, an offset.
private struct BlendShift: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .blendMode(phase.isIdentity ? .normal : .multiply)
      .underline(!phase.isIdentity)
      .offset(x: phase.isIdentity ? 0 : 8, y: 0)
  }
}

/// Adds an overlay in every phase.
private struct Starred: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .opacity(phase.isIdentity ? 1 : 0)
      .padding(.trailing, 2)
      .overlay(alignment: .trailing) { Text("*") }
  }
}

/// Sets the foreground style of the content through the environment.
private struct Tinted: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.foregroundStyle(phase.isIdentity ? Color.white : Color.red)
  }
}

private struct TintedAt: Transition {
  var color: Color

  func body(content: Content, phase: TransitionPhase) -> some View {
    content.foregroundStyle(color)
  }
}

/// A view only the willAppear phase has.
private struct GhostBefore: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    HStack(spacing: 0) {
      if phase == .willAppear { Text("GHOST") }
      content.opacity(phase.isIdentity ? 1 : 0)
    }
  }
}

/// A view only the identity phase has.
private struct BadgeAfter: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    HStack(spacing: 0) {
      content.opacity(phase.isIdentity ? 1 : 0)
      if phase.isIdentity { Text("BADGE") }
    }
  }
}

/// Adds a view with state and lifecycle handlers.
private struct WithCounter: Transition {
  let log: TransitionBodyProbeLog

  func body(content: Content, phase: TransitionPhase) -> some View {
    HStack(spacing: 1) {
      content.opacity(phase.isIdentity ? 1 : 0)
      AddedCounter(log: log)
    }
  }
}

private struct AddedCounter: View {
  @State private var taps = 0
  let log: TransitionBodyProbeLog

  var body: some View {
    Button("taps \(taps)") { taps += 1 }
      .onAppear { log.appears += 1 }
      .onDisappear { log.disappears += 1 }
  }
}

/// Returns two root views: the content and a view beside it.
private struct WithTail: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.opacity(phase.isIdentity ? 1 : 0)
    Text("TAIL").opacity(phase.isIdentity ? 1 : 0)
  }
}

/// Places its content twice.
private struct Doubled: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      content.opacity(phase.isIdentity ? 1 : 0)
      content.opacity(phase.isIdentity ? 1 : 0)
    }
  }
}

private struct TapCounter: View {
  @State private var count = 0

  var body: some View {
    Button("count \(count)") { count += 1 }
  }
}

/// Wraps the content in an offset that starts eight columns to the right.
private struct Shift: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.offset(x: phase.isIdentity ? 0 : 8, y: 0)
  }
}

/// Text that differs between phases and nothing that can interpolate.
private struct Brackets: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    HStack(spacing: 0) {
      Text(phase.isIdentity ? "[" : "<")
      content
      Text(phase.isIdentity ? "]" : ">")
    }
  }
}

/// Applies the built-in fixed offset inside a body.
private struct Nudge: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    OffsetTransition(CellSize(width: 8, height: 0)).apply(content: content, phase: phase)
  }
}

/// Applies a built-in move, which a body cannot render, and a built-in
/// opacity, which it can.
private struct MovedAndFaded: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    MoveTransition(edge: .leading).apply(
      content: OpacityTransition().apply(content: content, phase: phase), phase: phase)
  }
}

// MARK: - Frames from one renderer

private struct TransitionBodyPresenceHost<Content: View>: View {
  var visible: Bool
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("STAYS")
      if visible { content() }
    }
  }
}

/// One sampled frame.
@MainActor
private struct TransitionBodyFrame {
  var milliseconds: Int
  var surface: RasterSurface
  var resolved: ResolvedNode
  var issues: [RuntimeIssue]

  var lines: [String] { surface.lines }

  /// The boundary nodes of the presented tree, in tree order.
  var boundaries: [ResolvedNode] {
    func collect(_ node: ResolvedNode) -> [ResolvedNode] {
      (node.kind == .view(.transitionContent) ? [node] : []) + node.children.flatMap(collect)
    }
    return collect(resolved)
  }

  /// The horizontal offset of each offset node of the presented tree. An
  /// integer offset interpolates by truncating its scaled distance, so a
  /// sample a rounding error short of a whole cell is one cell behind.
  var offsetColumns: [Int] {
    func collect(_ node: ResolvedNode) -> [Int] {
      var columns: [Int] = []
      if case .offset(let x, _) = node.layoutBehavior { columns.append(x) }
      return columns + node.children.flatMap(collect)
    }
    return collect(resolved)
  }

  func foreground(row: Int, column: Int) -> Color? {
    surface.cells[row][column].style?.foregroundColor
  }

  /// Whether `row` has the same characters and foreground colours as the
  /// same row of `other`. Colours compare within a rounding tolerance.
  func row(_ row: Int, matches other: TransitionBodyFrame) -> Bool {
    let mine = surface.cells[row]
    let theirs = other.surface.cells[row]
    guard mine.count == theirs.count else { return false }
    return zip(mine, theirs).allSatisfy { lhs, rhs in
      guard lhs.character == rhs.character else { return false }
      switch (lhs.style?.foregroundColor, rhs.style?.foregroundColor) {
      case (nil, nil):
        return true
      case (let lhs?, let rhs?):
        return abs(lhs.red - rhs.red) < 1e-6 && abs(lhs.green - rhs.green) < 1e-6
          && abs(lhs.blue - rhs.blue) < 1e-6 && abs(lhs.alpha - rhs.alpha) < 1e-6
      default:
        return false
      }
    }
  }
}

@MainActor
private enum TransitionBodyFrames {
  static let transactionAnimation = Animation.linear(duration: .milliseconds(800))
  static let proposal = ProposedSize(width: .finite(24), height: .finite(4))

  /// Inserts `view` under an 800 ms linear transaction and samples the frame
  /// at each offset. Offset 0 is the frame of the insertion itself.
  static func insertion<V: View>(of view: V, at offsets: [Int]) throws -> [TransitionBodyFrame] {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let root = testIdentity("transition-body", "frames")
    let start = MonotonicInstant(offset: .seconds(100))
    var animated = TransactionSnapshot()
    animated.animationRequest = .animate(transactionAnimation.animationBox)
    return withAnimationSinks(controller) {
      controller.register(transactionAnimation)
      _ = renderer.renderArtifacts(
        TransitionBodyPresenceHost(visible: false) { view },
        context: .init(identity: root), proposal: proposal, frameInstant: start)
      return offsets.map { offset in
        let artifacts = renderer.renderArtifacts(
          TransitionBodyPresenceHost(visible: true) { view },
          context: .init(identity: root, transaction: offset == 0 ? animated : .init()),
          proposal: proposal, frameInstant: start.advanced(by: .milliseconds(offset)))
        return TransitionBodyFrame(
          milliseconds: offset,
          surface: artifacts.rasterSurface,
          resolved: artifacts.resolvedTree,
          issues: artifacts.diagnostics.runtime.issues)
      }
    }
  }

  /// `insertion(of:at:)` through the async renderer.
  static func asyncInsertion<V: View>(of view: V, at offsets: [Int]) async -> [TransitionBodyFrame]
  {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let root = testIdentity("transition-body", "frames")
    let start = MonotonicInstant(offset: .seconds(100))
    var animated = TransactionSnapshot()
    animated.animationRequest = .animate(transactionAnimation.animationBox)
    return await withAnimationSinks(controller) {
      controller.register(transactionAnimation)
      _ = await renderer.renderArtifactsAsync(
        TransitionBodyPresenceHost(visible: false) { view },
        context: .init(identity: root), proposal: proposal, frameInstant: start)
      var frames: [TransitionBodyFrame] = []
      for offset in offsets {
        let artifacts = await renderer.renderArtifactsAsync(
          TransitionBodyPresenceHost(visible: true) { view },
          context: .init(identity: root, transaction: offset == 0 ? animated : .init()),
          proposal: proposal, frameInstant: start.advanced(by: .milliseconds(offset)))
        frames.append(
          TransitionBodyFrame(
            milliseconds: offset,
            surface: artifacts.rasterSurface,
            resolved: artifacts.resolvedTree,
            issues: artifacts.diagnostics.runtime.issues))
      }
      return frames
    }
  }

  /// Renders `view` present from the first frame, with no animation.
  static func atRest<V: View>(_ view: V) throws -> TransitionBodyFrame {
    let artifacts = DefaultRenderer().renderArtifacts(
      TransitionBodyPresenceHost(visible: true) { view },
      context: .init(identity: testIdentity("transition-body", "frames")),
      proposal: proposal)
    return TransitionBodyFrame(
      milliseconds: 0,
      surface: artifacts.rasterSurface,
      resolved: artifacts.resolvedTree,
      issues: artifacts.diagnostics.runtime.issues)
  }
}

// MARK: - Run-loop probe

@MainActor
private final class TransitionBodyProbeClock { var now = MonotonicInstant.now() }

@MainActor
private final class TransitionBodyProbeLog {
  var shown: Binding<Bool>?
  var completions = 0
  var issues: [RuntimeIssue] = []
  var appears = 0
  var disappears = 0
}

enum TransitionBodyProbePolicy: Sendable, CustomStringConvertible {
  case normal, reduceMotion, stableOutput

  var description: String {
    switch self {
    case .normal: "normal"
    case .reduceMotion: "reduce-motion"
    case .stableOutput: "stable-output"
    }
  }
}

/// A run-loop harness around one conditional view, driven on an injected
/// frame clock.
@MainActor
private final class TransitionBodyProbe<Inserted: View> {
  let harness: StressRuntimeHarness<TransitionBodyProbeRoot<Inserted>>
  let clock: TransitionBodyProbeClock
  let log: TransitionBodyProbeLog

  init(
    named name: String,
    shown: Bool = false,
    policy: TransitionBodyProbePolicy = .normal,
    log: TransitionBodyProbeLog = TransitionBodyProbeLog(),
    @ViewBuilder inserted: @escaping () -> Inserted
  ) throws {
    self.log = log
    harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("transition-body", name),
      size: .init(width: 30, height: 5)
    ) {
      TransitionBodyProbeRoot(
        initiallyShown: shown, policy: policy, log: log, inserted: inserted)
    }
    harness.runLoop.runtimeIssueSink = RuntimeIssueSink { issue in
      log.issues.append(issue)
    }
    // The clock starts after the mount frame: a frame never runs earlier
    // than the frame before it.
    let clock = TransitionBodyProbeClock()
    self.clock = clock
    harness.runLoop.frameClock = { clock.now }
  }

  private var controller: AnimationController {
    harness.runLoop.renderer.internalAnimationController
  }

  var frame: String { harness.frame }

  /// One row of the frame without its trailing spaces.
  func line(_ row: Int) -> String {
    let rows = frame.split(separator: "\n", omittingEmptySubsequences: false)
    guard rows.indices.contains(row) else { return "" }
    return String(rows[row].reversed().drop { $0 == " " }.reversed())
  }

  /// The number of leading spaces of a row, or `nil` for a blank row.
  func indent(_ row: Int) -> Int? {
    let line = line(row)
    return line.isEmpty ? nil : line.prefix { $0 == " " }.count
  }

  /// The number of rows of the frame that contain `text`.
  func rows(containing text: String) -> Int {
    frame.split(separator: "\n", omittingEmptySubsequences: false)
      .filter { $0.contains(text) }.count
  }

  var activeAnimationCount: Int { controller.activeAnimationCount }

  var registeredAnimationCount: Int { controller.debugStateSnapshot().registeredAnimationCount }

  var removingCount: Int { controller.debugStateSnapshot().removingNodeIDs.count }

  var activeAnimationBoxes: Set<AnimationBox> {
    Set(controller.debugStateSnapshot().activeAnimationBoxesByKey.values)
  }

  /// The identities that have a property animation in flight.
  var animationIdentities: Set<Identity> {
    Set(controller.debugStateSnapshot().activeAnimationKeys.map(\.identity))
  }

  /// The slots that have a property animation in flight.
  var animationSlots: Set<AnimatableSlot> {
    Set(
      controller.debugStateSnapshot().activeAnimationKeys.compactMap { key in
        if case .property(let slot) = key.scope { slot } else { nil }
      })
  }

  func animationIdentities(slot: AnimatableSlot) -> Set<Identity> {
    Set(
      controller.debugStateSnapshot().activeAnimationKeys
        .filter { $0.scope == .property(slot) }.map(\.identity))
  }

  /// The boundary nodes of the tree the controller last processed.
  var boundaryIdentities: [Identity] {
    func collect(_ node: ResolvedNode) -> [Identity] {
      (node.kind == .view(.transitionContent) ? [node.identity] : [])
        + node.children.flatMap(collect)
    }
    return controller.debugStateSnapshot().previousTreeRoot.map(collect) ?? []
  }

  func shutdown() { harness.shutdown() }

  /// Runs `body` with the animation sinks bound, passing the start instant.
  func run(_ body: (MonotonicInstant) throws -> Void) throws {
    try withAnimationSinks(controller) { try body(clock.now) }
  }

  /// Flips presence and renders the frame of the change. `animation: nil`
  /// is a plain state write, or `withAnimation(nil)` when `disabling`.
  func toggle(animation: Animation?, disabling: Bool = false) throws {
    let shown = try #require(log.shown)
    let log = log
    if let animation {
      withAnimation(animation, completionCriteria: .logicallyComplete) {
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
    // Every frame rendered at an exact instant arms its own 33 ms cadence
    // while a transition is registered, so a test that samples several
    // instants meets several interleaved cadences afterwards.
    var turns = 0
    while let wake = harness.runLoop.scheduler.nextWakeInstant(after: clock.now), wake < target,
      turns < 1024
    {
      clock.now = wake
      _ = try harness.render()
      turns += 1
    }
    #expect(turns < 1024, "the scheduler must reach the target within the turn budget")
    clock.now = target
    harness.runLoop.scheduler.requestDeadline(clock.now)
    _ = try harness.render()
  }

  /// Runs 1200 ms of armed turns, which is longer than any animation that
  /// is in flight when a test settles. A registered transition keeps a frame
  /// deadline armed while its view is present, so there is no quiescent
  /// scheduler to wait for.
  func settle() throws {
    try advance(to: clock.now.advanced(by: .milliseconds(1200)))
  }
}

private struct TransitionBodyProbeRoot<Inserted: View>: View {
  @State private var shown: Bool
  @State private var hostTaps = 0
  let policy: TransitionBodyProbePolicy
  let log: TransitionBodyProbeLog
  let inserted: () -> Inserted

  init(
    initiallyShown: Bool,
    policy: TransitionBodyProbePolicy,
    log: TransitionBodyProbeLog,
    inserted: @escaping () -> Inserted
  ) {
    _shown = State(initialValue: initiallyShown)
    self.policy = policy
    self.log = log
    self.inserted = inserted
  }

  var body: some View {
    let _ = capture()
    VStack(alignment: .leading, spacing: 0) {
      Button("host \(hostTaps)") { hostTaps += 1 }
      if shown { inserted() }
    }
    .environment(\.accessibilityReduceMotion, policy == .reduceMotion)
    .environment(\.stableOutput, policy == .stableOutput)
  }

  private func capture() {
    log.shown = $shown
  }
}
