import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct GestureRunLoopDispatchTests {
  @Test("TapGesture fires through the full RunLoop mouse path")
  func tapGestureFiresThroughRunLoop() async throws {
    @MainActor final class Box {
      var count = 0
    }

    let box = Box()
    let terminalSize = CellSize(width: 20, height: 5)
    let rootIdentity = Identity(components: [.named("GestureRunLoopTap")])
    let view = Text("Tap")
      .frame(minWidth: 5, maxWidth: 5, minHeight: 1, maxHeight: 1)
      .onTapGesture {
        box.count += 1
      }

    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let probePointerRegistry = LocalPointerHandlerRegistry()
    let probeGestureRegistry = LocalGestureRegistry()
    let probeGestureStateRegistry = LocalGestureStateRegistry()
    var probeContext = ResolveContext(identity: rootIdentity, environmentValues: env)
    probeContext.localPointerHandlerRegistry = probePointerRegistry
    probeContext.localGestureRegistry = probeGestureRegistry
    probeContext.localGestureStateRegistry = probeGestureStateRegistry
    let initial = DefaultRenderer().render(
      view,
      context: probeContext,
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let region = try #require(initial.semanticSnapshot.interactionRegions.first)
    let point = centerPoint(of: region.rect)

    let host = RecordingGestureTerminalHost(size: terminalSize)
    let pointer = PointerLocation.subCell(
      location: point,
      source: .nativePixels,
      metrics: .estimated
    )
    let result = try await runHarness(
      host: host,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      schedule: [
        .init(event: .mouse(.init(kind: .down(.primary), location: pointer))),
        .init(event: .mouse(.init(kind: .up(.primary), location: pointer))),
      ],
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(box.count == 1)
  }

  @Test("high-priority ancestor gesture defeats a descendant button through the RunLoop")
  func highPriorityAncestorGestureDefeatsDescendantControl() async throws {
    @MainActor final class Counts {
      var gesture = 0
      var button = 0
    }

    let counts = Counts()
    let terminalSize = CellSize(width: 20, height: 5)
    let rootIdentity = Identity(components: [.named("HighPriorityControl")])
    let view = VStack {
      Button("Control") {
        counts.button += 1
      }
    }
    .frame(minWidth: 10, maxWidth: 10, minHeight: 3, maxHeight: 3)
    .highPriorityGesture(
      TapGesture().onEnded {
        counts.gesture += 1
      }
    )

    var environment = EnvironmentValues()
    environment.terminalSize = terminalSize
    let pointerRegistry = LocalPointerHandlerRegistry()
    let gestureRegistry = LocalGestureRegistry()
    let gestureStateRegistry = LocalGestureStateRegistry()
    var context = ResolveContext(identity: rootIdentity, environmentValues: environment)
    context.localPointerHandlerRegistry = pointerRegistry
    context.localGestureRegistry = gestureRegistry
    context.localGestureStateRegistry = gestureStateRegistry
    let initial = DefaultRenderer().render(
      view,
      context: context,
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let buttonRegion = try #require(
      initial.semanticSnapshot.interactionRegions
        .filter { $0.pointerGesturePriority == .ordinary }
        .max { $0.hitTestOrder < $1.hitTestOrder }
    )
    let point = centerPoint(of: buttonRegion.rect)
    let result = try await runHarness(
      host: RecordingGestureTerminalHost(size: terminalSize),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      schedule: [
        .init(event: .mouse(.init(kind: .down(.primary), location: point))),
        .init(event: .mouse(.init(kind: .up(.primary), location: point))),
      ],
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(counts.gesture == 1)
    #expect(counts.button == 0)
  }

  @Test("an ordinary tap gesture claims a button click through the RunLoop")
  func ordinaryTapGestureClaimsButtonClick() async throws {
    @MainActor final class Counts {
      var gesture = 0
      var button = 0
    }

    let counts = Counts()
    let terminalSize = CellSize(width: 20, height: 5)
    let rootIdentity = Identity(components: [.named("OrdinaryTapControl")])
    let view = Button("Control") {
      counts.button += 1
    }
    .gesture(
      TapGesture().onEnded {
        counts.gesture += 1
      }
    )

    var environment = EnvironmentValues()
    environment.terminalSize = terminalSize
    let pointerRegistry = LocalPointerHandlerRegistry()
    let gestureRegistry = LocalGestureRegistry()
    let gestureStateRegistry = LocalGestureStateRegistry()
    var context = ResolveContext(identity: rootIdentity, environmentValues: environment)
    context.localPointerHandlerRegistry = pointerRegistry
    context.localGestureRegistry = gestureRegistry
    context.localGestureStateRegistry = gestureStateRegistry
    let initial = DefaultRenderer().render(
      view,
      context: context,
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let region = try #require(
      initial.semanticSnapshot.interactionRegions
        .max { $0.hitTestOrder < $1.hitTestOrder }
    )
    let point = centerPoint(of: region.rect)
    let result = try await runHarness(
      host: RecordingGestureTerminalHost(size: terminalSize),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      schedule: [
        .init(event: .mouse(.init(kind: .down(.primary), location: point))),
        .init(event: .mouse(.init(kind: .up(.primary), location: point))),
      ],
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(counts.gesture == 1)
    #expect(counts.button == 0)
  }

  @Test(
    "a deadline-recognized long press preserves its attachment role through release",
    arguments: DeadlineLongPressAttachmentRole.allCases
  )
  func deadlineRecognizedLongPressPreservesAttachmentRole(
    role: DeadlineLongPressAttachmentRole
  ) async throws {
    @MainActor final class Counts {
      let updates = MainActorConditionSignal()
      var button = 0
      var longPress = 0 {
        didSet { updates.notify() }
      }
    }

    let counts = Counts()
    let terminalSize = CellSize(width: 20, height: 5)
    let rootIdentity = Identity(
      components: [IdentityComponent(rawValue: "DeadlineLongPressControl.\(role.rawValue)")]
    )
    let button = Button("Control") {
      counts.button += 1
    }
    let longPress = LongPressGesture(minimumDuration: .milliseconds(20))
      .onEnded { _ in counts.longPress += 1 }
    let view: AnyView =
      switch role {
      case .ordinary:
        AnyView(button.gesture(longPress))
      case .highPriority:
        AnyView(button.highPriorityGesture(longPress))
      case .simultaneous:
        AnyView(button.simultaneousGesture(longPress))
      }

    let point = try interactionPoint(
      for: view,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity
    )
    var environment = EnvironmentValues()
    environment.terminalSize = terminalSize
    let host = RecordingGestureTerminalHost(size: terminalSize)
    let inputReader = InjectedTerminalInputReader()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: inputReader,
      signalReader: EmptyGestureSignals(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: environment,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      exitKeyBindings: .none,
      viewBuilder: { _, _ in view }
    )

    let task = Task {
      try await runLoop.run()
    }

    await host.firstPresent.wait()
    inputReader.send(.mouse(.init(kind: .down(.primary), location: point)))
    await counts.updates.wait { counts.longPress == 1 }
    inputReader.send(.mouse(.init(kind: .up(.primary), location: point)))
    inputReader.finish()

    let result = try await task.value
    #expect(result.exitReason == .inputEnded)
    #expect(counts.longPress == 1)
    #expect(counts.button == role.expectedButtonActivations)
  }

  @Test(
    "a deadline-recognized ancestor long press preserves its role over a descendant button",
    arguments: DeadlineLongPressAttachmentRole.allCases
  )
  func deadlineRecognizedAncestorLongPressPreservesRoleOverDescendantButton(
    role: DeadlineLongPressAttachmentRole
  ) async throws {
    @MainActor final class Counts {
      let updates = MainActorConditionSignal()
      var button = 0
      var longPress = 0 {
        didSet { updates.notify() }
      }
    }

    let counts = Counts()
    let terminalSize = CellSize(width: 20, height: 5)
    let rootIdentity = Identity(
      components: [IdentityComponent(rawValue: "DeadlineAncestorLongPressControl.\(role.rawValue)")]
    )
    let content = VStack {
      Button("Control") {
        counts.button += 1
      }
    }
    .frame(minWidth: 10, maxWidth: 10, minHeight: 3, maxHeight: 3)
    let longPress = LongPressGesture(minimumDuration: .milliseconds(20))
      .onEnded { _ in counts.longPress += 1 }
    let view: AnyView =
      switch role {
      case .ordinary:
        AnyView(content.gesture(longPress))
      case .highPriority:
        AnyView(content.highPriorityGesture(longPress))
      case .simultaneous:
        AnyView(content.simultaneousGesture(longPress))
      }

    let point = try interactionPoint(
      for: view,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity
    )
    var environment = EnvironmentValues()
    environment.terminalSize = terminalSize
    let host = RecordingGestureTerminalHost(size: terminalSize)
    let inputReader = InjectedTerminalInputReader()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: inputReader,
      signalReader: EmptyGestureSignals(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: environment,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      exitKeyBindings: .none,
      viewBuilder: { _, _ in view }
    )

    let task = Task {
      try await runLoop.run()
    }

    await host.firstPresent.wait()
    inputReader.send(.mouse(.init(kind: .down(.primary), location: point)))
    await counts.updates.wait { counts.longPress == 1 }
    inputReader.send(.mouse(.init(kind: .up(.primary), location: point)))
    inputReader.finish()

    let result = try await task.value
    #expect(result.exitReason == .inputEnded)
    #expect(counts.longPress == 1)
    #expect(counts.button == role.expectedButtonActivations)
  }

  @Test("a failed ordinary ancestor long press leaves its descendant button eligible")
  func failedAncestorLongPressLeavesDescendantButtonEligible() async throws {
    @MainActor final class Counts {
      var button = 0
      var longPress = 0
    }

    let counts = Counts()
    let terminalSize = CellSize(width: 20, height: 5)
    let rootIdentity = Identity(components: [.named("FailedAncestorLongPressControl")])
    let view = VStack {
      Button("Control") {
        counts.button += 1
      }
    }
    .frame(minWidth: 10, maxWidth: 10, minHeight: 3, maxHeight: 3)
    .gesture(
      LongPressGesture(minimumDuration: .seconds(60))
        .onEnded { _ in counts.longPress += 1 }
    )

    let point = try interactionPoint(
      for: view,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity
    )
    let result = try await runHarness(
      host: RecordingGestureTerminalHost(size: terminalSize),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      schedule: [
        .init(event: .mouse(.init(kind: .down(.primary), location: point))),
        .init(event: .mouse(.init(kind: .up(.primary), location: point))),
      ],
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(counts.longPress == 0)
    #expect(counts.button == 1)
  }

  @Test("a stationary click activates a button with a simultaneous drag gesture")
  func stationaryClickActivatesButtonWithSimultaneousDragGesture() async throws {
    @MainActor final class Counts {
      var button = 0
      var drag = 0
    }

    let counts = Counts()
    let terminalSize = CellSize(width: 20, height: 5)
    let rootIdentity = Identity(components: [.named("SimultaneousDragControl")])
    let view = Button("Control") {
      counts.button += 1
    }
    .simultaneousGesture(
      DragGesture(minimumDistance: 1)
        .onEnded { _ in counts.drag += 1 }
    )

    var environment = EnvironmentValues()
    environment.terminalSize = terminalSize
    let pointerRegistry = LocalPointerHandlerRegistry()
    let gestureRegistry = LocalGestureRegistry()
    let gestureStateRegistry = LocalGestureStateRegistry()
    var context = ResolveContext(identity: rootIdentity, environmentValues: environment)
    context.localPointerHandlerRegistry = pointerRegistry
    context.localGestureRegistry = gestureRegistry
    context.localGestureStateRegistry = gestureStateRegistry
    let initial = DefaultRenderer().render(
      view,
      context: context,
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let region = try #require(
      initial.semanticSnapshot.interactionRegions
        .max { $0.hitTestOrder < $1.hitTestOrder }
    )
    let point = centerPoint(of: region.rect)
    let result = try await runHarness(
      host: RecordingGestureTerminalHost(size: terminalSize),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      schedule: [
        .init(event: .mouse(.init(kind: .down(.primary), location: point))),
        .init(event: .mouse(.init(kind: .up(.primary), location: point))),
      ],
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(counts.button == 1)
    #expect(counts.drag == 0)

    let dragPoint = Point(x: point.x + 2, y: point.y)
    let dragResult = try await runHarness(
      host: RecordingGestureTerminalHost(size: terminalSize),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      schedule: [
        .init(event: .mouse(.init(kind: .down(.primary), location: point))),
        .init(event: .mouse(.init(kind: .dragged(.primary), location: dragPoint))),
        .init(event: .mouse(.init(kind: .up(.primary), location: dragPoint))),
      ],
      viewBuilder: { view }
    )

    #expect(dragResult.exitReason == .inputEnded)
    // A simultaneous lane observes recognition without claiming the control.
    #expect(counts.button == 2)
    #expect(counts.drag == 1)
  }

  @Test("a default simultaneous drag and its button both recognize a stationary click")
  func simultaneousDefaultDragAndButtonBothRecognizeStationaryClick() async throws {
    @MainActor final class Counts {
      var button = 0
      var drag = 0
    }

    let counts = Counts()
    let terminalSize = CellSize(width: 20, height: 5)
    let rootIdentity = Identity(components: [.named("SimultaneousDefaultDragControl")])
    let view = Button("Control") {
      counts.button += 1
    }
    .simultaneousGesture(
      DragGesture()
        .onEnded { _ in counts.drag += 1 }
    )

    let point = try interactionPoint(
      for: view,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity
    )
    let result = try await runHarness(
      host: RecordingGestureTerminalHost(size: terminalSize),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      schedule: [
        .init(event: .mouse(.init(kind: .down(.primary), location: point))),
        .init(event: .mouse(.init(kind: .up(.primary), location: point))),
      ],
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(counts.button == 1)
    #expect(counts.drag == 1)
  }

  @Test("a simultaneous tap and its button both recognize an on-target click")
  func simultaneousTapAndButtonBothRecognizeOnTargetClick() async throws {
    @MainActor final class Counts {
      var button = 0
      var tap = 0
    }

    let counts = Counts()
    let terminalSize = CellSize(width: 20, height: 5)
    let rootIdentity = Identity(components: [.named("SimultaneousTapControl")])
    let view = Button("Control") {
      counts.button += 1
    }
    .simultaneousGesture(
      TapGesture()
        .onEnded { counts.tap += 1 }
    )

    let point = try interactionPoint(
      for: view,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity
    )
    let result = try await runHarness(
      host: RecordingGestureTerminalHost(size: terminalSize),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      schedule: [
        .init(event: .mouse(.init(kind: .down(.primary), location: point))),
        .init(event: .mouse(.init(kind: .up(.primary), location: point))),
      ],
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(counts.button == 1)
    #expect(counts.tap == 1)
  }

  @Test("an off-target release activates neither a simultaneous tap nor its button")
  func simultaneousTapOffTargetReleaseActivatesNeither() async throws {
    @MainActor final class Counts {
      var button = 0
      var tap = 0
    }

    let counts = Counts()
    let terminalSize = CellSize(width: 20, height: 5)
    let rootIdentity = Identity(components: [.named("SimultaneousTapOffTargetControl")])
    let view = Button("Control") {
      counts.button += 1
    }
    .simultaneousGesture(
      TapGesture()
        .onEnded { counts.tap += 1 }
    )

    let point = try interactionPoint(
      for: view,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity
    )
    let offTarget = Point(x: 19, y: 4)
    let result = try await runHarness(
      host: RecordingGestureTerminalHost(size: terminalSize),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      schedule: [
        .init(event: .mouse(.init(kind: .down(.primary), location: point))),
        .init(event: .mouse(.init(kind: .up(.primary), location: offTarget))),
      ],
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(counts.button == 0)
    #expect(counts.tap == 0)
  }

  @Test("a high-priority default drag claims and suppresses a stationary button click")
  func highPriorityDefaultDragSuppressesStationaryButtonClick() async throws {
    @MainActor final class Counts {
      var button = 0
      var drag = 0
    }

    let counts = Counts()
    let terminalSize = CellSize(width: 20, height: 5)
    let rootIdentity = Identity(components: [.named("HighPriorityDefaultDragControl")])
    let view = Button("Control") {
      counts.button += 1
    }
    .highPriorityGesture(
      DragGesture()
        .onEnded { _ in counts.drag += 1 }
    )

    let point = try interactionPoint(
      for: view,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity
    )
    let result = try await runHarness(
      host: RecordingGestureTerminalHost(size: terminalSize),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      schedule: [
        .init(event: .mouse(.init(kind: .down(.primary), location: point))),
        .init(event: .mouse(.init(kind: .up(.primary), location: point))),
      ],
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(counts.button == 0)
    #expect(counts.drag == 1)
  }

  @Test("SpatialTapGesture delivers local coordinates through the full RunLoop mouse path")
  func spatialTapGestureCarriesLocalCoordinatesThroughRunLoop() async throws {
    @MainActor final class Box {
      var location: Point?
    }

    let box = Box()
    let terminalSize = CellSize(width: 20, height: 5)
    let rootIdentity = Identity(components: [.named("GestureRunLoopSpatialTap")])
    let view = Text("Tap")
      .frame(minWidth: 5, maxWidth: 5, minHeight: 1, maxHeight: 1)
      .gesture(
        SpatialTapGesture().onEnded { value in
          box.location = value.location
        }
      )

    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let probePointerRegistry = LocalPointerHandlerRegistry()
    let probeGestureRegistry = LocalGestureRegistry()
    let probeGestureStateRegistry = LocalGestureStateRegistry()
    var probeContext = ResolveContext(identity: rootIdentity, environmentValues: env)
    probeContext.localPointerHandlerRegistry = probePointerRegistry
    probeContext.localGestureRegistry = probeGestureRegistry
    probeContext.localGestureStateRegistry = probeGestureStateRegistry
    let initial = DefaultRenderer().render(
      view,
      context: probeContext,
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let region = try #require(initial.semanticSnapshot.interactionRegions.first)
    let point = Point(
      x: Double(region.rect.origin.x + 3),
      y: Double(region.rect.origin.y)
    )

    let host = RecordingGestureTerminalHost(size: terminalSize)
    let pointer = PointerLocation.subCell(
      location: point,
      source: .nativePixels,
      metrics: .estimated
    )
    let result = try await runHarness(
      host: host,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      schedule: [
        .init(event: .mouse(.init(kind: .down(.primary), location: pointer))),
        .init(event: .mouse(.init(kind: .up(.primary), location: pointer))),
      ],
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(box.location == Point(x: 3, y: 0))
  }

  @Test("Terminal-pixel mouse input reaches DragGesture as fractional location")
  func terminalPixelMouseInputReachesDragGestureAsFractionalLocation() async throws {
    @MainActor final class Box {
      var location: Point?
    }

    let box = Box()
    let terminalSize = CellSize(width: 20, height: 5)
    let rootIdentity = Identity(components: [.named("GestureRunLoopTerminalPixelDrag")])
    let view = Text("Drag")
      .frame(minWidth: 5, maxWidth: 5, minHeight: 1, maxHeight: 1)
      .gesture(
        DragGesture().onChanged { value in
          box.location = value.location
        }
      )

    let metrics = CellPixelMetrics(width: 8, height: 16, source: .reported)
    var parser = TerminalInputParser(
      mouseCoordinateMode: .pixels(metrics: metrics, source: .terminalPixels)
    )
    let events = parser.feed(
      Array("\u{001B}[<0;5;9M\u{001B}[<32;13;9M\u{001B}[<0;13;9m".utf8)
    )

    let result = try await runHarness(
      host: RecordingGestureTerminalHost(size: terminalSize),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      schedule: events.map { ScheduledGestureInputEvent(event: $0) },
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(box.location == Point(x: 1.5, y: 0.5))
  }

  @Test("a named drag wrapper captures and receives the full pointer path")
  func namedDragWrapperCapturesFullPointerPath() async throws {
    @MainActor final class Box {
      let changed = MainActorConditionSignal()
      var changedValues: [DragGesture.Value] = []
      var endedValue: DragGesture.Value?
    }

    let box = Box()
    let terminalSize = CellSize(width: 20, height: 5)
    let rootIdentity = Identity(components: [.named("NamedDragWrapper")])
    let view = Text("Drag")
      .frame(minWidth: 5, maxWidth: 5, minHeight: 1, maxHeight: 1)
      .gesture(
        NamedDragWrapper(
          onChanged: {
            box.changedValues.append($0)
            box.changed.notify()
          },
          onEnded: { box.endedValue = $0 }
        )
      )

    var environment = EnvironmentValues()
    environment.terminalSize = terminalSize
    let pointerRegistry = LocalPointerHandlerRegistry()
    let gestureRegistry = LocalGestureRegistry()
    let gestureStateRegistry = LocalGestureStateRegistry()
    var context = ResolveContext(identity: rootIdentity, environmentValues: environment)
    context.localPointerHandlerRegistry = pointerRegistry
    context.localGestureRegistry = gestureRegistry
    context.localGestureStateRegistry = gestureStateRegistry
    let initial = DefaultRenderer().render(
      view,
      context: context,
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let region = try #require(initial.semanticSnapshot.interactionRegions.first)
    let start = centerPoint(of: region.rect)
    let firstDrag = Point(x: start.x + 2, y: start.y)
    let lastDrag = Point(x: start.x + 4, y: start.y)
    // Each movement is gated on the previous one having been observed:
    // without the gates, the run loop's pointer coalescing can fold both
    // dragged events into one movement sample (deterministically so on a
    // serialized lane, where the script's tight yield loop outruns the
    // consumer), and the full pointer path this test exists to assert is
    // never delivered as separate samples.
    let result = try await runHarness(
      host: RecordingGestureTerminalHost(size: terminalSize),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      schedule: [
        .init(event: .mouse(.init(kind: .down(.primary), location: start))),
        .init(event: .mouse(.init(kind: .dragged(.primary), location: firstDrag))),
        .init(
          event: .mouse(.init(kind: .dragged(.primary), location: lastDrag)),
          gate: { await box.changed.wait(until: { box.changedValues.count >= 1 }) }
        ),
        .init(
          event: .mouse(.init(kind: .up(.primary), location: lastDrag)),
          gate: { await box.changed.wait(until: { box.changedValues.count >= 2 }) }
        ),
      ],
      viewBuilder: { view }
    )

    let ended = try #require(box.endedValue)
    #expect(result.exitReason == .inputEnded)
    #expect(
      box.changedValues.map { $0.location.x - $0.startLocation.x }
        == [2, 4, 4]
    )
    #expect(ended.location.x - ended.startLocation.x == 4)
    #expect(ended.path.first?.location == ended.startLocation)
    #expect(ended.path.last?.location == ended.location)
  }

  @Test("LongPressGesture fires through the full RunLoop deadline path")
  func longPressGestureFiresThroughRunLoop() async throws {
    @MainActor final class Box {
      let updates = MainActorConditionSignal()
      var count = 0 {
        didSet { updates.notify() }
      }
    }

    let box = Box()
    let terminalSize = CellSize(width: 20, height: 5)
    let rootIdentity = Identity(components: [.named("GestureRunLoopLongPress")])
    let view = Text("Hold")
      .frame(minWidth: 5, maxWidth: 5, minHeight: 1, maxHeight: 1)
      .onLongPressGesture(minimumDuration: .milliseconds(20)) {
        box.count += 1
      }

    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let probePointerRegistry = LocalPointerHandlerRegistry()
    let probeGestureRegistry = LocalGestureRegistry()
    let probeGestureStateRegistry = LocalGestureStateRegistry()
    var probeContext = ResolveContext(identity: rootIdentity, environmentValues: env)
    probeContext.localPointerHandlerRegistry = probePointerRegistry
    probeContext.localGestureRegistry = probeGestureRegistry
    probeContext.localGestureStateRegistry = probeGestureStateRegistry
    let initial = DefaultRenderer().render(
      view,
      context: probeContext,
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let region = try #require(initial.semanticSnapshot.interactionRegions.first)
    let point = centerPoint(of: region.rect)

    let host = RecordingGestureTerminalHost(size: terminalSize)
    let inputReader = InjectedTerminalInputReader()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: inputReader,
      signalReader: EmptyGestureSignals(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: env,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      exitKeyBindings: .none,
      viewBuilder: { _, _ in view }
    )

    let task = Task {
      try await runLoop.run()
    }

    await host.firstPresent.wait()
    inputReader.send(.mouse(.init(kind: .down(.primary), location: point)))
    await box.updates.wait { box.count == 1 }
    inputReader.finish()

    let result = try await task.value
    #expect(result.exitReason == .inputEnded)
    #expect(box.count == 1)
  }

  @Test("Exclusive tap composition works through the full RunLoop mouse path")
  func exclusiveTapCompositionFiresThroughRunLoop() async throws {
    @MainActor final class Counts {
      var single = 0
      var double = 0
    }

    let counts = Counts()
    // This harness processes scripted events at DEBUG frame cadence (a
    // first render alone can exceed the real inter-tap window), so widen
    // the window: the test exercises dispatch plumbing, not tap timing —
    // the timing behavior is pinned by the recognizer unit tests.
    //
    // The window is wall-clock by design (F158: it resolves at recognizer
    // construction), so any finite budget is a race against gate load, not a
    // margin. A 120s window lost that race twice on the degraded amd64 runner
    // class, where this test itself has been starved for 279-284s: the second
    // press landed after expiry and the recognizer emitted two singles instead
    // of one double. Pick a window no starvation can outlast rather than a
    // larger guess. Nothing here waits on expiry — a lone single tap is only
    // reported once the window closes, and this test asserts `single == 0` —
    // so the run loop still exits on input end.
    TapGesture.interTapWindowOverride = .seconds(86_400)
    defer { TapGesture.interTapWindowOverride = nil }
    let terminalSize = CellSize(width: 20, height: 5)
    let rootIdentity = Identity(components: [.named("GestureRunLoopExclusiveTap")])
    let view = Text("Tap")
      .frame(minWidth: 5, maxWidth: 5, minHeight: 1, maxHeight: 1)
      .gesture(
        TapGesture(count: 2).onEnded { counts.double += 1 }
          .exclusively(before: TapGesture().onEnded { counts.single += 1 })
      )

    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let probePointerRegistry = LocalPointerHandlerRegistry()
    let probeGestureRegistry = LocalGestureRegistry()
    let probeGestureStateRegistry = LocalGestureStateRegistry()
    var probeContext = ResolveContext(identity: rootIdentity, environmentValues: env)
    probeContext.localPointerHandlerRegistry = probePointerRegistry
    probeContext.localGestureRegistry = probeGestureRegistry
    probeContext.localGestureStateRegistry = probeGestureStateRegistry
    let initial = DefaultRenderer().render(
      view,
      context: probeContext,
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let region = try #require(initial.semanticSnapshot.interactionRegions.first)
    let point = centerPoint(of: region.rect)

    let host = RecordingGestureTerminalHost(size: terminalSize)
    let result = try await runHarness(
      host: host,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      schedule: [
        .init(event: .mouse(.init(kind: .down(.primary), location: point))),
        .init(event: .mouse(.init(kind: .up(.primary), location: point))),
        .init(event: .mouse(.init(kind: .down(.primary), location: point))),
        .init(event: .mouse(.init(kind: .up(.primary), location: point))),
      ],
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(counts.double == 1)
    #expect(counts.single == 0)
  }
}

private struct NamedDragWrapper: Gesture {
  typealias Value = DragGesture.Value
  typealias Body = _EndedGesture<_ChangedGesture<DragGesture>>

  let onChanged: @MainActor (DragGesture.Value) -> Void
  let onEnded: @MainActor (DragGesture.Value) -> Void

  var body: Body {
    DragGesture(minimumDistance: 1)
      .onChanged(onChanged)
      .onEnded(onEnded)
  }
}

enum DeadlineLongPressAttachmentRole: String, CaseIterable, CustomStringConvertible,
  Sendable
{
  case ordinary
  case highPriority
  case simultaneous

  var description: String { rawValue }

  var expectedButtonActivations: Int {
    switch self {
    case .ordinary, .highPriority: 0
    case .simultaneous: 1
    }
  }
}

@MainActor
private func interactionPoint<V: View>(
  for view: V,
  terminalSize: CellSize,
  rootIdentity: Identity
) throws -> Point {
  var environment = EnvironmentValues()
  environment.terminalSize = terminalSize
  let pointerRegistry = LocalPointerHandlerRegistry()
  let gestureRegistry = LocalGestureRegistry()
  let gestureStateRegistry = LocalGestureStateRegistry()
  var context = ResolveContext(identity: rootIdentity, environmentValues: environment)
  context.localPointerHandlerRegistry = pointerRegistry
  context.localGestureRegistry = gestureRegistry
  context.localGestureStateRegistry = gestureStateRegistry
  let initial = DefaultRenderer().render(
    view,
    context: context,
    proposal: .init(width: terminalSize.width, height: terminalSize.height)
  )
  let region = try #require(
    initial.semanticSnapshot.interactionRegions
      .max { $0.hitTestOrder < $1.hitTestOrder }
  )
  return centerPoint(of: region.rect)
}

@MainActor
private func runHarness<V: View>(
  host: RecordingGestureTerminalHost,
  terminalSize: CellSize,
  rootIdentity: Identity,
  schedule: [ScheduledGestureInputEvent],
  viewBuilder: @escaping () -> V
) async throws -> RunLoopResult<Int> {
  var env = EnvironmentValues()
  env.terminalSize = terminalSize
  let runLoop = RunLoop(
    rootIdentity: rootIdentity,
    presentationSurface: host,
    terminalInputReader: ScriptedGestureInput(schedule: schedule),
    signalReader: EmptyGestureSignals(),
    scheduler: FrameScheduler(),
    stateContainer: StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    ),
    focusTracker: FocusTracker(
      invalidationIdentities: [rootIdentity]
    ),
    environmentValues: env,
    proposal: .init(width: terminalSize.width, height: terminalSize.height),
    viewBuilder: { _, _ in viewBuilder() }
  )
  return try await runLoop.run()
}

private struct ScheduledGestureInputEvent {
  let event: InputEvent
  /// Awaited before the event is yielded. The run loop deliberately coalesces
  /// same-batch pointer drags into one movement sample
  /// (`RunLoop.drainPendingEvents`), so a script that must observe each
  /// movement individually gates each event on evidence that the previous one
  /// was dispatched — a condition wait, never a sleep or a yield count.
  let gate: (@Sendable () async -> Void)?

  init(event: InputEvent, gate: (@Sendable () async -> Void)? = nil) {
    self.event = event
    self.gate = gate
  }
}

private func centerPoint(of rect: CellRect) -> Point {
  Point(
    x: Double(rect.origin.x + rect.size.width / 2),
    y: Double(rect.origin.y + rect.size.height / 2)
  )
}

private final class ScriptedGestureInput: TerminalInputReading {
  private let schedule: [ScheduledGestureInputEvent]

  init(schedule: [ScheduledGestureInputEvent]) {
    self.schedule = schedule
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let schedule = self.schedule
      let task = Task {
        for item in schedule {
          if let gate = item.gate {
            await gate()
          }
          continuation.yield(item.event)
        }
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}

private final class EmptyGestureSignals: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private final class RecordingGestureTerminalHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private let presentCountStorage = Mutex(0)

  /// Fires the first time the runtime presents a frame, so tests can `await`
  /// the initial render directly instead of polling `presentCount`.
  let firstPresent = AsyncEvent()

  var presentCount: Int {
    presentCountStorage.withLock { $0 }
  }

  init(size: CellSize) {
    self.surfaceSize = size
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_: RasterSurface) throws -> TerminalPresentationMetrics {
    presentCountStorage.withLock { $0 += 1 }
    firstPresent.fire()
    return .init(bytesWritten: 0, linesTouched: 0, cellsChanged: 0, strategy: .fullRepaint)
  }
}
