import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Removal of a custom `Transition` body (STUI-1545): the departing content
/// renders through the body of the `.didDisappear` phase and moves toward it
/// from the state on screen.
///
/// Frame tests render one renderer at fixed instants and read the placed tree
/// and the raster each frame drew. Run-loop tests step an injected frame
/// clock to each scheduler wake. Nothing waits.
@MainActor
@Suite("Transition body removal", .serialized)
struct TransitionBodyRemovalTests {
  private static let letters = "ABCDEFGHIJKLMNOPQRST"
  /// The start, the three quarters and the end of the 800 ms transaction.
  private static let instants = [0, 200, 400, 600, 800]
  private static let progress = [0.0, 0.25, 0.5, 0.75, 1.0]
  private static let transactionAnimation = RemovalBodyFrames.transactionAnimation
  private static let ownAnimation = Animation.linear(duration: .milliseconds(400))

  // MARK: - Frames at fixed instants

  @Test("an interpolable body animates its clip path and its opacity to the didDisappear phase")
  func interpolableBodyFrames() throws {
    let frames = try RemovalBodyFrames.removal(
      of: Text(Self.letters).foregroundStyle(Color.white).transition(RemovalReveal()),
      at: Self.instants)
    for (frame, progress) in zip(frames, Self.progress) {
      let label = "\(frame.milliseconds) ms"
      // Coverage: the clip path has shrunk to `1 - progress` of the width, so
      // that many columns of the text are still painted.
      let columns = Int((Double(Self.letters.count) * (1 - progress)).rounded())
      #expect(frame.lines[1] == String(Self.letters.prefix(columns)), "\(label)")
      guard progress < 1 else {
        // The curve has ended: the removal draws nothing on its last frame.
        #expect(frame.boundaries.isEmpty, "\(label)")
        continue
      }
      // Opacity: the boundary the body's modifiers land on carries the
      // interpolated value, and it is part of a display-only overlay.
      let boundary = try #require(frame.boundaries.first, "\(label)")
      #expect(boundary.isTransient, "\(label)")
      let opacity = try #require(boundary.drawMetadata.baseStyle.explicitOpacity, "\(label)")
      #expect(abs(opacity - (1 - 0.8 * progress)) < 1e-9, "\(label): \(opacity)")
      // The cells are those of the same body held at that progress.
      let held = try RemovalBodyFrames.atRest(
        Text(Self.letters).foregroundStyle(Color.white)
          .transition(RemovalRevealAt(progress: 1 - progress)))
      #expect(frame.row(1, matches: held), "\(label)")
      #expect(frame.issues.isEmpty, "\(label): \(frame.issues)")
    }
    // The opacity is visible in the cells: the first painted letter gets
    // dimmer from one sample to the next.
    let brightness = frames.dropLast().map { $0.foreground(row: 1, column: 0)?.red ?? -1 }
    #expect(brightness == brightness.sorted(by: >) && Set(brightness).count == brightness.count)
  }

  @Test("a value that cannot interpolate shows its didDisappear value from the first frame")
  func nonInterpolableDifferenceTakesTheDidDisappearValueAtOnce() throws {
    let frames = try RemovalBodyFrames.removal(
      of: Text("PRESENT").transition(RemovalBlendShift()), at: Self.instants)
    // At rest the identity phase asks for `.normal`.
    let atRest = try RemovalBodyFrames.atRest(Text("PRESENT").transition(RemovalBlendShift()))
    #expect(atRest.boundaries.first?.drawEffects.ordered == [.blendMode(.normal)])

    for (frame, progress) in zip(frames.dropLast(), Self.progress) {
      let label = "\(frame.milliseconds) ms"
      // `blendMode` is not a slot. The didDisappear phase asks for
      // `.multiply`, which shows from the first frame of the removal and
      // holds.
      let boundary = try #require(frame.boundaries.first, "\(label)")
      #expect(boundary.drawEffects.ordered == [.blendMode(.multiply)], "\(label)")
      // The offset in the same body is a slot: the text is drawn at the
      // sampled offset, which starts where the view was.
      let column = try #require(frame.offsetColumns.first, "\(label)")
      #expect(
        frame.lines[1] == String(repeating: " ", count: column) + "PRESENT",
        "\(label): \(frame.lines[1])")
      #expect(abs(Double(column) - 8 * progress) <= 1, "\(label): \(column)")
      #expect(frame.issues.isEmpty, "\(label): \(frame.issues)")
    }
    let columns = frames.dropLast().compactMap(\.offsetColumns.first)
    #expect(columns.first == 0, "\(columns)")
    #expect(columns == columns.sorted(), "\(columns)")
    #expect(frames.last?.lines[1] == "")
  }

  @Test("a view the body adds is drawn in every frame of the removal")
  func addedOverlayIsDrawnInEveryFrame() throws {
    let frames = try RemovalBodyFrames.removal(
      of: Text("PRESENT").transition(RemovalStarred()), at: Self.instants)
    for frame in frames.dropLast() {
      // The star is part of the didDisappear body, so it is drawn for as long
      // as the removal lasts. The content fades out beside it.
      #expect(frame.lines[1].hasSuffix("*"), "\(frame.milliseconds) ms: \(frame.lines[1])")
      #expect(
        frame.lines[1].contains("PRESENT") == (frame.milliseconds < 800),
        "\(frame.milliseconds) ms: \(frame.lines[1])")
    }
    #expect(frames.first?.lines[1] == "PRESENT *")
    // The content dims while the star keeps its colour.
    let content = frames.dropLast().map { $0.foreground(row: 1, column: 0)?.red ?? -1 }
    #expect(content == content.sorted(by: >) && Set(content).count == content.count, "\(content)")
    let star = Set(frames.dropLast().map { $0.foreground(row: 1, column: 8)?.red ?? -1 })
    #expect(star.count == 1, "\(star)")
    #expect(frames.last?.lines[1] == "")
  }

  @Test("the abortable frame path, where the graph is suspended, shows the same frames")
  func framesOnTheAbortablePath() async throws {
    // The async renderer runs the abortable frame head: the prepared graph
    // is not live while the removal is planned, and the frame tail runs on
    // its worker. The didDisappear phase is evaluated without the graph and
    // laid out on the main actor, so the frames are those of the one-shot
    // path.
    let reveal = Text(Self.letters).foregroundStyle(Color.white).transition(RemovalReveal())
    let frames = await RemovalBodyFrames.asyncRemoval(of: reveal, at: Self.instants)
    let oneShot = try RemovalBodyFrames.removal(of: reveal, at: Self.instants)
    for (frame, expected) in zip(frames, oneShot) {
      #expect(frame.lines == expected.lines, "\(frame.milliseconds) ms")
      #expect(frame.row(1, matches: expected), "\(frame.milliseconds) ms")
      #expect(frame.issues.isEmpty)
    }
    #expect(frames.map { $0.lines[1].count } == [20, 15, 10, 5, 0])

    let starred = Text("PRESENT").transition(RemovalStarred())
    let starredFrames = await RemovalBodyFrames.asyncRemoval(of: starred, at: Self.instants)
    for (frame, expected) in zip(
      starredFrames, try RemovalBodyFrames.removal(of: starred, at: Self.instants))
    {
      #expect(frame.lines == expected.lines, "\(frame.milliseconds) ms")
      #expect(frame.row(1, matches: expected), "\(frame.milliseconds) ms")
    }
  }
}

// MARK: - Frames: channels, styles and what a removal cannot honour

extension TransitionBodyRemovalTests {
  @Test("a mixed transition removes with its effect channel and its body channel")
  func mixedTransitionRemovesWithBothChannels() throws {
    let frames = try RemovalBodyFrames.removal(
      of: Text("PRESENT").foregroundStyle(Color.white)
        .transition(RemovalShift().combined(with: .opacity)),
      at: Self.instants)
    for (frame, progress) in zip(frames.dropLast(), Self.progress) {
      let label = "\(frame.milliseconds) ms"
      // The body channel moves the offset the body wraps the content in.
      let column = try #require(frame.offsetColumns.first, "\(label)")
      #expect(
        frame.lines[1] == String(repeating: " ", count: column) + "PRESENT",
        "\(label): \(frame.lines[1])")
      #expect(abs(Double(column) - 8 * progress) <= 1, "\(label): \(column)")
      // The effect channel fades the overlay at its root.
      let root = try #require(frame.overlayRoots.first, "\(label)")
      let opacity = try #require(root.drawMetadata.baseStyle.explicitOpacity, "\(label)")
      #expect(abs(opacity - (1 - progress)) < 1e-9, "\(label): \(opacity)")
    }
    let columns = frames.dropLast().compactMap(\.offsetColumns.first)
    #expect(columns.first == 0 && columns == columns.sorted(), "\(columns)")
    let brightness = frames.dropLast().map {
      $0.foreground(row: 1, column: $0.offsetColumns.first ?? 0)?.red ?? -1
    }
    #expect(brightness == brightness.sorted(by: >) && Set(brightness).count == brightness.count)
    #expect(frames.last?.lines[1] == "")
    #expect(frames.last?.overlayRoots.isEmpty == true)
  }

  @Test("a foreground style the body sets animates on the views of the frozen content")
  func inheritedForegroundStyleAnimatesOnTheContent() throws {
    let content = VStack(alignment: .leading, spacing: 0) {
      Text("AB")
      Text("CD").foregroundStyle(Color.green)
    }
    let frames = try RemovalBodyFrames.removal(
      of: content.transition(RemovalTinted()), at: Self.instants)
    let white = try RemovalBodyFrames.atRest(content.transition(RemovalTintedAt(color: .white)))
    let red = try RemovalBodyFrames.atRest(content.transition(RemovalTintedAt(color: .red)))
    // The first text reads the style from the environment the body wrote. It
    // starts at the colour on screen and moves to the didDisappear colour.
    #expect(try #require(frames.first).row(1, matches: white))
    let reds = frames.dropLast().map { $0.foreground(row: 1, column: 0)?.green ?? -1 }
    #expect(reds == reds.sorted(by: >) && Set(reds).count == reds.count, "\(reds)")
    let late = frames[3]
    #expect(!late.row(1, matches: white) && !late.row(1, matches: red))
    // A view that sets its own style does not inherit the body's: it keeps
    // its colour for the whole removal.
    for frame in frames.dropLast() {
      #expect(frame.row(2, matches: white), "\(frame.milliseconds) ms")
      #expect(frame.issues.isEmpty, "\(frame.milliseconds) ms: \(frame.issues)")
    }
  }

  @Test("a tint the body sets animates on the views of the frozen content")
  func inheritedTintAnimatesOnTheContent() throws {
    let frames = try RemovalBodyFrames.removal(
      of: Text("AB").transition(RemovalTintShift()), at: Self.instants)
    // The tint reaches a view through its environment, which is read when
    // the view is drawn. The frozen text takes the body's tint, from the
    // colour on screen to the didDisappear colour.
    let greens = try frames.dropLast().map { frame -> Double in
      let text = try #require(frame.transientNode(drawing: "AB"), "\(frame.milliseconds) ms")
      guard case .color(let color)? = text.environmentSnapshot.style.tintStyle else {
        Issue.record("no colour tint at \(frame.milliseconds) ms")
        return -1
      }
      #expect(frame.issues.isEmpty, "\(frame.milliseconds) ms: \(frame.issues)")
      return color.green
    }
    #expect(abs((greens.first ?? -1) - Color.white.green) < 1e-6, "\(greens)")
    #expect(greens == greens.sorted(by: >) && Set(greens).count == greens.count, "\(greens)")
  }

  @Test("an environment value the didDisappear phase writes for its content is reported")
  func environmentWrittenForContentIsReported() throws {
    let frames = try RemovalBodyFrames.removal(
      of: Text("PRESENT").transition(RemovalUnderlined()), at: Self.instants)
    // The content was resolved before the removal and is drawn as it was: it
    // does not pick up the underline the didDisappear phase asks for.
    for frame in frames.dropLast() {
      #expect(frame.lines[1] == "PRESENT", "\(frame.milliseconds) ms")
      #expect(
        frame.surface.cells[1].allSatisfy { $0.style?.underlineStyle == nil },
        "\(frame.milliseconds) ms")
    }
    // That would be a silent no-op, so the removal reports it, once, with the
    // transition and the key.
    let issues = frames.flatMap(\.issues).filter {
      $0.code == "transition.removalEnvironmentIgnored"
    }
    #expect(issues.count == 1)
    let issue = try #require(issues.first)
    #expect(issue.severity == .warning)
    #expect(issue.message.contains("RemovalUnderlined"), "\(issue.message)")
    #expect(issue.message.contains("UnderlineStyleKey"), "\(issue.message)")
    #expect(try #require(frames.first).issues.count == 1)
    // The opacity in the same body still animates.
    let opacities = frames.dropLast().compactMap {
      $0.boundaries.first?.drawMetadata.baseStyle.explicitOpacity
    }
    #expect(opacities.count == 4 && opacities == opacities.sorted(by: >), "\(opacities)")
  }

  @Test("modifiers applied outside the transition stay on the departing view")
  func modifiersOutsideTheTransitionAreKept() throws {
    let view = Text(Self.letters).foregroundStyle(Color.white)
      .transition(RemovalDim())
      .clipShape(RemovalRevealShape(fraction: 0.5))
      .blendMode(.multiply)
      .opacity(0.5)
    let atRest = try RemovalBodyFrames.atRest(view)
    #expect(atRest.lines[1] == String(Self.letters.prefix(10)))
    let frames = try RemovalBodyFrames.removal(of: view, at: Self.instants)
    for (frame, progress) in zip(frames.dropLast(), Self.progress) {
      let label = "\(frame.milliseconds) ms"
      // The clip shape and the blend mode were stamped on the root of the
      // body by modifiers outside it. The removal draws the didDisappear
      // body, which has neither, and keeps both.
      #expect(frame.lines[1] == String(Self.letters.prefix(10)), "\(label)")
      let boundary = try #require(frame.boundaries.first, "\(label)")
      #expect(boundary.drawEffects.ordered == [.blendMode(.multiply)], "\(label)")
      // The outer opacity multiplies the body's.
      let opacity = try #require(boundary.drawMetadata.baseStyle.explicitOpacity, "\(label)")
      #expect(abs(opacity - 0.5 * (1 - progress)) < 1e-9, "\(label): \(opacity)")
    }
    #expect(frames.last?.lines[1] == "")
  }

  @Test("a modifier applied outside the transition does not stop the body's insertion")
  func modifiersOutsideTheTransitionOnInsertion() throws {
    // The insertion pairs the willAppear body with the live tree. An outer
    // clip shape is on the live root and not in the body: the body's own clip
    // still animates, inside it, and the outer opacity multiplies the body's.
    let sequence = RemovalBodySequence(
      Text(Self.letters).foregroundStyle(Color.white)
        .transition(RemovalReveal())
        .clipShape(RemovalRevealShape(fraction: 0.9))
        .opacity(0.5),
      visible: false)
    var columns: [Int] = []
    var opacities: [Double] = []
    // 26 frames, 33 ms apart: the last one is past the 800 ms curve.
    for index in 0..<26 {
      let frame = sequence.frame(visible: true, animation: index == 0 ? Self.linear : nil)
      columns.append(frame.lines[1].count)
      opacities.append(
        frame.boundaries.first?.drawMetadata.baseStyle.explicitOpacity ?? -1)
    }
    #expect(columns.first == 0, "\(columns)")
    #expect(columns == columns.sorted(), "\(columns)")
    // Half way the body's clip uncovers ten columns; at the end the outer
    // clip's eighteen are the limit.
    #expect(columns[12] == 10, "\(columns)")
    #expect(columns.last == 18, "\(columns)")
    #expect(abs(opacities[0] - 0.1) < 1e-9, "\(opacities)")
    #expect(abs((opacities.last ?? -1) - 0.5) < 1e-9, "\(opacities)")
  }

  @Test("the departing body and the views it adds have no semantics, focus or hit regions")
  func departingBodyIsNotSemantic() throws {
    let view = Button("inner") {}.transition(RemovalWithButton(log: RemovalProbeLog()))
    let present = try RemovalBodyFrames.atRest(view)
    #expect(present.semantics.focusRegions.count == 2)
    let absent = try RemovalBodyFrames.atRest(view, visible: false)
    let frames = try RemovalBodyFrames.removal(of: view, at: [0, 400])
    for frame in frames {
      let label = "\(frame.milliseconds) ms"
      // The overlay is drawn: both buttons are on the row.
      #expect(frame.lines[1].contains("inner") && frame.lines[1].contains("extra"), "\(label)")
      let overlay = try #require(frame.overlayRoots.first, "\(label)")
      let identities = Self.identities(in: overlay)
      #expect(identities.count > 3, "\(label)")
      // Nothing in it reaches the semantic snapshot: the snapshot is the one
      // of a tree the view was never in.
      #expect(frame.semantics.focusRegions == absent.semantics.focusRegions, "\(label)")
      #expect(
        frame.semantics.interactionRegions == absent.semantics.interactionRegions, "\(label)")
      #expect(
        frame.semantics.accessibilityNodes == absent.semantics.accessibilityNodes, "\(label)")
      #expect(frame.semantics.focusRegions.allSatisfy { !identities.contains($0.identity) })
      #expect(
        frame.semantics.interactionRegions.allSatisfy { !identities.contains($0.identity) })
      // And it is outside layout: the live tree has no node of it.
      #expect(Self.identities(in: frame.resolved).isDisjoint(with: identities), "\(label)")
    }
  }

  private static func identities(in node: PlacedNode) -> Set<Identity> {
    var result: Set<Identity> = [node.identity]
    for child in node.children { result.formUnion(identities(in: child)) }
    return result
  }

  private static func identities(in node: ResolvedNode) -> Set<Identity> {
    var result: Set<Identity> = [node.identity]
    for child in node.children { result.formUnion(identities(in: child)) }
    return result
  }
}

// MARK: - Interruption

extension TransitionBodyRemovalTests {
  /// One 33 ms frame of the 800 ms linear curve.
  private static let linearStep = 33.0 / 800.0
  private static let linear = Animation.linear(duration: .milliseconds(800))
  /// A soft spring: its velocity is still high when the tests interrupt it.
  private static let spring = Animation.spring(duration: .milliseconds(1600), bounce: 0)

  private static func opacity(_ frame: RemovalBodyFrame) throws -> Double {
    let boundaries = frame.boundaries
    try #require(boundaries.count == 1, "\(frame.milliseconds) ms: \(boundaries.count) boundaries")
    return try #require(boundaries[0].drawMetadata.baseStyle.explicitOpacity)
  }

  /// The opacity the body's boundary shows on each frame of an insertion
  /// that a removal interrupts on frame `flip`.
  private static func removalDuringInsertion(
    _ animation: Animation, flip: Int, frames: Int
  ) throws -> [Double] {
    let sequence = RemovalBodySequence(Text("PRESENT").transition(RemovalDim()), visible: false)
    var values: [Double] = []
    for index in 0..<frames {
      let visible = index < flip
      let frame = sequence.frame(
        visible: visible, animation: index == 0 || index == flip ? animation : nil)
      values.append(try opacity(frame))
      // Before the flip the boundary is the live one; from the flip on it is
      // part of the removal overlay.
      #expect(frame.boundaries[0].isTransient == !visible, "frame \(index)")
    }
    return values
  }

  /// The same for a removal that an insertion interrupts on frame `flip`.
  private static func reinsertionDuringRemoval(
    _ animation: Animation, flip: Int, frames: Int
  ) throws -> [Double] {
    let sequence = RemovalBodySequence(Text("PRESENT").transition(RemovalDim()), visible: true)
    var values: [Double] = []
    for index in 0..<frames {
      let visible = index >= flip
      let frame = sequence.frame(
        visible: visible, animation: index == 0 || index == flip ? animation : nil)
      values.append(try opacity(frame))
      #expect(frame.boundaries[0].isTransient == !visible, "frame \(index)")
    }
    return values
  }

  private static func steps(_ values: [Double]) -> [Double] {
    zip(values.dropFirst(), values).map { $0 - $1 }
  }

  @Test("a removal during a linear insertion continues from the value on screen")
  func linearRemovalDuringInsertion() throws {
    let values = try Self.removalDuringInsertion(Self.linear, flip: 13, frames: 26)
    let steps = Self.steps(values)
    // The insertion rises one step a frame. The frame of the removal shows
    // the next sample of the same line: nothing jumps back to the identity
    // value, and nothing restarts from the willAppear value.
    #expect(values[0] == 0)
    for step in steps[0..<13] {
      #expect(abs(step - Self.linearStep) < 1e-9, "\(steps)")
    }
    #expect(abs(values[13] - 13 * Self.linearStep) < 1e-9, "\(values)")
    // From there the value falls toward the didDisappear value, and no frame
    // moves more than one normal step.
    for step in steps[13...] {
      #expect(step < 0 && abs(step) <= Self.linearStep + 1e-9, "\(steps)")
    }
    #expect(steps.allSatisfy { abs($0) <= Self.linearStep + 1e-9 }, "\(steps)")
  }

  @Test("a re-insertion during a linear removal continues from the value on screen")
  func linearReinsertionDuringRemoval() throws {
    let values = try Self.reinsertionDuringRemoval(Self.linear, flip: 13, frames: 26)
    let steps = Self.steps(values)
    #expect(values[0] == 1)
    for step in steps[0..<13] {
      #expect(abs(step + Self.linearStep) < 1e-9, "\(steps)")
    }
    // The frame of the re-insertion shows the removal's next sample, not the
    // willAppear value and not the identity value.
    #expect(abs(values[13] - (1 - 13 * Self.linearStep)) < 1e-9, "\(values)")
    for step in steps[13...] {
      #expect(step > 0 && abs(step) <= Self.linearStep + 1e-9, "\(steps)")
    }
    #expect(steps.allSatisfy { abs($0) <= Self.linearStep + 1e-9 }, "\(steps)")
  }

  @Test("a removal during a spring insertion keeps the spring's velocity")
  func springRemovalDuringInsertion() throws {
    let values = try Self.removalDuringInsertion(Self.spring, flip: 7, frames: 18)
    let steps = Self.steps(values)
    // `steps[6]` is the step into the frame of the removal, which is still a
    // sample of the insertion's curve. `steps[7]` is the first step of the
    // removal's curve. A spring that restarted at rest would stand still or
    // turn back there; this one keeps moving the way it was, at about the
    // speed it had, before the new target pulls it back.
    let before = steps[6]
    let after = steps[7]
    #expect(before > 0.03, "\(steps)")
    #expect(after > 0, "\(steps)")
    #expect(after > 0.6 * before && after < 1.1 * before, "\(before) then \(after)")
    // No step after the interruption is larger than the largest before it.
    let largest = try #require(steps[0..<7].map(abs).max())
    #expect(steps[7...].allSatisfy { abs($0) <= largest + 1e-9 }, "\(steps)")
    // It then turns and heads for the didDisappear value.
    let peak = try #require(values.max())
    #expect(try #require(values.firstIndex(of: peak)) > 7, "\(values)")
    #expect(try #require(values.last) < peak - 0.03, "\(values)")
  }

  @Test("a re-insertion during a spring removal keeps the spring's velocity")
  func springReinsertionDuringRemoval() throws {
    let values = try Self.reinsertionDuringRemoval(Self.spring, flip: 7, frames: 18)
    let steps = Self.steps(values)
    let before = steps[6]
    let after = steps[7]
    #expect(before < -0.03, "\(steps)")
    #expect(after < 0, "\(steps)")
    #expect(abs(after) > 0.6 * abs(before) && abs(after) < 1.1 * abs(before), "\(steps)")
    let largest = try #require(steps[0..<7].map(abs).max())
    #expect(steps[7...].allSatisfy { abs($0) <= largest + 1e-9 }, "\(steps)")
    let trough = try #require(values.min())
    #expect(try #require(values.firstIndex(of: trough)) > 7, "\(values)")
    #expect(try #require(values.last) > trough + 0.03, "\(values)")
  }

  @Test("a removal during an insertion retargets the insertion's animations")
  func runLoopRemovalDuringInsertion() throws {
    let probe = try RemovalProbe(named: "removal-mid-insertion") { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 1 { Text(Self.letters).transition(RemovalReveal()) }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.transactionAnimation, completion: "in")
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      // The clip path and the opacity are half way.
      #expect(probe.activeAnimationCount == 2)
      #expect(probe.line(1) == String(Self.letters.prefix(10)), "\(probe.frame)")
      #expect(probe.log.completions.isEmpty)

      try probe.set(0, animation: Self.transactionAnimation, completion: "out")
      // The removal shows what was on screen. The two animations are still
      // in flight, now toward the didDisappear values, and they belong to
      // the removal: their views are in no live tree.
      #expect(probe.line(1) == String(Self.letters.prefix(10)), "\(probe.frame)")
      #expect(probe.removingCount == 1)
      #expect(probe.activeAnimationCount == 2)
      // Retargeting released the batch the insertion retained.
      #expect(probe.log.completions == ["in"])

      // Ten columns fall to none over the removal's own 800 ms.
      let flip = start.advanced(by: .milliseconds(400))
      try probe.advance(to: flip.advanced(by: .milliseconds(400)))
      #expect(probe.line(1) == String(Self.letters.prefix(5)), "\(probe.frame)")
      try probe.advance(to: flip.advanced(by: .milliseconds(800)))
      #expect(probe.line(1) == "", "\(probe.frame)")
      #expect(probe.activeAnimationCount == 0)
      #expect(probe.log.completions == ["in", "out"])
      try probe.step()
      #expect(probe.removingCount == 0)
    }
  }

  @Test("a re-insertion during a removal takes the removal's animations back")
  func runLoopReinsertionDuringRemoval() throws {
    let probe = try RemovalProbe(named: "reinsertion-mid-removal") { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 { Text(Self.letters).transition(RemovalReveal()) }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.transactionAnimation, completion: "out")
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.line(1) == String(Self.letters.prefix(10)), "\(probe.frame)")
      #expect(probe.removingCount == 1)

      try probe.set(0, animation: Self.transactionAnimation, completion: "in")
      // The overlay is gone and the live view shows what the overlay showed.
      // It does not start again from the willAppear body, which has no
      // columns at all.
      #expect(probe.removingCount == 0)
      #expect(probe.line(1) == String(Self.letters.prefix(10)), "\(probe.frame)")
      #expect(probe.activeAnimationCount == 2)
      #expect(probe.log.completions == ["out"])

      let flip = start.advanced(by: .milliseconds(400))
      try probe.advance(to: flip.advanced(by: .milliseconds(400)))
      #expect(probe.line(1) == String(Self.letters.prefix(15)), "\(probe.frame)")
      try probe.advance(to: flip.advanced(by: .milliseconds(800)))
      #expect(probe.line(1) == Self.letters, "\(probe.frame)")
      #expect(probe.activeAnimationCount == 0)
      #expect(probe.log.completions == ["out", "in"])
    }
  }

  @Test("a re-insertion that does not play ends the removal's animations at the identity body")
  func reinsertionWithoutAnimationSnaps() throws {
    let probe = try RemovalProbe(named: "reinsertion-snap") { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 { Text(Self.letters).transition(RemovalReveal()) }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.transactionAnimation, completion: "out")
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.activeAnimationCount == 2)
      try probe.set(0, animation: nil)
      #expect(probe.removingCount == 0)
      #expect(probe.activeAnimationCount == 0)
      #expect(probe.line(1) == Self.letters, "\(probe.frame)")
      #expect(probe.log.completions == ["out"])
      try probe.settle()
      #expect(probe.line(1) == Self.letters, "\(probe.frame)")
    }
  }
}

// MARK: - Journeys through each container

extension TransitionBodyRemovalTests {
  @Test("an if inside a container removes through the body, on the run loop's frames")
  func ifInAContainer() throws {
    let probe = try RemovalProbe(named: "if") { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 { Text(Self.letters).transition(RemovalReveal()) }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.transactionAnimation)
      for (offset, columns) in zip([0, 200, 400, 600], [20, 15, 10, 5]) {
        if offset > 0 { try probe.advance(to: start.advanced(by: .milliseconds(offset))) }
        #expect(
          probe.line(1) == String(Self.letters.prefix(columns)), "\(offset) ms: \(probe.frame)")
        #expect(probe.removingCount == 1, "\(offset) ms")
        // The clip path and the opacity each run as one property animation.
        #expect(probe.activeAnimationCount == 2, "\(offset) ms")
      }
      // The view's node left the tree: the departed-node channel.
      #expect(!probe.removalNodeIsLive)
      #expect(probe.log.completions.isEmpty)
      try probe.advance(to: start.advanced(by: .milliseconds(800)))
      #expect(probe.line(1) == "", "\(probe.frame)")
      #expect(probe.activeAnimationCount == 0)
      #expect(probe.log.completions == ["done"])
      try probe.step()
      #expect(probe.removingCount == 0)
      #expect(probe.log.issues.isEmpty, "\(probe.log.issues)")
    }
  }

  @Test("layout collapses on the first frame of the removal")
  func layoutCollapsesOnTheFirstRemovalFrame() throws {
    let probe = try RemovalProbe(named: "collapse") { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 { Text(Self.letters).transition(RemovalReveal()) }
        Text("BELOW")
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      #expect(probe.line(2) == "BELOW")
      try probe.set(1, animation: Self.transactionAnimation)
      // The sibling moves up at once, into the row the departing view still
      // paints: the removal takes no part in layout.
      #expect(probe.line(1) == "BELOW" + Self.letters.dropFirst(5), "\(probe.frame)")
      #expect(probe.line(2) == "", "\(probe.frame)")
      #expect(probe.removingCount == 1)
    }
  }

  @Test("an if/else swap removes the departing branch through its body")
  func ifElseSwap() throws {
    let probe = try RemovalProbe(named: "if-else") { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        Group {
          if step == 0 {
            Text(Self.letters).transition(RemovalReveal())
          } else {
            Text("else")
          }
        }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.transactionAnimation)
      // The arriving branch fades in from nothing under the departing one.
      #expect(probe.line(1) == Self.letters, "\(probe.frame)")
      #expect(probe.removingCount == 1)
      #expect(!probe.removalNodeIsLive)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.line(1) == "else" + "EFGHIJ", "\(probe.frame)")
      try probe.advance(to: start.advanced(by: .milliseconds(800)))
      try probe.step()
      #expect(probe.line(1) == "else", "\(probe.frame)")
      #expect(probe.removingCount == 0)
      #expect(probe.log.completions == ["done"])
    }
  }

  @Test(
    "a branch that leaves a slot its node stays in removes through its body",
    arguments: [false, true])
  func adoptedSlotRemoval(hasElse: Bool) throws {
    let dots = String(repeating: ".", count: 20)
    let probe = try RemovalProbe(named: "adopted-\(hasElse)") { step in
      Text(dots).overlay(alignment: .leading) {
        if step == 0 {
          Text(Self.letters).transition(RemovalReveal())
        } else if hasElse {
          Text("else")
        }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.transactionAnimation)
      // The overlay's slot keeps its graph node across the flip, so no node
      // departs: the removal is found through the registered identity that
      // left, the adopted-slot channel.
      #expect(probe.removingCount == 1)
      #expect(probe.removalNodeIsLive)
      #expect(probe.line(0).dropFirst(4) == Self.letters.dropFirst(4), "\(probe.frame)")
      #expect(probe.activeAnimationCount >= 2)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(
        probe.line(0).dropFirst(4) == "EFGHIJ" + String(repeating: ".", count: 10),
        "\(probe.frame)")
      #expect(probe.removalNodeIsLive)
      try probe.advance(to: start.advanced(by: .milliseconds(800)))
      try probe.step()
      #expect(probe.line(0) == (hasElse ? "else" : "....") + dots.dropFirst(4), "\(probe.frame)")
      #expect(probe.removingCount == 0)
      #expect(probe.log.completions == ["done"])
      #expect(probe.log.issues.isEmpty, "\(probe.log.issues)")
    }
  }

  @Test("a ForEach row in a VStack removes through its body")
  func forEachRowRemoval() throws {
    let probe = try RemovalProbe(named: "for-each") { step in
      VStack(alignment: .leading, spacing: 0) {
        ForEach(step == 0 ? [1, 2, 3] : [1, 2], id: \.self) { item in
          Text("\(item)" + Self.letters.dropFirst()).transition(RemovalReveal())
        }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.transactionAnimation)
      #expect(probe.line(2) == "3" + Self.letters.dropFirst(), "\(probe.frame)")
      #expect(probe.removingCount == 1)
      #expect(probe.activeAnimationCount == 2)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.line(2) == "3" + Self.letters.dropFirst().prefix(9), "\(probe.frame)")
      // The rows that stay are untouched.
      #expect(probe.line(0) == "1" + Self.letters.dropFirst(), "\(probe.frame)")
      #expect(probe.line(1) == "2" + Self.letters.dropFirst(), "\(probe.frame)")
      try probe.advance(to: start.advanced(by: .milliseconds(800)))
      try probe.step()
      #expect(probe.line(2) == "", "\(probe.frame)")
      #expect(probe.removingCount == 0)
      #expect(probe.log.completions == ["done"])
    }
  }

  @Test("an id change removes the old view through its body")
  func idChange() throws {
    let probe = try RemovalProbe(named: "id") { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        Text(step == 0 ? Self.letters : "second").transition(RemovalReveal()).id(step)
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.transactionAnimation)
      // The new view is clipped to nothing on its first frame; the old one
      // is still whole.
      #expect(probe.line(1) == Self.letters, "\(probe.frame)")
      #expect(probe.removingCount == 1)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      // Half of "second" has been revealed over half of the old text.
      #expect(probe.line(1) == "sec" + "DEFGHIJ", "\(probe.frame)")
      try probe.advance(to: start.advanced(by: .milliseconds(800)))
      try probe.step()
      #expect(probe.line(1) == "second", "\(probe.frame)")
      #expect(probe.removingCount == 0)
      #expect(probe.log.completions == ["done"])
    }
  }

  @Test(
    "a view whose container leaves with it has no surviving parent to draw in, as before",
    arguments: [true, false])
  func removalNeedsASurvivingParent(custom: Bool) throws {
    let probe = try RemovalProbe(named: "no-parent-\(custom)") { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 {
          VStack(alignment: .leading, spacing: 0) {
            Text("HEAD")
            if custom {
              Text(Self.letters).transition(RemovalReveal())
            } else {
              Text(Self.letters).transition(.opacity)
            }
          }
        }
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      #expect(probe.line(2) == Self.letters)
      try probe.set(1, animation: Self.transactionAnimation)
      // The container left with its children. The walk up from the
      // transition's view stops at it, because it has several children, and
      // it did not survive: no overlay is planned, for a body as for a
      // built-in transition.
      #expect(probe.removingCount == 0)
      #expect(probe.activeAnimationCount == 0)
      #expect(probe.line(1) == "" && probe.line(2) == "", "\(probe.frame)")
      try probe.settle()
      #expect(probe.log.issues.isEmpty, "\(probe.log.issues)")
    }
  }

  @Test("a removal without a body is what it was: one overlay and no property animation")
  func removalsWithoutABodyAreUnchanged() throws {
    for marked in [false, true] {
      let probe = try RemovalProbe(named: "plain-\(marked)") { step in
        VStack(alignment: .leading, spacing: 0) {
          Text("TITLE")
          if step == 0 {
            if marked { Text("PLAIN").transition(.opacity) } else { Text("PLAIN") }
          }
        }
      }
      defer { probe.shutdown() }
      try probe.run { start in
        try probe.set(1, animation: Self.transactionAnimation)
        #expect(probe.removingCount == 1, "marked \(marked)")
        #expect(probe.activeAnimationCount == 0, "marked \(marked)")
        #expect(probe.line(1) == "PLAIN", "marked \(marked): \(probe.frame)")
        try probe.advance(to: start.advanced(by: .milliseconds(400)))
        #expect(probe.line(1) == "PLAIN", "marked \(marked): \(probe.frame)")
        #expect(probe.activeAnimationCount == 0, "marked \(marked)")
        try probe.advance(to: start.advanced(by: .milliseconds(800)))
        #expect(probe.line(1) == "", "marked \(marked): \(probe.frame)")
        #expect(probe.log.completions == ["done"], "marked \(marked)")
        try probe.step()
        #expect(probe.removingCount == 0, "marked \(marked)")
      }
    }
  }
}

// MARK: - Structure, lifecycle of added views, and the environment

extension TransitionBodyRemovalTests {
  @Test("the departing body takes no clicks and holds no focus region")
  func departingBodyIsNotInteractive() throws {
    let log = RemovalProbeLog()
    let probe = try RemovalProbe(named: "inert", log: log) { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 {
          Button("inner") { log.taps += 1 }.transition(RemovalWithButton(log: log))
        }
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      #expect(probe.harness.focusRegionCount == 2)
      #expect(probe.harness.actionRegistrationCount == 2)
      try probe.harness.clickText("extra")
      #expect(log.taps == 1)

      try probe.set(1, animation: Self.transactionAnimation)
      // Both buttons are still drawn, and neither is there to interact
      // with.
      #expect(probe.line(1).contains("inner") && probe.line(1).contains("extra"), "\(probe.frame)")
      #expect(probe.removingCount == 1)
      #expect(probe.harness.focusRegionCount == 0)
      #expect(probe.harness.actionRegistrationCount == 0)
      try probe.harness.clickText("extra")
      try probe.harness.clickText("inner")
      #expect(log.taps == 1)
      #expect(probe.line(1).contains("inner") && probe.line(1).contains("extra"), "\(probe.frame)")
      #expect(probe.removingCount == 1)
    }
  }

  @Test("a view only the identity phase has is gone on the first frame of the removal")
  func identityOnlyViewLeavesAtOnce() throws {
    let probe = try RemovalProbe(named: "identity-only") { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 { Text("PRESENT").transition(RemovalBadgeBefore()) }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      #expect(probe.line(1) == "PRESENTBADGE")
      try probe.set(1, animation: Self.transactionAnimation)
      // The badge exists only in the identity body. The removal draws the
      // didDisappear body, which has no badge.
      #expect(probe.line(1) == "PRESENT", "\(probe.frame)")
      #expect(probe.removingCount == 1)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.line(1) == "PRESENT", "\(probe.frame)")
      try probe.settle()
      #expect(probe.log.issues.isEmpty, "\(probe.log.issues)")
    }
  }

  @Test(
    "a view only the didDisappear phase has is drawn at once, and its handlers are reported",
    arguments: RemovalGhostKind.allCases)
  func didDisappearOnlyView(kind: RemovalGhostKind) throws {
    let log = RemovalProbeLog()
    let probe = try RemovalProbe(named: "ghost-\(kind)", log: log) { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 {
          Text("PRESENT").frame(width: 14, alignment: .leading)
            .transition(RemovalGhost(kind: kind, log: log))
        }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      #expect(probe.line(1) == "PRESENT")
      try probe.set(1, animation: Self.transactionAnimation)
      // The ghost is part of the didDisappear body, so it is drawn from the
      // first frame of the removal to the last.
      #expect(
        probe.line(1).hasPrefix("PRESENT") && probe.line(1).contains("GHOST"), "\(probe.frame)")
      try probe.harness.clickText("GHOST")
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(
        probe.line(1).hasPrefix("PRESENT") && probe.line(1).contains("GHOST"), "\(probe.frame)")
      try probe.settle()
      // Nothing it declares ever ran.
      #expect(log.taps == 0 && log.appears == 0)

      let issues = log.issues.filter { $0.code == "transition.removalHandlersIgnored" }
      if kind == .text {
        // A view with nothing to run is only drawn.
        #expect(log.issues.isEmpty, "\(log.issues)")
      } else {
        #expect(issues.count == 1, "\(log.issues)")
        let issue = try #require(issues.first)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("RemovalGhost"), "\(issue.message)")
        #expect(log.issues.count == 1, "\(log.issues)")
      }
    }
  }

  @Test("content placed twice shows the frozen content twice")
  func contentPlacedTwice() throws {
    let probe = try RemovalProbe(named: "twice") { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 { Text("PRESENT").transition(RemovalDoubled()) }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.transactionAnimation)
      // Each placement has its own boundary, and each animates.
      #expect(probe.animationIdentities(slot: .opacity).count == 2)
      for offset in [0, 400] {
        if offset > 0 { try probe.advance(to: start.advanced(by: .milliseconds(offset))) }
        #expect(probe.line(1) == "PRESENT" && probe.line(2) == "PRESENT", "\(probe.frame)")
      }
      try probe.advance(to: start.advanced(by: .milliseconds(800)))
      #expect(probe.line(1) == "" && probe.line(2) == "", "\(probe.frame)")
    }
  }

  @Test("content placed twice only in the didDisappear phase shows the frozen content twice")
  func contentPlacedTwiceOnlyOnRemoval() throws {
    let probe = try RemovalProbe(named: "echo") { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 { Text("PRESENT").transition(RemovalEcho()) }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      #expect(probe.line(1) == "PRESENT" && probe.line(2) == "")
      try probe.set(1, animation: Self.transactionAnimation)
      // The second placement has no content of its own on screen to take, so
      // it shows the one there is.
      #expect(probe.line(1) == "PRESENT" && probe.line(2) == "PRESENT", "\(probe.frame)")
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.line(1) == "PRESENT" && probe.line(2) == "PRESENT", "\(probe.frame)")
      try probe.settle()
      #expect(probe.log.issues.isEmpty, "\(probe.log.issues)")
    }
  }

  @Test("a body that places content inside a view that resolves during layout snaps, and says so")
  func contentInsideLayoutRealizedStructure() throws {
    let probe = try RemovalProbe(named: "geometry") { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 { Text("PRESENT").transition(RemovalInGeometry()) }
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      #expect(probe.line(1) == "PRESENT")
      try probe.set(1, animation: Self.transactionAnimation)
      // The content is somewhere inside the GeometryReader, which the
      // resolved tree does not show. Drawing the body around the wrong thing
      // would be worse than not drawing it.
      #expect(probe.line(1) == "", "\(probe.frame)")
      #expect(probe.removingCount == 0)
      #expect(probe.activeAnimationCount == 0)
      try probe.settle()
      let issues = probe.log.issues.filter { $0.code == "transition.removalContentNotFound" }
      #expect(issues.count == 1, "\(probe.log.issues)")
      #expect(issues.first?.message.contains("RemovalInGeometry") == true)
      #expect(probe.log.issues.count == 1, "\(probe.log.issues)")
    }
  }

  @Test("a view the body adds that reads its size during layout is drawn in the removal")
  func layoutRealizedViewTheBodyAdds() throws {
    let probe = try RemovalProbe(named: "geometry-overlay") { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 { Text("PRESENT").transition(RemovalMeasured()) }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      #expect(probe.line(1) == "PRESENT  w4")
      try probe.set(1, animation: Self.transactionAnimation)
      #expect(probe.line(1) == "PRESENT  w4", "\(probe.frame)")
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.line(1) == "PRESENT  w4", "\(probe.frame)")
      try probe.settle()
      #expect(probe.log.issues.isEmpty, "\(probe.log.issues)")
    }
  }

  @Test("the departing body reads the environment its host last resolved under")
  func departingBodyReadsTheLastEnvironment() throws {
    let probe = try RemovalProbe(named: "environment") { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 { Text("PRESENT").transition(RemovalLabelled()) }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      #expect(probe.line(1) == "PRESENT label one")
      // The value changes while the view is on screen. The label in the body
      // reads it, so the host resolves again and registers the new
      // environment.
      try #require(probe.log.label).wrappedValue = "two"
      _ = try probe.harness.render()
      #expect(probe.line(1) == "PRESENT label two")

      try probe.set(1, animation: Self.transactionAnimation)
      // The didDisappear body is evaluated under that environment.
      #expect(probe.line(1) == "PRESENT label two", "\(probe.frame)")
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.line(1) == "PRESENT label two", "\(probe.frame)")
    }
  }
}

// MARK: - Curves, completion and what does not play

extension TransitionBodyRemovalTests {
  @Test(
    "logicallyComplete fires when the body's last value settles, removed one turn later",
    arguments: [true, false])
  func completionBarriers(custom: Bool) throws {
    // The same script for a custom body and for the built-in opacity: the
    // two barriers fire on the same frames.
    for criteria in [AnimationCompletionCriteria.logicallyComplete, .removed] {
      let probe = try RemovalProbe(named: "barrier-\(custom)-\(criteria)") { step in
        VStack(alignment: .leading, spacing: 0) {
          Text("TITLE")
          if step == 0 {
            if custom {
              Text(Self.letters).transition(RemovalReveal())
            } else {
              Text(Self.letters).transition(.opacity)
            }
          }
        }
      }
      defer { probe.shutdown() }
      try probe.run { start in
        try probe.set(1, animation: Self.transactionAnimation, criteria: criteria)
        try probe.advance(to: start.advanced(by: .milliseconds(799)))
        #expect(probe.log.completions.isEmpty, "\(criteria)")
        #expect(probe.removingCount == 1, "\(criteria)")
        try probe.advance(to: start.advanced(by: .milliseconds(800)))
        // The curve has ended. The overlay entry is held for one more turn,
        // drawing nothing, so the two barriers are distinct.
        #expect(probe.removingCount == 1, "\(criteria)")
        #expect(probe.line(1) == "", "\(criteria): \(probe.frame)")
        #expect(
          probe.log.completions == (criteria == .logicallyComplete ? ["done"] : []),
          "\(criteria)")
        try probe.step()
        #expect(probe.removingCount == 0, "\(criteria)")
        #expect(probe.log.completions == ["done"], "\(criteria)")
      }
    }
  }

  @Test("a transition's own animation drives the removal of its body")
  func ownAnimationDrivesTheRemoval() throws {
    let probe = try RemovalProbe(named: "own") { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 {
          Text(Self.letters).transition(RemovalReveal().animation(Self.ownAnimation))
        }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.transactionAnimation)
      #expect(probe.activeAnimationBoxes == [Self.ownAnimation.animationBox])
      // 200 ms is half of the transition's own 400 ms.
      try probe.advance(to: start.advanced(by: .milliseconds(200)))
      #expect(probe.line(1) == String(Self.letters.prefix(10)), "\(probe.frame)")
      try probe.advance(to: start.advanced(by: .milliseconds(399)))
      #expect(probe.activeAnimationCount == 2)
      #expect(probe.removingCount == 1)
      #expect(probe.log.completions.isEmpty)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.line(1) == "", "\(probe.frame)")
      #expect(probe.activeAnimationCount == 0)
      // The removal retained the transaction's batch, so its completion
      // fires when the removal ends, not at the transaction's 800 ms.
      #expect(probe.log.completions == ["done"])
      try probe.step()
      #expect(probe.removingCount == 0)
    }
  }

  @Test("an own animation plays the removal when the state change carries no animation")
  func ownAnimationPlaysWithoutAnAnimatedTransaction() throws {
    let probe = try RemovalProbe(named: "own-unanimated") { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 {
          Text(Self.letters).transition(RemovalReveal().animation(Self.ownAnimation))
        }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: nil)
      #expect(probe.line(1) == Self.letters, "\(probe.frame)")
      #expect(probe.removingCount == 1)
      try probe.advance(to: start.advanced(by: .milliseconds(200)))
      #expect(probe.line(1) == String(Self.letters.prefix(10)), "\(probe.frame)")
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.line(1) == "", "\(probe.frame)")
      try probe.step()
      #expect(probe.removingCount == 0)
    }
  }

  @Test("a body with nothing to interpolate is gone at once")
  func bodyWithoutAnInterpolableDifference() throws {
    let probe = try RemovalProbe(named: "nothing") { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 { Text("PRESENT").transition(RemovalBrackets()) }
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      #expect(probe.line(1) == "[PRESENT]")
      try probe.set(1, animation: Self.transactionAnimation)
      // The brackets are text, which is not a slot. Nothing animates, so
      // nothing holds the departing view: neither body is drawn again.
      #expect(probe.line(1) == "", "\(probe.frame)")
      #expect(probe.activeAnimationCount == 0)
      // The removal ended on its first sample, which is the logical end of
      // the transaction's animations.
      #expect(probe.log.completions == ["done"])
      try probe.step()
      #expect(probe.removingCount == 0)
      #expect(probe.line(1) == "", "\(probe.frame)")
      #expect(probe.log.issues.isEmpty, "\(probe.log.issues)")
    }
  }

  @Test("animation(nil) snaps the removal of a body")
  func nilAnimationSnaps() throws {
    let probe = try RemovalProbe(named: "nil-animation") { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 { Text(Self.letters).transition(RemovalReveal().animation(nil)) }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.transactionAnimation)
      #expect(probe.line(1) == "", "\(probe.frame)")
      #expect(probe.removingCount == 0)
      #expect(probe.activeAnimationCount == 0)
      // Nothing retained the batch: the completion drains at the
      // transaction's own 800 ms, as for an identity transition.
      try probe.advance(to: start.advanced(by: .milliseconds(799)))
      #expect(probe.log.completions.isEmpty)
      try probe.advance(to: start.advanced(by: .milliseconds(800)))
      #expect(probe.log.completions == ["done"])
    }
  }

  @Test(
    "without a curve the removal of a body snaps",
    arguments: RemovalSnapCase.allCases)
  func removalWithoutACurveSnaps(snap: RemovalSnapCase) throws {
    let probe = try RemovalProbe(named: "snap-\(snap)", policy: snap.policy) { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 {
          Text(Self.letters).transition(RemovalReveal().animation(Self.ownAnimation))
        }
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      #expect(probe.line(1) == Self.letters)
      switch snap {
      case .disabledTransaction:
        // `withAnimation(nil)` wins over the transition's own animation.
        try probe.set(1, animation: nil, disabling: true)
      case .reduceMotion, .stableOutput:
        try probe.set(1, animation: Self.transactionAnimation)
      }
      #expect(probe.line(1) == "", "\(probe.frame)")
      #expect(probe.activeAnimationCount == 0)
      try probe.step()
      #expect(probe.removingCount == 0)
      #expect(probe.line(1) == "", "\(probe.frame)")
    }
  }

  @Test("without any animation the removal of a body snaps")
  func unanimatedRemovalSnaps() throws {
    let probe = try RemovalProbe(named: "unanimated") { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 { Text(Self.letters).transition(RemovalReveal()) }
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      try probe.set(1, animation: nil)
      #expect(probe.line(1) == "", "\(probe.frame)")
      #expect(probe.removingCount == 0)
      #expect(probe.activeAnimationCount == 0)
    }
  }

  @Test("reduced motion turned on during a removal ends it")
  func reducedMotionMidRemovalEndsIt() throws {
    let probe = try RemovalProbe(named: "reduce-mid") { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 { Text(Self.letters).transition(RemovalReveal()) }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.transactionAnimation)
      try probe.advance(to: start.advanced(by: .milliseconds(200)))
      #expect(probe.line(1) == String(Self.letters.prefix(15)), "\(probe.frame)")
      #expect(probe.removingCount == 1)
      #expect(probe.activeAnimationCount == 2)

      try #require(probe.log.reduceMotion).wrappedValue = true
      _ = try probe.harness.render()
      // The removal ends, and the animations it owned end with it: they are
      // not left running for views that are in no tree.
      #expect(probe.removingCount == 0)
      #expect(probe.activeAnimationCount == 0)
      #expect(probe.line(1) == "", "\(probe.frame)")
      #expect(probe.log.completions == ["done"])
      try probe.settle()
      #expect(probe.activeAnimationCount == 0)
      #expect(probe.log.completions == ["done"])
    }
  }
}

// MARK: - Matched geometry

extension TransitionBodyRemovalTests {
  /// The columns of the mark the body adds and of the matched text of the
  /// departing view, on each sampled frame of a matched swap.
  private static func matchedTravel(outside: Bool) throws -> [(mark: Int, hero: Int)] {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let animation = Animation.linear(duration: .seconds(1))
    let root = testIdentity("transition-body-removal", "matched", "\(outside)")
    let proposal = ProposedSize(width: .finite(30), height: .finite(3))
    let start = RemovalBodyFrames.start
    var animated = TransactionSnapshot()
    animated.animationRequest = .animate(animation.animationBox)
    return try withAnimationSinks(controller) {
      controller.register(animation)
      _ = renderer.renderArtifacts(
        RemovalMatchedHost(right: false, outside: outside),
        context: .init(identity: root), proposal: proposal, frameInstant: start)
      return try [0, 250, 500, 750].map { offset in
        let frame = RemovalBodyFrame(
          milliseconds: offset,
          artifacts: renderer.renderArtifacts(
            RemovalMatchedHost(right: true, outside: outside),
            context: .init(identity: root, transaction: offset == 0 ? animated : .init()),
            proposal: proposal, frameInstant: start.advanced(by: .milliseconds(offset))))
        let mark = try #require(frame.transientText(">"), "\(offset) ms")
        let hero = try #require(frame.transientText("ONE"), "\(offset) ms")
        return (mark.origin.x, hero.origin.x)
      }
    }
  }

  @Test("a match on the content travels inside the body, whose own views stay where they were")
  func matchedContentTravelsInsideTheBody() throws {
    let travel = try Self.matchedTravel(outside: false)
    // The body's mark stays at the departing view's frozen rect for the
    // whole removal.
    #expect(travel.map(\.mark) == [0, 0, 0, 0], "\(travel)")
    // The matched text leaves it, on the way to its counterpart at column
    // 10.
    #expect(travel.first?.hero == 1, "\(travel)")
    let hero = travel.map(\.hero)
    #expect(hero == hero.sorted() && Set(hero).count == hero.count, "\(travel)")
    #expect(try #require(hero.last) > 6, "\(travel)")
  }

  @Test("a match applied outside the transition moves the whole departing body")
  func matchOutsideTheTransitionMovesTheBody() throws {
    let travel = try Self.matchedTravel(outside: true)
    // The match is on the body's root, so the mark travels with the text.
    let mark = travel.map(\.mark)
    #expect(mark.first == 0, "\(travel)")
    #expect(mark == mark.sorted() && Set(mark).count == mark.count, "\(travel)")
    #expect(travel.allSatisfy { $0.hero == $0.mark + 1 }, "\(travel)")
  }
}

// MARK: - Composition: wrappers, several roots, nested and asymmetric bodies

extension TransitionBodyRemovalTests {
  @Test("a layout wrapper outside the transition stays frozen around the body")
  func wrapperOutsideTheTransition() throws {
    let frames = try RemovalBodyFrames.removal(
      of: Text(Self.letters).transition(RemovalReveal()).padding(.leading, 2),
      at: Self.instants)
    for (frame, columns) in zip(frames, [20, 15, 10, 5, 0]) {
      // The padding left the tree with the view. It is part of the frozen
      // snapshot, and the body plays inside it.
      let expected = columns == 0 ? "" : "  " + Self.letters.prefix(columns)
      #expect(frame.lines[1] == expected, "\(frame.milliseconds) ms: \(frame.lines[1])")
    }
    let root = try #require(frames.first?.overlayRoots.first)
    #expect(root.kind != .view(.transitionContent))
    #expect(try #require(frames.first).boundaries.count == 1)
  }

  @Test("a body with several roots removes each root through its own phase")
  func multiRootBody() throws {
    let probe = try RemovalProbe(named: "multi-root") { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 { Text("PRESENT").transition(RemovalWithTail()) }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      #expect(probe.line(1) == "PRESENT" && probe.line(2) == "TAIL")
      try probe.set(1, animation: Self.transactionAnimation)
      // Each root left on its own, so each has its own removal, and each
      // offset animates.
      #expect(probe.removingCount == 2)
      #expect(probe.animationIdentities(slot: .offset).count == 2)
      #expect(probe.line(1) == "PRESENT" && probe.line(2) == "TAIL", "\(probe.frame)")
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(abs((probe.indent(1) ?? -8) - 4) <= 1, "\(probe.frame)")
      #expect(abs((probe.indent(2) ?? -8) - 4) <= 1, "\(probe.frame)")
      try probe.advance(to: start.advanced(by: .milliseconds(800)))
      try probe.step()
      #expect(probe.line(1) == "" && probe.line(2) == "", "\(probe.frame)")
      #expect(probe.removingCount == 0)
      #expect(probe.log.completions == ["done"])
      #expect(probe.log.issues.isEmpty, "\(probe.log.issues)")
    }
  }

  @Test("combined bodies both play on removal")
  func combinedBodies() throws {
    let frames = try RemovalBodyFrames.removal(
      of: Text("PRESENT").foregroundStyle(Color.white)
        .transition(RemovalShift().combined(with: RemovalDim())),
      at: Self.instants)
    for (frame, progress) in zip(frames.dropLast(), Self.progress) {
      let label = "\(frame.milliseconds) ms"
      let column = try #require(frame.offsetColumns.first, "\(label)")
      #expect(abs(Double(column) - 8 * progress) <= 1, "\(label): \(column)")
      // The outer body's opacity is on its boundary, around the inner body's
      // offset.
      let opacities = frame.boundaries.compactMap(\.drawMetadata.baseStyle.explicitOpacity)
      #expect(opacities.count == 1, "\(label)")
      #expect(abs((opacities.first ?? -1) - (1 - progress)) < 1e-9, "\(label): \(opacities)")
      #expect(frame.boundaries.count == 2, "\(label)")
    }
    #expect(frames.last?.boundaries.isEmpty == true)
  }

  @Test("an asymmetric transition removes through its removal side only")
  func asymmetricRemoval() throws {
    let frames = try RemovalBodyFrames.removal(
      of: Text("PRESENT").foregroundStyle(Color.white).transition(
        AsymmetricTransition(insertion: RemovalShift(), removal: RemovalDim())),
      at: Self.instants)
    for (frame, progress) in zip(frames.dropLast(), Self.progress) {
      let label = "\(frame.milliseconds) ms"
      // The insertion side shows its identity phase: the text does not move.
      #expect(frame.offsetColumns == [0], "\(label)")
      #expect(frame.lines[1] == "PRESENT" || progress > 0.9, "\(label): \(frame.lines[1])")
      let opacities = frame.boundaries.compactMap(\.drawMetadata.baseStyle.explicitOpacity)
      #expect(abs((opacities.first ?? -1) - (1 - progress)) < 1e-9, "\(label): \(opacities)")
    }
  }

  @Test("an insertion value the removal does not change is left to finish in the removal")
  func insertionValueContinuesInTheRemoval() throws {
    // The insertion side moves the offset from eight columns to none. The
    // removal side fades and leaves the offset alone, so the offset animation
    // the insertion started keeps its target and its curve. It goes on in the
    // removal's overlay, where it now belongs.
    let sequence = RemovalBodySequence(
      Text("PRESENT").transition(
        AsymmetricTransition(insertion: RemovalShift(), removal: RemovalDim())),
      visible: false)
    var columns: [Int] = []
    var opacities: [Double] = []
    for index in 0..<30 {
      let visible = index < 8
      let frame = sequence.frame(
        visible: visible, animation: index == 0 || index == 8 ? Self.linear : nil)
      columns.append(try #require(frame.offsetColumns.first, "frame \(index)"))
      let column = try #require(columns.last)
      #expect(
        frame.lines[1] == String(repeating: " ", count: column) + "PRESENT",
        "frame \(index): \(frame.lines[1])")
      opacities.append(
        frame.boundaries.compactMap(\.drawMetadata.baseStyle.explicitOpacity).first ?? -1)
    }
    // The offset never jumps: not to the identity value when the removal
    // starts, and not back toward the willAppear value.
    #expect(columns.first == 8, "\(columns)")
    #expect(columns == columns.sorted(by: >), "\(columns)")
    #expect(zip(columns.dropFirst(), columns).allSatisfy { $1 - $0 <= 1 }, "\(columns)")
    #expect(columns[8] >= 5, "\(columns)")
    // It reaches zero on the insertion's own schedule, 800 ms after the
    // insertion began, while the removal is still fading.
    #expect(columns[23] > 0 && columns[25] == 0, "\(columns)")
    #expect(opacities[25] > 0.2 && opacities[25] < 0.5, "\(opacities)")
    #expect(opacities[8...].elementsEqual(opacities[8...].sorted(by: >)), "\(opacities)")
  }

  @Test("an animation of the body that repeats forever does not hold the removal")
  func repeatingAnimationDoesNotHoldTheRemoval() throws {
    // The insertion side's offset repeats forever. The removal side fades
    // and leaves the offset alone, so that animation plays on in the overlay.
    // The removal lasts as long as the fade it started, and takes the
    // repeating animation with it.
    let forever = Animation.linear(duration: .milliseconds(200)).repeatForever(autoreverses: true)
    let sequence = RemovalBodySequence(
      Text("PRESENT").transition(
        AsymmetricTransition(insertion: RemovalShift(), removal: RemovalDim())),
      visible: false)
    _ = sequence.frame(visible: true, animation: forever)
    for _ in 0..<5 { _ = sequence.frame(visible: true) }
    var columns: Set<Int> = []
    var lastWithOverlay = -1
    for index in 0..<30 {
      let frame = sequence.frame(visible: false, animation: index == 0 ? Self.linear : nil)
      if let column = frame.offsetColumns.first {
        columns.insert(column)
        lastWithOverlay = index
      }
    }
    // The offset kept moving while the view left.
    #expect(columns.count > 3, "\(columns)")
    // The fade ends 800 ms after the removal began: the frame at 792 ms is
    // the last that draws, and nothing is left running after it.
    #expect(lastWithOverlay == 24, "\(lastWithOverlay)")
    #expect(sequence.controller.debugStateSnapshot().removingNodeIDs.isEmpty)
    #expect(sequence.controller.activeAnimationCount == 0)
  }

  @Test("the content's own animations end when the removal starts, as before")
  func contentAnimationsAreSuperseded() throws {
    let probe = try RemovalProbe(named: "content-animation") { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step < 2 {
          Text("AB").opacity(step == 1 ? 0.4 : 1).transition(RemovalTinted())
        }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      // An opacity of the content itself is animating when the view leaves.
      try probe.set(1, animation: Self.transactionAnimation, completion: "dim")
      try probe.advance(to: start.advanced(by: .milliseconds(200)))
      #expect(probe.animationIdentities(slot: .opacity).count == 1)
      try probe.set(2, animation: Self.transactionAnimation, completion: "out")
      // The content is frozen, so that animation ends, and its completion
      // fires. The foreground style the body hands to the same view is the
      // body's, and it animates: on the text, and on the boundary, which
      // reads the same environment value.
      #expect(probe.animationIdentities(slot: .opacity).isEmpty)
      #expect(probe.animationIdentities(slot: .foregroundShapeStyle).count == 2)
      #expect(probe.removingCount == 1)
      #expect(probe.log.completions == ["dim"])
      #expect(probe.line(1) == "AB", "\(probe.frame)")
      let flip = start.advanced(by: .milliseconds(200))
      try probe.advance(to: flip.advanced(by: .milliseconds(800)))
      #expect(probe.line(1) == "", "\(probe.frame)")
      #expect(probe.activeAnimationCount == 0)
      #expect(probe.log.completions == ["dim", "out"])
    }
  }

  @Test("a mixed removal during its insertion is continuous in both channels")
  func mixedRemovalDuringInsertion() throws {
    let sequence = RemovalBodySequence(
      Text("PRESENT").transition(RemovalShift().combined(with: .opacity)), visible: false)
    var columns: [Int] = []
    var opacities: [Double] = []
    for index in 0..<26 {
      let visible = index < 13
      let frame = sequence.frame(
        visible: visible, animation: index == 0 || index == 13 ? Self.linear : nil)
      columns.append(try #require(frame.offsetColumns.first, "frame \(index)"))
      // The effect channel's opacity is on the view while it is live, and at
      // the root of the overlay once it is leaving.
      let node = try #require(
        visible ? Self.liveOffsetNode(in: frame.placed) : frame.overlayRoots.first,
        "frame \(index)")
      opacities.append(try #require(node.drawMetadata.baseStyle.explicitOpacity))
    }
    // The body channel: the offset falls toward zero, then rises again from
    // where it was, a cell at a time.
    #expect(columns.first == 8, "\(columns)")
    #expect(zip(columns.dropFirst(), columns).allSatisfy { abs($0 - $1) <= 1 }, "\(columns)")
    #expect(columns[13] <= columns[12] && columns[25] > columns[13], "\(columns)")
    // The effect channel: the opacity rises, then falls from where it was.
    let steps = Self.steps(opacities)
    #expect(steps.allSatisfy { abs($0) <= Self.linearStep + 1e-9 }, "\(opacities)")
    #expect(steps[0..<12].allSatisfy { $0 > 0 } && steps[13...].allSatisfy { $0 < 0 })
  }

  private static func liveOffsetNode(in node: PlacedNode) -> PlacedNode? {
    if case .offset = node.layoutBehavior, !node.isTransient { return node }
    for child in node.children {
      if let found = liveOffsetNode(in: child) { return found }
    }
    return nil
  }

  @Test("a mixed transition whose body cannot be drawn plays its effects and says so")
  func mixedTransitionWithoutADrawableBody() throws {
    let probe = try RemovalProbe(named: "mixed-geometry") { step in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 {
          Text("PRESENT").transition(RemovalInGeometry().combined(with: .opacity))
        }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.transactionAnimation)
      // The effect channel fades the frozen view, as it did before bodies
      // played on removal. No animation of the body runs.
      #expect(probe.removingCount == 1)
      #expect(probe.activeAnimationCount == 0)
      #expect(probe.line(1) == "PRESENT", "\(probe.frame)")
      try probe.advance(to: start.advanced(by: .milliseconds(800)))
      try probe.step()
      #expect(probe.removingCount == 0)
      #expect(probe.line(1) == "", "\(probe.frame)")
      let issues = probe.log.issues.filter { $0.code == "transition.removalContentNotFound" }
      #expect(issues.count == 1, "\(probe.log.issues)")
    }
  }

  @Test("each curve of a body removal is evaluated once a frame")
  func eachCurveIsEvaluatedOnceAFrame() throws {
    // A stateful custom curve keeps a count of its evaluations in its own
    // state. One evaluation a frame keeps that count equal to the frame
    // number, and the total equal to the number of frames.
    let recorder = StateRecorder()
    let curve = Animation(RecordingCustomAnimation(id: "body-removal-once", recorder: recorder))
    let sequence = RemovalBodySequence(Text("PRESENT").transition(RemovalDim()), visible: true)
    for index in 0..<8 {
      let frame = sequence.frame(visible: false, animation: index == 0 ? curve : nil)
      #expect(frame.boundaries.count == 1, "frame \(index)")
      #expect(recorder.callCount == index + 1, "frame \(index)")
      #expect(recorder.lastObserved == index, "frame \(index)")
    }
  }
}

// MARK: - Transitions

/// A rectangle covering `fraction` of the width. Every fraction has the same
/// element topology, so two of them interpolate.
private struct RemovalRevealShape: Shape {
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

/// An interpolable body: a clip path that covers the whole view at identity
/// and nothing outside it, and an opacity.
private struct RemovalReveal: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .clipShape(RemovalRevealShape(fraction: phase.isIdentity ? 1 : 0))
      .opacity(phase.isIdentity ? 1 : 0.2)
  }
}

/// The body of `RemovalReveal` held at one progress in every phase.
private struct RemovalRevealAt: Transition {
  var progress: Double

  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .clipShape(RemovalRevealShape(fraction: progress))
      .opacity(0.2 + 0.8 * progress)
  }
}

/// A value that cannot interpolate, a blend mode, beside one that can, an
/// offset.
private struct RemovalBlendShift: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .blendMode(phase.isIdentity ? .normal : .multiply)
      .offset(x: phase.isIdentity ? 0 : 8, y: 0)
  }
}

/// Adds an overlay in every phase.
private struct RemovalStarred: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .opacity(phase.isIdentity ? 1 : 0)
      .padding(.trailing, 2)
      .overlay(alignment: .trailing) { Text("*") }
  }
}

/// An opacity from one to zero.
private struct RemovalDim: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.opacity(phase.isIdentity ? 1 : 0)
  }
}

/// Wraps the content in an offset that ends eight columns to the right.
private struct RemovalShift: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.offset(x: phase.isIdentity ? 0 : 8, y: 0)
  }
}

/// Sets the foreground style of the content through the environment.
private struct RemovalTinted: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.foregroundStyle(phase.isIdentity ? Color.white : Color.red)
  }
}

/// Sets the tint of the content through the environment.
private struct RemovalTintShift: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.tint(phase.isIdentity ? Color.white : Color.red)
  }
}

private struct RemovalTintedAt: Transition {
  var color: Color

  func body(content: Content, phase: TransitionPhase) -> some View {
    content.foregroundStyle(color)
  }
}

/// Writes an environment value for the content outside the identity phase,
/// beside an opacity.
private struct RemovalUnderlined: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .underline(!phase.isIdentity)
      .opacity(phase.isIdentity ? 1 : 0.5)
  }
}

/// Adds a button in every phase.
private struct RemovalWithButton: Transition {
  let log: RemovalProbeLog

  func body(content: Content, phase: TransitionPhase) -> some View {
    HStack(spacing: 1) {
      content.opacity(phase.isIdentity ? 1 : 0.5)
      Button("extra") { log.taps += 1 }
    }
  }
}

/// A view only the identity phase has.
private struct RemovalBadgeBefore: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    HStack(spacing: 0) {
      content.opacity(phase.isIdentity ? 1 : 0.5)
      if phase.isIdentity { Text("BADGE") }
    }
  }
}

enum RemovalGhostKind: String, CaseIterable, Sendable {
  case button, tapGesture, onAppear, task, text
}

/// A view only the didDisappear phase has, over the trailing edge of the
/// content.
private struct RemovalGhost: Transition {
  var kind: RemovalGhostKind
  let log: RemovalProbeLog

  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .opacity(phase.isIdentity ? 1 : 0.5)
      .overlay(alignment: .trailing) {
        if phase == .didDisappear {
          switch kind {
          case .button:
            Button("GHOST") { log.taps += 1 }
          case .tapGesture:
            Text("GHOST").onTapGesture { log.taps += 1 }
          case .onAppear:
            Text("GHOST").onAppear { log.appears += 1 }
          case .task:
            Text("GHOST").task { log.appears += 1 }
          case .text:
            Text("GHOST")
          }
        }
      }
  }
}

/// Places its content twice.
private struct RemovalDoubled: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      content.opacity(phase.isIdentity ? 1 : 0.5)
      content.opacity(phase.isIdentity ? 1 : 0.5)
    }
  }
}

/// Places its content a second time outside the identity phase.
private struct RemovalEcho: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      content
      if !phase.isIdentity { content }
    }
    .opacity(phase.isIdentity ? 1 : 0.5)
  }
}

/// Places its content inside a view that resolves during layout.
private struct RemovalInGeometry: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    GeometryReader { _ in content }
      .frame(width: 20, height: 1)
      .opacity(phase.isIdentity ? 1 : 0)
  }
}

/// Adds a view that reads its size during layout, beside the content.
private struct RemovalMeasured: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .padding(.trailing, 6)
      .overlay(alignment: .trailing) {
        GeometryReader { proxy in Text("w\(proxy.size.width)") }.frame(width: 4, height: 1)
      }
      .opacity(phase.isIdentity ? 1 : 0.5)
  }
}

private struct RemovalLabel: View {
  @Environment(\.removalProbeLabel) private var label

  var body: some View { Text("label \(label)") }
}

/// Adds a view that reads the environment, in every phase.
private struct RemovalLabelled: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    HStack(spacing: 1) {
      content.opacity(phase.isIdentity ? 1 : 0.5)
      RemovalLabel()
    }
  }
}

/// Text that differs between phases and nothing that can interpolate.
private struct RemovalBrackets: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    HStack(spacing: 0) {
      Text(phase.isIdentity ? "[" : "<")
      content
      Text(phase.isIdentity ? "]" : ">")
    }
  }
}

/// A mark the body puts before the content, and an opacity.
private struct RemovalMarked: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    HStack(spacing: 0) {
      Text(">")
      content
    }
    .opacity(phase.isIdentity ? 1 : 0.5)
  }
}

/// A matched pair across an if/else. The departing side carries the body
/// transition, with the match inside its content or outside the transition.
private struct RemovalMatchedHost: View {
  let right: Bool
  let outside: Bool

  var body: some View {
    HStack(spacing: 0) {
      if right {
        Text("").frame(width: 10)
        Text("TWO").frame(width: 4, alignment: .leading).matchedGeometryEffect(id: "hero")
      } else {
        if outside {
          Text("ONE").frame(width: 4, alignment: .leading)
            .transition(RemovalMarked())
            .matchedGeometryEffect(id: "hero")
        } else {
          Text("ONE").frame(width: 4, alignment: .leading)
            .matchedGeometryEffect(id: "hero")
            .transition(RemovalMarked())
        }
        Text("").frame(width: 10)
      }
    }
  }
}

enum RemovalSnapCase: String, CaseIterable, Sendable {
  case disabledTransaction, reduceMotion, stableOutput

  var policy: RemovalProbePolicy {
    switch self {
    case .disabledTransaction: .normal
    case .reduceMotion: .reduceMotion
    case .stableOutput: .stableOutput
    }
  }
}

enum RemovalProbePolicy: Sendable {
  case normal, reduceMotion, stableOutput
}

/// Returns two root views, each in an offset.
private struct RemovalWithTail: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.offset(x: phase.isIdentity ? 0 : 8, y: 0)
    Text("TAIL").offset(x: phase.isIdentity ? 0 : 8, y: 0)
  }
}

// MARK: - Frames from one renderer

private struct RemovalBodyPresenceHost<Content: View>: View {
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
private struct RemovalBodyFrame {
  var milliseconds: Int
  var surface: RasterSurface
  var resolved: ResolvedNode
  /// The placed tree the frame drew, removal overlays included.
  var placed: PlacedNode
  var semantics: SemanticSnapshot
  var issues: [RuntimeIssue]

  var lines: [String] { surface.lines }

  /// The boundary nodes of the tree the frame drew, in tree order.
  var boundaries: [PlacedNode] {
    func collect(_ node: PlacedNode) -> [PlacedNode] {
      (node.kind == .view(.transitionContent) ? [node] : []) + node.children.flatMap(collect)
    }
    return collect(placed)
  }

  /// The horizontal offset of each offset node of the tree the frame drew.
  /// An integer offset interpolates by truncating its scaled distance, so a
  /// sample a rounding error short of a whole cell is one cell behind.
  var offsetColumns: [Int] {
    func collect(_ node: PlacedNode) -> [Int] {
      var columns: [Int] = []
      if case .offset(let x, _) = node.layoutBehavior { columns.append(x) }
      return columns + node.children.flatMap(collect)
    }
    return collect(placed)
  }

  /// The roots of the removal overlays the frame drew, in tree order.
  var overlayRoots: [PlacedNode] {
    func collect(_ node: PlacedNode) -> [PlacedNode] {
      node.isTransient ? [node] : node.children.flatMap(collect)
    }
    return collect(placed)
  }

  /// The first node of a removal overlay that draws `text`.
  func transientNode(drawing text: String) -> PlacedNode? {
    func find(_ node: PlacedNode) -> PlacedNode? {
      if node.isTransient, node.drawPayload == .text(text) { return node }
      for child in node.children {
        if let found = find(child) { return found }
      }
      return nil
    }
    return find(placed)
  }

  /// The bounds of the first node of a removal overlay that draws `text`.
  func transientText(_ text: String) -> CellRect? {
    transientNode(drawing: text)?.bounds
  }

  func foreground(row: Int, column: Int) -> Color? {
    surface.cells[row][column].style?.foregroundColor
  }

  /// Whether `row` has the same characters and foreground colours as the
  /// same row of `other`. Colours compare within a rounding tolerance.
  func row(_ row: Int, matches other: RemovalBodyFrame) -> Bool {
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

  init(milliseconds: Int, artifacts: FrameArtifacts) {
    self.milliseconds = milliseconds
    surface = artifacts.rasterSurface
    resolved = artifacts.resolvedTree
    placed = artifacts.placedTree
    semantics = artifacts.semanticSnapshot
    issues = artifacts.diagnostics.runtime.issues
  }
}

@MainActor
private enum RemovalBodyFrames {
  static let transactionAnimation = Animation.linear(duration: .milliseconds(800))
  static let proposal = ProposedSize(width: .finite(24), height: .finite(4))
  static let root = testIdentity("transition-body-removal", "frames")
  static let start = MonotonicInstant(offset: .seconds(100))

  private static var animated: TransactionSnapshot {
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(transactionAnimation.animationBox)
    return transaction
  }

  /// Shows `view`, removes it under an 800 ms linear transaction, and samples
  /// the frame at each offset. Offset 0 is the frame of the removal itself.
  static func removal<V: View>(of view: V, at offsets: [Int]) throws -> [RemovalBodyFrame] {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    return withAnimationSinks(controller) {
      controller.register(transactionAnimation)
      _ = renderer.renderArtifacts(
        RemovalBodyPresenceHost(visible: true) { view },
        context: .init(identity: root), proposal: proposal,
        frameInstant: start.advanced(by: .seconds(-1)))
      return offsets.map { offset in
        RemovalBodyFrame(
          milliseconds: offset,
          artifacts: renderer.renderArtifacts(
            RemovalBodyPresenceHost(visible: false) { view },
            context: .init(identity: root, transaction: offset == 0 ? animated : .init()),
            proposal: proposal, frameInstant: start.advanced(by: .milliseconds(offset))))
      }
    }
  }

  /// `removal(of:at:)` through the async renderer.
  static func asyncRemoval<V: View>(of view: V, at offsets: [Int]) async -> [RemovalBodyFrame] {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    return await withAnimationSinks(controller) {
      controller.register(transactionAnimation)
      _ = await renderer.renderArtifactsAsync(
        RemovalBodyPresenceHost(visible: true) { view },
        context: .init(identity: root), proposal: proposal,
        frameInstant: start.advanced(by: .seconds(-1)))
      var frames: [RemovalBodyFrame] = []
      for offset in offsets {
        frames.append(
          RemovalBodyFrame(
            milliseconds: offset,
            artifacts: await renderer.renderArtifactsAsync(
              RemovalBodyPresenceHost(visible: false) { view },
              context: .init(identity: root, transaction: offset == 0 ? animated : .init()),
              proposal: proposal, frameInstant: start.advanced(by: .milliseconds(offset)))))
      }
      return frames
    }
  }

  /// Renders `view` from the first frame, present or absent, with no
  /// animation.
  static func atRest<V: View>(_ view: V, visible: Bool = true) throws -> RemovalBodyFrame {
    RemovalBodyFrame(
      milliseconds: 0,
      artifacts: DefaultRenderer().renderArtifacts(
        RemovalBodyPresenceHost(visible: visible) { view },
        context: .init(identity: root), proposal: proposal))
  }
}

// MARK: - Run-loop probe

@MainActor
private final class RemovalProbeClock { var now = MonotonicInstant.now() }

@MainActor
private final class RemovalProbeLog {
  var step: Binding<Int>?
  var reduceMotion: Binding<Bool>?
  var label: Binding<String>?
  /// The names of the completions that fired, in order.
  var completions: [String] = []
  var issues: [RuntimeIssue] = []
  var appears = 0
  var disappears = 0
  var taps = 0
}

private enum RemovalProbeLabelKey: EnvironmentKey { static let defaultValue = "none" }
extension EnvironmentValues {
  fileprivate var removalProbeLabel: String {
    get { self[RemovalProbeLabelKey.self] }
    set { self[RemovalProbeLabelKey.self] = newValue }
  }
}

/// A run-loop harness around a view that is a function of one integer of
/// state, driven on an injected frame clock.
@MainActor
private final class RemovalProbe<Content: View> {
  let harness: StressRuntimeHarness<RemovalProbeRoot<Content>>
  let clock: RemovalProbeClock
  let log: RemovalProbeLog

  init(
    named name: String,
    policy: RemovalProbePolicy = .normal,
    log: RemovalProbeLog = RemovalProbeLog(),
    @ViewBuilder content: @escaping (Int) -> Content
  ) throws {
    self.log = log
    harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("transition-body-removal", name),
      size: .init(width: 30, height: 6)
    ) {
      RemovalProbeRoot(policy: policy, log: log, content: content)
    }
    harness.runLoop.runtimeIssueSink = RuntimeIssueSink { issue in
      log.issues.append(issue)
    }
    // The clock starts after the mount frame: a frame never runs earlier
    // than the frame before it.
    let clock = RemovalProbeClock()
    self.clock = clock
    harness.runLoop.frameClock = { clock.now }
  }

  var controller: AnimationController {
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

  var activeAnimationCount: Int { controller.activeAnimationCount }

  var removingCount: Int { controller.debugStateSnapshot().removingNodeIDs.count }

  var activeAnimationBoxes: Set<AnimationBox> {
    Set(controller.debugStateSnapshot().activeAnimationBoxesByKey.values)
  }

  func animationIdentities(slot: AnimatableSlot) -> Set<Identity> {
    Set(
      controller.debugStateSnapshot().activeAnimationKeys
        .filter { $0.scope == .property(slot) }.map(\.identity))
  }

  /// Whether a removal in flight is keyed on a node that is still in the
  /// live tree: the adopted-slot channel, where the incoming branch took the
  /// departing view's graph node.
  var removalNodeIsLive: Bool {
    let state = controller.debugStateSnapshot()
    func nodeIDs(_ node: ResolvedNode) -> Set<ViewNodeID> {
      var ids = Set(node.viewNodeID.map { [$0] } ?? [])
      for child in node.children { ids.formUnion(nodeIDs(child)) }
      return ids
    }
    let live = state.previousTreeRoot.map(nodeIDs) ?? []
    return !state.removingNodeIDs.isEmpty && state.removingNodeIDs.isSubset(of: live)
  }

  func shutdown() { harness.shutdown() }

  /// Runs `body` with the animation sinks bound, passing the start instant.
  func run(_ body: (MonotonicInstant) throws -> Void) throws {
    try withAnimationSinks(controller) { try body(clock.now) }
  }

  /// Writes the step and renders the frame of the change. `animation: nil`
  /// is a plain state write, or `withAnimation(nil)` when `disabling`.
  func set(
    _ step: Int,
    animation: Animation?,
    criteria: AnimationCompletionCriteria = .logicallyComplete,
    completion name: String = "done",
    disabling: Bool = false
  ) throws {
    let binding = try #require(log.step)
    let log = log
    if let animation {
      withAnimation(animation, completionCriteria: criteria) {
        binding.wrappedValue = step
      } completion: {
        log.completions.append(name)
      }
    } else if disabling {
      withAnimation(nil) { binding.wrappedValue = step }
    } else {
      binding.wrappedValue = step
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

  /// Renders the next armed turn, if there is one.
  func step() throws {
    guard let wake = harness.runLoop.scheduler.nextWakeInstant(after: clock.now) else { return }
    clock.now = wake
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

private struct RemovalProbeRoot<Content: View>: View {
  @State private var step = 0
  @State private var reduceMotion = false
  @State private var label = "one"
  let policy: RemovalProbePolicy
  let log: RemovalProbeLog
  let content: (Int) -> Content

  var body: some View {
    let _ = capture()
    content(step)
      .environment(\.accessibilityReduceMotion, reduceMotion || policy == .reduceMotion)
      .environment(\.stableOutput, policy == .stableOutput)
      .environment(\.removalProbeLabel, label)
  }

  private func capture() {
    log.step = $step
    log.reduceMotion = $reduceMotion
    log.label = $label
  }
}

/// Renders a view whose presence a test flips, one frame at a time, on one
/// renderer.
@MainActor
private final class RemovalBodySequence<V: View> {
  private let renderer = DefaultRenderer()
  private let view: V
  private var milliseconds = 0

  var controller: AnimationController { renderer.internalAnimationController }

  init(_ view: V, visible: Bool) {
    self.view = view
    _ = render(visible: visible, animation: nil)
  }

  /// Renders the next frame, `interval` milliseconds after the last one. An
  /// `animation` makes it the frame of an animated change.
  func frame(visible: Bool, animation: Animation? = nil, after interval: Int = 33)
    -> RemovalBodyFrame
  {
    milliseconds += interval
    return render(visible: visible, animation: animation)
  }

  private func render(visible: Bool, animation: Animation?) -> RemovalBodyFrame {
    var transaction = TransactionSnapshot()
    if let animation {
      transaction.animationRequest = .animate(animation.animationBox)
    }
    return withAnimationSinks(controller) {
      if let animation { controller.register(animation) }
      return RemovalBodyFrame(
        milliseconds: milliseconds,
        artifacts: renderer.renderArtifacts(
          RemovalBodyPresenceHost(visible: visible) { [view] in view },
          context: .init(identity: RemovalBodyFrames.root, transaction: transaction),
          proposal: RemovalBodyFrames.proposal,
          frameInstant: RemovalBodyFrames.start.advanced(by: .milliseconds(milliseconds))))
    }
  }
}
