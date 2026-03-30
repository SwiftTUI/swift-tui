import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import TerminalUIScenes
@testable import View

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

private enum FocusedTitleKey: FocusedValueKey {
  typealias Value = String
}

@MainActor
@Suite
struct InteractiveRuntimeTests {
  private let lifecycleProbeIdentity = testIdentity("LifecycleRuntimeRoot", "RuntimeRoot[0]")

  @Test("state container requests invalidation when state changes")
  func stateContainerRequestsInvalidation() {
    let invalidator = RecordingInvalidator()
    let container = StateContainer(
      initialState: 0,
      invalidationIdentities: [testIdentity("RuntimeRoot")]
    )
    container.invalidator = invalidator

    let didChange = container.mutate { state in
      state = 1
    }

    #expect(didChange)
    #expect(container.state == 1)
    #expect(invalidator.requests == [[testIdentity("RuntimeRoot")]])
  }

  @Test("state container ignores unchanged replacements and mutations")
  func stateContainerIgnoresUnchangedUpdates() {
    let invalidator = RecordingInvalidator()
    let container = StateContainer(
      initialState: 7,
      invalidationIdentities: [testIdentity("RuntimeRoot")]
    )
    container.invalidator = invalidator

    #expect(!container.replace(with: 7))
    #expect(
      !container.mutate { state in
        state = 7
      })
    #expect(container.state == 7)
    #expect(invalidator.requests.isEmpty)
  }

  @Test("focus tracker preserves and wraps focus across regions")
  func focusTrackerWraps() {
    let invalidator = RecordingInvalidator()
    let tracker = FocusTracker(invalidationIdentities: [testIdentity("RuntimeRoot")])
    tracker.invalidator = invalidator

    let regions = [
      focusRegion(testIdentity("first")),
      focusRegion(testIdentity("second")),
      focusRegion(testIdentity("third")),
    ]

    let initialChange = tracker.updateRegions(regions)
    #expect(!initialChange)
    #expect(tracker.currentFocusIdentity == testIdentity("first"))

    tracker.focusNext()
    #expect(tracker.currentFocusIdentity == testIdentity("second"))

    tracker.focusNext()
    #expect(tracker.currentFocusIdentity == testIdentity("third"))

    tracker.focusNext()
    #expect(tracker.currentFocusIdentity == testIdentity("first"))

    tracker.focusPrevious()
    #expect(tracker.currentFocusIdentity == testIdentity("third"))
    #expect(invalidator.requests.count == 4)
  }

  @Test(
    "focus tracker falls back to the first remaining region when the focused identity disappears")
  func focusTrackerFallsBackWhenFocusedRegionDisappears() {
    let invalidator = RecordingInvalidator()
    let tracker = FocusTracker(invalidationIdentities: [testIdentity("RuntimeRoot")])
    tracker.invalidator = invalidator

    let first = focusRegion(testIdentity("first"))
    let second = focusRegion(testIdentity("second"))
    let third = focusRegion(testIdentity("third"))

    #expect(!tracker.updateRegions([first, second, third]))
    #expect(tracker.currentFocusIdentity == testIdentity("first"))

    _ = tracker.focusNext()
    #expect(tracker.currentFocusIdentity == testIdentity("second"))

    let changed = tracker.updateRegions([first, third])

    #expect(changed)
    #expect(tracker.currentFocusIdentity == testIdentity("first"))
    #expect(
      invalidator.requests.contains([
        testIdentity("second"),
        testIdentity("first"),
      ])
    )
  }

  @Test("focus tracker uses geometry for directional movement and does not wrap")
  func focusTrackerMovesByGeometryWithoutWrapping() {
    let invalidator = RecordingInvalidator()
    let tracker = FocusTracker(invalidationIdentities: [testIdentity("RuntimeRoot")])
    tracker.invalidator = invalidator

    #expect(
      !tracker.updateRegions([
        focusRegion(testIdentity("TopLeft"), x: 0, y: 0),
        focusRegion(testIdentity("BottomLeft"), x: 0, y: 2),
        focusRegion(testIdentity("TopRight"), x: 12, y: 0),
        focusRegion(testIdentity("BottomRight"), x: 12, y: 2),
      ]))
    #expect(tracker.currentFocusIdentity == testIdentity("TopLeft"))

    tracker.moveFocus(.right)
    #expect(tracker.currentFocusIdentity == testIdentity("TopRight"))

    tracker.moveFocus(.right)
    #expect(tracker.currentFocusIdentity == testIdentity("TopRight"))

    tracker.moveFocus(.down)
    #expect(tracker.currentFocusIdentity == testIdentity("BottomRight"))

    tracker.moveFocus(.left)
    #expect(tracker.currentFocusIdentity == testIdentity("BottomLeft"))

    tracker.moveFocus(.up)
    #expect(tracker.currentFocusIdentity == testIdentity("TopLeft"))
    #expect(invalidator.requests.count == 4)
  }

  @Test("focus tracker directional movement prefers the current focus section")
  func focusTrackerDirectionalMovementPrefersCurrentSection() {
    let tracker = FocusTracker(invalidationIdentities: [testIdentity("RuntimeRoot")])
    let scopePath = [testIdentity("Root", "Scope")]
    let sectionIdentity = testIdentity("Root", "Scope", "Section")

    #expect(
      !tracker.updateRegions([
        focusRegion(
          testIdentity("Root", "Scope", "Section", "Current"),
          x: 0,
          y: 0,
          scopePath: scopePath,
          sectionIdentity: sectionIdentity
        ),
        focusRegion(
          testIdentity("Root", "OtherCloser"),
          x: 6,
          y: 0
        ),
        focusRegion(
          testIdentity("Root", "Scope", "Section", "FarPeer"),
          x: 12,
          y: 0,
          scopePath: scopePath,
          sectionIdentity: sectionIdentity
        ),
      ]))

    tracker.moveFocus(.right)
    #expect(tracker.currentFocusIdentity == testIdentity("Root", "Scope", "Section", "FarPeer"))
  }

  @Test("focus tracker directional movement prefers the deepest shared scope when sections tie")
  func focusTrackerDirectionalMovementPrefersDeepestSharedScope() {
    let tracker = FocusTracker(invalidationIdentities: [testIdentity("RuntimeRoot")])

    #expect(
      !tracker.updateRegions([
        focusRegion(
          testIdentity("Root", "Scope", "Nested", "Current"),
          x: 0,
          y: 0,
          scopePath: [testIdentity("Root", "Scope"), testIdentity("Root", "Scope", "Nested")]
        ),
        focusRegion(
          testIdentity("Root", "OutsideCloser"),
          x: 4,
          y: 0
        ),
        focusRegion(
          testIdentity("Root", "Scope", "Peer"),
          x: 8,
          y: 0,
          scopePath: [testIdentity("Root", "Scope")]
        ),
        focusRegion(
          testIdentity("Root", "Scope", "Nested", "Peer"),
          x: 12,
          y: 0,
          scopePath: [testIdentity("Root", "Scope"), testIdentity("Root", "Scope", "Nested")]
        ),
      ]))

    tracker.moveFocus(.right)
    #expect(tracker.currentFocusIdentity == testIdentity("Root", "Scope", "Nested", "Peer"))
  }

  @Test("focused values registry resolves the nearest published ancestor value")
  func focusedValuesRegistryResolvesNearestAncestorValue() {
    let registry = LocalFocusedValuesRegistry()

    var rootValues = FocusedValues()
    rootValues[FocusedTitleKey.self] = "root"
    registry.register(identity: testIdentity("Root"), values: rootValues)

    var sectionValues = FocusedValues()
    sectionValues[FocusedTitleKey.self] = "section"
    registry.register(identity: testIdentity("Root", "Scope", "Section"), values: sectionValues)

    var leafValues = FocusedValues()
    leafValues[FocusedTitleKey.self] = "leaf"
    registry.register(
      identity: testIdentity("Root", "Scope", "Section", "Leaf"), values: leafValues)

    let focusedValues = registry.focusedValues(
      for: testIdentity("Root", "Scope", "Section", "Leaf", "Field"))

    #expect(focusedValues[FocusedTitleKey.self] == "leaf")
  }

  @Test("focus scope and section boundaries are preserved in extracted focus regions")
  func focusScopeAndSectionBoundariesAreCapturedInFocusRegions() {
    let artifacts = DefaultRenderer().render(
      scopeSectionFixture(),
      context: .init(identity: testIdentity("Root"))
    )

    let focusRegions = artifacts.semanticSnapshot.focusRegions

    #expect(
      focusRegions.map(\.identity) == [
        testIdentity("Root", "Scope", "Leading"),
        testIdentity("Root", "Scope", "Section", "First"),
        testIdentity("Root", "Scope", "Section", "Second"),
      ])
    #expect(focusRegions[0].scopePath == [testIdentity("Root", "Scope")])
    #expect(focusRegions[0].sectionIdentity == nil)
    #expect(focusRegions[1].scopePath == [testIdentity("Root", "Scope")])
    #expect(focusRegions[1].sectionIdentity == testIdentity("Root", "Scope", "Section"))
    #expect(focusRegions[2].scopePath == [testIdentity("Root", "Scope")])
    #expect(focusRegions[2].sectionIdentity == testIdentity("Root", "Scope", "Section"))
    #expect(
      !focusRegions.contains(where: {
        $0.identity == testIdentity("Root", "Scope")
          || $0.identity == testIdentity("Root", "Scope", "Section")
      })
    )
  }

  @Test("local action registry dispatches the registered identity handler")
  func localActionRegistryDispatchesIdentityHandler() {
    let registry = LocalActionRegistry()
    final class CounterBox {
      var value = 0
    }

    let value = CounterBox()
    registry.register(identity: testIdentity("counter", "increment")) {
      value.value += 1
      return true
    }

    #expect(registry.dispatch(identity: testIdentity("counter", "increment")))
    #expect(value.value == 1)
  }

  @Test("dynamic state store preserves typed values and local invalidation identities")
  func dynamicStateStorePreservesTypedValues() {
    let invalidator = RecordingInvalidator()
    let store = DynamicStateStore(invalidationIdentities: [testIdentity("RuntimeRoot")])
    store.invalidator = invalidator

    let key = "RuntimeRoot#State[InteractiveRuntimeTests:1:1]"
    let initial: Int = store.value(for: key, seedValue: 0)
    let repeated: Int = store.value(for: key, seedValue: 99)

    #expect(initial == 0)
    #expect(repeated == 0)

    store.set(3, for: key, invalidationIdentity: testIdentity("RuntimeRoot", "Child"))

    let updated: Int = store.value(for: key, seedValue: 0)
    #expect(updated == 3)
    #expect(invalidator.requests == [[testIdentity("RuntimeRoot", "Child")]])
  }

  @Test("key parser handles arrows, backspace, and required controls")
  func keyParserParsesExpectedSequences() {
    var parser = KeyParser()

    #expect(parser.feed([0x1B, 0x5B]).isEmpty)
    #expect(parser.feed([0x43]) == [.arrowRight])

    let remaining = parser.feed([
      0x1B, 0x5B, 0x41,
      0x1B, 0x5B, 0x42,
      0x7F,
      0x0D,
      0x09,
      0x1B, 0x5B, 0x44,
      0x1B, 0x5B, 0x5A,
      0x20,
      0x71,
      0x03,
    ])

    #expect(
      remaining == [
        .arrowUp,
        .arrowDown,
        .backspace,
        .enter,
        .tab,
        .arrowLeft,
        .shiftTab,
        .space,
        .character("q"),
        .ctrlC,
      ])
  }

  @Test("terminal input parser decodes partial mixed SGR mouse streams")
  func terminalInputParserDecodesMixedMouseStreams() {
    var parser = TerminalInputParser()

    #expect(parser.feed([0x1B, 0x5B, 0x3C, 0x32, 0x30]).isEmpty)

    let events = parser.feed([
      0x3B, 0x31, 0x30, 0x3B, 0x31, 0x32, 0x4D,
      0x71,
      0x1B, 0x5B, 0x3C, 0x36, 0x35, 0x3B, 0x35, 0x3B, 0x37, 0x4D,
      0x1B, 0x5B, 0x3C, 0x33, 0x34, 0x3B, 0x35, 0x3B, 0x37, 0x4D,
      0x1B, 0x5B, 0x3C, 0x33, 0x35, 0x3B, 0x35, 0x3B, 0x37, 0x4D,
      0x1B, 0x5B, 0x3C, 0x30, 0x3B, 0x35, 0x3B, 0x37, 0x6D,
    ])

    #expect(
      events == [
        .mouse(
          .init(
            kind: .down(.primary),
            location: .init(x: 9, y: 11),
            modifiers: [.shift, .control]
          )
        ),
        .key(.character("q")),
        .mouse(
          .init(
            kind: .scrolled(deltaX: 0, deltaY: 1),
            location: .init(x: 4, y: 6)
          )
        ),
        .mouse(
          .init(
            kind: .dragged(.secondary),
            location: .init(x: 4, y: 6)
          )
        ),
        .mouse(
          .init(
            kind: .moved,
            location: .init(x: 4, y: 6)
          )
        ),
        .mouse(
          .init(
            kind: .up(.primary),
            location: .init(x: 4, y: 6)
          )
        ),
      ])
  }

  @Test("input event coalescer collapses pointer bursts without crossing boundaries")
  func inputEventCoalescerCollapsesPointerBursts() {
    let events: [InputEvent] = [
      .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 1), location: .init(x: 2, y: 3))),
      .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 2), location: .init(x: 2, y: 3))),
      .mouse(.init(kind: .dragged(.primary), location: .init(x: 4, y: 1))),
      .mouse(.init(kind: .dragged(.primary), location: .init(x: 7, y: 1))),
      .key(.character("q")),
      .mouse(.init(kind: .moved, location: .init(x: 1, y: 1))),
      .mouse(.init(kind: .moved, location: .init(x: 3, y: 1))),
      .mouse(.init(kind: .down(.primary), location: .init(x: 3, y: 1))),
    ]

    #expect(
      coalescedInputEvents(events) == [
        .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 3), location: .init(x: 2, y: 3))),
        .mouse(.init(kind: .dragged(.primary), location: .init(x: 7, y: 1))),
        .key(.character("q")),
        .mouse(.init(kind: .moved, location: .init(x: 3, y: 1))),
        .mouse(.init(kind: .down(.primary), location: .init(x: 3, y: 1))),
      ])
  }

  @Test("input reader drains nonblocking pointer bursts across multiple reads")
  func inputReaderDrainsPointerBurstsAcrossMultipleReads() async throws {
    var descriptors: [Int32] = [0, 0]
    #expect(unsafe pipe(&descriptors) == 0)

    let readDescriptor = descriptors[0]
    let writeDescriptor = descriptors[1]
    var didCloseReadDescriptor = false
    var didCloseWriteDescriptor = false
    defer {
      if !didCloseReadDescriptor {
        _ = Darwin.close(readDescriptor)
      }
      if !didCloseWriteDescriptor {
        _ = Darwin.close(writeDescriptor)
      }
    }

    let currentFlags = fcntl(readDescriptor, F_GETFL)
    #expect(currentFlags >= 0)
    #expect(fcntl(readDescriptor, F_SETFL, currentFlags | O_NONBLOCK) >= 0)

    let scrollSequence: [UInt8] = [
      0x1B, 0x5B, 0x3C, 0x36, 0x35, 0x3B, 0x35, 0x3B, 0x37, 0x4D,
    ]
    let burstBytes = Array(
      repeating: scrollSequence,
      count: 52
    ).flatMap { $0 }

    try writeAllBytes(burstBytes, to: writeDescriptor)
    _ = Darwin.close(writeDescriptor)
    didCloseWriteDescriptor = true

    let inputReader = InputReader(fileDescriptor: readDescriptor)
    let receivedEvents = await Task {
      var events: [InputEvent] = []
      for await event in inputReader.inputEvents() {
        events.append(event)
      }
      return events
    }.value

    _ = Darwin.close(readDescriptor)
    didCloseReadDescriptor = true

    #expect(
      receivedEvents == [
        .mouse(
          .init(
            kind: .scrolled(deltaX: 0, deltaY: 52),
            location: .init(x: 4, y: 6)
          )
        )
      ])
  }

  @Test("input reader coalesces staggered pointer bursts before yielding")
  func inputReaderCoalescesStaggeredPointerBursts() async throws {
    var descriptors: [Int32] = [0, 0]
    #expect(unsafe pipe(&descriptors) == 0)

    let readDescriptor = descriptors[0]
    let writeDescriptor = descriptors[1]
    var didCloseReadDescriptor = false
    var didCloseWriteDescriptor = false
    defer {
      if !didCloseReadDescriptor {
        _ = Darwin.close(readDescriptor)
      }
      if !didCloseWriteDescriptor {
        _ = Darwin.close(writeDescriptor)
      }
    }

    let currentFlags = fcntl(readDescriptor, F_GETFL)
    #expect(currentFlags >= 0)
    #expect(fcntl(readDescriptor, F_SETFL, currentFlags | O_NONBLOCK) >= 0)

    let scrollSequence: [UInt8] = [
      0x1B, 0x5B, 0x3C, 0x36, 0x35, 0x3B, 0x35, 0x3B, 0x37, 0x4D,
    ]
    let inputReader = InputReader(fileDescriptor: readDescriptor)

    let receivedEventsTask = Task {
      var events: [InputEvent] = []
      for await event in inputReader.inputEvents() {
        events.append(event)
      }
      return events
    }

    let writerTask = Task {
      for _ in 0..<20 {
        try writeAllBytes(scrollSequence, to: writeDescriptor)
        // Keep writes staggered but still well inside the 1 ms flush window.
        // Task.sleep() was coarse enough on some runners to miss coalescing
        // entirely and turn this into a scheduler test instead.
        usleep(50)
      }
    }

    _ = await writerTask.result
    _ = Darwin.close(writeDescriptor)
    didCloseWriteDescriptor = true
    let receivedEvents = await receivedEventsTask.value

    _ = Darwin.close(readDescriptor)
    didCloseReadDescriptor = true

    #expect(!receivedEvents.isEmpty)
    #expect(receivedEvents.count < 20)
    #expect(
      receivedEvents.allSatisfy { event in
        guard case .mouse(let mouseEvent) = event,
          case .scrolled(let deltaX, let deltaY) = mouseEvent.kind
        else {
          return false
        }
        return deltaX == 0
          && deltaY > 0
          && mouseEvent.location == .init(x: 4, y: 6)
      }
    )
    #expect(
      receivedEvents.reduce(0) { partial, event in
        guard case .mouse(let mouseEvent) = event,
          case .scrolled(_, let deltaY) = mouseEvent.kind
        else {
          return partial
        }
        return partial + deltaY
      } == 20
    )
  }

  @Test("terminal host enables raw mode and restores saved attributes")
  func terminalHostEnablesAndRestoresRawMode() throws {
    let controller = MockTerminalController()
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .previewUnicode
    )

    try host.enableRawMode()
    try host.disableRawMode()

    #expect(controller.setAttributesCalls.count == 2)
    #expect(termiosEqual(controller.setAttributesCalls[1], controller.originalAttributes))
    #expect(!termiosEqual(controller.setAttributesCalls[0], controller.originalAttributes))
    #expect(
      controller.writes == [
        "\u{001B}]10;?\u{0007}",
        "\u{001B}]11;?\u{0007}",
        "\u{001B}]4;1;?\u{0007}",
        "\u{001B}]4;2;?\u{0007}",
        "\u{001B}]4;3;?\u{0007}",
        "\u{001B}]4;4;?\u{0007}",
        "\u{001B}]4;6;?\u{0007}",
        "\u{001B}]4;8;?\u{0007}",
        "\u{001B}[?1049h",
        "\u{001B}[2J",
        "\u{001B}[1;1H",
        "\u{001B}[?25l",
        "\u{001B}[2J",
        "\u{001B}[1;1H",
        "\u{001B}[0m",
        "\u{001B}[?25h",
        "\u{001B}[?1049l",
      ])
  }

  @Test("terminal host enables and disables mouse reporting for capable terminals")
  func terminalHostTogglesMouseReportingInRawMode() throws {
    let controller = MockTerminalController()
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .trueColor
    )

    try host.enableRawMode()
    try host.disableRawMode()

    #expect(controller.writes.contains("\u{001B}[?1002h\u{001B}[?1006h"))
    #expect(controller.writes.contains("\u{001B}[?1002l\u{001B}[?1006l"))
  }

  @Test("terminal host resets retained presentation state across raw-mode sessions")
  func terminalHostResetsRetainedPresentationStateAcrossSessions() throws {
    let controller = MockTerminalController()
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .previewUnicode
    )
    let surface = RasterSurface(
      size: .init(width: 8, height: 1),
      lines: ["session"]
    )

    try host.enableRawMode()
    _ = try host.present(surface)
    try host.disableRawMode()

    try host.enableRawMode()
    let metrics = try host.present(surface)
    try host.disableRawMode()

    #expect(metrics.strategy == .fullRepaint)
    #expect(metrics.usedFullRepaint)
  }

  @Test("state-aware builder exposes scroll indicators and text input cursor")
  @MainActor
  func builderReflectsScrollableListAndTextInput() throws {
    let root = interactiveDemoScene(
      state: .init(value: 12),
      focusedIdentity: InteractiveDemoIdentity.inputField
    )
    let resolved = root.resolve(
      in: .init(
        identity: InteractiveDemoIdentity.root,
        environmentValues: .init()
      )
    )

    let listNode = try #require(
      resolved.descendant(with: InteractiveDemoIdentity.presetList)
    )
    let menuNode = try #require(
      resolved.descendant(with: InteractiveDemoIdentity.presetMenu)
    )
    let inputNode = try #require(
      resolved.descendant(with: InteractiveDemoIdentity.inputField)
    )
    let selectionModeNode = try #require(
      resolved.descendant(with: InteractiveDemoIdentity.selectionModePicker)
    )

    #expect(listNode.drawPayload != .none)
    #expect(menuNode.semanticMetadata.presentationRole == .picker)
    #expect(inputNode.semanticMetadata.presentationRole == .textField)
    #expect(selectionModeNode.semanticMetadata.presentationRole == .picker)
    #expect(inputNode.descendant(withText: "12_") != nil)
    #expect(resolved.descendant(withText: "Live Metrics") != nil)
    #expect(resolved.descendant(withText: "Preset Sync") != nil)
    #expect(resolved.descendant(withText: "Run Compare") != nil)
    #expect(resolved.descendant(withText: "Preset Trend") != nil)
    #expect(resolved.descendant(withText: "Run Stats") != nil)
    #expect(resolved.descendant(withText: "Preset Flow") != nil)
    #expect(resolved.descendant(withText: "Selection Modes") != nil)
    #expect(resolved.descendant(withText: "Wide: \u{754C}\u{1F642}e\u{301} cells align") != nil)
    #expect(resolved.descendant(withText: "Scroll: viewport clips overflow") != nil)
    #expect(
      resolved.descendant(withText: "Tab | Enter | arrows | q | unicode | mono | plain | dark")
        != nil)

    let artifacts = DefaultRenderer().render(
      interactiveDemoScene(
        state: .init(value: 12),
        focusedIdentity: InteractiveDemoIdentity.inputField
      ),
      context: .init(
        identity: InteractiveDemoIdentity.root
      )
    )
    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(
      artifacts.semanticSnapshot.focusRegions.map(\.identity).contains(
        InteractiveDemoIdentity.presetMenu))
    #expect(
      artifacts.semanticSnapshot.focusRegions.map(\.identity).contains(
        InteractiveDemoIdentity.inputField))
    #expect(
      artifacts.semanticSnapshot.focusRegions.map(\.identity).contains(
        InteractiveDemoIdentity.selectionModePicker))
    #expect(surface.contains("↓"))
    #expect(surface.contains("12_"))
  }

  @Test("interactive demo traversal follows the authored control surfaces")
  @MainActor
  func interactiveDemoTraversalMatchesControlSurfaceOrder() throws {
    let artifacts = DefaultRenderer().render(
      interactiveDemoScene(
        state: .init(value: 12),
        focusedIdentity: nil
      ),
      context: .init(identity: InteractiveDemoIdentity.root)
    )

    let expectedOrder: [Identity] = [
      InteractiveDemoIdentity.incrementButton,
      InteractiveDemoIdentity.decrementButton,
      InteractiveDemoIdentity.resetButton,
      InteractiveDemoIdentity.accentToggle,
      InteractiveDemoIdentity.presetMenu,
      InteractiveDemoIdentity.presetList,
      InteractiveDemoIdentity.inputField,
      InteractiveDemoIdentity.selectionModePicker,
      InteractiveDemoIdentity.textLabDisclosure,
      verticalScrollIndicatorIdentity(for: InteractiveDemoIdentity.textLabScrollPreview),
    ]

    #expect(artifacts.semanticSnapshot.focusRegions.map(\.identity) == expectedOrder)

    let tracker = FocusTracker(
      invalidationIdentities: [InteractiveDemoIdentity.root]
    )
    _ = tracker.updateRegions(artifacts.semanticSnapshot.focusRegions)
    #expect(tracker.currentFocusIdentity == expectedOrder[0])

    for identity in expectedOrder.dropFirst() {
      tracker.focusNext()
      #expect(tracker.currentFocusIdentity == identity)
    }

    tracker.focusNext()
    #expect(tracker.currentFocusIdentity == expectedOrder[0])
  }

  @Test("interactive demo disables reset at zero and re-enables it off zero")
  @MainActor
  func interactiveDemoReflectsDisabledResetState() throws {
    let disabledArtifacts = DefaultRenderer().render(
      interactiveDemoScene(
        state: .init(value: 0),
        focusedIdentity: nil
      ),
      context: .init(identity: InteractiveDemoIdentity.root)
    )
    let enabledArtifacts = DefaultRenderer().render(
      interactiveDemoScene(
        state: .init(value: 1),
        focusedIdentity: nil
      ),
      context: .init(identity: InteractiveDemoIdentity.root)
    )

    let disabledReset = try #require(
      disabledArtifacts.resolvedTree.descendant(with: InteractiveDemoIdentity.resetButton)
    )
    let enabledReset = try #require(
      enabledArtifacts.resolvedTree.descendant(with: InteractiveDemoIdentity.resetButton)
    )

    #expect(disabledReset.kind == .view("Button"))
    #expect(disabledReset.environmentSnapshot.style.isEnabled == false)
    #expect(enabledReset.environmentSnapshot.style.isEnabled == true)
    #expect(
      disabledArtifacts.semanticSnapshot.focusRegions.map(\.identity) == [
        InteractiveDemoIdentity.incrementButton,
        InteractiveDemoIdentity.decrementButton,
        InteractiveDemoIdentity.accentToggle,
        InteractiveDemoIdentity.presetMenu,
        InteractiveDemoIdentity.presetList,
        InteractiveDemoIdentity.inputField,
        InteractiveDemoIdentity.selectionModePicker,
        InteractiveDemoIdentity.textLabDisclosure,
        verticalScrollIndicatorIdentity(for: InteractiveDemoIdentity.textLabScrollPreview),
      ])
    #expect(
      disabledArtifacts.semanticSnapshot.interactionRegions.contains {
        $0.identity == InteractiveDemoIdentity.incrementButton
      })
    #expect(
      disabledArtifacts.semanticSnapshot.interactionRegions.contains {
        $0.identity == InteractiveDemoIdentity.decrementButton
      })
    #expect(
      !disabledArtifacts.semanticSnapshot.interactionRegions.contains {
        $0.identity == InteractiveDemoIdentity.resetButton
      })
    #expect(
      enabledArtifacts.semanticSnapshot.interactionRegions.contains {
        $0.identity == InteractiveDemoIdentity.resetButton
      })
  }

  @Test("interactive demo scene exercises truncation, clipping, wide glyphs, and styled text")
  @MainActor
  func interactiveDemoSceneExercisesModernTextFeatures() {
    let artifacts = DefaultRenderer().render(
      modernTextFeatureFixture(displayedInput: "12"),
      context: .init(identity: testIdentity("InteractiveDemo", "text-features"))
    )
    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    let hasStyledAccentRun = artifacts.rasterSurface.styleRuns.contains { run in
      run.style.foregroundColor == .cyan
        && run.style.emphasis == .bold
        && run.style.underlineStyle == .init(pattern: .dash, color: .yellow)
        && run.style.strikethroughStyle == .init(pattern: .dot, color: .red)
        && run.style.opacity == 0.8
    }

    #expect(surface.contains("Clip: [12]"))
    #expect(surface.contains("…"))
    #expect(
      artifacts.resolvedTree.descendant(withText: "Wide: \u{754C}\u{1F642}e\u{301} cells align")
        != nil)
    #expect(surface.contains("Scroll: viewport clips overflow"))
    #expect(!surface.contains("Scroll: semantic content bounds persist"))
    #expect(surface.contains("Style run: accent emphasis"))
    #expect(hasStyledAccentRun)
  }

  @MainActor
  @Test("headless run loop updates the selection-mode picker directly from focus")
  func headlessRunLoopChangesSelectionMode() async throws {
    let terminal = RecordingTerminalHost()
    let result = try await makeRuntimeHarness(
      terminal: terminal,
      events: [.tab, .tab, .tab, .tab, .tab, .tab, .arrowDown, .escape, .tab, .character("q")]
    )

    #expect(result.exitReason == .quitKey)
    #expect(result.finalState.selectionMode == .accent)
    #expect(
      terminal.frames.contains(where: {
        $0.contains("(*) Inspect") && $0.contains("( ) Accent")
      }))
    let lastFrame = try #require(terminal.frames.last)
    #expect(lastFrame.contains("( ) Inspect"))
    #expect(lastFrame.contains("(*) Accent"))
    #expect(lastFrame.contains("Mode accent"))
  }

  @MainActor
  @Test("headless run loop scrolls the preset viewport and applies the selected preset")
  func headlessRunLoopScrollsPresetViewport() async throws {
    let terminal = RecordingTerminalHost()
    let result = try await makeRuntimeHarness(
      terminal: terminal,
      events: [.tab, .tab, .tab, .tab, .arrowDown, .arrowDown, .arrowUp, .enter, .character("q")]
    )

    #expect(result.exitReason == .quitKey)
    #expect(result.finalState == InteractiveDemoState(value: 2))
    let firstFrame = try #require(terminal.frames.first)
    #expect(firstFrame.contains("▤ Presets"))
    #expect(firstFrame.contains("││-9"))
    #expect(firstFrame.contains("││↓"))
    #expect(
      terminal.frames.contains(where: {
        $0.contains("││↑")
          && $0.contains("││▌ 2")
      }))
    let lastFrame = try #require(terminal.frames.last)
    #expect(lastFrame.contains("││▌ 2 *"))
  }

  @MainActor
  @Test("headless run loop edits the text field and applies a typed value")
  func headlessRunLoopEditsTextField() async throws {
    let terminal = RecordingTerminalHost()
    let result = try await makeRuntimeHarness(
      terminal: terminal,
      events: [
        .tab, .tab, .tab, .tab, .tab, .backspace, .character("-"), .character("1"), .character("2"),
        .enter, .character("q"),
      ]
    )

    #expect(result.exitReason == .quitKey)
    #expect(result.finalState.value == -12)
    #expect(result.finalState.inputBuffer == "-12")
    let firstMetrics = try #require(terminal.presentationMetrics.first)
    let firstSurfaceSize = try #require(terminal.presentedSurfaceSizes.first)
    #expect(terminal.frames.contains(where: { $0.contains("0_") }))
    #expect(terminal.frames.contains(where: { $0.contains("-12_") }))
    let lastFrame = try #require(terminal.frames.last)
    #expect(lastFrame.contains("-12_"))
    #expect(firstMetrics.usedFullRepaint)
    #expect(firstMetrics.cellsChanged == firstSurfaceSize.width * firstSurfaceSize.height)
  }

  @MainActor
  @Test("headless run loop toggles accent preview through the local binding action path")
  func headlessRunLoopTogglesAccentPreview() async throws {
    let terminal = RecordingTerminalHost()
    let result = try await makeRuntimeHarness(
      terminal: terminal,
      events: [.tab, .tab, .enter, .character("q")]
    )

    #expect(result.exitReason == .quitKey)
    #expect(result.finalState.accentPreviewEnabled)
    #expect(terminal.frames.contains(where: { $0.contains("Accent Preview") }))
  }

  @MainActor
  @Test("run loop passes scheduled invalidations into resolve context")
  func runLoopPassesScheduledInvalidationsIntoResolveContext() async throws {
    let terminal = RecordingTerminalHost()
    let recorder = RunLoopInvalidationRecorder()
    let rootIdentity = testIdentity("RunLoopProbe")
    let childIdentity = rootIdentity.child("ProbeRoot[0]")
    let stateContainer = StateContainer(
      initialState: 0,
      invalidationIdentities: [childIdentity]
    )

    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      terminalHost: terminal,
      inputReader: ScriptedInputReader(events: [.enter, .character("q")]),
      signalReader: EmptySignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: stateContainer,
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      keyHandler: { keyEvent, _, stateContainer in
        guard keyEvent == .enter else {
          return .ignored
        }
        _ = stateContainer.mutate { $0 += 1 }
        return .handled
      },
      viewBuilder: { state, _ in
        RunLoopInvalidationProbeRoot(
          state: state,
          recorder: recorder
        )
      }
    )

    let result = try await runLoop.run()

    #expect(result.exitReason == .quitKey)
    #expect(result.finalState == 1)

    let initialRoot = try #require(
      recorder.records.first { $0.state == 0 && $0.identity == rootIdentity }
    )
    let initialChild = try #require(
      recorder.records.first { $0.state == 0 && $0.identity == childIdentity }
    )
    let updatedRoot = try #require(
      recorder.records.first { $0.state == 1 && $0.identity == rootIdentity }
    )
    let updatedChild = try #require(
      recorder.records.first { $0.state == 1 && $0.identity == childIdentity }
    )

    #expect(initialRoot.invalidatedIdentities == [rootIdentity])
    #expect(initialRoot.isSelfInvalidated)
    #expect(initialRoot.subtreeAffected)

    #expect(initialChild.invalidatedIdentities == [rootIdentity])
    #expect(!initialChild.isSelfInvalidated)
    #expect(initialChild.subtreeAffected)

    #expect(updatedRoot.invalidatedIdentities == [childIdentity])
    #expect(!updatedRoot.isSelfInvalidated)
    #expect(updatedRoot.subtreeAffected)

    #expect(updatedChild.invalidatedIdentities == [childIdentity])
    #expect(updatedChild.isSelfInvalidated)
    #expect(updatedChild.subtreeAffected)
  }

  @MainActor
  @Test("standalone Link opens its destination on keyboard activation")
  func standaloneLinkOpensDestinationOnKeyboardActivation() async throws {
    let terminal = RecordingTerminalHost(
      surfaceSizeProvider: { .init(width: 20, height: 1) }
    )
    let recorder = LinkOpenRecorder()

    let result = try await runTerminalInputHarness(
      terminal: terminal,
      events: [
        .key(.enter),
        .key(.character("q")),
      ],
      rootIdentity: testIdentity("StandaloneLinkRuntime"),
      terminalSize: .init(width: 20, height: 1),
      configureEnvironmentValues: { environmentValues in
        environmentValues.openLinkAction = OpenLinkAction { destination in
          recorder.destinations.append(destination)
          return true
        }
      },
      viewBuilder: {
        Link("Docs", destination: "https://example.com")
          .id(testIdentity("StandaloneLinkRuntime", "Link"))
      }
    )

    #expect(result.exitReason == .quitKey)
    #expect(recorder.destinations == ["https://example.com"])
  }

  @MainActor
  @Test("inline links inside a Text view focus separately and open in order")
  func inlineLinksFocusSeparatelyAndOpenInOrder() async throws {
    let terminal = RecordingTerminalHost(
      surfaceSizeProvider: { .init(width: 24, height: 1) }
    )
    let recorder = LinkOpenRecorder()

    let result = try await runTerminalInputHarness(
      terminal: terminal,
      events: [
        .key(.enter),
        .key(.tab),
        .key(.enter),
        .key(.character("q")),
      ],
      rootIdentity: testIdentity("InlineLinkRuntime"),
      terminalSize: .init(width: 24, height: 1),
      configureEnvironmentValues: { environmentValues in
        environmentValues.openLinkAction = OpenLinkAction { destination in
          recorder.destinations.append(destination)
          return true
        }
      },
      viewBuilder: {
        Text(
          "\(Link("One", destination: "https://one.example")) \(Link("Two", destination: "https://two.example"))"
        )
      }
    )

    #expect(result.exitReason == .quitKey)
    #expect(
      recorder.destinations == [
        "https://one.example",
        "https://two.example",
      ]
    )
  }

  @MainActor
  @Test("mouse activation opens links through the runtime action path")
  func mouseActivationOpensLinksThroughRuntimeActionPath() async throws {
    let rootIdentity = testIdentity("MouseLinkRuntime")
    let linkIdentity = testIdentity("MouseLinkRuntime", "Link")
    let terminalSize = Size(width: 20, height: 1)
    let view = Link("Docs", destination: "https://example.com")
      .id(linkIdentity)
    let rect = try #require(
      renderedInteractionRect(
        for: primaryRouteID(for: linkIdentity),
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )

    let terminal = RecordingTerminalHost(
      surfaceSizeProvider: { terminalSize }
    )
    let recorder = LinkOpenRecorder()
    let result = try await runTerminalInputHarness(
      terminal: terminal,
      events: [
        .mouse(.init(kind: .down(.primary), location: centerPoint(of: rect))),
        .mouse(.init(kind: .up(.primary), location: centerPoint(of: rect))),
        .key(.character("q")),
      ],
      rootIdentity: rootIdentity,
      terminalSize: terminalSize,
      configureEnvironmentValues: { environmentValues in
        environmentValues.openLinkAction = OpenLinkAction { destination in
          recorder.destinations.append(destination)
          return true
        }
      },
      viewBuilder: {
        view
      }
    )

    #expect(result.exitReason == .quitKey)
    #expect(recorder.destinations == ["https://example.com"])
  }

  @Test("reused interactive subtrees replay local handlers after registry reset")
  func reusedInteractiveSubtreesReplayLocalHandlers() {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let actionRegistry = LocalActionRegistry()
    let keyRegistry = LocalKeyHandlerRegistry()
    let recorder = ReusedHandlerRecorder()

    _ = renderer.render(
      ReusedHandlerRoot(recorder: recorder, dirtyLabel: "Dirty 0"),
      context: .init(
        identity: testIdentity("Root"),
        localActionRegistry: actionRegistry,
        localKeyHandlerRegistry: keyRegistry,
        applyEnvironmentValues: true
      )
    )

    #expect(actionRegistry.dispatch(identity: testIdentity("Root", "Harness[0]")))
    #expect(keyRegistry.dispatch(identity: testIdentity("Root", "Harness[0]"), event: .enter))
    #expect(recorder.actionCount == 1)
    #expect(recorder.keyEvents == [.enter])

    actionRegistry.reset()
    keyRegistry.reset()

    let updated = renderer.render(
      ReusedHandlerRoot(recorder: recorder, dirtyLabel: "Dirty 1"),
      context: .init(
        identity: testIdentity("Root"),
        invalidatedIdentities: [testIdentity("Root", "Harness[1]")],
        localActionRegistry: actionRegistry,
        localKeyHandlerRegistry: keyRegistry,
        applyEnvironmentValues: true
      )
    )

    #expect(updated.diagnostics.resolvedNodesReused > 0)
    #expect(actionRegistry.dispatch(identity: testIdentity("Root", "Harness[0]")))
    #expect(keyRegistry.dispatch(identity: testIdentity("Root", "Harness[0]"), event: .space))
    #expect(recorder.actionCount == 2)
    #expect(recorder.keyEvents == [.enter, .space])
  }

  @MainActor
  @Test("run loop applies lifecycle callbacks only after a frame is committed")
  func runLoopAppliesLifecycleCallbacksOnlyAfterCommit() async throws {
    let recorder = RuntimeLifecycleRecorder()
    let terminal = RecordingTerminalHost(
      presentObserver: {
        recorder.recordAppearCountAtPresent()
      }
    )

    let result = try await makeLifecycleRuntimeHarness(
      terminal: terminal,
      recorder: recorder,
      focusable: true,
      events: [
        .init(delayNanoseconds: 50_000_000, value: .character("q"))
      ]
    )

    #expect(result.exitReason == .quitKey)
    #expect(terminal.frames.count == 1)
    #expect(recorder.appearCountsAtPresent == [0])
    #expect(recorder.events(matchingPrefix: "appear:").count == 1)
  }

  @MainActor
  @Test(
    "run loop consumes lifecycle deltas and previous disappear handlers across committed frames")
  func runLoopConsumesLifecycleDeltasAcrossCommittedFrames() async throws {
    let recorder = RuntimeLifecycleRecorder()
    let terminal = RecordingTerminalHost()

    let result = try await makeLifecycleRuntimeHarness(
      terminal: terminal,
      recorder: recorder,
      events: [
        .init(delayNanoseconds: 50_000_000, value: .character("t")),
        .init(delayNanoseconds: 50_000_000, value: .character("q")),
      ]
    )

    #expect(result.exitReason == .quitKey)
    #expect(result.finalState.showChild == false)
    #expect(await recorder.waitForEvent("taskStart:\(lifecycleProbeIdentity)"))
    #expect(await recorder.waitForEvent("disappear:\(lifecycleProbeIdentity)"))
    #expect(await recorder.waitForEvent("taskCancel:\(lifecycleProbeIdentity)"))
    #expect(
      recorder.events(matchingPrefix: "appear:") == [
        "appear:\(lifecycleProbeIdentity)"
      ])
  }

  @MainActor
  @Test("run loop cancels lifecycle tasks on quit key")
  func runLoopCancelsLifecycleTasksOnQuitKey() async throws {
    let recorder = RuntimeLifecycleRecorder()

    let result = try await makeLifecycleRuntimeHarness(
      terminal: RecordingTerminalHost(),
      recorder: recorder,
      events: [
        .init(delayNanoseconds: 50_000_000, value: .character("q"))
      ]
    )

    #expect(result.exitReason == .quitKey)
    #expect(await recorder.waitForEvent("taskCancel:\(lifecycleProbeIdentity)"))
  }

  @MainActor
  @Test("run loop cancels lifecycle tasks on ctrl-c")
  func runLoopCancelsLifecycleTasksOnCtrlC() async throws {
    let recorder = RuntimeLifecycleRecorder()

    let result = try await makeLifecycleRuntimeHarness(
      terminal: RecordingTerminalHost(),
      recorder: recorder,
      events: [
        .init(delayNanoseconds: 50_000_000, value: .ctrlC)
      ]
    )

    #expect(result.exitReason == .ctrlC)
    #expect(await recorder.waitForEvent("taskCancel:\(lifecycleProbeIdentity)"))
  }

  @MainActor
  @Test("run loop cancels lifecycle tasks when input ends")
  func runLoopCancelsLifecycleTasksWhenInputEnds() async throws {
    let recorder = RuntimeLifecycleRecorder()

    let result = try await makeLifecycleRuntimeHarness(
      terminal: RecordingTerminalHost(),
      recorder: recorder,
      events: []
    )

    #expect(result.exitReason == .inputEnded)
    #expect(await recorder.waitForEvent("taskCancel:\(lifecycleProbeIdentity)"))
  }

  @MainActor
  @Test("run loop cancels lifecycle tasks on signal exit")
  func runLoopCancelsLifecycleTasksOnSignalExit() async throws {
    let recorder = RuntimeLifecycleRecorder()

    let result = try await makeLifecycleRuntimeHarness(
      terminal: RecordingTerminalHost(),
      recorder: recorder,
      events: [],
      signals: [
        .init(delayNanoseconds: 50_000_000, value: "SIGTERM")
      ]
    )

    #expect(result.exitReason == .signal("SIGTERM"))
    #expect(await recorder.waitForEvent("taskCancel:\(lifecycleProbeIdentity)"))
  }

  @MainActor
  @Test("app runtime rerenders on SIGWINCH without exiting")
  func appRuntimeRerendersOnSIGWINCHWithoutExiting() async throws {
    let initialSize = Size(width: 24, height: 6)
    let resizedSize = Size(width: 32, height: 8)
    var currentSize = initialSize
    var appliedResize = false
    var presentationCount = 0
    let quitGate = AsyncEventGate()

    let terminal = RecordingTerminalHost(
      surfaceSizeProvider: { currentSize },
      presentObserver: {
        presentationCount += 1
        if !appliedResize {
          appliedResize = true
          currentSize = resizedSize
        } else if presentationCount >= 2 {
          Task {
            await quitGate.open()
          }
        }
      }
    )

    let result = try await MultiSceneLauncher.run(
      scene: WindowGroup("Resize Window") {
        Text("Resize")
      },
      sessionName: "InteractiveRuntimeTests.ResizeWindow",
      terminalHost: terminal,
      inputReader: GateInputReader(gate: quitGate, event: .character("q")),
      signalReader: TimedSignalReader(
        signals: [
          .init(delayNanoseconds: 50_000_000, value: "SIGWINCH")
        ]
      )
    )

    #expect(result.exitReason == .quitKey)
    #expect(result.renderedFrames == 2)
    #expect(terminal.presentedSurfaceSizes == [initialSize, resizedSize])
  }

  @MainActor
  @Test("mouse input updates built-in controls through click drag and wheel paths")
  func mouseInputUpdatesBuiltInControls() async throws {
    let box = MouseControlBox()
    let terminalSize = Size(width: 72, height: 48)
    let terminal = RecordingTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("MouseFixture")
    let view = mouseControlFixture(box: box)

    let buttonRect = try #require(
      renderedInteractionRect(
        for: primaryRouteID(for: testIdentity("MouseFixture", "Button")),
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )
    let stepperRootRect = try #require(
      renderedInteractionRect(
        for: primaryRouteID(for: testIdentity("MouseFixture", "Stepper")),
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )
    let stepperIncrementRect = try #require(
      renderedInteractionRect(
        for: primaryRouteID(
          for: stepperIncrementIdentity(for: testIdentity("MouseFixture", "Stepper"))
        ),
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )
    let sliderTrackRect = try #require(
      renderedInteractionRect(
        for: primaryRouteID(
          for: sliderTrackIdentity(for: testIdentity("MouseFixture", "Slider"))
        ),
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )
    let pickerRootRect = try #require(
      renderedInteractionRect(
        for: primaryRouteID(for: testIdentity("MouseFixture", "Picker")),
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )
    let pickerOptionRect = try #require(
      renderedInteractionRect(
        for: primaryRouteID(
          for: pickerOptionIdentity(for: testIdentity("MouseFixture", "Picker"), index: 2)
        ),
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )
    let listRootRect = try #require(
      renderedInteractionRect(
        for: primaryRouteID(for: testIdentity("MouseFixture", "List")),
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )
    let listRowRect = try #require(
      renderedInteractionRect(
        for: primaryRouteID(
          for: listRowIdentity(for: testIdentity("MouseFixture", "List"), rowIndex: 2)
        ),
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )
    let tableRootRect = try #require(
      renderedInteractionRect(
        for: primaryRouteID(for: testIdentity("MouseFixture", "Table")),
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )
    let scrollRect = try #require(
      renderedInteractionRect(
        for: primaryRouteID(for: testIdentity("MouseFixture", "Scroll")),
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )
    let fieldRect = try #require(
      renderedInteractionRect(
        for: primaryRouteID(for: testIdentity("MouseFixture", "Field")),
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )

    _ = try await runTerminalInputHarness(
      terminal: terminal,
      events: [
        .mouse(.init(kind: .down(.primary), location: centerPoint(of: buttonRect))),
        .mouse(.init(kind: .up(.primary), location: centerPoint(of: buttonRect))),
        .mouse(
          .init(kind: .scrolled(deltaX: 0, deltaY: -1), location: centerPoint(of: stepperRootRect))),
        .mouse(.init(kind: .down(.primary), location: centerPoint(of: stepperIncrementRect))),
        .mouse(.init(kind: .up(.primary), location: centerPoint(of: stepperIncrementRect))),
        .mouse(.init(kind: .down(.primary), location: leadingPoint(of: sliderTrackRect))),
        .mouse(.init(kind: .dragged(.primary), location: trailingPoint(of: sliderTrackRect))),
        .mouse(.init(kind: .up(.primary), location: trailingPoint(of: sliderTrackRect))),
        .mouse(
          .init(kind: .scrolled(deltaX: 0, deltaY: -1), location: centerPoint(of: pickerRootRect))),
        .mouse(.init(kind: .down(.primary), location: centerPoint(of: pickerOptionRect))),
        .mouse(.init(kind: .up(.primary), location: centerPoint(of: pickerOptionRect))),
        .mouse(
          .init(kind: .scrolled(deltaX: 0, deltaY: 1), location: centerPoint(of: listRootRect))),
        .mouse(.init(kind: .down(.primary), location: centerPoint(of: listRowRect))),
        .mouse(.init(kind: .up(.primary), location: centerPoint(of: listRowRect))),
        .mouse(
          .init(kind: .scrolled(deltaX: 0, deltaY: 1), location: centerPoint(of: tableRootRect))),
        .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 1), location: centerPoint(of: scrollRect))),
        .mouse(.init(kind: .down(.primary), location: centerPoint(of: fieldRect))),
        .mouse(.init(kind: .up(.primary), location: centerPoint(of: fieldRect))),
        .key(.character("A")),
      ],
      rootIdentity: rootIdentity,
      terminalSize: terminalSize,
      viewBuilder: { view }
    )

    #expect(box.buttonTaps == 1)
    #expect(box.stepperValue == 3)
    #expect(box.sliderValue == 10)
    #expect(box.pickerSelection == 3)
    #expect(box.listSelection == 2 || box.listSelection == 3)
    #expect(box.tableSelection == 2)
    #expect(box.scrollPosition.y == 1)
    #expect(box.text == "A")
  }

  @MainActor
  @Test("mouse click on a ScrollView indicator jumps scrolling to that location")
  func mouseClickOnScrollIndicatorJumpsToLocation() async throws {
    let box = MouseControlBox()
    let terminalSize = Size(width: 16, height: 8)
    let rootIdentity = testIdentity("ScrollIndicatorClickFixture")
    let view =
      ScrollView(
        .vertical,
        position: .init(
          get: { box.scrollPosition },
          set: { box.scrollPosition = $0 }
        )
      ) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<10) { index in
            Text("Row \(index)")
          }
        }
      }
      .id(testIdentity("ScrollIndicatorClickFixture", "Scroll"))
      .frame(width: 10, height: 5, alignment: .topLeading)

    let indicatorRect = try #require(
      renderedInteractionRect(
        for: primaryRouteID(
          for: verticalScrollIndicatorIdentity(
            for: testIdentity("ScrollIndicatorClickFixture", "Scroll")
          )
        ),
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )

    _ = try await runTerminalInputHarness(
      terminal: RecordingTerminalHost(surfaceSizeProvider: { terminalSize }),
      events: [
        .mouse(.init(kind: .down(.primary), location: bottomPoint(of: indicatorRect))),
        .mouse(.init(kind: .up(.primary), location: bottomPoint(of: indicatorRect))),
      ],
      rootIdentity: rootIdentity,
      terminalSize: terminalSize,
      viewBuilder: { view }
    )

    #expect(box.scrollPosition.y == 5)
  }

  @MainActor
  @Test("mouse drag on a ScrollView indicator tracks the dragged scroll position")
  func mouseDragOnScrollIndicatorTracksDraggedPosition() async throws {
    let box = MouseControlBox()
    let terminalSize = Size(width: 16, height: 8)
    let rootIdentity = testIdentity("ScrollIndicatorDragFixture")
    let view =
      ScrollView(
        .vertical,
        position: .init(
          get: { box.scrollPosition },
          set: { box.scrollPosition = $0 }
        )
      ) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<10) { index in
            Text("Row \(index)")
          }
        }
      }
      .id(testIdentity("ScrollIndicatorDragFixture", "Scroll"))
      .frame(width: 10, height: 5, alignment: .topLeading)

    let indicatorRect = try #require(
      renderedInteractionRect(
        for: primaryRouteID(
          for: verticalScrollIndicatorIdentity(
            for: testIdentity("ScrollIndicatorDragFixture", "Scroll")
          )
        ),
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )

    _ = try await runTerminalInputHarness(
      terminal: RecordingTerminalHost(surfaceSizeProvider: { terminalSize }),
      events: [
        .mouse(.init(kind: .down(.primary), location: topPoint(of: indicatorRect))),
        .mouse(.init(kind: .dragged(.primary), location: centerPoint(of: indicatorRect))),
        .mouse(.init(kind: .up(.primary), location: centerPoint(of: indicatorRect))),
      ],
      rootIdentity: rootIdentity,
      terminalSize: terminalSize,
      viewBuilder: { view }
    )

    #expect(box.scrollPosition.y == 3)
  }

  @MainActor
  @Test("ScrollView without an explicit position binding manages keyboard scrolling internally")
  func scrollViewWithoutExplicitPositionHandlesKeyboardScrolling() async throws {
    let terminalSize = Size(width: 20, height: 8)
    let terminal = RecordingTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("ImplicitKeyboardScrollFixture")
    let view =
      VStack(alignment: .leading, spacing: 1) {
        Button("Focus") {}
          .id(testIdentity("ImplicitKeyboardScrollFixture", "Button"))

        ScrollView(.vertical) {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<6) { index in
              Text("Key \(index)")
            }
          }
        }
        .id(testIdentity("ImplicitKeyboardScrollFixture", "Scroll"))
        .frame(width: 10, height: 3, alignment: .topLeading)
      }
      .frame(width: terminalSize.width, height: terminalSize.height, alignment: .topLeading)

    let result = try await runTerminalInputHarness(
      terminal: terminal,
      events: [
        .key(.tab),
        .key(.arrowDown),
      ],
      rootIdentity: rootIdentity,
      terminalSize: terminalSize,
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    let firstFrame = try #require(terminal.frames.first)
    let lastFrame = try #require(terminal.frames.last)
    #expect(firstFrame.contains("Key 0"))
    #expect(!lastFrame.contains("Key 0"))
    #expect(lastFrame.contains("Key 1"))
    #expect(lastFrame.contains("Key 3"))
  }

  @MainActor
  @Test("ScrollView without an explicit position binding manages pointer scrolling internally")
  func scrollViewWithoutExplicitPositionHandlesPointerScrolling() async throws {
    let terminalSize = Size(width: 20, height: 8)
    let terminal = RecordingTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("ImplicitPointerScrollFixture")
    let view =
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<10) { index in
            Text("Mouse \(index)")
          }
        }
      }
      .id(testIdentity("ImplicitPointerScrollFixture", "Scroll"))
      .frame(width: 10, height: 5, alignment: .topLeading)

    let scrollRect = try #require(
      renderedInteractionRect(
        for: primaryRouteID(for: testIdentity("ImplicitPointerScrollFixture", "Scroll")),
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )
    let indicatorRect = try #require(
      renderedInteractionRect(
        for: primaryRouteID(
          for: verticalScrollIndicatorIdentity(
            for: testIdentity("ImplicitPointerScrollFixture", "Scroll")
          )
        ),
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )

    let result = try await runTerminalInputHarness(
      terminal: terminal,
      events: [
        .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 1), location: centerPoint(of: scrollRect))),
        .mouse(.init(kind: .down(.primary), location: bottomPoint(of: indicatorRect))),
        .mouse(.init(kind: .up(.primary), location: bottomPoint(of: indicatorRect))),
      ],
      rootIdentity: rootIdentity,
      terminalSize: terminalSize,
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    let firstFrame = try #require(terminal.frames.first)
    let lastFrame = try #require(terminal.frames.last)
    #expect(firstFrame.contains("Mouse 0"))
    #expect(!lastFrame.contains("Mouse 0"))
    #expect(lastFrame.contains("Mouse 5"))
    #expect(lastFrame.contains("Mouse 9"))
  }

  @MainActor
  @Test("button drag-out cancel prevents activation")
  func mouseDragOutCancelsButtonActivation() async throws {
    let box = MouseControlBox()
    let terminalSize = Size(width: 24, height: 8)
    let rootIdentity = testIdentity("CancelFixture")
    let view = Button("Tap") {
      box.buttonTaps += 1
    }
    .id(testIdentity("CancelFixture", "Button"))

    let buttonRect = try #require(
      renderedInteractionRect(
        for: primaryRouteID(for: testIdentity("CancelFixture", "Button")),
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )

    _ = try await runTerminalInputHarness(
      terminal: RecordingTerminalHost(surfaceSizeProvider: { terminalSize }),
      events: [
        .mouse(.init(kind: .down(.primary), location: centerPoint(of: buttonRect))),
        .mouse(
          .init(
            kind: .dragged(.primary),
            location: .init(
              x: buttonRect.origin.x + buttonRect.size.width + 4,
              y: buttonRect.origin.y
            )
          )
        ),
        .mouse(
          .init(
            kind: .up(.primary),
            location: .init(
              x: buttonRect.origin.x + buttonRect.size.width + 4,
              y: buttonRect.origin.y
            )
          )
        ),
      ],
      rootIdentity: rootIdentity,
      terminalSize: terminalSize,
      viewBuilder: { view }
    )

    #expect(box.buttonTaps == 0)
  }

  @MainActor
  @Test("passive hover motion does not trigger an extra frame")
  func passiveHoverDoesNotTriggerExtraFrame() async throws {
    let box = MouseControlBox()
    let terminalSize = Size(width: 24, height: 8)
    let terminal = RecordingTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("HoverFixture")
    let view = Button("Tap") {
      box.buttonTaps += 1
    }
    .id(testIdentity("HoverFixture", "Button"))

    let buttonRect = try #require(
      renderedInteractionRect(
        for: primaryRouteID(for: testIdentity("HoverFixture", "Button")),
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )

    let result = try await runTerminalInputHarness(
      terminal: terminal,
      events: [
        .mouse(.init(kind: .moved, location: centerPoint(of: buttonRect)))
      ],
      rootIdentity: rootIdentity,
      terminalSize: terminalSize,
      viewBuilder: { view }
    )

    #expect(result.renderedFrames == 1)
    #expect(box.buttonTaps == 0)
  }

  @MainActor
  @Test("run loop collapses queued scroll bursts into a small number of rendered updates")
  func runLoopBatchesQueuedScrollBursts() async throws {
    final class ScrollPositionBox: @unchecked Sendable {
      var position = ScrollPosition.zero
    }

    let box = ScrollPositionBox()
    let terminalSize = Size(width: 24, height: 10)
    let terminal = RecordingTerminalHost(
      surfaceSizeProvider: { terminalSize },
      presentObserver: {
        usleep(5_000)
      }
    )
    let rootIdentity = testIdentity("BurstScrollFixture")
    let scrollIdentity = testIdentity("BurstScrollFixture", "Scroll")
    let view =
      ScrollView(
        .vertical,
        position: Binding(
          get: { box.position },
          set: { box.position = $0 }
        )
      ) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<30) { index in
            Text("Burst \(index)")
          }
        }
      }
      .id(scrollIdentity)
      .frame(width: 12, height: 4, alignment: .topLeading)

    let scrollRect = try #require(
      renderedInteractionRect(
        for: primaryRouteID(for: scrollIdentity),
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )

    let events = (0..<20).map { _ in
      InputEvent.mouse(
        .init(
          kind: .scrolled(deltaX: 0, deltaY: 1),
          location: centerPoint(of: scrollRect)
        )
      )
    }

    let result = try await runTerminalInputHarness(
      terminal: terminal,
      events: events,
      rootIdentity: rootIdentity,
      terminalSize: terminalSize,
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(result.renderedFrames <= 6)
    #expect(box.position.y == 20)
  }
}

private final class RecordingInvalidator: Invalidating {
  private(set) var requests: [Set<Identity>] = []

  func requestInvalidation(of identities: Set<Identity>) {
    requests.append(identities)
  }
}

private final class MockTerminalController: TerminalControlling {
  let originalAttributes: termios
  private(set) var setAttributesCalls: [termios] = []
  private(set) var writes: [String] = []
  private(set) var fileStatusFlags: Int32 = 0

  init() {
    var attributes = termios()
    attributes.c_iflag = tcflag_t(ICRNL | IXON)
    attributes.c_oflag = tcflag_t(OPOST)
    attributes.c_cflag = tcflag_t(CS8)
    attributes.c_lflag = tcflag_t(ECHO | ICANON | IEXTEN | ISIG)
    originalAttributes = attributes
  }

  func isATTY(_: Int32) -> Bool {
    true
  }

  func getAttributes(from _: Int32) throws -> termios {
    originalAttributes
  }

  func setAttributes(_ attributes: termios, on _: Int32) throws {
    setAttributesCalls.append(attributes)
  }

  func windowSize(of _: Int32) throws -> Size {
    .init(width: 80, height: 24)
  }

  func getFileStatusFlags(of _: Int32) throws -> Int32 {
    fileStatusFlags
  }

  func setFileStatusFlags(_ flags: Int32, on _: Int32) throws {
    fileStatusFlags = flags
  }

  func write(_ output: String, to _: Int32) throws {
    writes.append(output)
  }

  func read(
    from _: Int32,
    maxBytes _: Int,
    timeoutMilliseconds _: Int
  ) throws -> [UInt8] {
    []
  }
}

private final class RecordingTerminalHost: TerminalHosting {
  var surfaceSize: Size {
    surfaceSizeProvider()
  }
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance
  private(set) var frames: [String] = []
  private(set) var presentationMetrics: [TerminalPresentationMetrics] = []
  private(set) var presentedSurfaceSizes: [Size] = []
  private var lastPresentedSurface: RasterSurface?
  private let surfaceSizeProvider: () -> Size
  private let presentObserver: (() -> Void)?

  init(
    surfaceSizeProvider: @escaping () -> Size = { InteractiveDemoLayout.frameSize },
    capabilityProfile: TerminalCapabilityProfile = .previewUnicode,
    appearance: TerminalAppearance = .fallback,
    presentObserver: (() -> Void)? = nil
  ) {
    self.surfaceSizeProvider = surfaceSizeProvider
    self.capabilityProfile = capabilityProfile
    self.appearance = appearance
    self.presentObserver = presentObserver
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: Point) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    presentObserver?()
    let renderer = TerminalSurfaceRenderer(
      capabilityProfile: capabilityProfile
    )
    let rendered = renderer.render(surface)
    let plan = TerminalPresentationPlanner(
      capabilityProfile: capabilityProfile
    ).plan(
      previousSurface: lastPresentedSurface,
      currentSurface: surface
    )
    let bytesWritten: Int =
      switch plan.strategy {
      case .fullRepaint:
        TerminalPresentationMetrics.fullRepaint(
          for: surface,
          renderedOutput: rendered
        ).bytesWritten
      case .incremental:
        plan.spanUpdates.reduce(0) { partial, update in
          partial
            + cursorSequence(row: update.row, column: update.column).utf8.count
            + update.renderedSpan.utf8.count
        }
      }
    let metrics = TerminalPresentationMetrics(
      bytesWritten: bytesWritten,
      linesTouched: plan.linesTouched,
      cellsChanged: plan.cellsChanged,
      strategy: plan.strategy == .fullRepaint ? .fullRepaint : .incremental
    )
    presentationMetrics.append(metrics)
    presentedSurfaceSizes.append(surface.size)
    frames.append(rendered.replacingOccurrences(of: "\r\n", with: "\n"))
    lastPresentedSurface = surface
    return metrics
  }

  func write(_ output: String) throws {
    frames.append(output.replacingOccurrences(of: "\r\n", with: "\n"))
  }

  private func cursorSequence(row: Int, column: Int) -> String {
    "\u{001B}[\(max(1, row + 1));\(max(1, column + 1))H"
  }
}

private func writeAllBytes(
  _ bytes: [UInt8],
  to fileDescriptor: Int32
) throws {
  var totalBytesWritten = 0

  try unsafe bytes.withUnsafeBytes { rawBuffer in
    guard let baseAddress = rawBuffer.baseAddress else {
      return
    }

    while totalBytesWritten < bytes.count {
      let nextAddress = unsafe baseAddress.advanced(by: totalBytesWritten)
      let bytesRemaining = bytes.count - totalBytesWritten
      let bytesWritten = unsafe Darwin.write(fileDescriptor, nextAddress, bytesRemaining)
      guard bytesWritten >= 0 else {
        throw TerminalHostError.failedToWrite(errno: errno)
      }
      totalBytesWritten += bytesWritten
    }
  }
}

private struct RunLoopInvalidationRecord: Equatable {
  let state: Int
  let identity: Identity
  let invalidatedIdentities: Set<Identity>
  let isSelfInvalidated: Bool
  let subtreeAffected: Bool
}

private final class RunLoopInvalidationRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private(set) var records: [RunLoopInvalidationRecord] = []

  func record(_ record: RunLoopInvalidationRecord) {
    lock.lock()
    defer { lock.unlock() }
    records.append(record)
  }
}

@MainActor
private func interactiveProbeTextNode(
  _ content: String,
  in context: ResolveContext
) -> ResolvedNode {
  if let reused = context.reusedResolvedSubtreeIfAvailable() {
    return reused
  }
  context.recordResolvedComputation()
  return ResolvedNode(
    identity: context.identity,
    kind: .view("Text"),
    environmentSnapshot: context.environment,
    transactionSnapshot: context.transaction,
    drawPayload: .text(content)
  )
}

private struct RunLoopInvalidationProbeLeaf: View, ResolvableView {
  let state: Int
  let recorder: RunLoopInvalidationRecorder

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    recorder.record(
      RunLoopInvalidationRecord(
        state: state,
        identity: context.identity,
        invalidatedIdentities: context.invalidatedIdentities,
        isSelfInvalidated: context.isInvalidated(context.identity),
        subtreeAffected: context.invalidationAffectsSubtree()
      )
    )
    return [interactiveProbeTextNode("State \(state)", in: context)]
  }
}

private struct RunLoopInvalidationProbeRoot: View, ResolvableView {
  let state: Int
  let recorder: RunLoopInvalidationRecorder

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    if let reused = context.reusedResolvedSubtreeIfAvailable() {
      return [reused]
    }
    context.recordResolvedComputation()
    recorder.record(
      RunLoopInvalidationRecord(
        state: state,
        identity: context.identity,
        invalidatedIdentities: context.invalidatedIdentities,
        isSelfInvalidated: context.isInvalidated(context.identity),
        subtreeAffected: context.invalidationAffectsSubtree()
      )
    )

    let child = resolveView(
      RunLoopInvalidationProbeLeaf(
        state: state,
        recorder: recorder
      ),
      in: context.indexedChild(kind: .named("ProbeRoot"), index: 0)
    )
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("ProbeRoot"),
        children: [child],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction
      )
    ]
  }
}

private final class ReusedHandlerRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private(set) var actionCount = 0
  private(set) var keyEvents: [LocalKeyEvent] = []

  func recordAction() {
    lock.lock()
    defer { lock.unlock() }
    actionCount += 1
  }

  func recordKey(_ event: LocalKeyEvent) {
    lock.lock()
    defer { lock.unlock() }
    keyEvents.append(event)
  }
}

private struct ReusedHandlerProbe: View, ResolvableView {
  let recorder: ReusedHandlerRecorder

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    context.localActionRegistry?.register(identity: context.identity) {
      recorder.recordAction()
      return true
    }
    context.localKeyHandlerRegistry?.register(identity: context.identity) { event in
      recorder.recordKey(event)
      return true
    }
    return [interactiveProbeTextNode("Interactive", in: context)]
  }
}

private struct ReusedHandlerRoot: View, ResolvableView {
  let recorder: ReusedHandlerRecorder
  let dirtyLabel: String

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    if let reused = context.reusedResolvedSubtreeIfAvailable() {
      return [reused]
    }
    context.recordResolvedComputation()
    let interactiveChild = resolveView(
      ReusedHandlerProbe(recorder: recorder),
      in: context.indexedChild(kind: .named("Harness"), index: 0)
    )
    let dirtyChild = interactiveProbeTextNode(
      dirtyLabel,
      in: context.indexedChild(kind: .named("Harness"), index: 1)
    )
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("Harness"),
        children: [interactiveChild, dirtyChild],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction
      )
    ]
  }
}

private final class LinkOpenRecorder: @unchecked Sendable {
  var destinations: [LinkDestination] = []
}

private final class ScriptedInputReader: InputReading {
  private let scriptedEvents: [KeyEvent]

  init(events: [KeyEvent]) {
    scriptedEvents = events
  }

  func events() -> AsyncStream<KeyEvent> {
    AsyncStream { continuation in
      for event in scriptedEvents {
        continuation.yield(event)
      }
      continuation.finish()
    }
  }
}

private final class ScriptedTerminalInputReader: TerminalInputReading {
  private let scriptedEvents: [InputEvent]

  init(events: [InputEvent]) {
    scriptedEvents = events
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      for event in scriptedEvents {
        continuation.yield(event)
      }
      continuation.finish()
    }
  }
}

private final class EmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private struct TimedRuntimeEvent<Value: Sendable>: Sendable {
  let delayNanoseconds: UInt64
  let value: Value
}

private actor AsyncEventGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    if isOpen {
      return
    }

    await withCheckedContinuation { continuation in
      if isOpen {
        continuation.resume()
        return
      }
      waiters.append(continuation)
    }
  }

  func open() {
    guard !isOpen else {
      return
    }
    isOpen = true
    let continuations = waiters
    waiters.removeAll(keepingCapacity: false)

    for continuation in continuations {
      continuation.resume()
    }
  }
}

private final class GateInputReader: InputReading {
  private let gate: AsyncEventGate
  private let event: KeyEvent

  init(
    gate: AsyncEventGate,
    event: KeyEvent
  ) {
    self.gate = gate
    self.event = event
  }

  func events() -> AsyncStream<KeyEvent> {
    AsyncStream { continuation in
      let gate = gate
      let event = event
      let task = Task {
        await gate.wait()
        continuation.yield(event)
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}

private final class TimedInputReader: InputReading {
  private let scriptedEvents: [TimedRuntimeEvent<KeyEvent>]

  init(events: [TimedRuntimeEvent<KeyEvent>]) {
    scriptedEvents = events
  }

  func events() -> AsyncStream<KeyEvent> {
    AsyncStream { continuation in
      let scriptedEvents = scriptedEvents
      let task = Task {
        for event in scriptedEvents {
          if event.delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: event.delayNanoseconds)
          }
          continuation.yield(event.value)
        }
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}

private final class TimedSignalReader: SignalReading {
  private let scriptedSignals: [TimedRuntimeEvent<String>]

  init(signals: [TimedRuntimeEvent<String>]) {
    scriptedSignals = signals
  }

  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      let scriptedSignals = scriptedSignals
      let task = Task {
        for signal in scriptedSignals {
          if signal.delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: signal.delayNanoseconds)
          }
          continuation.yield(signal.value)
        }
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}

private struct LifecycleRuntimeState: Equatable, Sendable {
  var showChild = true
}

private final class RuntimeLifecycleRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private(set) var appearCountsAtPresent: [Int] = []
  private(set) var orderedEvents: [String] = []

  func record(_ event: String) {
    lock.lock()
    defer { lock.unlock() }
    orderedEvents.append(event)
  }

  func recordAppearCountAtPresent() {
    lock.lock()
    defer { lock.unlock() }
    let appearCount = orderedEvents.filter { $0.hasPrefix("appear:") }.count
    appearCountsAtPresent.append(appearCount)
  }

  func events(matchingPrefix prefix: String) -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return orderedEvents.filter { $0.hasPrefix(prefix) }
  }

  func waitForEvent(
    _ event: String,
    timeoutNanoseconds: UInt64 = 1_000_000_000
  ) async -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
      if contains(event) {
        return true
      }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return false
  }

  func runUntilCancelled(
    identity: Identity
  ) async {
    record("taskStart:\(identity)")
    while !Task.isCancelled {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    record("taskCancel:\(identity)")
  }

  private func contains(_ event: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return orderedEvents.contains(event)
  }
}

private struct LifecycleRuntimeProbe: View, ResolvableView {
  let recorder: RuntimeLifecycleRecorder
  let focusable: Bool

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let appearHandlerID = "\(context.identity)/appear"
    let disappearHandlerID = "\(context.identity)/disappear"
    let descriptor = TaskDescriptor(
      id: "\(context.identity)/task",
      priority: .medium
    )

    context.localLifecycleRegistry?.registerAppear(handlerID: appearHandlerID) {
      recorder.record("appear:\(context.identity)")
    }
    context.localLifecycleRegistry?.registerDisappear(handlerID: disappearHandlerID) {
      recorder.record("disappear:\(context.identity)")
    }
    context.localTaskRegistry?.register(
      identity: context.identity,
      registration: TaskRegistration(
        descriptor: descriptor,
        operation: {
          await recorder.runUntilCancelled(identity: context.identity)
        }
      )
    )

    var node = interactiveProbeTextNode("Lifecycle probe", in: context)
    node.lifecycleMetadata = .init(
      appearHandlerIDs: [appearHandlerID],
      disappearHandlerIDs: [disappearHandlerID],
      task: descriptor
    )
    if focusable {
      node.semanticMetadata = node.semanticMetadata.merging(
        .init(isFocusable: true)
      )
    }
    return [node]
  }
}

private struct LifecycleRuntimeRoot: View, ResolvableView {
  let state: LifecycleRuntimeState
  let recorder: RuntimeLifecycleRecorder
  let focusable: Bool

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    if let reused = context.reusedResolvedSubtreeIfAvailable() {
      return [reused]
    }
    context.recordResolvedComputation()
    let children =
      state.showChild
      ? [
        resolveView(
          LifecycleRuntimeProbe(
            recorder: recorder,
            focusable: focusable
          ),
          in: context.indexedChild(kind: .named("RuntimeRoot"), index: 0)
        )
      ]
      : []
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("RuntimeRoot"),
        children: children,
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction
      )
    ]
  }
}

@MainActor
private func modernTextFeatureFixture(
  displayedInput: String
) -> AnyView {
  AnyView(
    VStack(alignment: .leading, spacing: 0) {
      Text("Wide: \u{754C}\u{1F642}e\u{301} cells align")
        .frame(width: 32, height: 1, alignment: .leading)
      Text("Clip: [\(displayedInput)] orbit preview stays inside the viewport")
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(width: 24, height: 1, alignment: .leading)
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Scroll: viewport clips overflow")
          Text("Scroll: semantic content bounds persist")
          Text("Scroll: runtime offset comes next")
        }
      }
      .frame(width: 32, height: 1, alignment: .leading)
      Text("Style run: accent emphasis")
        .bold()
        .underline(pattern: .dash, color: .yellow)
        .strikethrough(pattern: .dot, color: .red)
        .foregroundStyle(.tint)
        .drawMetadata(.init(opacity: 0.8))
        .lineLimit(1)
        .background {
          Rectangle().fill(.windowBackground)
        }
        .frame(width: 32, height: 1, alignment: .leading)
    }
    .frame(width: 32, height: 4, alignment: .topLeading)
    .foregroundStyle(.foreground)
    .tint(Color.cyan)
  )
}

@MainActor
private func makeRuntimeHarness(
  terminal: RecordingTerminalHost,
  events: [KeyEvent]
) async throws -> RunLoopResult<InteractiveDemoState> {
  let inputReader = ScriptedInputReader(events: events)
  let signalReader = EmptySignalReader()
  let scheduler = FrameScheduler()
  let stateContainer = StateContainer(
    initialState: InteractiveDemoState(),
    invalidationIdentities: [InteractiveDemoIdentity.root]
  )
  let focusTracker = FocusTracker(
    invalidationIdentities: [InteractiveDemoIdentity.root]
  )
  var environmentValues = EnvironmentValues()
  environmentValues.interactiveDemoTerminalCapability = terminal.capabilityProfile
  environmentValues.terminalAppearance = terminal.appearance

  let runLoop = RunLoop(
    rootIdentity: InteractiveDemoIdentity.root,
    terminalHost: terminal,
    inputReader: inputReader,
    signalReader: signalReader,
    scheduler: scheduler,
    stateContainer: stateContainer,
    focusTracker: focusTracker,
    keyHandler: handleFocusedInteractiveDemoInput(
      keyEvent:focusedIdentity:stateContainer:
    ),
    environmentValues: environmentValues,
    viewBuilder: { state, focusedIdentity in
      interactiveDemoScene(
        state: state,
        focusedIdentity: focusedIdentity,
        bindings: interactiveDemoBindings(stateContainer: stateContainer)
      )
    }
  )

  return try await runLoop.run()
}

@MainActor
private func makeLifecycleRuntimeHarness(
  terminal: RecordingTerminalHost,
  recorder: RuntimeLifecycleRecorder,
  focusable: Bool = false,
  events: [TimedRuntimeEvent<KeyEvent>],
  signals: [TimedRuntimeEvent<String>] = []
) async throws -> RunLoopResult<LifecycleRuntimeState> {
  let runLoop = RunLoop(
    rootIdentity: testIdentity("LifecycleRuntimeRoot"),
    terminalHost: terminal,
    inputReader: TimedInputReader(events: events),
    signalReader: TimedSignalReader(signals: signals),
    scheduler: FrameScheduler(),
    stateContainer: StateContainer(
      initialState: LifecycleRuntimeState(),
      invalidationIdentities: [testIdentity("LifecycleRuntimeRoot")]
    ),
    focusTracker: FocusTracker(
      invalidationIdentities: [testIdentity("LifecycleRuntimeRoot")]
    ),
    keyHandler: { keyEvent, _, stateContainer in
      guard keyEvent == .character("t") else {
        return .ignored
      }
      _ = stateContainer.mutate { state in
        state.showChild.toggle()
      }
      return .handled
    },
    viewBuilder: { state, _ in
      LifecycleRuntimeRoot(
        state: state,
        recorder: recorder,
        focusable: focusable
      )
    }
  )

  return try await runLoop.run()
}

private func focusRegion(
  _ identity: Identity,
  x: Int = 0,
  y: Int = 0,
  width: Int = 5,
  height: Int = 1,
  scopePath: [Identity] = [],
  sectionIdentity: Identity? = nil
) -> FocusRegion {
  FocusRegion(
    identity: identity,
    rect: .init(
      origin: .init(x: x, y: y),
      size: .init(width: width, height: height)
    ),
    scopePath: scopePath,
    sectionIdentity: sectionIdentity
  )
}

@MainActor
private func scopeSectionFixture() -> some View {
  VStack(alignment: .leading, spacing: 0) {
    VStack(alignment: .leading, spacing: 0) {
      Button("Leading") {}
        .id(testIdentity("Root", "Scope", "Leading"))
      VStack(alignment: .leading, spacing: 0) {
        Button("First") {}
          .id(testIdentity("Root", "Scope", "Section", "First"))
        Button("Second") {}
          .id(testIdentity("Root", "Scope", "Section", "Second"))
      }
      .id(testIdentity("Root", "Scope", "Section"))
      .focusSection()
    }
    .id(testIdentity("Root", "Scope"))
    .focusScope()
  }
}

private func termiosEqual(_ lhs: termios, _ rhs: termios) -> Bool {
  unsafe withUnsafeBytes(of: lhs) { lhsBytes in
    unsafe withUnsafeBytes(of: rhs) { rhsBytes in
      unsafe lhsBytes.elementsEqual(rhsBytes)
    }
  }
}

@MainActor
private func runTerminalInputHarness<V: View>(
  terminal: RecordingTerminalHost,
  events: [InputEvent],
  rootIdentity: Identity,
  terminalSize: Size,
  configureEnvironmentValues: ((inout EnvironmentValues) -> Void)? = nil,
  viewBuilder: @escaping () -> V
) async throws -> RunLoopResult<Int> {
  var environmentValues = EnvironmentValues()
  environmentValues.terminalAppearance = terminal.appearance
  environmentValues.terminalSize = terminalSize
  configureEnvironmentValues?(&environmentValues)

  let runLoop = RunLoop(
    rootIdentity: rootIdentity,
    terminalHost: terminal,
    terminalInputReader: ScriptedTerminalInputReader(events: events),
    signalReader: EmptySignalReader(),
    scheduler: FrameScheduler(),
    stateContainer: StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    ),
    focusTracker: FocusTracker(
      invalidationIdentities: [rootIdentity]
    ),
    environmentValues: environmentValues,
    proposal: .init(width: terminalSize.width, height: terminalSize.height),
    viewBuilder: { _, _ in
      viewBuilder()
    }
  )

  return try await runLoop.run()
}

@MainActor
private func renderedInteractionRect<V: View>(
  for routeID: RouteID,
  in view: V,
  rootIdentity: Identity,
  terminalSize: Size,
  focusedIdentity: Identity? = nil
) -> Rect? {
  var environmentValues = EnvironmentValues()
  environmentValues.terminalSize = terminalSize
  environmentValues.focusedIdentity = focusedIdentity

  let artifacts = DefaultRenderer().render(
    view,
    context: .init(
      identity: rootIdentity,
      environmentValues: environmentValues
    ),
    proposal: .init(width: terminalSize.width, height: terminalSize.height)
  )

  return artifacts.semanticSnapshot.interactionRegions.first { region in
    region.routeID == routeID
  }?.rect
}

private func centerPoint(
  of rect: Rect
) -> Point {
  .init(
    x: rect.origin.x + max(0, rect.size.width / 2),
    y: rect.origin.y + max(0, rect.size.height / 2)
  )
}

private func leadingPoint(
  of rect: Rect
) -> Point {
  .init(
    x: rect.origin.x,
    y: rect.origin.y + max(0, rect.size.height / 2)
  )
}

private func trailingPoint(
  of rect: Rect
) -> Point {
  .init(
    x: rect.origin.x + max(0, rect.size.width - 1),
    y: rect.origin.y + max(0, rect.size.height / 2)
  )
}

private func topPoint(
  of rect: Rect
) -> Point {
  .init(
    x: rect.origin.x + max(0, rect.size.width / 2),
    y: rect.origin.y
  )
}

private func bottomPoint(
  of rect: Rect
) -> Point {
  .init(
    x: rect.origin.x + max(0, rect.size.width / 2),
    y: rect.origin.y + max(0, rect.size.height - 1)
  )
}

@MainActor
private final class MouseControlBox {
  var buttonTaps = 0
  var stepperValue = 1
  var sliderValue = 0
  var pickerSelection = 1
  var listSelection = 1
  var tableSelection = 1
  var scrollPosition = ScrollPosition.zero
  var text = ""
}

@MainActor
private func mouseControlFixture(
  box: MouseControlBox
) -> some View {
  VStack(alignment: .leading, spacing: 1) {
    Button("Tap") {
      box.buttonTaps += 1
    }
    .id(testIdentity("MouseFixture", "Button"))

    Stepper(
      "Stepper",
      value: .init(
        get: { box.stepperValue },
        set: { box.stepperValue = $0 }
      ),
      in: 0...5
    )
    .id(testIdentity("MouseFixture", "Stepper"))

    Slider(
      "Slider",
      value: .init(
        get: { box.sliderValue },
        set: { box.sliderValue = $0 }
      ),
      in: 0...10
    )
    .id(testIdentity("MouseFixture", "Slider"))

    Picker(
      "Picker",
      selection: .init(
        get: { box.pickerSelection },
        set: { box.pickerSelection = $0 }
      )
    ) {
      Text("One").tag(1)
      Text("Two").tag(2)
      Text("Three").tag(3)
    }
    .pickerStyle(.segmented)
    .id(testIdentity("MouseFixture", "Picker"))

    List(
      selection: .init(
        get: { box.listSelection },
        set: { box.listSelection = $0 }
      )
    ) {
      Text("One").tag(1)
      Text("Two").tag(2)
      Text("Three").tag(3)
    }
    .listStyle(.plain)
    .id(testIdentity("MouseFixture", "List"))
    .frame(width: 18, height: 5, alignment: .topLeading)

    Table(
      selection: .init(
        get: { box.tableSelection },
        set: { box.tableSelection = $0 }
      ),
      columns: [.init("Name")]
    ) {
      TableRow {
        Text("One")
      }
      .tag(1)
      TableRow {
        Text("Two")
      }
      .tag(2)
    }
    .tableHeaders(.hidden)
    .id(testIdentity("MouseFixture", "Table"))
    .frame(width: 18, height: 5, alignment: .topLeading)

    ScrollView(
      .vertical,
      position: .init(
        get: { box.scrollPosition },
        set: { box.scrollPosition = $0 }
      )
    ) {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(0..<6) { index in
          Text("Row \(index)")
        }
      }
    }
    .id(testIdentity("MouseFixture", "Scroll"))
    .frame(width: 10, height: 3, alignment: .topLeading)

    TextField(
      "Name",
      text: .init(
        get: { box.text },
        set: { box.text = $0 }
      )
    )
    .id(testIdentity("MouseFixture", "Field"))
  }
  .frame(width: 72, height: 48, alignment: .topLeading)
}

extension ResolvedNode {
  fileprivate func descendant(with identity: Identity) -> ResolvedNode? {
    if self.identity == identity {
      return self
    }

    for child in children {
      if let match = child.descendant(with: identity) {
        return match
      }
    }

    return nil
  }

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
