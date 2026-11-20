import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// `Animatable` views and view modifiers inside a custom `Transition` body
/// (STUI-1546): such a conformer receives interpolated `animatableData` on
/// every frame of the transition, on insertion and on removal.
///
/// On insertion the live body is the identity body, and each conformer in it
/// animates its data from what the `willAppear` body gives it. On removal the
/// departing view is drawn through the `didDisappear` body, which is
/// evaluated again on every frame with the data each conformer presents.
///
/// Every test drives the real run loop on an injected frame clock, one
/// scheduler wake at a time, and compares the data the bodies ran with to a
/// closed-form expectation. Nothing waits. The file uses only API that
/// existed before the change, so it compiles against the earlier engine,
/// where a conformer in a transition body showed its destination at once.
@MainActor
@Suite("Animatable inside a transition body", .serialized)
struct TransitionBodyAnimatableTests {
  private static let linear = Animation.linear(duration: .milliseconds(800))
  /// One frame of the 33 ms cadence, as a share of the 800 ms animation.
  private static let step = 33.0 / 800.0
  /// A spring that overshoots its target.
  private static let spring = Animation.spring(duration: .milliseconds(600), bounce: 0.5)
  /// A spring that does not overshoot, for the velocity of an interruption.
  private static let smooth = Animation.spring(duration: .milliseconds(800), bounce: 0)

  // MARK: - Insertion

  @Test(
    "modifier(active:identity:), a modifier and a view in a body get every linear sample on insertion",
    arguments: BodySite.allCases)
  func insertionDeliversEveryLinearSample(site: BodySite) throws {
    let probe = try AnimatableValueProbe(named: "body-insertion-linear-\(site)") { shown, log in
      if shown > 0.5 {
        Text("PRESENT").transition(site.transition(log))
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      let frames = try Self.insertion(probe, Self.linear)
      try Self.expectLinearInsertion(frames, in: probe)
      // What the body drew followed the samples: the first presented frame
      // shows the `willAppear` output, and the last one the identity output.
      for frame in frames {
        let value = try #require(frame.values.last ?? frames.last?.values.last ?? 1)
        #expect(site.drawn(in: frame) == site.expectedDrawing(at: value), "\(frame.milliseconds)")
      }
      // The view that holds the state ran for the mount and for the write,
      // and never for a tick.
      if animatableProbeEvaluatesSelectively {
        #expect(probe.log.evaluations["root"] == 2)
      }
    }
  }

  @Test("a spring delivers values beyond the target on insertion")
  func insertionSpringOvershoots() throws {
    for site in BodySite.allCases {
      let probe = try AnimatableValueProbe(named: "body-insertion-spring-\(site)") { shown, log in
        if shown > 0.5 {
          Text("PRESENT").transition(site.transition(log))
        }
      }
      defer { probe.shutdown() }
      try probe.run { _ in
        let frames = try Self.insertion(probe, Self.spring, ticks: 60)
        let values = frames.compactMap(\.values.last)
        // The data goes from 0 to 1 and the spring carries it past 1: with
        // `modifier(active:identity:)` that is `progress` above 1. The body
        // gets the values as they are: nothing clamps them to 0...1.
        let peak = try #require(values.max())
        #expect(peak > 1.02, "\(site): \(values)")
        #expect(values.first == 0, "\(site): \(values)")
        #expect(values.last == 1, "\(site): \(values)")
        #expect(values.allSatisfy { $0 >= 0 }, "\(site): \(values)")
        #expect(probe.log.completions == 1, "\(site)")
        #expect(probe.controller.activeValueAnimationCount == 0, "\(site)")
        if animatableProbeEvaluatesSelectively {
          #expect(frames.dropFirst().allSatisfy { $0.values.count <= 1 }, "\(site)")
        }
      }
    }
  }

  // MARK: - Removal

  @Test(
    "modifier(active:identity:), a modifier and a view in a body get every linear sample on removal",
    arguments: BodySite.allCases)
  func removalDeliversEveryLinearSample(site: BodySite) throws {
    let probe = try AnimatableValueProbe(
      named: "body-removal-linear-\(site)", initial: 1, showsSibling: false
    ) { shown, log in
      if shown > 0.5 {
        Text("PRESENT").transition(site.transition(log))
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      // At rest the body ran once, with the identity data.
      #expect(probe.log.values == [1])
      let root = try #require(probe.log.evaluations["root"])
      let frames = try Self.removal(probe, Self.linear)
      try Self.expectLinearRemoval(frames, in: probe)
      // The departing view is drawn through the `didDisappear` body with
      // each sample, where it was, until the removal ends.
      for frame in frames {
        guard let value = frame.values.last else {
          #expect(!frame.frame.contains("PRESENT"), "\(frame.milliseconds) ms")
          continue
        }
        #expect(site.drawn(in: frame) == site.expectedDrawing(at: value), "\(frame.milliseconds)")
      }
      // No live body ran for the removal: the view that holds the state ran
      // once more, for the write.
      if animatableProbeEvaluatesSelectively {
        #expect(probe.log.evaluations["root"] == root + 1)
      }
    }
  }

  @Test("a spring delivers values beyond the target on removal")
  func removalSpringOvershoots() throws {
    for site in BodySite.allCases {
      let probe = try AnimatableValueProbe(
        named: "body-removal-spring-\(site)", initial: 1, showsSibling: false
      ) { shown, log in
        if shown > 0.5 {
          Text("PRESENT").transition(site.transition(log))
        }
      }
      defer { probe.shutdown() }
      try probe.run { _ in
        let frames = try Self.removal(probe, Self.spring)
        let values = frames.compactMap(\.values.last)
        // The data goes from 1 to 0 and the spring carries it below 0: with
        // `modifier(active:identity:)` that is a negative `progress`.
        let trough = try #require(values.min())
        #expect(trough < -0.02, "\(site): \(values)")
        #expect(values.first == 1, "\(site): \(values)")
        #expect(values.allSatisfy { $0 <= 1 }, "\(site): \(values)")
        // The removal ends when the spring settles. Its last drawn frame is
        // within the spring's rest threshold of the target.
        #expect(abs(values.last ?? 1) < 0.01, "\(site): \(values)")
        #expect(probe.log.completions == 1, "\(site)")
        #expect(probe.controller.debugStateSnapshot().activeAnimationKeys.isEmpty, "\(site)")
        #expect(probe.controller.debugStateSnapshot().removingNodeIDs.isEmpty, "\(site)")
        #expect(frames.allSatisfy { $0.values.count <= 1 }, "\(site)")
      }
    }
  }

  // MARK: - Where a transition plays

  @Test("a ForEach row animates its site on insertion and on removal, and the other rows do not")
  func forEachRowAnimatesItsSite() throws {
    let probe = try AnimatableValueProbe(
      named: "for-each", initial: 1, showsSibling: false
    ) { rows, log in
      ForEach(0..<Int(rows), id: \.self) { row in
        Text("ROW \(row)").transition(Self.shift(log))
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      #expect(probe.frame.contains("ROW 0") && !probe.frame.contains("ROW 1"))
      _ = try probe.step()
      // A second row arrives: its site runs from 0 to 1.
      let inserted = [try probe.set(2, animation: Self.linear)] + (try probe.steps(27))
      for frame in inserted where frame.milliseconds <= 825 {
        let value = try #require(frame.values.last)
        #expect(abs(value - min(1, Double(frame.milliseconds) / 800)) < 1e-9, "\(value)")
        #expect(frame.line(0) == "ROW 0", "\(frame.milliseconds) ms: \(frame.line(0))")
        #expect(
          frame.line(1) == String(repeating: " ", count: traceShiftIndent(value)) + "ROW 1",
          "\(frame.milliseconds) ms: \(frame.line(1))")
      }
      #expect(inserted.filter { $0.milliseconds < 825 }.allSatisfy { $0.animationKeys == 1 })
      if animatableProbeEvaluatesSelectively {
        // A tick ran the arriving row's site and no other.
        #expect(
          inserted.filter { $0.milliseconds > 0 && $0.milliseconds <= 825 }
            .allSatisfy { $0.values.count == 1 })
      }

      // The row leaves: its site runs from 1 to 0 in the body the removal
      // draws, and the row that stays is not evaluated for it.
      let removed = [try probe.set(1, animation: Self.linear)] + (try probe.steps(27))
      let drawn = removed.filter { $0.milliseconds < 800 }
      #expect(drawn.count == 25)
      for frame in drawn {
        let value = try #require(frame.values.last)
        #expect(abs(value - (1 - Double(frame.milliseconds) / 800)) < 1e-9, "\(value)")
        #expect(frame.line(0) == "ROW 0", "\(frame.milliseconds) ms: \(frame.line(0))")
        #expect(
          frame.line(1) == String(repeating: " ", count: traceShiftIndent(value)) + "ROW 1",
          "\(frame.milliseconds) ms: \(frame.line(1))")
      }
      if animatableProbeEvaluatesSelectively {
        #expect(drawn.dropFirst().allSatisfy { $0.values.count == 1 })
      }
      #expect(removed.last?.frame.contains("ROW 1") == false)
      #expect(probe.controller.debugStateSnapshot().removingNodeIDs.isEmpty)
      #expect(probe.log.completions == 2)
    }
  }

  @Test("an id change removes the old view and inserts the new one, each through its site")
  func idChangeAnimatesBothSites() throws {
    let probe = try AnimatableValueProbe(
      named: "id-change", initial: 0, showsSibling: false
    ) { step, log in
      Text(step < 0.5 ? "FIRST" : "SECOND").transition(Self.shift(log)).id(Int(step))
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      _ = try probe.step()
      let frames = [try probe.set(1, animation: Self.linear)] + (try probe.steps(27))
      // Two sites animate on the frame of the change: the new view's, from 0
      // to 1, and the old view's, from 1 to 0 in the body its removal draws.
      #expect(frames.first?.animationKeys == 2)
      for frame in frames where frame.milliseconds < 800 {
        let progress = Double(frame.milliseconds) / 800
        #expect(
          frame.values.contains { abs($0 - progress) < 1e-9 },
          "\(frame.milliseconds) ms: \(frame.values)")
        #expect(
          frame.values.contains { abs($0 - (1 - progress)) < 1e-9 },
          "\(frame.milliseconds) ms: \(frame.values)")
        if animatableProbeEvaluatesSelectively, frame.milliseconds > 0 {
          #expect(frame.values.count == 2, "\(frame.milliseconds) ms: \(frame.values)")
        }
      }
      let end = try #require(frames.first { $0.milliseconds >= 800 })
      #expect(end.values.last == 1, "\(end.values)")
      #expect(end.animationKeys == 0)
      #expect(frames.last?.line(0) == "SECOND", "\(frames.last?.line(0) ?? "")")
      #expect(probe.controller.debugStateSnapshot().removingNodeIDs.isEmpty)
      #expect(probe.log.completions == 1)
    }
  }

  @Test("a branch in a slot its node stays in animates its site both ways")
  func adoptedSlotAnimatesItsSite() throws {
    let dots = String(repeating: ".", count: 20)
    let probe = try AnimatableValueProbe(
      named: "adopted-slot", initial: 1, showsSibling: false
    ) { shown, log in
      Text(dots).overlay(alignment: .leading) {
        if shown > 0.5 {
          Text("OVER").transition(Self.shift(log))
        }
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      #expect(probe.frame.hasPrefix("OVER"), "\(probe.frame)")
      _ = try probe.step()
      // The overlay's slot keeps its graph node across the flip. The removal
      // is found through the registered identity that left.
      let removed = [try probe.set(0, animation: Self.linear)] + (try probe.runToEnd())
      let drawn = removed.filter { $0.milliseconds < 800 }
      #expect(drawn.count == 25, "\(removed.map(\.milliseconds))")
      for frame in drawn {
        let value = try #require(frame.values.last)
        #expect(abs(value - (1 - Double(frame.milliseconds) / 800)) < 1e-9, "\(value)")
        let indent = traceShiftIndent(value)
        #expect(
          frame.line(0).dropFirst(indent).hasPrefix("OVER"),
          "\(frame.milliseconds) ms: \(frame.line(0))")
      }
      #expect(removed.last?.line(0) == dots, "\(removed.last?.line(0) ?? "")")

      let inserted = [try probe.set(1, animation: Self.linear)] + (try probe.steps(27))
      for frame in inserted where frame.milliseconds <= 825 {
        let value = try #require(frame.values.last)
        #expect(abs(value - min(1, Double(frame.milliseconds) / 800)) < 1e-9, "\(value)")
      }
      #expect(inserted.last?.frame.hasPrefix("OVER") == true)
      #expect(probe.log.completions == 2)
    }
  }

  // MARK: - Asymmetric and combined transitions

  @Test("each side of an asymmetric transition animates its own site")
  func asymmetricTransitionAnimatesTheActiveSide() throws {
    let probe = try AnimatableValueProbe(named: "asymmetric", showsSibling: false) { shown, log in
      if shown > 0.5 {
        Text("PRESENT").transition(
          .asymmetric(
            insertion: Self.shift(log),
            removal: .modifier(
              active: TraceFade(progress: 0, log: log), identity: TraceFade(progress: 1, log: log))
          ))
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      // Insertion: the insertion side's modifier goes from 0 to 1. The
      // removal side shows its identity data throughout.
      let inserted = try Self.insertion(probe, Self.linear)
      try Self.expectLinearInsertion(inserted, in: probe)
      #expect(Set(inserted.flatMap(\.secondary)) == [1], "\(inserted.map(\.secondary))")
      #expect(inserted.filter { $0.milliseconds < 825 }.allSatisfy { $0.animationKeys == 1 })

      // Removal: the removal side's modifier goes from 1 to 0, and the
      // insertion side shows its identity data.
      let before = probe.log.values.count
      let removed = [try probe.set(0, animation: Self.linear)] + (try probe.runToEnd())
      let fades = removed.compactMap(\.secondary.last)
      #expect(fades.first == 1, "\(fades)")
      for frame in removed {
        guard let value = frame.secondary.last else { continue }
        #expect(
          abs(value - (1 - Double(frame.milliseconds) / 800)) < 1e-9,
          "\(frame.milliseconds) ms: \(value)")
      }
      #expect(fades == fades.sorted(by: >) && Set(fades).count == fades.count, "\(fades)")
      #expect(Set(probe.log.values[before...]) == [1], "\(probe.log.values[before...])")
      #expect(probe.log.completions == 2)
    }
  }

  @Test("two bodies combined animate both sites, and a body combined with opacity both channels")
  func combinedTransitionsAnimateEverySite() throws {
    // Two custom bodies: each has a site, at different identities.
    let both = try AnimatableValueProbe(named: "combined-bodies", showsSibling: false) {
      shown, log in
      if shown > 0.5 {
        Text("PRESENT").transition(
          Self.shift(log).combined(
            with: .modifier(
              active: TraceFade(progress: 0, log: log), identity: TraceFade(progress: 1, log: log))
          ))
      }
    }
    defer { both.shutdown() }
    try both.run { _ in
      let inserted = try Self.insertion(both, Self.linear)
      try Self.expectLinearInsertion(inserted, in: both, valueKeys: 2)
      for frame in inserted {
        guard let value = frame.values.last else { continue }
        #expect(frame.secondary.last == value, "\(frame.milliseconds) ms: \(frame.secondary)")
      }
      let removed = [try both.set(0, animation: Self.linear)] + (try both.runToEnd())
      for frame in removed {
        guard let value = frame.values.last else { continue }
        #expect(abs(value - (1 - Double(frame.milliseconds) / 800)) < 1e-9)
        #expect(frame.secondary.last == value, "\(frame.milliseconds) ms: \(frame.secondary)")
      }
      #expect(removed.compactMap(\.values.last).count == 25)
      #expect(both.log.completions == 2)
    }

    // A body with a site and a built-in effect: the site's data animates,
    // and the effect fades the view, each once.
    let mixed = try AnimatableValueProbe(named: "combined-opacity", showsSibling: false) {
      shown, log in
      if shown > 0.5 {
        Text("PRESENT").transition(Self.shift(log).combined(with: .opacity))
      }
    }
    defer { mixed.shutdown() }
    try mixed.run { _ in
      let inserted = try Self.insertion(mixed, Self.linear)
      try Self.expectLinearInsertion(inserted, in: mixed, propertyAnimations: 1)
      let removed = [try mixed.set(0, animation: Self.linear)] + (try mixed.runToEnd())
      for frame in removed {
        guard let value = frame.values.last else { continue }
        #expect(abs(value - (1 - Double(frame.milliseconds) / 800)) < 1e-9)
      }
      #expect(removed.compactMap(\.values.last).count == 25)
      #expect(mixed.log.completions == 2)
      #expect(mixed.controller.debugStateSnapshot().activeAnimationKeys.isEmpty)
    }
  }

  // MARK: - A site beside a plain modifier

  @Test("a site and a plain modifier that differs by phase both animate, neither twice")
  func siteAndPlainModifierAnimateOnce() throws {
    let probe = try AnimatableValueProbe(named: "site-and-plain", showsSibling: false) {
      shown, log in
      if shown > 0.5 {
        Text("PRESENT").transition(ShiftAndFade(log: log))
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      // Insertion. The site drives the padding and the phase drives the
      // opacity, on one node. The padding is the site's: it never animates
      // as a slot, because the first presented frame already shows what the
      // `willAppear` body produces for it. The opacity is a slot, and
      // animates as one.
      var keys: [Set<AnimationKey>] = []
      var inserted = [try probe.set(1, animation: Self.linear)]
      keys.append(probe.controller.debugStateSnapshot().activeAnimationKeys)
      for _ in 0..<27 {
        inserted.append(try #require(try probe.step()))
        keys.append(probe.controller.debugStateSnapshot().activeAnimationKeys)
      }
      try Self.expectLinearInsertion(inserted, in: probe, propertyAnimations: 1)
      for frameKeys in keys.prefix(25) {
        #expect(Self.count(.value, in: frameKeys) == 1, "\(frameKeys.map(\.scope))")
        #expect(Self.count(.property(.opacity), in: frameKeys) == 1, "\(frameKeys.map(\.scope))")
        #expect(frameKeys.count == 2, "\(frameKeys.map(\.scope))")
      }
      #expect(keys.allSatisfy { Self.count(.property(.padding), in: $0) == 0 })
      #expect(keys.last?.isEmpty == true)

      // Removal: the same, toward the `didDisappear` body.
      keys = []
      var removed = [try probe.set(0, animation: Self.linear)]
      keys.append(probe.controller.debugStateSnapshot().activeAnimationKeys)
      while let frame = try probe.step(), removed.count < 64 {
        removed.append(frame)
        keys.append(probe.controller.debugStateSnapshot().activeAnimationKeys)
      }
      let drawn = removed.filter { $0.milliseconds < 800 }
      #expect(drawn.count == 25, "\(removed.map(\.milliseconds))")
      for frame in drawn {
        #expect(frame.values.count == 1, "\(frame.milliseconds) ms: \(frame.values)")
        let value = try #require(frame.values.last)
        #expect(abs(value - (1 - Double(frame.milliseconds) / 800)) < 1e-9)
      }
      for frameKeys in keys.prefix(25) {
        #expect(Self.count(.value, in: frameKeys) == 1, "\(frameKeys.map(\.scope))")
        #expect(Self.count(.property(.opacity), in: frameKeys) == 1, "\(frameKeys.map(\.scope))")
        #expect(frameKeys.count == 2, "\(frameKeys.map(\.scope))")
      }
      #expect(keys.allSatisfy { Self.count(.property(.padding), in: $0) == 0 })
      #expect(keys.last?.isEmpty == true)
      #expect(probe.log.completions == 2)
    }
  }

  @Test("the site's output and the plain modifier's value are both drawn at every instant")
  func siteAndPlainModifierFrames() throws {
    let offsets = [0, 200, 400, 600, 792]
    for removing in [false, true] {
      let scene = BodyFrames(named: "site-and-plain-\(removing)") { shown, log in
        if shown {
          Text("PRESENT").transition(ShiftAndFade(log: log))
        }
      }
      let frames = scene.artifacts(removing: removing, at: offsets)
      for (frame, offset) in zip(frames, offsets) {
        let progress = Double(offset) / 800
        let data = removing ? 1 - progress : progress
        // The site ran with the frame's data, and what its body wrote for
        // it is drawn: the padding.
        let ran = try #require(frame.values.last)
        #expect(abs(ran - data) < 1e-9, "\(offset) ms: \(frame.values)")
        #expect(
          frame.artifacts.rasterSurface.lines[1]
            == String(repeating: " ", count: traceShiftIndent(ran)) + "PRESENT",
          "\(offset) ms")
        // The opacity is the phase's, between 0.2 and 1, on the same node.
        let opacities = Self.explicitOpacities(in: frame.artifacts.placedTree)
        #expect(opacities.count == 1, "\(offset) ms: \(opacities)")
        #expect(
          abs((opacities.first ?? -1) - (0.2 + 0.8 * data)) < 1e-9, "\(offset) ms: \(opacities)")
      }
    }
  }

  @Test("a site and a plain modifier on a wrapper view both animate the same property")
  func wrappedSiteComposesWithAPlainModifier() throws {
    let offsets = [0, 200, 400, 600, 792]
    for removing in [false, true] {
      let scene = BodyFrames(named: "wrapped-\(removing)") { shown, log in
        if shown {
          Text("PRESENT").transition(FadeInsideDim(log: log))
        }
      }
      let frames = scene.artifacts(removing: removing, at: offsets)
      for (frame, offset) in zip(frames, offsets) {
        let progress = Double(offset) / 800
        let data = removing ? 1 - progress : progress
        #expect(abs((frame.values.last ?? -1) - data) < 1e-9, "\(offset) ms: \(frame.values)")
        // Two opacities on two views: the wrapper's is the phase's, and the
        // one inside is what the site's body wrote for the frame's data.
        let opacities = Self.explicitOpacities(in: frame.artifacts.placedTree)
        #expect(opacities.count == 2, "\(offset) ms: \(opacities)")
        #expect(
          abs((opacities.first ?? -1) - (0.2 + 0.8 * data)) < 1e-9, "\(offset) ms: \(opacities)")
        #expect(
          abs((opacities.last ?? -1) - (0.25 + 0.75 * data)) < 1e-9, "\(offset) ms: \(opacities)")
      }
    }
  }

  @Test("the modifier and the transition of the guide animate both ways")
  func documentedRevealAnimates() throws {
    for custom in [false, true] {
      let probe = try AnimatableValueProbe(named: "documented-\(custom)", showsSibling: false) {
        shown, _ in
        if shown > 0.5 {
          if custom {
            Text("Saved!").transition(RevealIn())
          } else {
            Text("Saved!").transition(
              .modifier(active: Reveal(progress: 0), identity: Reveal(progress: 1)))
          }
        }
      }
      defer { probe.shutdown() }
      try probe.run { _ in
        let inserted = try Self.insertion(probe, Self.linear)
        // The first presented frame is the `willAppear` output: transparent.
        #expect(inserted.first?.line(0) == "", "\(custom): \(inserted.first?.line(0) ?? "")")
        let arriving = inserted.filter { $0.milliseconds <= 825 && $0.milliseconds > 0 }
          .map { Self.indent($0) }
        #expect(arriving.first == 4 && arriving.last == 0, "\(custom): \(arriving)")
        #expect(arriving == arriving.sorted(by: >), "\(custom): \(arriving)")
        #expect(Set(arriving) == [0, 1, 2, 3, 4], "\(custom): \(arriving)")
        #expect(inserted.filter { $0.milliseconds < 825 }.allSatisfy { $0.animationKeys == 1 })

        let removed = [try probe.set(0, animation: Self.linear)] + (try probe.runToEnd())
        let leaving = removed.filter { $0.milliseconds < 800 }.map { Self.indent($0) }
        #expect(leaving.first == 0 && leaving.last == 4, "\(custom): \(leaving)")
        #expect(leaving == leaving.sorted(), "\(custom): \(leaving)")
        #expect(Set(leaving) == [0, 1, 2, 3, 4], "\(custom): \(leaving)")
        #expect(!probe.frame.contains("Saved!"), "\(custom)")
      }
    }
  }

  @Test("a modifier outside the transition is drawn with the site's output at every instant")
  func outerModifierFrames() throws {
    let offsets = [0, 200, 400, 600, 792]
    for removing in [false, true] {
      let scene = BodyFrames(named: "outer-\(removing)") { shown, log in
        if shown {
          Text("PRESENT")
            .transition(
              .modifier(
                active: TraceFade(progress: 0, log: log, isOnlySite: true),
                identity: TraceFade(progress: 1, log: log, isOnlySite: true))
            )
            .opacity(0.5)
        }
      }
      let frames = scene.artifacts(removing: removing, at: offsets)
      for (frame, offset) in zip(frames, offsets) {
        let progress = Double(offset) / 800
        let data = removing ? 1 - progress : progress
        #expect(abs((frame.values.last ?? -1) - data) < 1e-9, "\(offset) ms: \(frame.values)")
        // One view carries both: the opacity the site's body wrote for the
        // frame's data, under the opacity applied outside the transition.
        let opacities = Self.explicitOpacities(in: frame.artifacts.placedTree)
        #expect(opacities.count == 1, "\(offset) ms: \(opacities)")
        #expect(
          abs((opacities.first ?? -1) - (0.25 + 0.75 * data) * 0.5) < 1e-9,
          "\(offset) ms: \(opacities)")
      }
    }
  }

  @Test("a site that writes the foreground style of the content is drawn at every instant")
  func siteWritesAnInheritedStyle() throws {
    let offsets = [0, 200, 400, 600, 792]
    for removing in [false, true] {
      let scene = BodyFrames(named: "inherited-style-\(removing)") { shown, log in
        if shown {
          Text("PRESENT").transition(
            .modifier(
              active: TraceTint(progress: 0, log: log), identity: TraceTint(progress: 1, log: log)))
        }
      }
      let frames = scene.artifacts(removing: removing, at: offsets)
      for (frame, offset) in zip(frames, offsets) {
        let progress = Double(offset) / 800
        let data = removing ? 1 - progress : progress
        #expect(abs((frame.values.last ?? -1) - data) < 1e-9, "\(offset) ms: \(frame.values)")
        // The style reaches the content through the environment. On removal
        // the content is the view as it was last drawn, and the style the
        // body hands to it for the frame's data is applied when it is drawn.
        let cell = frame.artifacts.rasterSurface.cells[1][0]
        #expect(cell.character == "P", "\(offset) ms")
        let color = try #require(cell.style?.foregroundColor, "\(offset) ms")
        #expect(abs(color.red - data) < 1e-6, "\(offset) ms: \(color)")
        #expect(abs(color.blue - (1 - data)) < 1e-6, "\(offset) ms: \(color)")
      }
      // The style is the site's: no slot of the content animates beside it.
      #expect(scene.controller.activeAnimationCount == 0)
    }
  }

  @Test("a modifier outside the transition stays on a body whose site drives the same value")
  func outerModifierStaysBesideASite() throws {
    let probe = try AnimatableValueProbe(named: "outer-modifier", showsSibling: false) {
      shown, log in
      if shown > 0.5 {
        // The site drives the opacity of the node the body emits, and the
        // opacity outside the transition lands on that same node.
        Text("PRESENT")
          .transition(
            .modifier(
              active: TraceFade(progress: 0, log: log), identity: TraceFade(progress: 1, log: log))
          )
          .opacity(0.5)
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      // Insertion: the site's data is the one animation. The opacity never
      // animates as a slot: the frame of the insertion already shows the
      // `willAppear` output under the outer opacity.
      let inserted = try Self.insertion(probe, Self.linear)
      let running = inserted.filter { $0.milliseconds <= 825 }
      #expect(running.count == 26)
      for frame in running {
        let value = try #require(frame.secondary.last)
        #expect(abs(value - min(1, Double(frame.milliseconds) / 800)) < 1e-9, "\(value)")
      }
      #expect(
        running.allSatisfy { $0.propertyAnimations == 0 }, "\(running.map(\.propertyAnimations))")
      #expect(running.dropLast().allSatisfy { $0.animationKeys == 1 })
      #expect(running.last?.animationKeys == 0)

      // Removal: the same toward the `didDisappear` body.
      let removed = [try probe.set(0, animation: Self.linear)] + (try probe.runToEnd())
      let drawn = removed.filter { $0.milliseconds < 800 }
      #expect(drawn.count == 25)
      for frame in drawn {
        #expect(frame.secondary.count == 1, "\(frame.milliseconds) ms: \(frame.secondary)")
        let value = try #require(frame.secondary.last)
        #expect(abs(value - (1 - Double(frame.milliseconds) / 800)) < 1e-9, "\(value)")
      }
      #expect(drawn.allSatisfy { $0.propertyAnimations == 0 }, "\(drawn.map(\.propertyAnimations))")
      #expect(drawn.allSatisfy { $0.animationKeys == 1 })
      #expect(probe.log.completions == 2)
    }
  }

  @Test("a body with two roots animates its site once")
  func multiRootBodyAnimatesItsSiteOnce() throws {
    let probe = try AnimatableValueProbe(named: "multi-root", showsSibling: false) { shown, log in
      if shown > 0.5 {
        Text("PRESENT").transition(TwoRoots(log: log))
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      let inserted = try Self.insertion(probe, Self.linear)
      try Self.expectLinearInsertion(inserted, in: probe)
      #expect(inserted.last?.frame.contains("TAIL") == true)
      // Each root leaves through a removal of its own, and both draw the
      // body with the site's samples. The removal frame plans each, and
      // evaluates the body for each. Every later frame evaluates it once
      // for the two.
      let removed = [try probe.set(0, animation: Self.linear)] + (try probe.runToEnd())
      #expect(removed.first?.values == [1, 1], "\(removed.first?.values ?? [])")
      #expect(removed.dropFirst().allSatisfy { $0.values.count <= 1 })
      #expect(removed.first?.frame.contains("TAIL") == true)
      for frame in removed {
        guard let value = frame.values.last else { continue }
        #expect(abs(value - (1 - Double(frame.milliseconds) / 800)) < 1e-9)
      }
      #expect(removed.compactMap(\.values.last).count == 25)
      #expect(probe.log.completions == 2)
      #expect(!probe.frame.contains("PRESENT") && !probe.frame.contains("TAIL"))
    }
  }

  @Test("a view of a body with two roots keeps its transition when it alone is evaluated again")
  func rootOfAMultiRootBodyKeepsItsTransition() throws {
    let probe = try AnimatableValueProbe(
      named: "multi-root-registration", initial: 1, showsSibling: false
    ) { level, log in
      if level > 0.5 {
        Text("PRESENT").transition(LiveTwoRoots(level: level, log: log))
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      // The body emits its content and a label. Each has a graph node of its
      // own and is registered by the body's host.
      #expect(probe.controller.debugStateSnapshot().transitionIdentities.count == 2)
      // The data of the modifier on the first view animates while the view
      // stays. Each tick evaluates that view's node alone: the host, which
      // declares the transition, does not run.
      _ = try probe.step()
      _ = try probe.set(0.75, animation: Self.linear)
      let ticks = try probe.steps(27)
      #expect(ticks.compactMap(\.values.last).contains { $0 < 1 && $0 > 0.75 })
      #expect(probe.log.values.last == 0.75)
      #expect(probe.controller.debugStateSnapshot().transitionIdentities.count == 2)

      // Both views still leave through the body: each has a removal of its
      // own that plays it.
      let removed = try probe.set(0, animation: Self.linear)
      let state = probe.controller.debugStateSnapshot()
      #expect(state.removingNodeIDs.count == 2)
      #expect(
        state.removingIdentities.allSatisfy {
          probe.controller.removalBodyState(forIdentity: $0) != nil
        })
      #expect(removed.frame.contains("PRESENT") && removed.frame.contains("TAIL"))
      _ = try probe.runToEnd()
      #expect(!probe.frame.contains("PRESENT") && !probe.frame.contains("TAIL"))
      #expect(probe.log.completions == 2)
    }
  }

  @Test("a transition's own animation drives its sites without an animated transaction")
  func ownAnimationDrivesTheSites() throws {
    let probe = try AnimatableValueProbe(named: "own-animation", showsSibling: false) {
      shown, log in
      if shown > 0.5 {
        Text("PRESENT").transition(
          Self.shift(log).animation(.linear(duration: .milliseconds(400))))
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      // A plain state write: the transition's own 400 ms curve plays.
      var inserted = [try probe.set(1, animation: nil)]
      inserted += try probe.steps(16)
      #expect(inserted.first?.values.last == 0)
      let running = inserted.filter { $0.milliseconds <= 429 }
      #expect(running.count == 14, "\(inserted.map(\.milliseconds))")
      for frame in running {
        let value = try #require(frame.values.last)
        #expect(abs(value - min(1, Double(frame.milliseconds) / 400)) < 1e-9, "\(value)")
      }
      #expect(running.last?.values.last == 1)
      #expect(running.last?.animationKeys == 0)

      let removed = [try probe.set(0, animation: nil)] + (try probe.runToEnd())
      let drawn = removed.filter { $0.milliseconds < 400 }
      #expect(drawn.count == 13, "\(removed.map(\.milliseconds))")
      for frame in drawn {
        let value = try #require(frame.values.last)
        #expect(abs(value - (1 - Double(frame.milliseconds) / 400)) < 1e-9, "\(value)")
      }
      #expect(removed.filter { $0.milliseconds >= 400 }.allSatisfy { $0.values.isEmpty })
      #expect(probe.controller.debugStateSnapshot().activeAnimationKeys.isEmpty)
      #expect(!probe.frame.contains("PRESENT"))
    }
  }

  // MARK: - Interruption

  @Test("a removal during a linear insertion continues every site from its sample")
  func linearRemovalDuringInsertion() throws {
    let probe = try AnimatableValueProbe(named: "interrupt-in-linear", showsSibling: false) {
      shown, log in
      if shown > 0.5 {
        Text("PRESENT").transition(Self.shift(log))
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      var values = [try #require(try probe.set(1, animation: Self.linear).values.last)]
      for _ in 0..<12 {
        values.append(try #require(try probe.step()?.values.last))
      }
      // The write lands on the next frame of the cadence: the frame that
      // would have shown the thirteenth sample shows it, through the body
      // the removal draws.
      let turn = try probe.set(0, animation: Self.linear, atNextWake: true)
      values.append(try #require(turn.values.last))
      let flip = values.count - 1
      #expect(abs(values[flip] - 13 * Self.step) < 1e-9, "\(values)")
      values.append(contentsOf: try probe.runToEnd().compactMap(\.values.last))

      let steps = zip(values, values.dropFirst()).map { $1 - $0 }
      #expect(steps.allSatisfy { abs($0) <= Self.step + 1e-9 }, "\(steps)")
      #expect(steps[..<flip].allSatisfy { $0 > 0 }, "\(steps)")
      #expect(steps[flip...].allSatisfy { $0 < 0 }, "\(steps)")
      // The removal runs its own 800 ms from the flip, toward 0.
      #expect((values.last ?? 1) < 13 * Self.step * Self.step + 1e-9, "\(values)")
      #expect(values.count == flip + 1 + 24, "\(values.count)")
      // The insertion's completion fired when it was interrupted, the
      // removal's when it ended.
      #expect(probe.log.completions == 2)
      #expect(probe.controller.debugStateSnapshot().activeAnimationKeys.isEmpty)
      #expect(!probe.frame.contains("PRESENT"))
    }
  }

  @Test("a re-insertion during a linear removal continues every site from its sample")
  func linearReinsertionDuringRemoval() throws {
    let probe = try AnimatableValueProbe(
      named: "interrupt-out-linear", initial: 1, showsSibling: false
    ) { shown, log in
      if shown > 0.5 {
        Text("PRESENT").transition(Self.shift(log))
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      _ = try probe.step()
      var values = [try #require(try probe.set(0, animation: Self.linear).values.last)]
      for _ in 0..<12 {
        values.append(try #require(try probe.step()?.values.last))
      }
      let turn = try probe.set(1, animation: Self.linear, atNextWake: true)
      values.append(try #require(turn.values.last))
      let flip = values.count - 1
      // The view is live again, and its first frame shows what the removal
      // would have shown: the thirteenth sample of the removal.
      #expect(abs(values[flip] - (1 - 13 * Self.step)) < 1e-9, "\(values)")
      #expect(turn.line(0) == String(repeating: " ", count: 5) + "PRESENT", "\(turn.line(0))")
      for frame in try probe.steps(26) where values.last != 1 {
        if let value = frame.values.last { values.append(value) }
      }

      let steps = zip(values, values.dropFirst()).map { $1 - $0 }
      #expect(steps.allSatisfy { abs($0) <= Self.step + 1e-9 }, "\(steps)")
      #expect(steps[..<flip].allSatisfy { $0 < 0 }, "\(steps)")
      #expect(steps[flip...].allSatisfy { $0 > 0 }, "\(steps)")
      #expect(values.last == 1, "\(values)")
      #expect(probe.log.completions == 2)
      #expect(probe.controller.activeValueAnimationCount == 0)
      #expect(probe.controller.debugStateSnapshot().removingNodeIDs.isEmpty)
      #expect(probe.frame.contains("PRESENT"))
    }
  }

  @Test("a removal during a spring insertion keeps the sign and the size of the velocity")
  func springRemovalDuringInsertion() throws {
    let probe = try AnimatableValueProbe(named: "interrupt-in-spring", showsSibling: false) {
      shown, log in
      if shown > 0.5 {
        Text("PRESENT").transition(Self.shift(log))
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      var values = [try #require(try probe.set(1, animation: Self.smooth).values.last)]
      for _ in 0..<5 {
        values.append(try #require(try probe.step()?.values.last))
      }
      // Remove while the spring is moving fast.
      let turn = try probe.set(0, animation: Self.smooth, atNextWake: true)
      values.append(try #require(turn.values.last))
      let flip = values.count - 1
      values.append(contentsOf: try probe.runToEnd().compactMap(\.values.last))
      try Self.expectVelocityCarried(values, flip: flip, rising: true)
      #expect(abs(values.last ?? 1) < 0.01, "\(values)")
      #expect(probe.log.completions == 2)
    }
  }

  @Test("a re-insertion during a spring removal keeps the sign and the size of the velocity")
  func springReinsertionDuringRemoval() throws {
    let probe = try AnimatableValueProbe(
      named: "interrupt-out-spring", initial: 1, showsSibling: false
    ) { shown, log in
      if shown > 0.5 {
        Text("PRESENT").transition(Self.shift(log))
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      _ = try probe.step()
      var values = [try #require(try probe.set(0, animation: Self.smooth).values.last)]
      for _ in 0..<5 {
        values.append(try #require(try probe.step()?.values.last))
      }
      let turn = try probe.set(1, animation: Self.smooth, atNextWake: true)
      values.append(try #require(turn.values.last))
      let flip = values.count - 1
      for frame in try probe.steps(60) where values.last != 1 || values.count <= flip + 2 {
        if let value = frame.values.last { values.append(value) }
      }
      try Self.expectVelocityCarried(values, flip: flip, rising: false)
      #expect(values.last == 1, "\(values)")
      #expect(probe.log.completions == 2)
    }
  }

  // MARK: - Reduce Motion and stable output

  @Test("Reduce Motion or stable output from the start snaps the insertion and the removal")
  func policyFromTheStartSnaps() throws {
    for policy in [AnimatableValueProbePolicy.reduceMotion, .stableOutput] {
      let probe = try AnimatableValueProbe(
        named: "policy-start-\(policy)", policy: policy, showsSibling: false
      ) { shown, log in
        if shown > 0.5 {
          Text("PRESENT").transition(Self.shift(log))
        }
      }
      defer { probe.shutdown() }
      try probe.run { _ in
        // Insertion: one evaluation, with the identity data.
        let inserted = try probe.set(1, animation: Self.linear)
        #expect(inserted.values == [1], "\(policy): \(inserted.values)")
        #expect(inserted.animationKeys == 0, "\(policy)")
        #expect(inserted.line(0) == "PRESENT", "\(policy)")
        for frame in try probe.steps(4) {
          Self.expectNoFurtherSample(frame, "\(policy)")
        }
        // Removal: the view leaves at once and no sample follows.
        let removed = try probe.set(0, animation: Self.linear)
        #expect(!removed.frame.contains("PRESENT"), "\(policy)")
        #expect(removed.animationKeys == 0, "\(policy)")
        #expect(probe.controller.debugStateSnapshot().removingNodeIDs.isEmpty, "\(policy)")
        let after = probe.log.values.count
        _ = try probe.runToEnd()
        #expect(probe.log.values.count == after, "\(policy)")
        #expect(probe.log.values.allSatisfy { $0 == 0 || $0 == 1 }, "\(policy)")
        #expect(probe.log.completions == 2, "\(policy)")
      }
    }
  }

  @Test("Reduce Motion or stable output turned on in flight ends the insertion at its target")
  func policyTurnedOnDuringInsertion() throws {
    for policy in [AnimatableValueProbePolicy.reduceMotion, .stableOutput] {
      let probe = try AnimatableValueProbe(named: "policy-in-\(policy)", showsSibling: false) {
        shown, log in
        if shown > 0.5 {
          Text("PRESENT").transition(Self.shift(log))
        }
      }
      defer { probe.shutdown() }
      try probe.run { _ in
        _ = try probe.set(1, animation: Self.linear)
        _ = try probe.steps(5)
        #expect(abs((probe.log.values.last ?? -1) - 5 * Self.step) < 1e-9, "\(policy)")
        // The policy turns on at the next frame of the cadence, and the body
        // runs with its target on that frame.
        let turn = try probe.switchPolicy(to: policy)
        #expect(turn.values.last == 1, "\(policy): \(turn.values)")
        #expect(turn.animationKeys == 0, "\(policy)")
        #expect(turn.completions == 1, "\(policy)")
        #expect(turn.line(0) == "PRESENT", "\(policy): \(turn.line(0))")
        for frame in try probe.steps(4) {
          Self.expectNoFurtherSample(frame, "\(policy)")
        }
      }
    }
  }

  @Test("Reduce Motion or stable output turned on in flight ends the removal")
  func policyTurnedOnDuringRemoval() throws {
    for policy in [AnimatableValueProbePolicy.reduceMotion, .stableOutput] {
      let probe = try AnimatableValueProbe(
        named: "policy-out-\(policy)", initial: 1, showsSibling: false
      ) { shown, log in
        if shown > 0.5 {
          Text("PRESENT").transition(Self.shift(log))
        }
      }
      defer { probe.shutdown() }
      try probe.run { _ in
        _ = try probe.step()
        _ = try probe.set(0, animation: Self.linear)
        _ = try probe.steps(5)
        #expect(abs((probe.log.values.last ?? -1) - (1 - 5 * Self.step)) < 1e-9, "\(policy)")
        #expect(probe.frame.contains("PRESENT"), "\(policy)")
        // The removal ends on the frame the policy turns on: nothing is
        // drawn for it, and its body is not evaluated again.
        let turn = try probe.switchPolicy(to: policy)
        #expect(turn.values.isEmpty, "\(policy): \(turn.values)")
        #expect(!turn.frame.contains("PRESENT"), "\(policy)")
        #expect(turn.animationKeys == 0, "\(policy)")
        #expect(probe.controller.debugStateSnapshot().removingNodeIDs.isEmpty, "\(policy)")
        #expect(turn.completions == 1, "\(policy)")
        let after = probe.log.values.count
        _ = try probe.runToEnd()
        #expect(probe.log.values.count == after, "\(policy)")
      }
    }
  }

  // MARK: - No animation

  @Test("a plain insertion and a plain removal evaluate the site once, at its end value")
  func changeWithoutAnAnimationSnaps() throws {
    for disabling in [false, true] {
      let probe = try AnimatableValueProbe(
        named: "plain-\(disabling)", showsSibling: false
      ) { shown, log in
        if shown > 0.5 {
          Text("PRESENT").transition(Self.shift(log))
        }
      }
      defer { probe.shutdown() }
      try probe.run { _ in
        // A plain write, or `withAnimation(nil)`: the body runs once, with
        // the identity data.
        let inserted = try probe.set(1, animation: nil, disabling: disabling)
        #expect(inserted.values == [1], "\(inserted.values)")
        #expect(inserted.animationKeys == 0)
        #expect(inserted.line(0) == "PRESENT")
        for frame in try probe.steps(4) {
          Self.expectNoFurtherSample(frame, "plain")
        }
        // The view leaves at once. No body of the transition runs for it.
        let removed = try probe.set(0, animation: nil, disabling: disabling)
        #expect(removed.values.isEmpty, "\(removed.values)")
        #expect(!removed.frame.contains("PRESENT"))
        #expect(probe.controller.debugStateSnapshot().removingNodeIDs.isEmpty)
        _ = try probe.runToEnd()
        #expect(Set(probe.log.values) == [1], "\(probe.log.values)")
        if animatableProbeEvaluatesSelectively {
          #expect(probe.log.values == [1], "\(probe.log.values)")
        }
      }
    }
  }

  // MARK: - Confinement

  @Test("on insertion only the site's owner runs again on a tick, and its content keeps its state")
  func insertionEvaluationIsConfinedToTheOwner() throws {
    let probe = try AnimatableValueProbe(named: "confined-insertion") { shown, log in
      if shown > 0.5 {
        TraceCounter(log: log).transition(Self.shift(log))
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      let first = try probe.set(1, animation: Self.linear)
      #expect(first.values.last == 0)
      // Give the content state of its own while the insertion plays.
      _ = try probe.step()
      _ = try probe.harness.clickText("count 0")
      #expect(probe.frame.contains("count 1"), "\(probe.frame)")
      let root = try #require(probe.log.evaluations["root"])
      let sibling = try #require(probe.log.evaluations["sibling"])
      let unrelated = try #require(probe.log.evaluations["unrelated"])
      let content = try #require(probe.log.evaluations["content"])

      let ticks = try probe.steps(26)
      #expect(probe.log.values.last == 1)
      if animatableProbeEvaluatesSelectively {
        // One evaluation of the site for each tick of the animation, and
        // none of the views beside it.
        #expect(ticks.last?.values.isEmpty == true)
        #expect(ticks.allSatisfy { $0.values.count <= 1 }, "\(ticks.map(\.values))")
        #expect(probe.log.evaluations["root"] == root)
        #expect(probe.log.evaluations["sibling"] == sibling)
        #expect(probe.log.evaluations["unrelated"] == unrelated)
        // The content the body hosts did not run for a tick either.
        #expect(probe.log.evaluations["content"] == content)
      }
      // The content stayed mounted through every evaluation of the body.
      #expect(ticks.allSatisfy { $0.frame.contains("count 1") })
      #expect(probe.log.appears == 1)
      #expect(probe.log.disappears == 0)
    }
  }

  @Test("during a removal no live view runs for it")
  func removalEvaluatesNoLiveView() throws {
    let probe = try AnimatableValueProbe(named: "confined-removal", initial: 1) { shown, log in
      if shown > 0.5 {
        TraceCounter(log: log).transition(Self.shift(log))
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      _ = try probe.step()
      let first = try probe.set(0, animation: Self.linear)
      #expect(first.values == [1])
      // The content was torn down on the frame of the write.
      #expect(probe.log.disappears == 1)
      let root = try #require(probe.log.evaluations["root"])
      let sibling = try #require(probe.log.evaluations["sibling"])
      let unrelated = try #require(probe.log.evaluations["unrelated"])
      let content = try #require(probe.log.evaluations["content"])

      let ticks = try probe.runToEnd()
      // The transition's body ran for every frame it drew.
      #expect(ticks.compactMap(\.values.last).count == 24, "\(ticks.map(\.values))")
      // No view of the live tree ran: not the root, not the views beside
      // the departed one, and not the departed content.
      if animatableProbeEvaluatesSelectively {
        #expect(probe.log.evaluations["root"] == root)
        #expect(probe.log.evaluations["sibling"] == sibling)
        #expect(probe.log.evaluations["unrelated"] == unrelated)
      }
      #expect(probe.log.evaluations["content"] == content)
      #expect(probe.log.appears == 1)
      #expect(probe.log.disappears == 1)
    }
  }

  // MARK: - Shapes in a body

  @Test(
    "an Animatable shape that a body fills or strokes is evaluated through both directions",
    arguments: [ShapeUse.fill, .stroke])
  func bodyShapeAnimatesBothWays(use: ShapeUse) throws {
    let probe = try AnimatableValueProbe(named: "body-shape-\(use)", showsSibling: false) {
      shown, log in
      if shown > 0.5 {
        Text("PRESENT").transition(BarReveal(use: use, log: log))
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      // The shape is a slot of the body: `path(in:)` runs with data between
      // the two phases, and what is drawn follows it.
      let inserted = try Self.insertion(probe, Self.linear)
      let rising = inserted.flatMap(\.values)
      #expect(rising.contains { $0 > 0.05 && $0 < 0.95 }, "\(use): \(rising)")
      #expect(rising.last == 1, "\(use): \(rising)")
      let grown = inserted.prefix(26).map { Self.barExtent(in: $0, use) }
      #expect(grown == grown.sorted(), "\(use): \(grown)")
      // A stroke of an empty shape still draws its one edge.
      #expect((grown.first ?? 20) <= 1 && grown.last == 20, "\(use): \(grown)")
      #expect(Set(grown).count > 5, "\(use): \(grown)")

      let before = probe.log.values.count
      let removed = [try probe.set(0, animation: Self.linear)] + (try probe.runToEnd())
      let falling = Array(probe.log.values[before...])
      #expect(falling.contains { $0 > 0.05 && $0 < 0.95 }, "\(use): \(falling)")
      let shrunk = removed.prefix(25).map { Self.barExtent(in: $0, use) }
      #expect(shrunk == shrunk.sorted(by: >), "\(use): \(shrunk)")
      #expect(shrunk.first == 20, "\(use): \(shrunk)")
      #expect(Set(shrunk).count > 5, "\(use): \(shrunk)")
      #expect(probe.log.completions == 2, "\(use)")
    }
  }

  // MARK: - A conformer that resolves during layout

  @Test("a conformer inside a GeometryReader of the body gets its destination data at once")
  func layoutRealizedConformerSnaps() throws {
    let probe = try AnimatableValueProbe(named: "layout-realized", showsSibling: false) {
      shown, log in
      if shown > 0.5 {
        Text("PRESENT").transition(GaugeInGeometry(log: log))
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      // The content of a `GeometryReader` resolves while it lays out, after
      // the frame head. On insertion the conformer runs with the identity
      // data from the first frame, and the rest of the body animates.
      let inserted = try Self.insertion(probe, Self.linear)
      #expect(Set(inserted.flatMap(\.values)) == [1], "\(inserted.map(\.values))")
      #expect(inserted.first?.propertyAnimations == 1)
      #expect(inserted.allSatisfy { $0.frame.contains("##########") })

      // On removal it is drawn with the `didDisappear` data from the first
      // frame. It is part of a body that is drawn and not mounted: nothing
      // of it is left with the live sites when the removal has ended.
      let before = probe.log.values.count
      let removed = [try probe.set(0, animation: Self.linear)] + (try probe.runToEnd())
      #expect(Set(probe.log.values[before...]) == [0], "\(probe.log.values[before...])")
      #expect(removed.first?.frame.contains("PRESENT") == true)
      #expect(removed.allSatisfy { !$0.frame.contains("#") })
      #expect(probe.controller.valueSiteCount == 0)
      #expect(probe.controller.debugStateSnapshot().activeAnimationKeys.isEmpty)
      #expect(probe.log.completions == 2)
    }
  }

  // MARK: - A body with no site

  @Test("a body with no Animatable view or modifier is evaluated once for a removal")
  func bodyWithoutASiteIsEvaluatedOncePerRemoval() throws {
    let probe = try AnimatableValueProbe(
      named: "no-site", initial: 1, showsSibling: false
    ) { shown, log in
      if shown > 0.5 {
        Text("PRESENT").transition(CountedDim(log: log))
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      _ = try probe.step()
      let before = probe.log.evaluations["body"] ?? 0
      let removed = [try probe.set(0, animation: Self.linear)] + (try probe.runToEnd())
      #expect(removed.count >= 26)
      // One evaluation, of the `didDisappear` phase, when the removal
      // starts. No frame of the removal evaluates the body again.
      #expect(probe.log.evaluations["body"] == before + 1)
      #expect(probe.log.completions == 1)
    }
  }

  @Test("each phase of a body with a site is evaluated once for each frame that needs it")
  func phasesAreEvaluatedOncePerFrame() throws {
    let probe = try AnimatableValueProbe(named: "phases", showsSibling: false) { shown, log in
      if shown > 0.5 {
        Text("PRESENT").transition(CountedShift(log: log))
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      // The frame of the insertion evaluates the `willAppear` phase once, to
      // learn where the site starts. The slot channel takes that evaluation
      // and does not evaluate the phase again. The identity phase, which is
      // the live body, runs twice: when it resolves, and again with the
      // origin.
      _ = try probe.set(1, animation: Self.linear)
      #expect(probe.log.evaluations["willAppear"] == 1)
      if animatableProbeEvaluatesSelectively {
        #expect(probe.log.evaluations["identity"] == 2)
      }
      #expect(probe.log.evaluations["didDisappear"] == nil)
      // Each tick runs the live body once. No other phase is evaluated.
      _ = try probe.steps(27)
      #expect(probe.log.evaluations["willAppear"] == 1)
      if animatableProbeEvaluatesSelectively {
        #expect(probe.log.evaluations["identity"] == 2 + 25)
      }
      #expect(probe.log.evaluations["didDisappear"] == nil)

      // The removal evaluates the `didDisappear` phase once on its first
      // frame and once on each later frame it draws: 25 in all.
      let identity = probe.log.evaluations["identity"]
      let first = try probe.set(0, animation: Self.linear)
      #expect(first.values == [1])
      #expect(probe.log.evaluations["didDisappear"] == 1)
      _ = try probe.runToEnd()
      #expect(probe.log.evaluations["didDisappear"] == 25)
      #expect(probe.log.evaluations["willAppear"] == 1)
      #expect(probe.log.evaluations["identity"] == identity)
    }
  }

  // MARK: - The abortable renderer path

  @Test("the asynchronous renderer delivers the same samples in both directions")
  func asyncRendererDeliversTheSameSamples() async throws {
    let offsets = [0, 33, 66, 99, 400, 792, 825, 858]
    for removing in [false, true] {
      let sync = BodyFrames(named: "sync-\(removing)", content: shiftedText)
        .values(removing: removing, at: offsets)
      let asynchronous = await BodyFrames(named: "async-\(removing)", content: shiftedText)
        .valuesAsync(removing: removing, at: offsets)
      #expect(sync == asynchronous, "\(removing): \(sync) / \(asynchronous)")
      #expect(sync.count == offsets.count)
      for (frame, offset) in zip(sync, offsets) {
        if removing {
          // The removal draws until its 800 ms are over, and evaluates its
          // body once for each frame it draws.
          #expect(frame.count == (offset < 800 ? 1 : 0), "\(offset) ms: \(frame)")
          if let value = frame.last {
            #expect(abs(value - (1 - Double(offset) / 800)) < 1e-9, "\(offset) ms: \(value)")
          }
        } else {
          let value = try #require(frame.last)
          #expect(abs(value - min(1, Double(offset) / 800)) < 1e-9, "\(offset) ms: \(value)")
        }
      }
      if !removing {
        #expect(sync.first == [1, 0, 0], "\(sync)")
        #expect(sync.last?.last == 1, "\(sync)")
      }
    }
  }

  // MARK: - Aborted frames

  @Test("an aborted frame neither loses nor repeats a step of an insertion's sites")
  func abortedInsertionFrames() throws {
    let scene = BodyFrames(named: "aborted-insertion", content: shiftedText)
    scene.run {
      scene.render(shown: false, at: 0)
      // The frame that would start the insertion is aborted: its bodies ran,
      // and nothing of it stays. The frame that replaces it starts again
      // from the origin.
      scene.abort(shown: true, animated: true, at: 0)
      #expect(scene.log.values.last == 0)
      #expect(scene.controller.debugStateSnapshot().activeAnimationKeys.isEmpty)
      #expect(scene.controller.valueSiteCount == 0)
      scene.render(shown: true, animated: true, at: 0)
      #expect(scene.log.values.last == 0)
      #expect(scene.controller.activeValueAnimationCount == 1)

      scene.render(shown: true, at: 33)
      #expect(abs((scene.log.values.last ?? -1) - Self.step) < 1e-9)

      // A tick is aborted. The next frame's sample is the one for its own
      // instant: the aborted tick neither moved the animation nor cost it a
      // step.
      scene.abort(shown: true, at: 66)
      #expect(abs((scene.log.values.last ?? -1) - 2 * Self.step) < 1e-9)
      scene.render(shown: true, at: 99)
      #expect(abs((scene.log.values.last ?? -1) - 3 * Self.step) < 1e-9)

      // The frame that would end the insertion is aborted: it is still in
      // flight afterwards, and the next frame ends it.
      scene.abort(shown: true, at: 825)
      #expect(scene.log.values.last == 1)
      #expect(scene.controller.activeValueAnimationCount == 1)
      scene.render(shown: true, at: 858)
      #expect(scene.log.values.last == 1)
      #expect(scene.controller.activeValueAnimationCount == 0)
    }
  }

  @Test("an aborted frame neither loses nor repeats a step of a removal's sites")
  func abortedRemovalFrames() throws {
    let scene = BodyFrames(named: "aborted-removal", content: shiftedText)
    scene.run {
      scene.render(shown: true, at: 0)
      #expect(scene.log.values.last == 1)

      // The frame that would start the removal is aborted. The view is
      // still there afterwards, with nothing in flight.
      scene.abort(shown: false, animated: true, at: 33)
      #expect(scene.controller.debugStateSnapshot().removingNodeIDs.isEmpty)
      #expect(scene.controller.debugStateSnapshot().activeAnimationKeys.isEmpty)
      #expect(scene.controller.valueSiteCount == 1)
      scene.render(shown: false, animated: true, at: 33)
      #expect(scene.log.values.last == 1)
      #expect(scene.controller.debugStateSnapshot().removingNodeIDs.count == 1)
      #expect(scene.controller.activeValueAnimationCount == 1)

      scene.render(shown: false, at: 66)
      #expect(abs((scene.log.values.last ?? -1) - (1 - Self.step)) < 1e-9)

      // A tick is aborted before its frame is drawn. The removal's body
      // runs for a frame that is drawn, so it did not run, and the next
      // frame shows the sample for its own instant.
      let ticked = scene.log.values.count
      scene.abort(shown: false, at: 99)
      #expect(scene.log.values.count == ticked)
      scene.render(shown: false, at: 132)
      #expect(scene.log.values.count == ticked + 1)
      #expect(abs((scene.log.values.last ?? -1) - (1 - 3 * Self.step)) < 1e-9)

      // The frame that would end the removal is aborted: the removal is
      // still in flight afterwards, and the next frame ends it.
      let before = scene.log.values.count
      scene.abort(shown: false, at: 33 + 825)
      #expect(scene.controller.activeValueAnimationCount == 1)
      #expect(scene.controller.debugStateSnapshot().removingNodeIDs.count == 1)
      scene.render(shown: false, at: 33 + 825)
      #expect(scene.controller.activeValueAnimationCount == 0)
      // The frame the removal ends on draws nothing, so its body does not
      // run on it.
      #expect(scene.log.values.count == before)
      scene.render(shown: false, at: 33 + 858)
      #expect(scene.controller.debugStateSnapshot().removingNodeIDs.isEmpty)
    }
  }

  // MARK: - Shared steps and expectations

  /// The transition under test in most cases: `modifier(active:identity:)`
  /// around a modifier that conforms to `Animatable`.
  private static func shift(_ log: AnimatableValueLog) -> AnyTransition {
    .modifier(
      active: TraceShift(progress: 0, log: log), identity: TraceShift(progress: 1, log: log))
  }

  /// Inserts the view and renders the frame of the write and `ticks` more.
  /// A present view under a transition keeps a frame deadline armed, so the
  /// run does not end by itself.
  private static func insertion<Content: View>(
    _ probe: AnimatableValueProbe<Content>,
    _ animation: Animation,
    ticks: Int = 27
  ) throws -> [AnimatableValueFrame] {
    [try probe.set(1, animation: animation)] + (try probe.steps(ticks))
  }

  /// Removes the view on a frame of the cadence its transition keeps armed,
  /// and renders every frame until the scheduler has none left.
  private static func removal<Content: View>(
    _ probe: AnimatableValueProbe<Content>,
    _ animation: Animation
  ) throws -> [AnimatableValueFrame] {
    _ = try probe.step()
    return [try probe.set(0, animation: animation)] + (try probe.runToEnd())
  }

  /// The run of an 800 ms linear insertion on the 33 ms cadence, from the
  /// data of the `willAppear` phase (0) to the data of the identity phase
  /// (1): the origin on the first presented frame, `elapsed / 800` on every
  /// tick, exactly 1 at the end, one evaluation of the site a frame, and the
  /// completion once, on the frame that reaches the target.
  private static func expectLinearInsertion<Content: View>(
    _ frames: [AnimatableValueFrame],
    in probe: AnimatableValueProbe<Content>,
    valueKeys: Int = 1,
    propertyAnimations: Int = 0
  ) throws {
    let first = try #require(frames.first)
    // The frame of the write evaluates the site three times: when the live
    // body resolves, with the identity data; when the `willAppear` phase is
    // evaluated to learn the origin; and when the live body runs again with
    // that origin, which is what the frame presents.
    #expect(first.values.last == 0, "\(first.values)")
    if animatableProbeEvaluatesSelectively {
      #expect(first.values == [1, 0, 0], "\(first.values)")
    }
    let running = frames.filter { $0.milliseconds <= 825 }
    #expect(running.count == 26, "\(frames.map(\.milliseconds))")
    for frame in running {
      let expected = min(1, Double(frame.milliseconds) / 800)
      let value = try #require(frame.values.last)
      #expect(abs(value - expected) < 1e-9, "\(frame.milliseconds) ms: \(value)")
      if animatableProbeEvaluatesSelectively, frame.milliseconds > 0 {
        #expect(frame.values.count == 1, "\(frame.milliseconds) ms: \(frame.values)")
      }
    }
    let values = running.compactMap(\.values.last)
    #expect(values == values.sorted() && Set(values).count == values.count, "\(values)")
    #expect(values.last == 1, "\(values)")
    // The data is the site's one animation. What its body produced from each
    // sample was written as it was: nothing animates it a second time.
    #expect(running.dropLast().allSatisfy { $0.animationKeys == valueKeys + propertyAnimations })
    #expect(running.dropLast().allSatisfy { $0.propertyAnimations == propertyAnimations })
    #expect(running.last?.animationKeys == 0)
    // The completion fires once, on the frame that reaches the target.
    #expect(running.dropLast().allSatisfy { $0.completions == 0 })
    #expect(running.last?.completions == 1)
    // Nothing follows.
    for frame in frames where frame.milliseconds > 825 {
      if animatableProbeEvaluatesSelectively {
        #expect(frame.values.isEmpty, "\(frame.milliseconds) ms: \(frame.values)")
      }
      #expect(frame.completions == 1)
    }
  }

  /// The run of an 800 ms linear removal on the 33 ms cadence, from the data
  /// on screen (1) to the data of the `didDisappear` phase (0): the origin
  /// on the frame of the write, `1 - elapsed / 800` on every tick, one
  /// evaluation of the body a frame, and the completion once, on the frame
  /// the removal ends. That frame draws nothing, so the body's last
  /// evaluation is its last sample.
  private static func expectLinearRemoval<Content: View>(
    _ frames: [AnimatableValueFrame],
    in probe: AnimatableValueProbe<Content>
  ) throws {
    let first = try #require(frames.first)
    #expect(first.values == [1], "\(first.values)")
    let drawn = frames.filter { $0.milliseconds < 800 }
    #expect(drawn.count == 25, "\(frames.map(\.milliseconds))")
    for frame in drawn {
      let expected = 1 - Double(frame.milliseconds) / 800
      #expect(frame.values.count == 1, "\(frame.milliseconds) ms: \(frame.values)")
      let value = try #require(frame.values.last)
      #expect(abs(value - expected) < 1e-9, "\(frame.milliseconds) ms: \(value)")
    }
    let values = drawn.compactMap(\.values.last)
    #expect(values == values.sorted(by: >) && Set(values).count == values.count, "\(values)")
    #expect(drawn.allSatisfy { $0.animationKeys == 1 && $0.propertyAnimations == 0 })
    #expect(drawn.allSatisfy { $0.completions == 0 })
    // The removal ends on the first frame past its duration. Nothing is
    // evaluated on it or after it.
    let after = frames.filter { $0.milliseconds >= 800 }
    let end = try #require(after.first)
    #expect(end.milliseconds == 825)
    #expect(after.allSatisfy { $0.values.isEmpty }, "\(after.map(\.values))")
    #expect(after.allSatisfy { $0.animationKeys == 0 && $0.completions == 1 })
    #expect(probe.log.completions == 1)
    #expect(probe.controller.debugStateSnapshot().removingNodeIDs.isEmpty)
  }

  /// A frame after an animation ended, or with none: the site is not
  /// evaluated again. (Under the stack-lean profile every frame evaluates
  /// the whole tree, and the site then runs with its end value.)
  private static func expectNoFurtherSample(_ frame: AnimatableValueFrame, _ label: String) {
    if animatableProbeEvaluatesSelectively {
      #expect(frame.values.isEmpty, "\(label): \(frame.values)")
    } else {
      #expect(frame.values.allSatisfy { $0 == 1 }, "\(label): \(frame.values)")
    }
  }

  /// The first step after an interruption keeps the sign of the step before
  /// it and most of its size, and the value then turns round.
  private static func expectVelocityCarried(
    _ values: [Double],
    flip: Int,
    rising: Bool
  ) throws {
    let steps = zip(values, values.dropFirst()).map { $1 - $0 }
    let before = steps[flip - 1]
    let after = steps[flip]
    #expect(rising ? before > 0 && after > 0 : before < 0 && after < 0, "\(steps)")
    #expect((0.5...1.1).contains(after / before), "\(after / before): \(steps)")
    let largest = try #require(steps[..<flip].map(abs).max())
    #expect(steps[flip...].allSatisfy { abs($0) <= largest * 1.5 }, "\(steps)")
    #expect(steps[(flip + 1)...].contains { rising ? $0 < 0 : $0 > 0 }, "\(steps)")
  }

  /// The number of leading spaces of the first row.
  private static func indent(_ frame: AnimatableValueFrame) -> Int {
    frame.line(0).prefix { $0 == " " }.count
  }

  /// Every explicit opacity in a placed tree, in tree order.
  private static func explicitOpacities(in node: PlacedNode) -> [Double] {
    (node.drawMetadata.baseStyle.explicitOpacity.map { [$0] } ?? [])
      + node.children.flatMap(explicitOpacities)
  }

  /// What `count(_:in:)` counts.
  private enum KeyKind: Equatable {
    case value
    case property(AnimatableSlot)
  }

  /// The number of animations of one kind among `keys`.
  private static func count(_ kind: KeyKind, in keys: Set<AnimationKey>) -> Int {
    keys.filter { key in
      switch (kind, key.scope) {
      case (.value, .value): true
      case (.property(let slot), .property(let other)): slot == other
      default: false
      }
    }.count
  }

  /// The columns of the second row that the body's bar reaches.
  private static func barExtent(in frame: AnimatableValueFrame, _ use: ShapeUse) -> Int {
    let rows = frame.frame.split(separator: "\n", omittingEmptySubsequences: false)
    guard rows.count > 1 else { return 0 }
    let cells = Array(rows[1].prefix(20))
    switch use {
    case .fill, .clipShape:
      return cells.filter { $0 != " " }.count
    case .stroke:
      return (cells.lastIndex { $0 != " " } ?? -1) + 1
    }
  }
}

// MARK: - Fixtures

/// Where the `Animatable` conformer sits in the transition body.
enum BodySite: String, CaseIterable, Sendable, CustomStringConvertible {
  /// `AnyTransition.modifier(active:identity:)`, with `progress` 0 and 1.
  case activeIdentity
  /// A modifier around `content` in a custom `Transition`: a site at the
  /// identity the body resolves at.
  case modifier
  /// A view a custom `Transition` adds beside `content`: a site at a deeper
  /// identity.
  case view

  var description: String { rawValue }

  @MainActor
  func transition(_ log: AnimatableValueLog) -> AnyTransition {
    switch self {
    case .activeIdentity:
      .modifier(
        active: TraceShift(progress: 0, log: log), identity: TraceShift(progress: 1, log: log))
    case .modifier: AnyTransition(ShiftIn(log: log))
    case .view: AnyTransition(GaugeBeside(log: log))
    }
  }

  /// What the first row shows when the site ran with `value`.
  func expectedDrawing(at value: Double) -> String {
    switch self {
    case .activeIdentity, .modifier:
      String(repeating: " ", count: traceShiftIndent(value)) + "PRESENT"
    case .view:
      // A row is read without its trailing spaces.
      traceGaugeWidth(value) == 0
        ? "PRESENT" : "PRESENT " + String(repeating: "#", count: traceGaugeWidth(value))
    }
  }

  @MainActor
  func drawn(in frame: AnimatableValueFrame) -> String {
    frame.line(0)
  }
}

private func traceShiftIndent(_ progress: Double) -> Int {
  max(0, min(20, Int((10 * (1 - progress)).rounded())))
}

private func traceGaugeWidth(_ level: Double) -> Int {
  max(0, min(20, Int((10 * level).rounded())))
}

/// A modifier that conforms to `Animatable` and moves its content right by
/// ten columns at progress 0 and none at progress 1. Its body records the
/// data it ran with. The modifier is `@MainActor`, as every `ViewModifier`
/// is, and `Animatable`, which is nonisolated.
private struct TraceShift: ViewModifier, Animatable {
  var progress: Double
  let log: AnimatableValueLog

  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    let _ = log.values.append(progress)
    content.padding(.leading, traceShiftIndent(progress))
  }
}

/// A second `Animatable` modifier, which dims its content. It records to
/// the log's second channel, so it can sit beside `TraceShift`, unless it is
/// the only site of its test.
private struct TraceFade: ViewModifier, Animatable {
  var progress: Double
  let log: AnimatableValueLog
  var isOnlySite = false

  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    let _ = isOnlySite ? log.values.append(progress) : log.secondary.append(progress)
    content.opacity(0.25 + 0.75 * max(0, min(1, progress)))
  }
}

/// An `Animatable` modifier that gives its content a foreground style: red
/// at progress 1, blue at progress 0.
private struct TraceTint: ViewModifier, Animatable {
  var progress: Double
  let log: AnimatableValueLog

  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    let _ = log.values.append(progress)
    let amount = max(0, min(1, progress))
    content.foregroundStyle(Color(red: amount, green: 0, blue: 1 - amount))
  }
}

/// A body whose site writes the opacity of the content, inside a stack whose
/// own opacity differs between the phases.
private struct FadeInsideDim: Transition {
  let log: AnimatableValueLog

  func body(content: Content, phase: TransitionPhase) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      content.modifier(
        TraceFade(progress: phase.isIdentity ? 1 : 0, log: log, isOnlySite: true))
    }
    .opacity(phase.isIdentity ? 1 : 0.2)
  }
}

/// The modifier of the guide's "Drive A Transition With Your Own Modifier",
/// as it is printed there.
private struct Reveal: ViewModifier, Animatable {
  var progress: Double

  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    content
      .opacity(min(1, max(0, progress)))
      .padding(.leading, Int((4 * (1 - progress)).rounded()))
  }
}

/// The transition of the same section.
private struct RevealIn: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.modifier(Reveal(progress: phase.isIdentity ? 1 : 0))
  }
}

/// A view that conforms to `Animatable` and draws a bar of its level.
private struct TraceGauge: View, Animatable {
  var level: Double
  let log: AnimatableValueLog

  nonisolated var animatableData: Double {
    get { level }
    set { level = newValue }
  }

  var body: some View {
    let _ = log.values.append(level)
    Text(String(repeating: "#", count: traceGaugeWidth(level)))
  }
}

/// A custom transition whose body applies an `Animatable` modifier.
private struct ShiftIn: Transition {
  let log: AnimatableValueLog

  func body(content: Content, phase: TransitionPhase) -> some View {
    content.modifier(TraceShift(progress: phase.isIdentity ? 1 : 0, log: log))
  }
}

/// A custom transition whose body adds an `Animatable` view beside its
/// content, below the identity the body resolves at.
private struct GaugeBeside: Transition {
  let log: AnimatableValueLog

  func body(content: Content, phase: TransitionPhase) -> some View {
    HStack(spacing: 1) {
      content
      TraceGauge(level: phase.isIdentity ? 1 : 0, log: log)
    }
  }
}

/// A body that emits two views: its content under an `Animatable` modifier,
/// and a label.
private struct TwoRoots: Transition {
  let log: AnimatableValueLog

  func body(content: Content, phase: TransitionPhase) -> some View {
    content.modifier(TraceShift(progress: phase.isIdentity ? 1 : 0, log: log))
    Text("TAIL")
  }
}

/// A body that emits two views. The first is under an `Animatable` modifier
/// whose data, in the identity phase, is a value the view above supplies.
private struct LiveTwoRoots: Transition {
  var level: Double
  let log: AnimatableValueLog

  func body(content: Content, phase: TransitionPhase) -> some View {
    content.modifier(TraceShift(progress: phase.isIdentity ? level : 0, log: log))
    Text("TAIL")
  }
}

/// A body that dims its content and places an `Animatable` view inside a
/// `GeometryReader`, whose content resolves during layout.
private struct GaugeInGeometry: Transition {
  let log: AnimatableValueLog

  func body(content: Content, phase: TransitionPhase) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      content.opacity(phase.isIdentity ? 1 : 0.5)
      GeometryReader { _ in
        TraceGauge(level: phase.isIdentity ? 1 : 0, log: log)
      }
      .frame(width: 12, height: 1)
    }
  }
}

/// A body with an `Animatable` modifier and, on the same node, a plain
/// modifier whose value differs between the phases.
private struct ShiftAndFade: Transition {
  let log: AnimatableValueLog

  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .modifier(TraceShift(progress: phase.isIdentity ? 1 : 0, log: log))
      .opacity(phase.isIdentity ? 1 : 0.2)
  }
}

/// `ShiftIn`, counting the evaluations of its body by phase.
private struct CountedShift: Transition {
  let log: AnimatableValueLog

  func body(content: Content, phase: TransitionPhase) -> some View {
    let _ = log.count(
      phase == .willAppear ? "willAppear" : phase == .didDisappear ? "didDisappear" : "identity")
    content.modifier(TraceShift(progress: phase.isIdentity ? 1 : 0, log: log))
  }
}

/// A body with nothing that conforms to `Animatable`. It counts its own
/// evaluations.
private struct CountedDim: Transition {
  let log: AnimatableValueLog

  func body(content: Content, phase: TransitionPhase) -> some View {
    let _ = log.count("body")
    content.opacity(phase.isIdentity ? 1 : 0.2)
  }
}

/// A rectangle that covers the square of `fraction` of its width. The square
/// makes a sample differ from a morph of the two end paths.
private struct TraceBar: Shape, Animatable {
  var fraction: Double
  let log: AnimatableValueLog

  nonisolated var animatableData: Double {
    get { fraction }
    set { fraction = newValue }
  }

  func path(in rect: Rect) -> Path {
    log.values.append(fraction)
    let right = rect.origin.x + rect.size.width * fraction * fraction
    let bottom = rect.origin.y + rect.size.height
    var path = Path()
    path.move(to: Point(x: rect.origin.x, y: rect.origin.y))
    path.addLine(to: Point(x: right, y: rect.origin.y))
    path.addLine(to: Point(x: right, y: bottom))
    path.addLine(to: Point(x: rect.origin.x, y: bottom))
    path.closeSubpath()
    return path
  }
}

/// A body that draws an `Animatable` shape under its content, filled or
/// stroked.
private struct BarReveal: Transition {
  let use: ShapeUse
  let log: AnimatableValueLog

  func body(content: Content, phase: TransitionPhase) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      content
      bar(TraceBar(fraction: phase.isIdentity ? 1 : 0, log: log))
    }
  }

  @ViewBuilder
  private func bar(_ shape: TraceBar) -> some View {
    switch use {
    case .fill, .clipShape:
      shape.fill(Color.white).frame(width: 20, height: 2)
    case .stroke:
      shape.stroke(Color.white).frame(width: 20, height: 3)
    }
  }
}

/// Content with state of its own and lifecycle handlers.
private struct TraceCounter: View {
  @State private var count = 0
  let log: AnimatableValueLog

  var body: some View {
    let _ = log.count("content")
    Button("count \(count)") { count += 1 }
      .onAppear { log.appears += 1 }
      .onDisappear { log.disappears += 1 }
  }
}

// MARK: - Frames at fixed instants

/// One frame of `BodyFrames`: what the site ran with, and what was drawn.
private struct BodyFrameArtifacts {
  var values: [Double]
  var artifacts: FrameArtifacts
}

/// Renders one view under a transition through a renderer of its own at
/// fixed instants, so a frame can be prepared and aborted.
@MainActor
private final class BodyFrames<Content: View> {
  private let proposal = ProposedSize(width: .finite(30), height: .finite(3))
  private let animation = Animation.linear(duration: .milliseconds(800))

  let log = AnimatableValueLog()
  let renderer = DefaultRenderer()
  private let root: Identity
  private let start = MonotonicInstant(offset: .seconds(100))
  private let content: (Bool, AnimatableValueLog) -> Content

  init(
    named name: String,
    @ViewBuilder content: @escaping (Bool, AnimatableValueLog) -> Content
  ) {
    root = testIdentity("transition-body-animatable", "frames", name)
    self.content = content
  }

  var controller: AnimationController { renderer.internalAnimationController }

  func run(_ body: () -> Void) {
    withAnimationSinks(controller) {
      controller.register(animation)
      body()
    }
  }

  @discardableResult
  func render(shown: Bool, animated: Bool = false, at offset: Int) -> FrameArtifacts {
    renderer.renderArtifacts(
      view(shown), context: .init(identity: root, transaction: transaction(animated)),
      proposal: proposal, frameInstant: start.advanced(by: .milliseconds(offset)))
  }

  func abort(shown: Bool, animated: Bool = false, at offset: Int) {
    let draft = renderer.prepareFrameHeadForCancellationTesting(
      view(shown), context: .init(identity: root, transaction: transaction(animated)),
      proposal: proposal, frameInstant: start.advanced(by: .milliseconds(offset)))
    renderer.abortPreparedFrameHeadForCancellationTesting(draft)
  }

  /// Renders the view at rest, then one frame at each offset: the first
  /// flips its presence under the linear transaction, and the later ones
  /// are ticks. Returns the data the site ran with during each frame and
  /// what the frame drew.
  func artifacts(removing: Bool, at offsets: [Int]) -> [BodyFrameArtifacts] {
    var frames: [BodyFrameArtifacts] = []
    run {
      render(shown: removing, at: -33)
      for offset in offsets {
        let before = log.values.count
        let artifacts = render(shown: !removing, animated: offset == offsets[0], at: offset)
        frames.append(
          BodyFrameArtifacts(values: Array(log.values[before...]), artifacts: artifacts))
      }
    }
    return frames
  }

  /// The data the site ran with during each frame of ``artifacts(removing:at:)``.
  func values(removing: Bool, at offsets: [Int]) -> [[Double]] {
    artifacts(removing: removing, at: offsets).map(\.values)
  }

  /// The same through the abortable frame path.
  func valuesAsync(removing: Bool, at offsets: [Int]) async -> [[Double]] {
    var frames: [[Double]] = []
    let animation = animation
    await withAnimationSinks(controller) {
      controller.register(animation)
      _ = await renderer.renderArtifactsAsync(
        view(removing), context: .init(identity: root, transaction: transaction(false)),
        proposal: proposal, frameInstant: start.advanced(by: .milliseconds(-33)))
      for offset in offsets {
        let before = log.values.count
        _ = await renderer.renderArtifactsAsync(
          view(!removing),
          context: .init(identity: root, transaction: transaction(offset == offsets[0])),
          proposal: proposal, frameInstant: start.advanced(by: .milliseconds(offset)))
        frames.append(Array(log.values[before...]))
      }
    }
    return frames
  }

  private func view(_ shown: Bool) -> some View {
    BodyFramesHost(shown: shown, log: log, content: content)
  }

  private func transaction(_ animated: Bool) -> TransactionSnapshot {
    var transaction = TransactionSnapshot()
    if animated {
      transaction.animationRequest = .animate(animation.animationBox)
    }
    return transaction
  }
}

private struct BodyFramesHost<Content: View>: View {
  let shown: Bool
  let log: AnimatableValueLog
  let content: (Bool, AnimatableValueLog) -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("HEADER")
      content(shown, log)
    }
  }
}

/// The view most frame tests render: `modifier(active:identity:)` around a
/// modifier that conforms to `Animatable`.
@MainActor
@ViewBuilder
private func shiftedText(_ shown: Bool, _ log: AnimatableValueLog) -> some View {
  if shown {
    Text("PRESENT").transition(
      .modifier(
        active: TraceShift(progress: 0, log: log),
        identity: TraceShift(progress: 1, log: log)))
  }
}
