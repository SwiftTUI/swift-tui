// Adversarial set B: gesture and pointer state machines.
//
// Bug class: pointer streams that end irregularly — stage hand-offs inside
// sequenced/exclusive composites, releases that do not match their press
// (foreign button, off-target, stale host geometry, host cancel) and no-op
// control interactions. Motivated by the Sept–Oct 2026 reports STUI-554,
// STUI-569, STUI-588, STUI-709, STUI-712 and STUI-912, plus the Detail
// reports on `sequenced(before:)` stage two, taps after a returning drag,
// duplicate long-press updates and the Slider no-op setter.

import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: gestures", .serialized)
struct AdversarialSetBGestureTests {
  // MARK: - Recognizer level

  @Test func setB021SequencedLongPressThenDragMustSettleOnRelease() throws {
    var armed: [MonotonicInstant] = []
    var ends: [SequenceGesture<LongPressGesture, DragGesture>.Value] = []
    let rec = LongPressGesture(minimumDuration: .milliseconds(100))
      .sequenced(before: DragGesture())
      .onEnded { ends.append($0) }
      ._makeRecognizer(
        context: setBContext("Sequenced", requestDeadline: { armed.append($0) }))
    let t0 = MonotonicInstant.now()
    let origin = Point(x: 1, y: 0)
    func at(_ milliseconds: Int) -> MonotonicInstant {
      t0.advanced(by: .milliseconds(milliseconds))
    }

    // A press released before the hold completes fails stage one outright.
    _ = rec.handle(event: setBEvent(.down(.primary), at: origin, timestamp: t0))
    #expect(armed.count == 1)
    let early = rec.handle(event: setBEvent(.up(.primary), at: origin, timestamp: at(10)))
    #expect(early == .failed)
    #expect(rec.phase == .failed)
    #expect(!rec.isActive)
    #expect(ends.isEmpty)
    let firstDeadline = try #require(armed.first)
    #expect(!rec.handleDeadline(at: firstDeadline))

    // Hold through the deadline, then release without moving.
    rec.reArm()
    _ = rec.handle(event: setBEvent(.down(.primary), at: origin, timestamp: at(200)))
    #expect(armed.count == 2)
    let secondDeadline = try #require(armed.last)
    #expect(rec.handleDeadline(at: secondDeadline))
    #expect(rec.phase == .began)
    #expect(rec.isActive)
    _ = rec.handle(event: setBEvent(.up(.primary), at: origin, timestamp: at(350)))
    // Contract: the release ends the pointer stream; nothing stays active.
    #expect(!rec.isActive, "stage two must settle when the pointer lifts")
    #expect(rec.phase.isTerminal)
    let endsAfterRelease = ends.count

    // A later quick tap is a new interaction and cannot complete the
    // long-press-then-drag sequence on its own.
    rec.reArm()
    _ = rec.handle(event: setBEvent(.down(.primary), at: origin, timestamp: at(400)))
    _ = rec.handle(event: setBEvent(.up(.primary), at: origin, timestamp: at(410)))
    #expect(ends.count == endsAfterRelease, "a quick tap cannot finish a long-press sequence")
  }

  @Test func setB022ExclusiveDragFallbackFollowsLivePointerNotReplayedRelease() throws {
    var changes: [Double] = []
    var ends: [Double] = []
    let rec = TapGesture(count: 2).map { _ in 0.0 }
      .exclusively(before: DragGesture().map { $0.translation.dx })
      .onChanged { changes.append($0) }
      .onEnded { ends.append($0) }
      ._makeRecognizer(context: setBContext("ExclusiveReplay"))
    let t0 = MonotonicInstant.now()
    let origin = Point(x: 1, y: 0)
    let moved = Point(x: 3, y: 0)

    _ = rec.handle(event: setBEvent(.down(.primary), at: origin, timestamp: t0))
    _ = rec.handle(event: setBEvent(.up(.primary), at: origin, timestamp: t0))
    _ = rec.handle(
      event: setBEvent(
        .down(.primary), at: origin, timestamp: t0.advanced(by: .milliseconds(100))))
    #expect(changes.isEmpty)
    #expect(ends.isEmpty)

    // The second press moves: the double tap gives up and the drag takes
    // over the live press. Its evidence is the pointer, not the first tap's
    // already-consumed release.
    _ = rec.handle(
      event: setBEvent(
        .dragged(.primary), at: moved, timestamp: t0.advanced(by: .milliseconds(150))))
    #expect(!rec.phase.isTerminal, "the fallback drag is still following the pointer")
    #expect(changes.last == 2, "the drag reports the live translation")
    _ = rec.handle(
      event: setBEvent(
        .up(.primary), at: moved, timestamp: t0.advanced(by: .milliseconds(200))))
    #expect(rec.phase == .ended)
    #expect(ends == [2])
  }

  @Test func setB023DoubleTapSecondPressOutsideTargetDoesNotCount() throws {
    let t0 = MonotonicInstant.now()
    let inside = Point(x: 1, y: 0)
    let outside = Point(x: 100, y: 100)
    let later = t0.advanced(by: .milliseconds(50))
    let release = t0.advanced(by: .milliseconds(60))

    // A stray second press that also releases off target fails the sequence.
    var fired = 0
    let rec = TapGesture(count: 2).onEnded { fired += 1 }
      ._makeRecognizer(context: setBContext("DoubleTapOutsideUp"))
    _ = rec.handle(event: setBEvent(.down(.primary), at: inside, timestamp: t0))
    _ = rec.handle(event: setBEvent(.up(.primary), at: inside, timestamp: t0))
    #expect(rec.phase == .possible)
    _ = rec.handle(event: setBEvent(.down(.primary), at: outside, timestamp: later))
    _ = rec.handle(event: setBEvent(.up(.primary), at: outside, timestamp: release))
    #expect(rec.phase == .failed)
    #expect(fired == 0)

    // Same shape, but the stray press releases back over the target. A tap
    // is a press that begins AND ends on the target, so this is no tap.
    var firedInsideUp = 0
    let probe = TapGesture(count: 2).onEnded { firedInsideUp += 1 }
      ._makeRecognizer(context: setBContext("DoubleTapInsideUp"))
    _ = probe.handle(event: setBEvent(.down(.primary), at: inside, timestamp: t0))
    _ = probe.handle(event: setBEvent(.up(.primary), at: inside, timestamp: t0))
    _ = probe.handle(event: setBEvent(.down(.primary), at: outside, timestamp: later))
    _ = probe.handle(event: setBEvent(.up(.primary), at: inside, timestamp: release))
    #expect(probe.phase != .ended, "a press that begins off-target is not a tap")
    #expect(firedInsideUp == 0)
  }

  @Test func setB024ExclusiveDeadlineAfterEventTimeFailureReportsNoTransition() throws {
    var armed: [MonotonicInstant] = []
    var fired = 0
    let rec = TapGesture(count: 2).exclusively(before: TapGesture())
      .onEnded { fired += 1 }
      ._makeRecognizer(
        context: setBContext("ExclusiveDeadline", requestDeadline: { armed.append($0) }))
    let t0 = MonotonicInstant.now()
    let origin = Point(x: 1, y: 0)

    _ = rec.handle(event: setBEvent(.down(.primary), at: origin, timestamp: t0))
    _ = rec.handle(event: setBEvent(.up(.primary), at: origin, timestamp: t0))
    let window = try #require(armed.first)
    #expect(fired == 0)

    // The next press lands exactly when the inter-tap window closes: the
    // double tap fails at event time and the single-tap fallback recognizes
    // from the replayed first tap.
    _ = rec.handle(event: setBEvent(.down(.primary), at: origin, timestamp: window))
    #expect(rec.phase == .ended)
    #expect(fired == 1)

    // The scheduler wake for that same window then drains with nothing left
    // to transition: `handleDeadline` reports a transition only when one
    // happened as a result of the call.
    #expect(!rec.handleDeadline(at: window), "no transition happened on this deadline")
    #expect(fired == 1)
    _ = rec.handle(
      event: setBEvent(.up(.primary), at: origin, timestamp: window.advanced(by: .milliseconds(1))))
    #expect(fired == 1)
    #expect(rec.phase == .ended)
  }

  @Test func setB025LongPressEndedExactlyAtDeadlineIgnoresCancelAndLateRelease() throws {
    var armed: [MonotonicInstant] = []
    var fired: [Bool] = []
    let rec = LongPressGesture(minimumDuration: .milliseconds(50))
      .onEnded { fired.append($0) }
      ._makeRecognizer(
        context: setBContext("LongPressBoundary", requestDeadline: { armed.append($0) }))
    let t0 = MonotonicInstant.now()

    _ = rec.handle(event: setBEvent(.down(.primary), timestamp: t0))
    let deadline = try #require(armed.first)
    #expect(deadline == t0.advanced(by: .milliseconds(50)))
    #expect(rec.handleDeadline(at: deadline))
    #expect(rec.phase == .ended)
    #expect(fired == [true])

    // A host cancel after recognition and a late release change nothing.
    let cancel = rec.handle(
      event: setBEvent(.cancelled, timestamp: deadline.advanced(by: .milliseconds(1))))
    #expect(cancel == .ignored)
    let lateRelease = rec.handle(
      event: setBEvent(.up(.primary), timestamp: deadline.advanced(by: .milliseconds(10))))
    #expect(lateRelease == .ignored)
    #expect(!rec.handleDeadline(at: deadline.advanced(by: .seconds(1))))
    #expect(fired == [true])
    #expect(rec.currentValue(as: Bool.self) == true)

    // Release boundary: one nanosecond short fails, the exact instant ends.
    var shortFired = 0
    let short = LongPressGesture(minimumDuration: .milliseconds(50))
      .onEnded { _ in shortFired += 1 }
      ._makeRecognizer(context: setBContext("LongPressShort"))
    _ = short.handle(event: setBEvent(.down(.primary), timestamp: t0))
    let justShort = t0.advanced(by: Duration.milliseconds(50) - Duration.nanoseconds(1))
    let shortRelease = short.handle(event: setBEvent(.up(.primary), timestamp: justShort))
    #expect(shortRelease == .failed)
    #expect(short.phase == .failed)
    #expect(shortFired == 0)

    var exactFired = 0
    let exact = LongPressGesture(minimumDuration: .milliseconds(50))
      .onEnded { _ in exactFired += 1 }
      ._makeRecognizer(context: setBContext("LongPressExact"))
    _ = exact.handle(event: setBEvent(.down(.primary), timestamp: t0))
    let exactRelease = exact.handle(
      event: setBEvent(.up(.primary), timestamp: t0.advanced(by: .milliseconds(50))))
    #expect(exactRelease == .handled)
    #expect(exact.phase == .ended)
    #expect(exactFired == 1)
  }

  // MARK: - Composed runtime

  @Test func setB026NonPrimaryReleaseNeitherActivatesNorTearsDownPress() throws {
    let probe = SetBProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBGesture", "NonPrimaryRelease"),
      size: .init(width: 24, height: 5)
    ) {
      Button("Go") { probe.acts += 1 }
        .simultaneousGesture(
          DragGesture(minimumDistance: 0).onChanged { probe.changes.append($0.translation.dx) })
    }
    defer { harness.shutdown() }
    let press = try #require(harness.point(forText: "Go"))
    let moved = Point(x: press.x + 3, y: press.y)

    _ = try harness.sendMouse(.down(.primary), at: press)
    #expect(probe.changes == [0])
    #expect(harness.runLoop.pointerInteraction.isRouting)

    _ = try harness.sendMouse(.up(.secondary), at: press)
    #expect(probe.acts == 0)
    #expect(
      harness.runLoop.pointerInteraction.isRouting, "a foreign release must not end the press")

    _ = try harness.sendMouse(.dragged(.secondary), at: moved)
    #expect(probe.changes == [0])

    _ = try harness.sendMouse(.down(.middle), at: press)
    #expect(harness.runLoop.pointerInteraction.isRouting)
    #expect(probe.acts == 0)

    _ = try harness.sendMouse(.dragged(.primary), at: moved)
    #expect(probe.changes == [0, 3])

    _ = try harness.sendMouse(.up(.primary), at: press)
    #expect(probe.acts == 1)
    #expect(probe.changes == [0, 3, 0])
    #expect(!harness.runLoop.pointerInteraction.isRouting)
  }

  @Test func setB027SliderTrackPressAtCurrentValueDoesNotInvokeSetter() throws {
    let probe = SetBProbe()
    let control = testIdentity("SetBGesture", "SliderNoOp", "Control")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBGesture", "SliderNoOp"),
      size: .init(width: 40, height: 4)
    ) {
      Slider("Level", value: probe.binding, in: 0...10).id(control)
    }
    defer { harness.shutdown() }
    let trackIdentity = sliderTrackIdentity(for: control)
    let track = try #require(
      harness.runLoop.latestSemanticSnapshot.interactionRegions.first {
        $0.identity == trackIdentity
      })
    #expect(track.rect.size.width > 3)
    let row = Double(track.rect.origin.y)
    let lowerEnd = Point(x: Double(track.rect.origin.x + 1), y: row)
    let upperEnd = Point(x: Double(track.rect.origin.x + track.rect.size.width - 2), y: row)

    // The value is already at the lower bound: pressing, dragging and
    // releasing on that cell resolves to the same value every time.
    _ = try harness.sendMouse(.down(.primary), at: lowerEnd)
    _ = try harness.sendMouse(.dragged(.primary), at: lowerEnd)
    _ = try harness.sendMouse(.up(.primary), at: lowerEnd)
    #expect(probe.value == 0)
    #expect(probe.sets == 0, "a track interaction at the current value is a no-op")

    _ = try harness.sendMouse(.down(.primary), at: lowerEnd)
    _ = try harness.sendMouse(.dragged(.primary), at: upperEnd)
    #expect(probe.value == 10)
    #expect(probe.sets == 1)
    _ = try harness.sendMouse(.dragged(.primary), at: upperEnd)
    _ = try harness.sendMouse(.up(.primary), at: upperEnd)
    #expect(probe.sets == 1, "repeating the same track value must not write again")
    #expect(harness.frame.contains("10"), "\(harness.frame)")

    // A wheel notch at the upper bound cannot move the value, so it must not
    // write either; the opposite notch writes exactly once.
    _ = try harness.scrollPointer(at: upperEnd, deltaY: -1)
    #expect(probe.value == 10)
    #expect(probe.sets == 1)
    _ = try harness.scrollPointer(at: upperEnd, deltaY: 1)
    #expect(probe.value == 9)
    #expect(probe.sets == 2)
  }

  @Test func setB028CancelWithoutPressLeavesInteractionIdleAndExitsHover() throws {
    let probe = SetBProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBGesture", "CancelWithoutPress"),
      size: .init(width: 24, height: 5)
    ) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Hover").onPointerHover { probe.phases.append($0) }
        Button("Go") { probe.acts += 1 }
      }
    }
    defer { harness.shutdown() }

    // A cancel that no press preceded is inert.
    _ = try harness.sendMouse(.cancelled, at: Point(x: 0, y: 0))
    #expect(harness.runLoop.pointerInteraction == PointerInteractionState())
    #expect(harness.runLoop.pressedIdentity == nil)
    #expect(harness.runLoop.cancelledHostGeometryGestureCount == 0)
    #expect(probe.phases.isEmpty)

    // A cancel ends the pointer stream, so a live hover exits and the next
    // motion over the same view is a fresh entry, not a continuation.
    let hover = try #require(harness.point(forText: "Hover"))
    _ = try harness.movePointer(to: hover)
    #expect(setBTags(probe.phases) == ["entered"])
    _ = try harness.sendMouse(.cancelled, at: hover)
    #expect(setBTags(probe.phases) == ["entered", "exited"])
    #expect(harness.runLoop.lastPointerLocation == nil)
    _ = try harness.movePointer(to: hover)
    #expect(setBTags(probe.phases) == ["entered", "exited", "entered"])

    _ = try harness.clickText("Go")
    #expect(probe.acts == 1)
    #expect(!harness.runLoop.pointerInteraction.isRouting)
  }

  @Test func setB029DragLeavingAndReenteringTargetReleasedOutsideDoesNotActivate() throws {
    let probe = SetBProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBGesture", "DragReenter"),
      size: .init(width: 32, height: 5)
    ) {
      Button("Go") { probe.acts += 1 }
        .simultaneousGesture(
          DragGesture(minimumDistance: 0)
            .onChanged { probe.changes.append($0.translation.dx) }
            .onEnded { probe.ends.append($0.translation.dx) })
    }
    defer { harness.shutdown() }
    let press = try #require(harness.point(forText: "Go"))
    let far = Point(x: press.x + 12, y: press.y)
    let farther = Point(x: press.x + 14, y: press.y)

    _ = try harness.sendMouse(.down(.primary), at: press)
    _ = try harness.sendMouse(.dragged(.primary), at: far)
    _ = try harness.sendMouse(.dragged(.primary), at: press)
    _ = try harness.sendMouse(.up(.primary), at: farther)
    #expect(probe.changes == [0, 12, 0, 14])
    #expect(probe.ends == [14])
    #expect(probe.acts == 0, "a release outside the control does not activate it")
    #expect(!harness.runLoop.pointerInteraction.isRouting)

    // The same excursion released back over the control activates once.
    _ = try harness.sendMouse(.down(.primary), at: press)
    _ = try harness.sendMouse(.dragged(.primary), at: far)
    _ = try harness.sendMouse(.dragged(.primary), at: press)
    _ = try harness.sendMouse(.up(.primary), at: press)
    #expect(probe.ends == [14, 0])
    #expect(probe.acts == 1)
  }

  @Test func setB030StaleGeometryDragMidCaptureCancelsAndFreshPressAtSameCellActivates() throws {
    let probe = SetBProbe()
    let host = SetBGeometrySurface()
    let root = testIdentity("SetBGesture", "StaleGeometryDrag")
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: host,
      terminalInputReader: SetBGeometryInput(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root])
    ) { _, _ in
      Button("Activate") { probe.acts += 1 }
        .simultaneousGesture(
          DragGesture(minimumDistance: 0)
            .onChanged { probe.changes.append($0.translation.dx) }
            .onEnded { probe.ends.append($0.translation.dx) })
    }
    var rendered = 0
    func render() throws {
      loop.scheduler.requestSignal(named: "SIGWINCH")
      try loop.renderPendingFrames(renderedFrames: &rendered)
    }
    try render()
    let region = try #require(
      loop.latestSemanticSnapshot.interactionRegions.max { $0.hitTestOrder < $1.hitTestOrder })
    let origin = Point(x: Double(region.rect.origin.x), y: Double(region.rect.origin.y))
    let moved = Point(x: origin.x + 2, y: origin.y)
    func send(_ kind: MouseEvent.Kind, at point: Point, revision: UInt64) {
      var event = MouseEvent(kind: kind, location: point)
      event.hostGeometryStamp = .init(session: host.session, revision: revision)
      _ = loop.handle(.input(.mouse(event)))
    }

    send(.down(.primary), at: origin, revision: 1)
    send(.dragged(.primary), at: moved, revision: 1)
    #expect(probe.changes == [0, 2])
    #expect(loop.pointerInteraction.isRouting)

    // The host publishes new geometry; a sample stamped with the old one is
    // obsolete, and the press it belongs to is cancelled rather than
    // completed by any later stale release.
    host.revision = 2
    send(.dragged(.primary), at: moved, revision: 1)
    #expect(loop.cancelledHostGeometryGestureCount == 1)
    #expect(!loop.pointerInteraction.isRouting)
    #expect(probe.changes == [0, 2])
    #expect(probe.ends.isEmpty)
    send(.up(.primary), at: origin, revision: 1)
    #expect(probe.ends.isEmpty)
    #expect(probe.acts == 0)

    // The new revision is not usable until a frame has applied it.
    send(.down(.primary), at: origin, revision: 2)
    #expect(!loop.pointerInteraction.isRouting)
    #expect(loop.rejectedHostGeometryPointerCount == 3)

    try render()
    send(.down(.primary), at: origin, revision: 2)
    send(.up(.primary), at: origin, revision: 2)
    #expect(probe.acts == 1)
    #expect(probe.ends == [0])
    #expect(probe.changes == [0, 2, 0, 0])
    #expect(loop.rejectedHostGeometryPointerCount == 3)
    #expect(loop.cancelledHostGeometryGestureCount == 1)
    let stale = loop.reportedRuntimeIssues.filter { $0.code == "host.geometry.stalePointer" }
    #expect(!stale.isEmpty)
  }
}

// MARK: - Fixtures

private func setBEvent(
  _ kind: LocalPointerEvent.Kind,
  at point: Point = .zero,
  timestamp: MonotonicInstant
) -> LocalPointerEvent {
  LocalPointerEvent(
    kind: kind,
    location: point,
    targetRect: CellRect(origin: .zero, size: CellSize(width: 4, height: 1)),
    timestamp: timestamp
  )
}

private func setBContext(
  _ name: String,
  requestDeadline: @escaping @MainActor @Sendable (MonotonicInstant) -> Void = { _ in }
) -> GestureRecognizerBuildContext {
  GestureRecognizerBuildContext(
    attachingIdentity: testIdentity("SetBGesture", name),
    gestureStateRegistry: nil,
    requestDeadline: requestDeadline
  )
}

private func setBTags(_ phases: [HoverPhase]) -> [String] {
  phases.map { phase in
    switch phase {
    case .entered: "entered"
    case .moved: "moved"
    case .exited: "exited"
    }
  }
}

@MainActor
private final class SetBProbe {
  var acts = 0
  var changes: [Double] = []
  var ends: [Double] = []
  var phases: [HoverPhase] = []
  var value = 0
  var sets = 0

  var binding: Binding<Int> {
    Binding(
      get: { self.value },
      set: {
        self.value = $0
        self.sets += 1
      }
    )
  }
}

private final class SetBGeometrySurface: HostGeometryPresentationSurface,
  SemanticHostFramePresentationSurface
{
  var session: UInt64 = 7
  var revision: UInt64 = 1
  var size = CellSize(width: 24, height: 6)
  private(set) var frames: [SemanticHostFrame] = []
  var surfaceSize: CellSize { size }
  let appearance: TerminalAppearance = .fallback
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode

  func captureHostLayoutConfiguration() -> HostLayoutConfiguration {
    .init(
      size: size, appearance: appearance, theme: nil, graphics: .none, pointer: .cellOnly,
      geometry: .init(session: session, revision: revision)
    )
  }

  func present(_ frame: SemanticHostFrame) throws -> PresentationMetrics {
    frames.append(frame)
    return .init(
      bytesWritten: 0,
      linesTouched: frame.raster.size.height,
      cellsChanged: frame.raster.size.width * frame.raster.size.height,
      strategy: .fullRepaint
    )
  }
}

private final class SetBGeometryInput: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { $0.finish() }
  }
}
