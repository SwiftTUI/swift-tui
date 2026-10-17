@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized, FailOnSoundnessViolationGrowth(), .timeLimit(.minutes(1)))
struct AdversarialSetAGestureCompositionTests {
  @Test func setA701SimultaneousCompletionFreezesItsValueWhileTheOtherChildContinues() throws {
    // Hypothesis: a simultaneous composite keeps changing its terminal value as its unfinished child moves.
    let log = SetAGestureLog()
    let h = try make("701") {
      pad.gesture(
        LongPressGesture(minimumDuration: .seconds(10), maximumDistance: 20)
          .simultaneously(with: DragGesture().onEnded { log.drags.append($0) })
          .map { Int($0.second?.translation.dx ?? -1) }
          .onChanged { log.changes.append($0) }
          .onEnded { log.ends.append($0) })
    }
    defer { h.shutdown() }
    let p = try point(h)
    let t = MonotonicInstant.now()
    try mouse(.down(.primary), at: p, time: t, in: h)
    try mouse(.dragged(.primary), at: shifted(p, 2), time: t.advanced(by: .seconds(1)), in: h)
    try #require(log.changes == [0, 2])
    h.runLoop.drainGestureDeadlines(at: t.advanced(by: .seconds(11)))
    try h.render()
    try #require(log.ends == [2])
    try mouse(.dragged(.primary), at: shifted(p, 9), time: t.advanced(by: .seconds(12)), in: h)
    try mouse(.up(.primary), at: shifted(p, 9), time: t.advanced(by: .seconds(13)), in: h)
    #expect(log.changes == [0, 2] && log.ends == [2])
    #expect(log.drags.map(\.translation.dx) == [9])
  }

  @Test func setA702ExclusiveFallbackReplaysThePrefixExactlyOnce() throws {
    // Hypothesis: failure on release loses or duplicates the down event buffered for an exclusive fallback.
    let log = SetAGestureLog()
    let h = try make("702") {
      pad.gesture(
        LongPressGesture(minimumDuration: .seconds(30)).map { _ in 1 }
          .exclusively(before: TapGesture().map { _ in 2 })
          .onEnded { log.ends.append($0) })
    }
    defer { h.shutdown() }
    let p = try point(h)
    let t = MonotonicInstant.now()
    try mouse(.down(.primary), at: p, time: t, in: h)
    #expect(log.ends.isEmpty)
    try mouse(.up(.primary), at: p, time: t.advanced(by: .milliseconds(10)), in: h)
    #expect(log.ends == [2])
    h.runLoop.drainGestureDeadlines(at: t.advanced(by: .seconds(40)))
    try h.render()
    #expect(log.ends == [2])
  }

  @Test func setA703SequenceCompletionEventCannotAlsoCompleteItsSecondStage() throws {
    // Hypothesis: a sequence forwards the first child's terminating release into the second child.
    let log = SetAGestureLog()
    let h = try make("703") {
      pad.gesture(
        TapGesture().onEnded { log.events.append("first") }
          .sequenced(before: TapGesture().onEnded { log.events.append("second") })
          .onEnded { _ in log.events.append("sequence") })
    }
    defer { h.shutdown() }
    try h.clickText("Gesture pad")
    #expect(log.events == ["first"])
    try h.clickText("Gesture pad")
    #expect(log.events == ["first", "second", "sequence"])
  }

  @Test func setA704HostCancellationCannotRecognizeAnExclusiveFallback() throws {
    // Hypothesis: cancellation is treated as first-child failure and replays a successful fallback action.
    let log = SetAGestureLog()
    let h = try make("704") {
      pad.gesture(
        LongPressGesture(minimumDuration: .seconds(30)).map { _ in 1 }
          .exclusively(before: TapGesture().map { _ in 2 })
          .onEnded { log.ends.append($0) })
    }
    defer { h.shutdown() }
    let p = try point(h)
    try h.sendMouse(.down(.primary), at: p)
    try h.sendMouse(.cancelled, at: p)
    try h.sendMouse(.up(.primary), at: p)
    #expect(log.ends.isEmpty)
    try h.clickText("Gesture pad")
    #expect(log.ends == [2])
  }

  @Test func setA705FailedSequenceRearmsBothChildRecognizers() throws {
    // Hypothesis: rearming a failed first stage leaves the later stage or composite completion latch terminal.
    let log = SetAGestureLog()
    let h = try make("705") {
      pad.gesture(
        TapGesture().sequenced(before: DragGesture())
          .onEnded { value in
            if case .second(_, let drag) = value {
              log.ends.append(Int(drag?.translation.dx ?? -1))
            }
          })
    }
    defer { h.shutdown() }
    let p = try point(h)
    try h.drag(from: p, to: shifted(p, 2))
    try #require(log.ends.isEmpty)
    try h.clickText("Gesture pad")
    try h.drag(from: p, to: shifted(p, 4))
    #expect(log.ends == [4])
  }

  @Test func setA706RemovingAGestureMaskDiscardsItsPartialTapSequence() throws {
    // Hypothesis: a disabled gesture's retired multi-tap recognizer contributes old taps after re-enabling.
    TapGesture.interTapWindowOverride = .seconds(86_400)
    defer { TapGesture.interTapWindowOverride = nil }
    let log = SetAGestureLog()
    let h = try make("706") {
      pad.gesture(
        TapGesture(count: 2).onEnded { log.events.append("double") },
        including: log.flag ? .none : .all)
    }
    defer { h.shutdown() }
    try h.clickText("Gesture pad")
    try #require(log.events.isEmpty)
    log.flag = true
    try h.renderAfterExternalMutation()
    try #require(h.gestureRecognizerCount == 0)
    log.flag = false
    try h.renderAfterExternalMutation()
    try h.clickText("Gesture pad")
    #expect(log.events.isEmpty)
    try h.clickText("Gesture pad")
    #expect(log.events == ["double"])
  }

  @Test func setA707HighPriorityRecognitionSuppressesOrdinaryButNotSimultaneousPeers() throws {
    // Hypothesis: priority arbitration suppresses every attachment after a winner, including simultaneous peers.
    let log = SetAGestureLog()
    let h = try make("707") {
      Button("Gesture pad") { log.events.append("button") }
        .gesture(TapGesture().onEnded { log.events.append("ordinary") })
        .highPriorityGesture(TapGesture().onEnded { log.events.append("priority") })
        .simultaneousGesture(TapGesture().onEnded { log.events.append("simultaneous") })
    }
    defer { h.shutdown() }
    try h.clickText("Gesture pad")
    #expect(log.events.sorted() == ["priority", "simultaneous"])
  }

  @Test func setA708SubviewsMaskExcludesOnlyItsOwnAttachedRecognizer() throws {
    // Hypothesis: excluding the parent's attachment also suppresses child recognizers allowed by .subviews.
    let log = SetAGestureLog()
    let h = try make("708") {
      VStack {
        pad.gesture(TapGesture().onEnded { log.events.append("child") })
      }.gesture(TapGesture().onEnded { log.events.append("parent") }, including: .subviews)
    }
    defer { h.shutdown() }
    try h.clickText("Gesture pad")
    #expect(log.events == ["child"])
  }

  @Test func setA709FailedOrdinaryTapCannotStopItsSimultaneousDrag() throws {
    // Hypothesis: one attachment's movement failure terminates the independent simultaneous pointer stream.
    let log = SetAGestureLog()
    let h = try make("709") {
      pad.gesture(TapGesture().onEnded { log.events.append("tap") })
        .simultaneousGesture(DragGesture().onEnded { log.drags.append($0) })
    }
    defer { h.shutdown() }
    let p = try point(h)
    try h.drag(from: p, to: shifted(p, 3))
    #expect(log.events.isEmpty)
    #expect(log.drags.map(\.translation.dx) == [3])
  }

  @Test func setA710MissingNamedGestureSpaceFallsBackToTheGlobalPoint() throws {
    // Hypothesis: a missing named coordinate-space frame falls back to target-local coordinates.
    let log = SetAGestureLog()
    let h = try make("710") {
      HStack(spacing: 0) {
        Spacer().frame(width: 13)
        pad.gesture(
          SpatialTapGesture(coordinateSpace: .named("absent")).onEnded { log.taps.append($0) })
      }
    }
    defer { h.shutdown() }
    let p = try point(h)
    try clickPrecisely(p, in: h)
    #expect(try #require(log.taps.first).location == p)
  }

  @Test func setA711SameDescriptionNamedSpacesRetainTheirTypedKeysAtDispatch() throws {
    // Hypothesis: event-space publication conflates Int(1) and String("1") after correctly laying them out.
    let log = SetAGestureLog()
    let h = try make("711") {
      VStack(alignment: .leading, spacing: 0) {
        Text("Numeric origin").frame(height: 2).coordinateSpace(.named(1))
        Text("String origin").frame(height: 3).coordinateSpace(.named("1"))
        pad.gesture(SpatialTapGesture(coordinateSpace: .named(1)).onEnded { log.taps.append($0) })
      }
    }
    defer { h.shutdown() }
    let spaces = h.runLoop.latestSemanticSnapshot.namedCoordinateSpaces
    let numeric = try #require(spaces[.named(1)])
    let string = try #require(spaces[.named("1")])
    try #require(numeric.origin.y != string.origin.y)
    let p = try point(h)
    try clickPrecisely(p, in: h)
    let value = try #require(log.taps.first)
    #expect(
      value.location == .init(x: p.x - Double(numeric.origin.x), y: p.y - Double(numeric.origin.y)))
  }

  @Test func setA712DragPathIncludesTheDistinctReleaseSampleAndTimestamp() throws {
    // Hypothesis: completion reuses the last dragged sample and drops a release at a new position.
    let log = SetAGestureLog()
    let h = try make("712") { pad.gesture(DragGesture().onEnded { log.drags.append($0) }) }
    defer { h.shutdown() }
    let p = try point(h)
    let t = MonotonicInstant.now()
    try mouse(.down(.primary), at: p, time: t, in: h)
    try mouse(.dragged(.primary), at: shifted(p, 2), time: t.advanced(by: .milliseconds(10)), in: h)
    let release = t.advanced(by: .milliseconds(20))
    try mouse(.up(.primary), at: shifted(p, 4), time: release, in: h)
    let value = try #require(log.drags.first)
    #expect(value.path.count == 3)
    #expect(value.path.last?.time == release && value.time == release)
    #expect(value.path.last?.location == value.location)
    #expect(value.translation.dx == 4)
  }

  @Test func setA713SavedPointerPathDoesNotAliasTheNextGesturesSampleBuffer() throws {
    // Hypothesis: retained drag values share mutable sample storage cleared or extended when a new stroke starts.
    let log = SetAGestureLog()
    let h = try make("713") { pad.gesture(DragGesture().onEnded { log.drags.append($0) }) }
    defer { h.shutdown() }
    let p = try point(h)
    try h.drag(from: p, to: shifted(p, 2))
    let saved = try #require(log.drags.first).path
    try #require(saved.count == 3)
    try h.drag(from: shifted(p, 1), to: shifted(p, 6))
    try #require(log.drags.count == 2)
    #expect(log.drags[0].path == saved)
    #expect(log.drags[1].translation.dx == 5)
    #expect(log.drags[1].path != saved)
  }

  @Test func setA714ZeroTimestampSpanProducesFiniteZeroDragVelocity() throws {
    // Hypothesis: coalesced events sharing one timestamp divide by zero in velocity and end prediction.
    let log = SetAGestureLog()
    let h = try make("714") { pad.gesture(DragGesture().onEnded { log.drags.append($0) }) }
    defer { h.shutdown() }
    let p = try point(h)
    let t = MonotonicInstant.now()
    try mouse(.down(.primary), at: p, time: t, in: h)
    try mouse(.dragged(.primary), at: shifted(p, 3), time: t, in: h)
    try mouse(.up(.primary), at: shifted(p, 3), time: t, in: h)
    let value = try #require(log.drags.first)
    #expect(value.velocity == .zero)
    #expect(value.predictedEndTranslation == value.translation)
    #expect(value.predictedEndLocation == value.location)
  }

  @Test func setA715DragVelocityUsesTheRecentSegmentInsteadOfTheWholeStroke() throws {
    // Hypothesis: a long pause leaves the initial stroke sample in the trailing velocity estimate.
    let log = SetAGestureLog()
    let h = try make("715") { pad.gesture(DragGesture().onEnded { log.drags.append($0) }) }
    defer { h.shutdown() }
    let p = try point(h)
    let t = MonotonicInstant.now()
    try mouse(.down(.primary), at: p, time: t, in: h)
    try mouse(.dragged(.primary), at: shifted(p, 2), time: t.advanced(by: .seconds(1)), in: h)
    try mouse(
      .dragged(.primary), at: shifted(p, 7), time: t.advanced(by: .milliseconds(1050)), in: h)
    try mouse(.up(.primary), at: shifted(p, 12), time: t.advanced(by: .milliseconds(1100)), in: h)
    let value = try #require(log.drags.first)
    #expect(abs(value.velocity.dx - 100) < 1e-8)
    #expect(abs(value.predictedEndTranslation.dx - 37) < 1e-8)
  }

  @Test func setA716SubthresholdDragCannotEmitChangesOrCompletion() throws {
    // Hypothesis: the release branch recognizes a drag that never reached its authored minimum distance.
    let log = SetAGestureLog()
    let h = try make("716") {
      pad.gesture(
        DragGesture(minimumDistance: 4)
          .onChanged { log.changes.append(Int($0.translation.dx)) }
          .onEnded { log.drags.append($0) })
    }
    defer { h.shutdown() }
    let p = try point(h)
    try h.drag(from: p, to: shifted(p, 3))
    #expect(log.changes.isEmpty && log.drags.isEmpty)
    try h.drag(from: p, to: shifted(p, 4))
    #expect(!log.changes.isEmpty)
    #expect(log.drags.map(\.translation.dx) == [4])
  }

  @Test func setA717SpatialTapPreservesFractionalCoordinatesAndHostProvenance() throws {
    // Hypothesis: normalization rounds local tap values or reconstructs their original pointer as cell-only.
    let log = SetAGestureLog()
    let h = try make("717") {
      HStack(spacing: 0) {
        Spacer().frame(width: 7)
        pad.gesture(SpatialTapGesture().onEnded { log.taps.append($0) })
      }
    }
    defer { h.shutdown() }
    let p = try point(h)
    let region = try #require(
      h.runLoop.latestSemanticSnapshot.interactionRegions.last {
        $0.rect.contains(p.containingCell)
      })
    let precise = Point(x: Double(p.containingCell.x) + 0.125, y: Double(p.containingCell.y) + 0.75)
    let pointer = PointerLocation.subCell(
      location: precise, source: .webPixels,
      metrics: .init(width: 8, height: 16, source: .reported), rawPixel: .init(x: 101, y: 203))
    let t = MonotonicInstant.now()
    try event(.init(kind: .down(.primary), location: pointer, timestamp: t), in: h)
    try event(
      .init(kind: .up(.primary), location: pointer, timestamp: t.advanced(by: .milliseconds(5))),
      in: h)
    let value = try #require(log.taps.first)
    #expect(value.pointer == pointer)
    #expect(
      value.location
        == .init(
          x: precise.x - Double(region.rect.origin.x), y: precise.y - Double(region.rect.origin.y)))
  }

  @Test func setA718MappedChangedCallbacksDeduplicateTheMappedValue() throws {
    // Hypothesis: onChanged compares raw child values and repeats a callback whose mapped value is unchanged.
    let log = SetAGestureLog()
    let h = try make("718") {
      pad.gesture(
        DragGesture().map { _ in 42 }
          .onChanged { log.changes.append($0) }.onEnded { log.ends.append($0) })
    }
    defer { h.shutdown() }
    let p = try point(h)
    try h.drag(from: p, to: shifted(p, 5))
    #expect(log.changes == [42] && log.ends == [42])
  }

  @Test func setA719StackedEndedDecoratorsEachFireOnceInWrappingOrder() throws {
    // Hypothesis: one completion latch suppresses an outer decorator or fires it before its inner callback.
    let log = SetAGestureLog()
    let h = try make("719") {
      pad.gesture(
        TapGesture().onEnded { log.events.append("inner") }
          .onEnded { log.events.append("outer") })
    }
    defer { h.shutdown() }
    try h.clickText("Gesture pad")
    #expect(log.events == ["inner", "outer"])
    try h.clickText("Gesture pad")
    #expect(log.events == ["inner", "outer", "inner", "outer"])
  }

  @Test func setA720ActiveDragAdoptsNewCallbacksWithoutLosingItsBeginning() throws {
    // Hypothesis: reauthoring a callback either keeps its obsolete capture or replaces the in-flight recognizer.
    let log = SetAGestureLog()
    let h = try make("720") {
      let revision = log.revision
      pad.gesture(
        DragGesture().onChanged { _ in log.changes.append(revision) }
          .onEnded {
            log.ends.append(revision)
            log.drags.append($0)
          })
    }
    defer { h.shutdown() }
    let p = try point(h)
    try h.sendMouse(.down(.primary), at: p)
    try #require(log.changes == [0])
    log.revision = 7
    try h.renderAfterExternalMutation()
    try h.sendMouse(.dragged(.primary), at: shifted(p, 4))
    try h.sendMouse(.up(.primary), at: shifted(p, 4))
    #expect(log.changes.last == 7 && log.changes.dropFirst().allSatisfy { $0 == 7 })
    #expect(log.ends == [7])
    let value = try #require(log.drags.first)
    #expect(value.translation.dx == 4 && value.path.count == 3)
  }

  @Test func setA721IgnoredWheelEventBubblesUnchangedAndStopsAtAHandler() throws {
    // Hypothesis: wheel fallback normalizes away an axis or continues outward after a child claims the event.
    let log = SetAGestureLog()
    let h = try make("721") {
      VStack {
        pad.onScrollWheel { delta in
          log.events.append("inner:\(delta.deltaX),\(delta.deltaY)")
          return log.flag ? .handled : .ignored
        }
      }.onScrollWheel { delta in
        log.events.append("outer:\(delta.deltaX),\(delta.deltaY)")
        return .handled
      }
    }
    defer { h.shutdown() }
    let p = try point(h)
    try h.scrollPointer(at: p, deltaX: -3, deltaY: 5)
    #expect(log.events == ["inner:-3,5", "outer:-3,5"])
    log.flag = true
    try h.renderAfterExternalMutation()
    try h.scrollPointer(at: p, deltaX: 2, deltaY: -4)
    #expect(log.events == ["inner:-3,5", "outer:-3,5", "inner:2,-4"])
  }

  @Test func setA722StationaryPointerExitsARegionMovedByLayout() throws {
    // Hypothesis: hover continuity follows a retained identity after its geometry leaves the stationary pointer.
    let log = SetAGestureLog()
    let h = try make("722") {
      HStack(spacing: 0) {
        Spacer().frame(width: log.revision)
        Text("Hover pad").onPointerHover { log.recordHover($0, prefix: "hover") }
      }
    }
    defer { h.shutdown() }
    let p = try #require(h.point(forText: "Hover pad"))
    try h.movePointer(to: p)
    try #require(log.events == ["hover:entered"])
    log.revision = 25
    try h.renderAfterExternalMutation()
    #expect(log.events == ["hover:entered", "hover:exited"])
    let moved = try #require(h.point(forText: "Hover pad"))
    try h.movePointer(to: moved)
    #expect(log.events == ["hover:entered", "hover:exited", "hover:entered"])
  }

  @Test func setA723StackedHoverSubscriptionsRemainIndependentlyBalanced() throws {
    // Hypothesis: registering the second hover modifier replaces the first subscriber on their shared route.
    let log = SetAGestureLog()
    let h = try make("723") {
      pad.onPointerHover { log.recordHover($0, prefix: "first") }
        .onPointerHover { log.recordHover($0, prefix: "second") }
    }
    defer { h.shutdown() }
    try h.movePointer(to: point(h))
    try h.movePointer(to: .init(x: 59, y: 15))
    #expect(
      log.events.sorted() == ["first:entered", "first:exited", "second:entered", "second:exited"])
  }

  @Test func setA724CustomGestureBodyForwardsItsPointerCaptureRequirement() throws {
    // Hypothesis: a user-defined Gesture body forwards recognizer construction but loses its capture capability.
    let log = SetAGestureLog()
    #expect(SetAWrappedDrag._needsPointerCapture)
    let h = try make("724") { pad.gesture(SetAWrappedDrag().onEnded { log.ends.append($0) }) }
    defer { h.shutdown() }
    let p = try point(h)
    try h.drag(from: p, to: shifted(p, 35))
    #expect(log.ends == [35])
  }

  @Test func setA725DeclinedInnerDropPreservesTheFullPayloadForItsAncestor() throws {
    // Hypothesis: a declining nested destination consumes, rewrites, or double-delivers the original spatial drop.
    let log = SetAGestureLog()
    let paths: [DroppedPath] = [.init("/tmp/first file"), .init("/tmp/second")]
    let h = try make("725") {
      Panel(id: "set-a-drop-outer") {
        Panel(id: "set-a-drop-inner") { Text("Drop pad").focusable() }
          .dropDestination { delivered, context in
            log.events.append("inner")
            log.dropPaths.append(delivered)
            log.dropContexts.append(context)
            return false
          }
      }.dropDestination { delivered, context in
        log.events.append("outer")
        log.dropPaths.append(delivered)
        log.dropContexts.append(context)
        return true
      }
    }
    defer { h.shutdown() }
    let p = try #require(h.point(forText: "Drop pad"))
    try h.drop(paths: paths, context: .init(location: p, modifiers: [.ctrl, .shift]))
    #expect(log.events == ["inner", "outer"])
    #expect(log.dropPaths == [paths, paths])
    #expect(log.dropContexts.count == 2)
    #expect(log.dropContexts.allSatisfy { $0.location == p && $0.modifiers == [.ctrl, .shift] })
  }

  private var pad: some View { Text("Gesture pad").frame(width: 20, height: 3) }

  private func make<V: View>(_ id: String, @ViewBuilder content: @escaping () -> V) throws
    -> StressRuntimeHarness<V>
  {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetAGestureComposition", id),
      size: .init(width: 60, height: 16), content: content)
  }

  private func point<V: View>(_ h: StressRuntimeHarness<V>) throws -> Point {
    try #require(h.point(forText: "Gesture pad"))
  }

  private func shifted(_ point: Point, _ x: Double) -> Point {
    .init(x: point.x + x, y: point.y)
  }

  private func mouse<V: View>(
    _ kind: MouseEvent.Kind, at point: Point, time: MonotonicInstant, in h: StressRuntimeHarness<V>
  ) throws {
    try event(
      .init(
        kind: kind,
        location: .subCell(
          location: point, source: .nativePixels,
          metrics: .init(width: 8, height: 16, source: .reported)),
        timestamp: time), in: h)
  }

  private func event<V: View>(_ event: MouseEvent, in h: StressRuntimeHarness<V>) throws {
    #expect(h.runLoop.handle(.input(.mouse(event))) == nil)
    try h.render()
  }

  private func clickPrecisely<V: View>(_ point: Point, in h: StressRuntimeHarness<V>) throws {
    let t = MonotonicInstant.now()
    try mouse(.down(.primary), at: point, time: t, in: h)
    try mouse(.up(.primary), at: point, time: t.advanced(by: .milliseconds(5)), in: h)
  }
}

@MainActor
private final class SetAGestureLog {
  var events: [String] = []
  var changes: [Int] = []
  var ends: [Int] = []
  var drags: [DragGesture.Value] = []
  var taps: [SpatialTapGesture.Value] = []
  var dropPaths: [[DroppedPath]] = []
  var dropContexts: [DropContext] = []
  var flag = false
  var revision = 0

  func recordHover(_ phase: HoverPhase, prefix: String) {
    switch phase {
    case .entered: events.append("\(prefix):entered")
    case .moved: events.append("\(prefix):moved")
    case .exited: events.append("\(prefix):exited")
    }
  }
}

@MainActor
private struct SetAWrappedDrag: Gesture {
  typealias Value = Int

  var body: some Gesture<Int> { DragGesture().map { Int($0.translation.dx) } }
}
