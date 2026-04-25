import EmbeddedFonts
import Foundation
import Testing

@testable import Core
@testable import TerminalUI
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

  @Test("view node state slots preserve typed values and local invalidation identities")
  func viewNodeStateSlotsPreserveTypedValues() {
    let invalidator = RecordingInvalidator()
    let node = ViewNode(identity: testIdentity("RuntimeRoot"))
    node.beginEvaluation(frameID: 1, invalidator: invalidator)

    let initial: Int = node.stateSlot(ordinal: 0, seed: 0)
    let repeated: Int = node.stateSlot(ordinal: 0, seed: 99)

    #expect(initial == 0)
    #expect(repeated == 0)

    node.setStateSlot(ordinal: 0, value: 3)

    let updated: Int = node.stateSlot(ordinal: 0, seed: 0)
    #expect(updated == 3)
    #expect(invalidator.requests == [[testIdentity("RuntimeRoot")]])
  }

  @Test("key parser handles arrows, backspace, and required controls")
  func keyParserParsesExpectedSequences() {
    var parser = KeyParser()

    #expect(parser.feed([0x1B, 0x5B]).isEmpty)
    #expect(parser.feed([0x43]) == [KeyPress(.arrowRight)])

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
        KeyPress(.arrowUp),
        KeyPress(.arrowDown),
        KeyPress(.backspace),
        KeyPress(.return),
        KeyPress(.tab),
        KeyPress(.arrowLeft),
        KeyPress(.tab, modifiers: .shift),
        KeyPress(.space),
        KeyPress(.character("q")),
        KeyPress(.character("c"), modifiers: .ctrl),
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
            modifiers: [.shift, .ctrl]
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
        _ = close(readDescriptor)
      }
      if !didCloseWriteDescriptor {
        _ = close(writeDescriptor)
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
    _ = close(writeDescriptor)
    didCloseWriteDescriptor = true

    let inputReader = InputReader(fileDescriptor: readDescriptor)
    let receivedEvents = await Task {
      var events: [InputEvent] = []
      for await event in inputReader.inputEvents() {
        events.append(event)
      }
      return events
    }.value

    _ = close(readDescriptor)
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
        _ = close(readDescriptor)
      }
      if !didCloseWriteDescriptor {
        _ = close(writeDescriptor)
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
    _ = close(writeDescriptor)
    didCloseWriteDescriptor = true
    let receivedEvents = await receivedEventsTask.value

    _ = close(readDescriptor)
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
        "\u{001B}[?2004h",
        "\u{001B}[2J",
        "\u{001B}[1;1H",
        "\u{001B}[?2004l",
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
      resolved.descendant(withText: "Tab | Enter | arrows | q | unicode | mono | plain | increased")
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
    #expect(surface.contains("▼"))
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
      listRowIdentity(for: InteractiveDemoIdentity.presetList, rowIndex: 5),
      listRowIdentity(for: InteractiveDemoIdentity.presetList, rowIndex: 6),
      listRowIdentity(for: InteractiveDemoIdentity.presetList, rowIndex: 7),
      InteractiveDemoIdentity.inputField,
      InteractiveDemoIdentity.selectionModePicker,
      InteractiveDemoIdentity.textLabDisclosure,
      InteractiveDemoIdentity.textLabScrollPreview,
      verticalScrollIndicatorIdentity(for: InteractiveDemoIdentity.textLabScrollPreview),
    ]
    let traversalOrder: [Identity] = [
      InteractiveDemoIdentity.incrementButton,
      InteractiveDemoIdentity.decrementButton,
      InteractiveDemoIdentity.resetButton,
      InteractiveDemoIdentity.accentToggle,
      InteractiveDemoIdentity.presetMenu,
      listRowIdentity(for: InteractiveDemoIdentity.presetList, rowIndex: 5),
      InteractiveDemoIdentity.inputField,
      InteractiveDemoIdentity.selectionModePicker,
      InteractiveDemoIdentity.textLabDisclosure,
      InteractiveDemoIdentity.textLabScrollPreview,
      verticalScrollIndicatorIdentity(for: InteractiveDemoIdentity.textLabScrollPreview),
    ]

    #expect(artifacts.semanticSnapshot.focusRegions.map(\.identity) == expectedOrder)

    let tracker = FocusTracker(
      invalidationIdentities: [InteractiveDemoIdentity.root]
    )
    _ = tracker.updateRegions(artifacts.semanticSnapshot.focusRegions)
    #expect(tracker.currentFocusIdentity == traversalOrder[0])

    for identity in traversalOrder.dropFirst() {
      tracker.focusNext()
      #expect(tracker.currentFocusIdentity == identity)
    }

    tracker.focusNext()
    #expect(tracker.currentFocusIdentity == traversalOrder[0])
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
        listRowIdentity(for: InteractiveDemoIdentity.presetList, rowIndex: 1),
        listRowIdentity(for: InteractiveDemoIdentity.presetList, rowIndex: 2),
        listRowIdentity(for: InteractiveDemoIdentity.presetList, rowIndex: 3),
        listRowIdentity(for: InteractiveDemoIdentity.presetList, rowIndex: 4),
        listRowIdentity(for: InteractiveDemoIdentity.presetList, rowIndex: 5),
        InteractiveDemoIdentity.inputField,
        InteractiveDemoIdentity.selectionModePicker,
        InteractiveDemoIdentity.textLabDisclosure,
        InteractiveDemoIdentity.textLabScrollPreview,
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
    // Opacity is baked into the foreground color at rasterize time, so
    // the style run no longer carries the raw `.cyan` + `opacity == 0.8`
    // values.  Match on the decorations and emphasis (which flow through
    // untouched) and verify the foreground has been perturbed from pure
    // cyan by the opacity blend.
    let hasStyledAccentRun = artifacts.rasterSurface.styleRuns.contains { run in
      guard let fg = run.style.foregroundColor else { return false }
      return fg != Color.cyan
        && run.style.emphasis == .bold
        && run.style.underlineStyle == .init(pattern: .dash, color: .yellow)
        && run.style.strikethroughStyle == .init(pattern: .dot, color: .red)
        && run.style.opacity == 1.0
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
      events: [
        KeyPress(.tab), KeyPress(.tab), KeyPress(.tab), KeyPress(.tab), KeyPress(.tab),
        KeyPress(.tab), KeyPress(.arrowDown), KeyPress(.escape), KeyPress(.tab),
        KeyPress(.character("c"), modifiers: .ctrl),
      ]
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
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
      events: [
        KeyPress(.tab), KeyPress(.tab), KeyPress(.tab), KeyPress(.tab),
        KeyPress(.arrowDown), KeyPress(.arrowDown), KeyPress(.arrowDown), KeyPress(.return),
        KeyPress(.character("c"), modifiers: .ctrl),
      ]
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
    #expect(result.finalState == InteractiveDemoState(value: 2))
    let firstFrame = try #require(terminal.frames.first)
    #expect(firstFrame.contains("▤ Presets"))
    #expect(firstFrame.contains("│╭-5"))
    #expect(firstFrame.contains("│ ↑"))
    #expect(firstFrame.contains("│ ↓"))
    #expect(
      terminal.frames.contains(where: {
        $0.contains("│ ↑")
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
        KeyPress(.tab), KeyPress(.tab), KeyPress(.tab), KeyPress(.tab), KeyPress(.tab),
        KeyPress(.backspace),
        KeyPress(.character("-")), KeyPress(.character("1")), KeyPress(.character("2")),
        KeyPress(.return),
        KeyPress(.character("c"), modifiers: .ctrl),
      ]
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
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
      events: [
        KeyPress(.tab), KeyPress(.tab), KeyPress(.return),
        KeyPress(.character("c"), modifiers: .ctrl),
      ]
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
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
      inputReader: ScriptedInputReader(events: [
        KeyPress(.return), KeyPress(.character("c"), modifiers: .ctrl),
      ]),
      signalReader: EmptySignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: stateContainer,
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      keyHandler: { keyPress, _, stateContainer in
        guard keyPress == KeyPress(.return) else {
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

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
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
        .key(.return),
        .key(KeyPress(.character("c"), modifiers: .ctrl)),
      ],
      rootIdentity: testIdentity("StandaloneLinkRuntime"),
      terminalSize: .init(width: 20, height: 1),
      configureEnvironmentValues: { environmentValues in
        environmentValues.openLinkAction = OpenLinkAction { destination in
          recorder.record(destination)
          return true
        }
      },
      viewBuilder: {
        Link("Docs", destination: "https://example.com")
          .id(testIdentity("StandaloneLinkRuntime", "Link"))
      }
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
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
        .key(.return),
        .key(.tab),
        .key(.return),
        .key(KeyPress(.character("c"), modifiers: .ctrl)),
      ],
      rootIdentity: testIdentity("InlineLinkRuntime"),
      terminalSize: .init(width: 24, height: 1),
      configureEnvironmentValues: { environmentValues in
        environmentValues.openLinkAction = OpenLinkAction { destination in
          recorder.record(destination)
          return true
        }
      },
      viewBuilder: {
        Text(
          "\(Link("One", destination: "https://one.example")) \(Link("Two", destination: "https://two.example"))"
        )
      }
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
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
        .key(KeyPress(.character("c"), modifiers: .ctrl)),
      ],
      rootIdentity: rootIdentity,
      terminalSize: terminalSize,
      configureEnvironmentValues: { environmentValues in
        environmentValues.openLinkAction = OpenLinkAction { destination in
          recorder.record(destination)
          return true
        }
      },
      viewBuilder: {
        view
      }
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
    #expect(recorder.destinations == ["https://example.com"])
  }

  @Test("reused interactive subtrees keep local handlers across selective dirty frames")
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
    #expect(keyRegistry.dispatch(identity: testIdentity("Root", "Harness[0]"), event: .return))
    #expect(recorder.actionCount == 1)
    #expect(recorder.keyEvents == [.return])

    _ = renderer.render(
      ReusedHandlerRoot(recorder: recorder, dirtyLabel: "Dirty 1"),
      context: .init(
        identity: testIdentity("Root"),
        invalidatedIdentities: [testIdentity("Root", "Harness[1]")],
        localActionRegistry: actionRegistry,
        localKeyHandlerRegistry: keyRegistry,
        applyEnvironmentValues: true
      )
    )

    #expect(actionRegistry.dispatch(identity: testIdentity("Root", "Harness[0]")))
    #expect(keyRegistry.dispatch(identity: testIdentity("Root", "Harness[0]"), event: .space))
    #expect(recorder.actionCount == 2)
    #expect(recorder.keyEvents == [.return, .space])
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
        .init(delayNanoseconds: 50_000_000, value: KeyPress(.character("c"), modifiers: .ctrl))
      ]
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
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
        .init(delayNanoseconds: 50_000_000, value: KeyPress(.character("t"))),
        .init(delayNanoseconds: 50_000_000, value: KeyPress(.character("c"), modifiers: .ctrl)),
      ]
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
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
        .init(delayNanoseconds: 50_000_000, value: KeyPress(.character("c"), modifiers: .ctrl))
      ]
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
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
        .init(delayNanoseconds: 50_000_000, value: KeyPress(.character("c"), modifiers: .ctrl))
      ]
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
    #expect(await recorder.waitForEvent("taskCancel:\(lifecycleProbeIdentity)"))
  }

  @MainActor
  @Test("run loop cancels lifecycle tasks when input ends")
  func runLoopCancelsLifecycleTasksWhenInputEnds() async throws {
    let recorder = RuntimeLifecycleRecorder()

    let result = try await makeLifecycleRuntimeHarness(
      terminal: RecordingTerminalHost(),
      recorder: recorder,
      events: [] as [TimedRuntimeEvent<KeyPress>]
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
      events: [] as [TimedRuntimeEvent<KeyPress>],
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

    let result = try await runTestSceneSession(
      scene: WindowGroup("Resize Window") {
        Text("Resize")
      },
      sessionName: "InteractiveRuntimeTests.ResizeWindow",
      terminalHost: terminal,
      inputReader: GateInputReader(
        gate: quitGate, event: KeyPress(.character("c"), modifiers: .ctrl)),
      signalReader: TimedSignalReader(
        signals: [
          .init(delayNanoseconds: 50_000_000, value: "SIGWINCH")
        ]
      )
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
    #expect(result.renderedFrames == 2)
    #expect(terminal.presentedSurfaceSizes == [initialSize, resizedSize])
  }

  @MainActor
  @Test("literal tab overflow updates on SIGWINCH without requiring additional input")
  func literalTabOverflowUpdatesOnSIGWINCHWithoutAdditionalInput() async throws {
    let initialSize = Size(width: 40, height: 8)
    let resizedSize = Size(width: 24, height: 8)
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

    let result = try await runTestSceneSession(
      scene: WindowGroup("Literal Tab Resize") {
        SigwinchLiteralTabOverflowFixture()
      },
      sessionName: "InteractiveRuntimeTests.LiteralTabResize",
      terminalHost: terminal,
      inputReader: GateInputReader(
        gate: quitGate, event: KeyPress(.character("c"), modifiers: .ctrl)),
      signalReader: TimedSignalReader(
        signals: [
          .init(delayNanoseconds: 50_000_000, value: "SIGWINCH")
        ]
      )
    )

    let firstFrame = try #require(terminal.frames.first)
    let secondFrame = try #require(terminal.frames.last)

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
    #expect(result.renderedFrames == 2)
    #expect(terminal.presentedSurfaceSizes == [initialSize, resizedSize])
    #expect(firstFrame.contains("▾") == false)
    #expect(secondFrame.contains("▾"))
    #expect(secondFrame.contains("…") == false)
  }

  @MainActor
  @Test("toast auto-dismiss rerenders without additional input")
  func toastAutoDismissRerendersWithoutAdditionalInput() async throws {
    let terminalSize = Size(width: 32, height: 8)
    let terminal = RecordingTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("ToastRuntimeRoot")
    let stateContainer = StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    )
    let quitGate = AsyncEventGate()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      terminalHost: terminal,
      inputReader: GateInputReader(
        gate: quitGate, event: KeyPress(.character("c"), modifiers: .ctrl)),
      signalReader: EmptySignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: stateContainer,
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in
        ToastAutoDismissHarnessView(terminalSize: terminalSize)
      }
    )
    let runTask = Task {
      try await runLoop.run()
    }

    let toastDismissed = try await waitUntil(timeoutNanoseconds: 10_000_000_000) {
      guard terminal.frames.count >= 2 else {
        return false
      }
      return !(terminal.frames.last ?? "").contains("Action performed")
    }
    await quitGate.open()
    let result = try await runTask.value

    let firstFrame = try #require(terminal.frames.first)
    let lastFrame = try #require(terminal.frames.last)

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
    #expect(toastDismissed)
    #expect(result.renderedFrames >= 2)
    #expect(firstFrame.contains("Action performed"))
    #expect(!lastFrame.contains("Action performed"))
  }

  @MainActor
  @Test("imperative presentation handle mutations invalidate and render on the next frame")
  func imperativePresentationHandleMutationRerendersOnNextFrame() async throws {
    let terminalSize = Size(width: 40, height: 10)
    let terminal = RecordingTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("ImperativePresentationRuntimeRoot")
    let stateContainer = StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    )
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      terminalHost: terminal,
      inputReader: GateInputReader(
        gate: AsyncEventGate(), event: KeyPress(.character("c"), modifiers: .ctrl)),
      signalReader: TimedSignalReader(
        signals: [
          .init(delayNanoseconds: 1_000_000_000, value: "SIGTERM")
        ]
      ),
      scheduler: FrameScheduler(),
      stateContainer: stateContainer,
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in
        ImperativeAlertPresentationHarnessView(terminalSize: terminalSize)
      }
    )
    let result = try await runLoop.run()

    let firstFrame = try #require(terminal.frames.first)
    let lastFrame = try #require(terminal.frames.last)

    #expect(result.exitReason == .signal("SIGTERM"))
    #expect(result.renderedFrames == 2)
    #expect(!firstFrame.contains("Imperative alert"))
    #expect(lastFrame.contains("Imperative alert"))
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
      renderedScrollViewportRect(
        for: testIdentity("MouseFixture", "Scroll"),
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
  @Test("focusing an offscreen ScrollView descendant scrolls to the minimum visible offset")
  func focusingOffscreenScrollViewDescendantScrollsToMinimumVisibleOffset() throws {
    final class ScrollBox {
      var position = ScrollPosition.zero
    }

    let terminalSize = Size(width: 20, height: 8)
    let terminal = RecordingTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("FocusDrivenScrollFixture")
    let scrollIdentity = testIdentity("FocusDrivenScrollFixture", "Scroll")
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let box = ScrollBox()

    func rowIdentity(_ index: Int) -> Identity {
      testIdentity("FocusDrivenScrollFixture", "Scroll", "Row\(index)")
    }

    let view =
      ScrollView(
        .vertical,
        showsIndicators: false,
        position: Binding(
          get: { box.position },
          set: { box.position = $0 }
        )
      ) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<8) { index in
            Button("Row \(index)") {}
              .id(rowIdentity(index))
          }
        }
      }
      .id(scrollIdentity)
      .frame(width: 10, height: 3, alignment: .topLeading)

    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = terminal.appearance
    environmentValues.terminalSize = terminalSize

    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      terminalHost: terminal,
      terminalInputReader: ScriptedTerminalInputReader(events: []),
      signalReader: EmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      environmentValues: environmentValues,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in
        view
      }
    )

    scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    #expect(box.position == .zero)
    #expect((terminal.frames.last ?? "").contains("Row 0"))
    #expect(!(terminal.frames.last ?? "").contains("Row 5"))

    #expect(focusTracker.setFocus(to: rowIdentity(5)))
    scheduler.requestInvalidation(of: [rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    #expect(box.position == .init(x: 0, y: 3))
    #expect(!(terminal.frames.last ?? "").contains("Row 0"))
    #expect((terminal.frames.last ?? "").contains("Row 5"))
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
      renderedScrollViewportRect(
        for: testIdentity("ImplicitPointerScrollFixture", "Scroll"),
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
  @Test("ScrollView without an explicit position binding manages pointer scrolling with LazyVStack")
  func scrollViewWithoutExplicitPositionHandlesPointerScrollingWithLazyVStack() async throws {
    let terminalSize = Size(width: 20, height: 8)
    let terminal = RecordingTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("ImplicitPointerLazyScrollFixture")
    let view =
      ScrollView(.vertical) {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<10) { index in
            Text("Mouse \(index)")
          }
        }
      }
      .id(testIdentity("ImplicitPointerLazyScrollFixture", "Scroll"))
      .frame(width: 10, height: 5, alignment: .topLeading)

    let scrollRect = try #require(
      renderedScrollViewportRect(
        for: testIdentity("ImplicitPointerLazyScrollFixture", "Scroll"),
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )
    let indicatorRect = try #require(
      renderedInteractionRect(
        for: primaryRouteID(
          for: verticalScrollIndicatorIdentity(
            for: testIdentity("ImplicitPointerLazyScrollFixture", "Scroll")
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
  @Test("ScrollView internal pointer scrolling preserves outer stateful content scope")
  func scrollViewInternalPointerScrollingPreservesOuterStatefulContentScope() async throws {
    let terminalSize = Size(width: 20, height: 8)
    let terminal = RecordingTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("ImplicitPointerStatefulScrollFixture")
    let view = StatefulImplicitPointerScrollFixture()

    let scrollRect = try #require(
      renderedScrollViewportRect(
        for: testIdentity("ImplicitPointerStatefulScrollFixture", "Scroll"),
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )

    let result = try await runTerminalInputHarness(
      terminal: terminal,
      events: [
        .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 1), location: bottomPoint(of: scrollRect)))
      ],
      rootIdentity: rootIdentity,
      terminalSize: terminalSize,
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(terminal.frames.count >= 2)
    let firstFrame = try #require(terminal.frames.first)
    let lastFrame = try #require(terminal.frames.last)
    #expect(firstFrame != lastFrame)
  }

  @MainActor
  @Test("gallery-like ScrollView content survives pointer scrolling")
  func galleryLikeScrollViewContentSurvivesPointerScrolling() async throws {
    let terminalSize = Size(width: 80, height: 24)
    let terminal = RecordingTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("GalleryLikeScrollFixture")
    let view = GalleryLikeScrollFixture()

    let scrollRect = try #require(
      renderedScrollViewportRect(
        for: testIdentity("GalleryLikeScrollFixture", "Scroll"),
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )

    let result = try await runTerminalInputHarness(
      terminal: terminal,
      events: [
        .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 1), location: bottomPoint(of: scrollRect))),
        .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 1), location: bottomPoint(of: scrollRect))),
      ],
      rootIdentity: rootIdentity,
      terminalSize: terminalSize,
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(terminal.frames.count >= 2)
  }

  @MainActor
  @Test("root-alias ScrollView content survives pointer scrolling")
  func rootAliasScrollViewContentSurvivesPointerScrolling() async throws {
    let terminalSize = Size(width: 80, height: 24)
    let terminal = RecordingTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("RootAliasGalleryLikeScrollFixture")
    let view = RootAliasGalleryLikeScrollFixture()

    let scrollRect = try #require(
      renderedScrollViewportRect(
        for: rootIdentity,
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )

    let result = try await runTerminalInputHarness(
      terminal: terminal,
      events: [
        .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 1), location: bottomPoint(of: scrollRect))),
        .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 1), location: bottomPoint(of: scrollRect))),
      ],
      rootIdentity: rootIdentity,
      terminalSize: terminalSize,
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(terminal.frames.count >= 2)
  }

  @MainActor
  @Test("layout-hosted ScrollView content survives pointer scrolling")
  func layoutHostedScrollViewContentSurvivesPointerScrolling() async throws {
    let terminalSize = Size(width: 80, height: 24)
    let terminal = RecordingTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("LayoutHostedGalleryLikeScrollFixture")
    let view = LayoutHostedGalleryLikeScrollFixture()

    let scrollRect = try #require(
      renderedScrollViewportRect(
        for: testIdentity("LayoutHostedGalleryLikeScrollFixture", "Layout[0]"),
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )

    let result = try await runTerminalInputHarness(
      terminal: terminal,
      events: [
        .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 1), location: bottomPoint(of: scrollRect))),
        .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 1), location: bottomPoint(of: scrollRect))),
      ],
      rootIdentity: rootIdentity,
      terminalSize: terminalSize,
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(terminal.frames.count >= 2)
  }

  /// End-to-end regression: send pointer scroll events through the
  /// real run loop and verify that the external position binding
  /// actually advanced.  Existing scroll tests only assert that
  /// `frames.count >= 2`, which can pass even when the rendered
  /// surface never reflects the scroll (the "have to click before it
  /// updates" symptom that recurs in the gallery).
  @MainActor
  @Test("pointer scroll advances external position binding through full run loop")
  func pointerScrollAdvancesExternalBindingThroughFullRunLoop() async throws {
    let terminalSize = Size(width: 30, height: 8)
    let terminal = RecordingTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("PointerScrollExternalBinding")
    let scrollIdentity = testIdentity("PointerScrollExternalBinding", "Scroll")
    let positionBox = LockedBox(ScrollPosition.zero)

    let view = TallExternalBindingScrollFixture(
      scrollIdentity: scrollIdentity,
      positionBox: positionBox
    )

    let scrollRect = try #require(
      renderedScrollViewportRect(
        for: scrollIdentity,
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )

    let result = try await runTerminalInputHarness(
      terminal: terminal,
      events: [
        .mouse(
          .init(
            kind: .scrolled(deltaX: 0, deltaY: 1),
            location: centerPoint(of: scrollRect)
          )),
        .mouse(
          .init(
            kind: .scrolled(deltaX: 0, deltaY: 1),
            location: centerPoint(of: scrollRect)
          )),
      ],
      rootIdentity: rootIdentity,
      terminalSize: terminalSize,
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(
      positionBox.value.y >= 1,
      "external scroll position should have advanced through the run loop"
    )
  }

  /// Mirrors the gallery animations tab: a ScrollView wrapping a
  /// view that contains a continuously-cycling `PhaseAnimator`.  The
  /// animation pump and the pointer-scroll pump must both make
  /// progress simultaneously — historically the animation pump's
  /// continuous deadline-wakes have masked scroll invalidations,
  /// so a scroll arrived at the runtime but never reached a render.
  @MainActor
  @Test("pointer scroll advances binding while a PhaseAnimator is cycling")
  func pointerScrollAdvancesWhilePhaseAnimatorCycling() async throws {
    let terminalSize = Size(width: 40, height: 12)
    let terminal = RecordingTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("PointerScrollWithAnimation")
    let scrollIdentity = testIdentity("PointerScrollWithAnimation", "Scroll")
    let positionBox = LockedBox(ScrollPosition.zero)

    let view = AnimatingTallScrollFixture(
      scrollIdentity: scrollIdentity,
      positionBox: positionBox
    )

    let scrollRect = try #require(
      renderedScrollViewportRect(
        for: scrollIdentity,
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )

    let result = try await runTerminalInputHarness(
      terminal: terminal,
      events: [
        .mouse(
          .init(
            kind: .scrolled(deltaX: 0, deltaY: 1),
            location: centerPoint(of: scrollRect)
          )),
        .mouse(
          .init(
            kind: .scrolled(deltaX: 0, deltaY: 1),
            location: centerPoint(of: scrollRect)
          )),
      ],
      rootIdentity: rootIdentity,
      terminalSize: terminalSize,
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(
      positionBox.value.y >= 1,
      "scroll should still advance while a PhaseAnimator is cycling"
    )
  }

  /// Mirrors the gallery animations tab exactly: a ScrollView with
  /// `.frame(maxWidth: .infinity, maxHeight: .infinity)` (instead of
  /// a fixed `.frame(width:height:)`) wrapping content with
  /// `.padding(1)` and a continuously cycling PhaseAnimator.  This
  /// is the exact body shape that started failing when the user
  /// wrapped the animations tab in a ScrollView.
  @MainActor
  @Test("gallery-shaped ScrollView (.frame maxWidth/.maxHeight) advances on pointer scroll")
  func galleryShapedScrollViewAdvancesOnPointerScroll() async throws {
    let terminalSize = Size(width: 60, height: 20)
    let terminal = RecordingTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("GalleryShapedScroll")
    let scrollIdentity = testIdentity("GalleryShapedScroll", "Scroll")
    let positionBox = LockedBox(ScrollPosition.zero)

    let view = GalleryShapedAnimatingScrollFixture(
      scrollIdentity: scrollIdentity,
      positionBox: positionBox
    )

    let scrollRect = try #require(
      renderedScrollViewportRect(
        for: scrollIdentity,
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )

    let result = try await runTerminalInputHarness(
      terminal: terminal,
      events: [
        .mouse(
          .init(
            kind: .scrolled(deltaX: 0, deltaY: 1),
            location: centerPoint(of: scrollRect)
          )),
        .mouse(
          .init(
            kind: .scrolled(deltaX: 0, deltaY: 1),
            location: centerPoint(of: scrollRect)
          )),
        .mouse(
          .init(
            kind: .scrolled(deltaX: 0, deltaY: 1),
            location: centerPoint(of: scrollRect)
          )),
      ],
      rootIdentity: rootIdentity,
      terminalSize: terminalSize,
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(
      positionBox.value.y >= 1,
      "gallery-shaped ScrollView should advance on pointer scroll"
    )
  }

  /// Verifies that pointer scrolling produces an observably
  /// different rendered surface — not just an updated binding.
  /// Without this assertion, a regression where the binding writes
  /// land but the renderer never picks them up (the click-to-flush
  /// bug) would pass binding-only checks.
  @MainActor
  @Test("pointer scroll causes a follow-up render that reflects the new offset")
  func pointerScrollProducesObservableFollowUpFrame() async throws {
    let terminalSize = Size(width: 30, height: 8)
    let terminal = RecordingTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("PointerScrollVisibleFrame")
    let scrollIdentity = testIdentity("PointerScrollVisibleFrame", "Scroll")
    let positionBox = LockedBox(ScrollPosition.zero)

    let view = TallExternalBindingScrollFixture(
      scrollIdentity: scrollIdentity,
      positionBox: positionBox
    )

    let scrollRect = try #require(
      renderedScrollViewportRect(
        for: scrollIdentity,
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )

    let result = try await runTerminalInputHarness(
      terminal: terminal,
      events: [
        .mouse(
          .init(
            kind: .scrolled(deltaX: 0, deltaY: 3),
            location: centerPoint(of: scrollRect)
          ))
      ],
      rootIdentity: rootIdentity,
      terminalSize: terminalSize,
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(positionBox.value.y >= 1)
    #expect(
      terminal.frames.count >= 2,
      "scroll event should drive at least one follow-up frame"
    )
    let firstFrame = try #require(terminal.frames.first)
    let lastFrame = try #require(terminal.frames.last)
    #expect(
      firstFrame != lastFrame,
      "the rendered surface should differ between pre- and post-scroll frames"
    )
  }

  /// Regression for scroll views hosted inside a selected `TabView`
  /// pane. The scroll state can advance while the selected pane keeps
  /// presenting its stale pre-scroll snapshot, which looks like the
  /// scroll view is frozen until some unrelated interaction forces a
  /// broader refresh.
  @MainActor
  @Test("pointer scroll updates the visible surface for a TabView-hosted scroll pane")
  func pointerScrollUpdatesVisibleSurfaceForTabHostedScrollPane() async throws {
    let terminalSize = Size(width: 36, height: 10)
    let terminal = RecordingTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("TabHostedScrollVisibleFrame")
    let scrollIdentity = testIdentity("TabHostedScrollVisibleFrame", "Scroll")
    let positionBox = LockedBox(ScrollPosition.zero)

    let view = TabHostedTallExternalBindingScrollFixture(
      scrollIdentity: scrollIdentity,
      positionBox: positionBox
    )

    let scrollRect = try #require(
      renderedScrollViewportRect(
        for: scrollIdentity,
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )

    let result = try await runTerminalInputHarness(
      terminal: terminal,
      events: [
        .mouse(
          .init(
            kind: .scrolled(deltaX: 0, deltaY: 3),
            location: centerPoint(of: scrollRect)
          ))
      ],
      rootIdentity: rootIdentity,
      terminalSize: terminalSize,
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(positionBox.value.y >= 1)
    #expect(
      terminal.frames.count >= 2,
      "scroll event should drive at least one follow-up frame"
    )
    let firstFrame = try #require(terminal.frames.first)
    let lastFrame = try #require(terminal.frames.last)
    #expect(
      firstFrame != lastFrame,
      "the selected tab pane should repaint immediately after scroll"
    )
  }

  @MainActor
  @Test("pointer scroll updates the visible surface for a WindowGroup-hosted scroll pane")
  func pointerScrollUpdatesVisibleSurfaceForWindowGroupHostedScrollPane() async throws {
    let terminalSize = Size(width: 36, height: 10)
    let terminal = RecordingTerminalHost(surfaceSizeProvider: { terminalSize })
    let scrollIdentity = testIdentity("SceneHostedScrollVisibleFrame", "Scroll")
    let positionBox = LockedBox(ScrollPosition.zero)
    let scene = WindowGroup("Scene Hosted Scroll") {
      TabHostedTallExternalBindingScrollFixture(
        scrollIdentity: scrollIdentity,
        positionBox: positionBox
      )
    }
    let rootIdentity = Identity(components: ["App", "Scene Hosted Scroll"])

    let scrollRect = try #require(
      renderedScrollViewportRect(
        for: scrollIdentity,
        in: WindowHostView(
          content: ScopedBuilder {
            TabHostedTallExternalBindingScrollFixture(
              scrollIdentity: scrollIdentity,
              positionBox: positionBox
            )
          }
        ),
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )

    let result = try await runTestSceneSession(
      scene: scene,
      sessionName: "InteractiveRuntimeTests.SceneHostedScrollVisibleFrame",
      terminalHost: terminal,
      inputReader: SceneScriptedTerminalInputReader(
        events: [
          .mouse(
            .init(
              kind: .scrolled(deltaX: 0, deltaY: 3),
              location: centerPoint(of: scrollRect)
            ))
        ]
      ),
      signalReader: EmptySignalReader()
    )

    #expect(result.exitReason == RunLoopExitReason.inputEnded)
    #expect(positionBox.value.y >= 1)
    #expect(terminal.frames.count >= 2)
    let firstFrame = try #require(terminal.frames.first)
    let lastFrame = try #require(terminal.frames.last)
    #expect(
      firstFrame != lastFrame,
      "WindowGroup-hosted scroll panes should repaint immediately after scroll"
    )
  }

  /// Gallery-parity regression: the real gallery doesn't pass an
  /// explicit position binding to its ScrollView, so scroll state
  /// lives in the ScrollView's own `@State private var internalPosition`.
  /// The TabView above it owns its selection via a `@State` binding —
  /// which triggers the code path that captures the ScrollView's
  /// subtree into a `ResolvedContentView` and causes the ScrollView's
  /// own ViewNode to be orphaned from the snapshot walk whenever
  /// selective dirty evaluation runs only its evaluator.
  ///
  /// Before the fix, scroll-induced state changes on the ScrollView
  /// never reached the rendered surface until some unrelated re-resolve
  /// of the TabView body forced a full snapshot rebuild (e.g. a mouse
  /// click anywhere in the console).
  ///
  /// This test uses scripted terminal input for determinism and
  /// asserts the rendered surface advances after a single scroll
  /// event, without any follow-up interaction.
  @MainActor
  @Test(
    "scroll on TabView-hosted internal-@State ScrollView updates the rendered surface without a follow-up click"
  )
  func scrollOnTabViewHostedInternalStateScrollViewUpdatesRenderedSurface() async throws {
    let terminalSize = Size(width: 60, height: 20)
    let terminal = RecordingTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("InternalStateTabScrollFixture")

    let scrollRect = try #require(
      renderedFirstScrollViewportRect(
        in: TabHostedInternalStateGalleryFixture(),
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )

    let result = try await runTerminalInputHarness(
      terminal: terminal,
      events: [
        .mouse(
          .init(
            kind: .scrolled(deltaX: 0, deltaY: 3),
            location: centerPoint(of: scrollRect)
          ))
      ],
      rootIdentity: rootIdentity,
      terminalSize: terminalSize,
      viewBuilder: { TabHostedInternalStateGalleryFixture() }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(terminal.frames.count >= 2)
    let firstFrame = try #require(terminal.frames.first)
    let lastFrame = try #require(terminal.frames.last)
    #expect(
      firstFrame.contains("Gallery row 0"),
      "initial render should show the first row of scroll content"
    )
    #expect(
      firstFrame != lastFrame,
      "the rendered surface should differ after scrolling — a last frame that still matches the first means scroll state changes never reached the snapshot (the click-to-flush regression)"
    )
    #expect(
      !lastFrame.contains("Gallery row 0"),
      "scrolling 3 rows down should push the top-of-scroll row above the viewport"
    )
  }

  @Test("real InputReader scroll bursts update the visible gallery pane before any follow-up click")
  func realInputReaderScrollBurstsUpdateVisibleGalleryPaneBeforeFollowUpClick() async throws {
    var descriptors: [Int32] = [0, 0]
    #expect(unsafe pipe(&descriptors) == 0)

    let readDescriptor = descriptors[0]
    let writeDescriptor = descriptors[1]
    var didCloseReadDescriptor = false
    var didCloseWriteDescriptor = false
    defer {
      if !didCloseReadDescriptor {
        _ = close(readDescriptor)
      }
      if !didCloseWriteDescriptor {
        _ = close(writeDescriptor)
      }
    }

    let currentFlags = fcntl(readDescriptor, F_GETFL)
    #expect(currentFlags >= 0)
    #expect(fcntl(readDescriptor, F_SETFL, currentFlags | O_NONBLOCK) >= 0)

    let terminalSize = Size(width: 60, height: 20)
    let terminal = DamageRecordingTerminalHost(surfaceSizeProvider: { terminalSize })
    let scrollIdentity = testIdentity("RealInputReaderGalleryScroll", "Scroll")
    let positionBox = LockedBox(ScrollPosition.zero)
    let scene = WindowGroup("Real Input Gallery Scroll") {
      TabHostedGalleryShapedAnimatingScrollFixture(
        scrollIdentity: scrollIdentity,
        positionBox: positionBox
      )
    }
    let rootIdentity = testIdentity("App", "Real Input Gallery Scroll")

    let scrollRect = try #require(
      renderedScrollViewportRect(
        for: scrollIdentity,
        in: WindowHostView(
          content: ScopedBuilder {
            TabHostedGalleryShapedAnimatingScrollFixture(
              scrollIdentity: scrollIdentity,
              positionBox: positionBox
            )
          }
        ),
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )

    let inputReader = InputReader(fileDescriptor: readDescriptor)
    let runTask = Task {
      try await runTestSceneSession(
        scene: scene,
        sessionName: "InteractiveRuntimeTests.RealInputReaderGalleryScroll",
        terminalHost: terminal,
        inputReader: inputReader,
        signalReader: EmptySignalReader()
      )
    }

    let didRenderInitialFrame = try await waitUntil {
      !terminal.visibleFrames.isEmpty
    }
    #expect(didRenderInitialFrame)

    let scrollBytes = sgrScrollDown(at: centerPoint(of: scrollRect))
    for _ in 0..<12 {
      try writeAllBytes(scrollBytes, to: writeDescriptor)
    }

    let scrollBurstBecameVisible = try await waitUntil {
      positionBox.value.y >= 10
        && (terminal.visibleFrames.last ?? "").contains("Gallery row 5")
    }

    let frameAfterScrollBurst = terminal.visibleFrames.last ?? ""
    let positionAfterScrollBurst = positionBox.value

    let clickBytes = sgrPrimaryClick(at: .init(x: 1, y: 1))
    let frameCountBeforeClick = terminal.visibleFrames.count
    try writeAllBytes(clickBytes, to: writeDescriptor)
    _ = try await waitUntil(timeoutNanoseconds: 500_000_000) {
      terminal.visibleFrames.count > frameCountBeforeClick
    }

    let frameAfterClick = terminal.visibleFrames.last ?? ""

    _ = close(writeDescriptor)
    didCloseWriteDescriptor = true

    let result = try await runTask.value

    _ = close(readDescriptor)
    didCloseReadDescriptor = true

    #expect(result.exitReason == RunLoopExitReason.inputEnded)
    #expect(
      scrollBurstBecameVisible,
      "the scroll burst should be observable before the follow-up click"
    )
    #expect(positionAfterScrollBurst.y >= 10)
    #expect(
      frameAfterScrollBurst.contains("Gallery row 5"),
      "the scroll burst should visibly advance the pane before any later click"
    )
    #expect(
      frameAfterClick.contains("Gallery row 5"),
      "the follow-up click should not be required to reveal the earlier scroll"
    )
  }

  @Test(
    "injected terminal input scroll bursts update the visible gallery pane before any follow-up click"
  )
  func injectedTerminalInputScrollBurstsUpdateVisibleGalleryPaneBeforeFollowUpClick() async throws {
    let terminalSize = Size(width: 60, height: 20)
    let terminal = DamageRecordingTerminalHost(surfaceSizeProvider: { terminalSize })
    let scrollIdentity = testIdentity("InjectedInputGalleryScroll", "Scroll")
    let positionBox = LockedBox(ScrollPosition.zero)
    let scene = WindowGroup("Injected Input Gallery Scroll") {
      TabHostedGalleryShapedAnimatingScrollFixture(
        scrollIdentity: scrollIdentity,
        positionBox: positionBox
      )
    }
    let rootIdentity = testIdentity("App", "Injected Input Gallery Scroll")

    let scrollRect = try #require(
      renderedScrollViewportRect(
        for: scrollIdentity,
        in: WindowHostView(
          content: ScopedBuilder {
            TabHostedGalleryShapedAnimatingScrollFixture(
              scrollIdentity: scrollIdentity,
              positionBox: positionBox
            )
          }
        ),
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )

    let inputReader = InjectedSceneTerminalInputReader()
    let runTask = Task {
      try await runTestSceneSession(
        scene: scene,
        sessionName: "InteractiveRuntimeTests.InjectedInputGalleryScroll",
        terminalHost: terminal,
        inputReader: inputReader,
        signalReader: EmptySignalReader()
      )
    }

    let didRenderInitialFrame = try await waitUntil {
      !terminal.visibleFrames.isEmpty
    }
    #expect(didRenderInitialFrame)

    let scrollBytes = sgrScrollDown(at: centerPoint(of: scrollRect))
    for _ in 0..<12 {
      inputReader.send(scrollBytes)
    }

    let scrollBurstBecameVisible = try await waitUntil {
      positionBox.value.y >= 10
        && (terminal.visibleFrames.last ?? "").contains("Gallery row 5")
    }

    let frameAfterScrollBurst = terminal.visibleFrames.last ?? ""
    let positionAfterScrollBurst = positionBox.value

    let frameCountBeforeClick = terminal.visibleFrames.count
    inputReader.send(sgrPrimaryClick(at: .init(x: 1, y: 1)))
    _ = try await waitUntil(timeoutNanoseconds: 500_000_000) {
      terminal.visibleFrames.count > frameCountBeforeClick
    }

    let frameAfterClick = terminal.visibleFrames.last ?? ""

    inputReader.finish()
    let result = try await runTask.value

    #expect(result.exitReason == RunLoopExitReason.inputEnded)
    #expect(
      scrollBurstBecameVisible,
      "the injected-input scroll burst should be observable before the follow-up click"
    )
    #expect(positionAfterScrollBurst.y >= 10)
    #expect(
      frameAfterScrollBurst.contains("Gallery row 5"),
      "the injected-input scroll burst should visibly advance the pane before any later click"
    )
    #expect(
      frameAfterClick.contains("Gallery row 5"),
      "the follow-up click should not be required to reveal the earlier scroll"
    )
  }

  @MainActor
  @Test(
    "handled pointer scrolling invalidates the scroll route even for external position bindings")
  func handledPointerScrollingInvalidatesScrollRouteForExternalBindings() throws {
    let terminalSize = Size(width: 20, height: 8)
    let terminal = RecordingTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("ExternalPointerScrollInvalidation")
    let scrollIdentity = testIdentity("ExternalPointerScrollInvalidation", "Scroll")
    let scheduler = FrameScheduler()
    let box = LockedBox(ScrollPosition.zero)

    let view =
      ScrollView(
        .vertical,
        position: Binding(
          get: { box.value },
          set: { box.value = $0 }
        )
      ) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<10) { index in
            Text("Mouse \(index)")
          }
        }
      }
      .id(scrollIdentity)
      .frame(width: 10, height: 5, alignment: .topLeading)

    let scrollRect = try #require(
      renderedScrollViewportRect(
        for: scrollIdentity,
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )

    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = terminal.appearance
    environmentValues.terminalSize = terminalSize

    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      terminalHost: terminal,
      terminalInputReader: ScriptedTerminalInputReader(events: []),
      signalReader: EmptySignalReader(),
      scheduler: scheduler,
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
        view
      }
    )

    scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    #expect(
      runLoop.handle(
        .input(
          .mouse(
            .init(kind: .scrolled(deltaX: 0, deltaY: 1), location: centerPoint(of: scrollRect))
          ))) == nil)
    #expect(box.value == .init(x: 0, y: 1))

    let scheduledFrame = try #require(
      scheduler.consumeReadyFrame(at: .now())
    )
    #expect(scheduledFrame.causes.contains(.invalidation))
    #expect(scheduledFrame.invalidatedIdentities == [scrollIdentity])
  }

  @MainActor
  @Test("clamped pointer scrolling does not schedule a frame when nothing changes")
  func clampedPointerScrollingDoesNotScheduleFrameWhenNothingChanges() throws {
    let terminalSize = Size(width: 20, height: 8)
    let terminal = RecordingTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("ClampedPointerScroll")
    let scrollIdentity = testIdentity("ClampedPointerScroll", "Scroll")
    let scheduler = FrameScheduler()
    let box = LockedBox(ScrollPosition.zero)

    let view =
      ScrollView(
        .vertical,
        position: Binding(
          get: { box.value },
          set: { box.value = $0 }
        )
      ) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<10) { index in
            Text("Mouse \(index)")
          }
        }
      }
      .id(scrollIdentity)
      .frame(width: 10, height: 5, alignment: .topLeading)

    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = terminal.appearance
    environmentValues.terminalSize = terminalSize

    let previewArtifacts = DefaultRenderer().render(
      view,
      context: .init(
        identity: rootIdentity,
        environmentValues: environmentValues
      ),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )
    let scrollRoute = try #require(
      previewArtifacts.semanticSnapshot.scrollRoutes.first { route in
        route.identity == scrollIdentity
      }
    )
    let focusIdentity = try #require(
      previewArtifacts.semanticSnapshot.focusRegions.first?.identity
    )
    let maxY = max(
      0,
      scrollRoute.contentBounds.size.height - scrollRoute.viewportRect.size.height
    )
    box.value = .init(x: 0, y: maxY)

    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      terminalHost: terminal,
      terminalInputReader: ScriptedTerminalInputReader(events: []),
      signalReader: EmptySignalReader(),
      scheduler: scheduler,
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
        view
      }
    )

    scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    _ = runLoop.focusTracker.setFocus(to: focusIdentity)
    scheduler.reset()

    #expect(
      runLoop.handle(
        .input(
          .mouse(
            .init(
              kind: .scrolled(deltaX: 0, deltaY: 1),
              location: centerPoint(of: scrollRoute.viewportRect))
          ))) == nil)
    #expect(box.value == .init(x: 0, y: maxY))
    #expect(scheduler.consumeReadyFrame(at: .now()) == nil)
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
    final class ScrollPositionBox: Sendable {
      private let storage = LockedBox(ScrollPosition.zero)

      var position: ScrollPosition {
        get { storage.value }
        set { storage.value = newValue }
      }
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
      renderedScrollViewportRect(
        for: scrollIdentity,
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

  @MainActor
  @Test("run loop collapses queued scroll bursts through LazyVStack content")
  func runLoopBatchesQueuedScrollBurstsWithLazyStacks() async throws {
    final class ScrollPositionBox: Sendable {
      private let storage = LockedBox(ScrollPosition.zero)

      var position: ScrollPosition {
        get { storage.value }
        set { storage.value = newValue }
      }
    }

    let box = ScrollPositionBox()
    let terminalSize = Size(width: 24, height: 10)
    let terminal = RecordingTerminalHost(
      surfaceSizeProvider: { terminalSize },
      presentObserver: {
        usleep(5_000)
      }
    )
    let rootIdentity = testIdentity("BurstLazyScrollFixture")
    let scrollIdentity = testIdentity("BurstLazyScrollFixture", "Scroll")
    let view =
      ScrollView(
        .vertical,
        position: Binding(
          get: { box.position },
          set: { box.position = $0 }
        )
      ) {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<30) { index in
            Text("Burst \(index)")
          }
        }
      }
      .id(scrollIdentity)
      .frame(width: 12, height: 4, alignment: .topLeading)

    let scrollRect = try #require(
      renderedScrollViewportRect(
        for: scrollIdentity,
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

  @MainActor
  @Test("run loop emits viewport lifecycle transitions for full-lazy ForEach rows")
  func runLoopEmitsViewportLifecycleTransitionsForFullLazyRows() async throws {
    let recorder = RuntimeLifecycleRecorder()
    let terminalSize = Size(width: 24, height: 8)
    let terminal = RecordingTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("LazyForEachLifecycleRuntime")
    let scrollIdentity = testIdentity("LazyForEachLifecycleRuntime", "Scroll")
    let view =
      ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<4) { index in
            ScrollLifecycleRuntimeProbe(
              label: "row-\(index)",
              text: "Row \(index)",
              recorder: recorder
            )
          }
        }
      }
      .id(scrollIdentity)
      .frame(width: 12, height: 2, alignment: .topLeading)

    let scrollRect = try #require(
      renderedScrollViewportRect(
        for: scrollIdentity,
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )

    let result = try await runTerminalInputHarness(
      terminal: terminal,
      events: [
        .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 1), location: centerPoint(of: scrollRect)))
      ],
      rootIdentity: rootIdentity,
      terminalSize: terminalSize,
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(await recorder.waitForEvent("appear:row-0"))
    #expect(await recorder.waitForEvent("appear:row-1"))
    #expect(await recorder.waitForEvent("appear:row-2"))
    #expect(await recorder.waitForEvent("disappear:row-0"))
    #expect(await recorder.waitForEvent("taskStart:row-2"))
    #expect(await recorder.waitForEvent("taskCancel:row-0"))
    #expect(!recorder.events(matchingPrefix: "appear:").contains("appear:row-3"))
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
  private let setAttributesCallsStorage = LockedBox<[termios]>([])
  private let writesStorage = LockedBox<[String]>([])
  private let fileStatusFlagsStorage = LockedBox<Int32>(0)

  private(set) var setAttributesCalls: [termios] {
    get { setAttributesCallsStorage.value }
    set { setAttributesCallsStorage.value = newValue }
  }

  private(set) var writes: [String] {
    get { writesStorage.value }
    set { writesStorage.value = newValue }
  }

  private(set) var fileStatusFlags: Int32 {
    get { fileStatusFlagsStorage.value }
    set { fileStatusFlagsStorage.value = newValue }
  }

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
    setAttributesCallsStorage.withLock { $0.append(attributes) }
  }

  func windowSize(of _: Int32) throws -> Size {
    .init(width: 80, height: 24)
  }

  func getFileStatusFlags(of _: Int32) throws -> Int32 {
    fileStatusFlags
  }

  func setFileStatusFlags(_ flags: Int32, on _: Int32) throws {
    fileStatusFlagsStorage.value = flags
  }

  func write(_ output: String, to _: Int32) throws {
    writesStorage.withLock { $0.append(output) }
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
          capabilityProfile: capabilityProfile
        ).bytesWritten
      case .incremental:
        plan.rowBatches.reduce(0) { partial, rowBatch in
          partial
            + cursorSequence(row: rowBatch.row, column: rowBatch.anchorColumn).utf8.count
            + rowBatch.renderedBatch.utf8.count
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

private final class DamageRecordingTerminalHost: TerminalHosting, DamageAwareTerminalHosting {
  var surfaceSize: Size {
    surfaceSizeProvider()
  }
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance
  private(set) var visibleFrames: [String] = []
  private(set) var presentationMetrics: [TerminalPresentationMetrics] = []
  private var lastSubmittedSurface: RasterSurface?
  private var visibleSurface: RasterSurface?
  private let surfaceSizeProvider: () -> Size

  init(
    surfaceSizeProvider: @escaping () -> Size = { InteractiveDemoLayout.frameSize },
    capabilityProfile: TerminalCapabilityProfile = .previewUnicode,
    appearance: TerminalAppearance = .fallback
  ) {
    self.surfaceSizeProvider = surfaceSizeProvider
    self.capabilityProfile = capabilityProfile
    self.appearance = appearance
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: Point) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    try present(surface, damage: nil)
  }

  @discardableResult
  func present(
    _ surface: RasterSurface,
    damage: PresentationDamage?
  ) throws -> TerminalPresentationMetrics {
    let renderer = TerminalSurfaceRenderer(
      capabilityProfile: capabilityProfile
    )
    let plan = TerminalPresentationPlanner(
      capabilityProfile: capabilityProfile
    ).plan(
      previousSurface: lastSubmittedSurface,
      currentSurface: surface,
      damage: damage
    )

    switch plan.strategy {
    case .fullRepaint:
      visibleSurface = surface
    case .incremental:
      if var visibleSurface {
        let previousSurface = lastSubmittedSurface ?? visibleSurface
        let rowCount = max(
          max(previousSurface.cells.count, surface.cells.count),
          max(previousSurface.size.height, surface.size.height)
        )
        let rowsToDiff =
          if let damage {
            damage.dirtyRows
              .filter { $0 >= 0 && $0 < rowCount }
              .sorted()
          } else {
            Array(0..<rowCount)
          }

        let requiredWidth = max(
          visibleSurface.size.width,
          surface.size.width,
          previousSurface.size.width
        )
        let requiredHeight = max(
          visibleSurface.size.height,
          surface.size.height,
          previousSurface.size.height
        )
        if visibleSurface.cells.count < requiredHeight {
          visibleSurface.cells.append(
            contentsOf: Array(
              repeating: Array(repeating: RasterCell.empty, count: requiredWidth),
              count: requiredHeight - visibleSurface.cells.count
            )
          )
        }
        for row in visibleSurface.cells.indices
        where visibleSurface.cells[row].count < requiredWidth {
          visibleSurface.cells[row].append(
            contentsOf: Array(
              repeating: RasterCell.empty,
              count: requiredWidth - visibleSurface.cells[row].count
            )
          )
        }
        visibleSurface.size = .init(width: requiredWidth, height: requiredHeight)

        for row in rowsToDiff {
          let previousRow = row < previousSurface.cells.count ? previousSurface.cells[row] : []
          let currentRow = row < surface.cells.count ? surface.cells[row] : []
          let width = max(
            previousSurface.size.width,
            surface.size.width,
            previousRow.count,
            currentRow.count
          )
          let spans = renderer.diffSpans(
            previousRow: previousRow,
            currentRow: currentRow,
            width: width
          )

          for span in spans {
            for column in span {
              let cell =
                if column < currentRow.count {
                  currentRow[column]
                } else {
                  RasterCell.empty
                }
              visibleSurface.cells[row][column] = cell
            }
          }
        }

        self.visibleSurface = visibleSurface
      } else {
        visibleSurface = surface
      }
    }

    let renderedVisibleSurface = renderer.render(visibleSurface ?? surface)
    visibleFrames.append(renderedVisibleSurface.replacingOccurrences(of: "\r\n", with: "\n"))
    lastSubmittedSurface = surface

    let metrics = TerminalPresentationMetrics(
      bytesWritten: 0,
      linesTouched: plan.linesTouched,
      cellsChanged: plan.cellsChanged,
      strategy: plan.strategy == .fullRepaint ? .fullRepaint : .incremental
    )
    presentationMetrics.append(metrics)
    return metrics
  }

  func write(_: String) throws {}
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
      let bytesWritten = unsafe write(fileDescriptor, nextAddress, bytesRemaining)
      guard bytesWritten >= 0 else {
        throw TerminalHostError.failedToWrite(errno: errno)
      }
      totalBytesWritten += bytesWritten
    }
  }
}

private func waitUntil(
  timeoutNanoseconds: UInt64 = 5_000_000_000,
  pollNanoseconds: UInt64 = 5_000_000,
  condition: () -> Bool
) async throws -> Bool {
  let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
  while DispatchTime.now().uptimeNanoseconds < deadline {
    if condition() {
      return true
    }
    try await Task.sleep(nanoseconds: pollNanoseconds)
  }
  return condition()
}

private func sgrScrollDown(
  at point: Point
) -> [UInt8] {
  Array("\u{001B}[<65;\(point.x + 1);\(point.y + 1)M".utf8)
}

private func sgrPrimaryClick(
  at point: Point
) -> [UInt8] {
  Array(
    "\u{001B}[<0;\(point.x + 1);\(point.y + 1)M\u{001B}[<0;\(point.x + 1);\(point.y + 1)m"
      .utf8
  )
}

private struct RunLoopInvalidationRecord: Equatable {
  let state: Int
  let identity: Identity
  let invalidatedIdentities: Set<Identity>
  let isSelfInvalidated: Bool
  let subtreeAffected: Bool
}

private final class RunLoopInvalidationRecorder: Sendable {
  private let recordsStorage = LockedBox<[RunLoopInvalidationRecord]>([])

  private(set) var records: [RunLoopInvalidationRecord] {
    get { recordsStorage.value }
    set { recordsStorage.value = newValue }
  }

  func record(_ record: RunLoopInvalidationRecord) {
    recordsStorage.withLock { $0.append(record) }
  }
}

@MainActor
private func interactiveProbeTextNode(
  _ content: String,
  in context: ResolveContext
) -> ResolvedNode {
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

private final class ReusedHandlerRecorder: Sendable {
  private struct State: Sendable {
    var actionCount = 0
    var keyEvents: [KeyEvent] = []
  }

  private let state = LockedBox(State())

  private(set) var actionCount: Int {
    get { state.value.actionCount }
    set { state.withLock { $0.actionCount = newValue } }
  }

  private(set) var keyEvents: [KeyEvent] {
    get { state.value.keyEvents }
    set { state.withLock { $0.keyEvents = newValue } }
  }

  func recordAction() {
    state.withLock { $0.actionCount += 1 }
  }

  func recordKey(_ event: KeyEvent) {
    state.withLock { $0.keyEvents.append(event) }
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

private final class LinkOpenRecorder: Sendable {
  private let destinationsStorage = LockedBox<[LinkDestination]>([])

  var destinations: [LinkDestination] {
    destinationsStorage.value
  }

  func record(_ destination: LinkDestination) {
    destinationsStorage.withLock { $0.append(destination) }
  }
}

private final class ScriptedInputReader: InputReading {
  private let scriptedEvents: [KeyPress]

  init(events: [KeyPress]) {
    scriptedEvents = events
  }

  convenience init(events: [KeyEvent]) {
    self.init(events: events.map { KeyPress($0) })
  }

  func events() -> AsyncStream<KeyPress> {
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

private final class SceneScriptedTerminalInputReader: InputReading, TerminalInputReading {
  private let scriptedEvents: [InputEvent]

  init(events: [InputEvent]) {
    scriptedEvents = events
  }

  func events() -> AsyncStream<KeyPress> {
    AsyncStream { continuation in
      continuation.finish()
    }
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

private final class InjectedSceneTerminalInputReader: InputReading, TerminalInputReading {
  private let inputReader = InjectedTerminalInputReader()

  func send(
    _ bytes: [UInt8]
  ) {
    inputReader.send(bytes)
  }

  func finish() {
    inputReader.finish()
  }

  func events() -> AsyncStream<KeyPress> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    inputReader.inputEvents()
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
  private let event: KeyPress

  init(
    gate: AsyncEventGate,
    event: KeyPress
  ) {
    self.gate = gate
    self.event = event
  }

  convenience init(
    gate: AsyncEventGate,
    event: KeyEvent
  ) {
    self.init(gate: gate, event: KeyPress(event))
  }

  func events() -> AsyncStream<KeyPress> {
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
  private let scriptedEvents: [TimedRuntimeEvent<KeyPress>]

  init(events: [TimedRuntimeEvent<KeyPress>]) {
    scriptedEvents = events
  }

  convenience init(events: [TimedRuntimeEvent<KeyEvent>]) {
    self.init(
      events: events.map { event in
        .init(
          delayNanoseconds: event.delayNanoseconds,
          value: KeyPress(event.value)
        )
      }
    )
  }

  func events() -> AsyncStream<KeyPress> {
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

private final class RuntimeLifecycleRecorder: Sendable {
  private struct State: Sendable {
    var appearCountsAtPresent: [Int] = []
    var orderedEvents: [String] = []
  }

  private let state = LockedBox(State())

  private(set) var appearCountsAtPresent: [Int] {
    get { state.value.appearCountsAtPresent }
    set { state.withLock { $0.appearCountsAtPresent = newValue } }
  }

  private(set) var orderedEvents: [String] {
    get { state.value.orderedEvents }
    set { state.withLock { $0.orderedEvents = newValue } }
  }

  func record(_ event: String) {
    state.withLock { $0.orderedEvents.append(event) }
  }

  func recordAppearCountAtPresent() {
    state.withLock { state in
      let appearCount = state.orderedEvents.filter { $0.hasPrefix("appear:") }.count
      state.appearCountsAtPresent.append(appearCount)
    }
  }

  func events(matchingPrefix prefix: String) -> [String] {
    state.withLock { $0.orderedEvents.filter { $0.hasPrefix(prefix) } }
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

  func runUntilCancelled(
    label: String
  ) async {
    record("taskStart:\(label)")
    while !Task.isCancelled {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    record("taskCancel:\(label)")
  }

  private func contains(_ event: String) -> Bool {
    state.withLock { $0.orderedEvents.contains(event) }
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

private struct ScrollLifecycleRuntimeProbe: View, ResolvableView {
  let label: String
  let text: String
  let recorder: RuntimeLifecycleRecorder

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let appearHandlerID = "\(context.identity)/appear"
    let disappearHandlerID = "\(context.identity)/disappear"
    let descriptor = TaskDescriptor(
      id: "\(context.identity)/task",
      priority: .medium
    )

    context.localLifecycleRegistry?.registerAppear(handlerID: appearHandlerID) {
      recorder.record("appear:\(label)")
    }
    context.localLifecycleRegistry?.registerDisappear(handlerID: disappearHandlerID) {
      recorder.record("disappear:\(label)")
    }
    context.localTaskRegistry?.register(
      identity: context.identity,
      registration: TaskRegistration(
        descriptor: descriptor,
        operation: {
          await recorder.runUntilCancelled(label: label)
        }
      )
    )

    var node = interactiveProbeTextNode(text, in: context)
    node.lifecycleMetadata = .init(
      appearHandlerIDs: [appearHandlerID],
      disappearHandlerIDs: [disappearHandlerID],
      task: descriptor
    )
    return [node]
  }
}

private struct LifecycleRuntimeRoot: View, ResolvableView {
  let state: LifecycleRuntimeState
  let recorder: RuntimeLifecycleRecorder
  let focusable: Bool

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
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
  events: [KeyPress]
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
      keyPress:focusedIdentity:stateContainer:
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
private func makeRuntimeHarness(
  terminal: RecordingTerminalHost,
  events: [KeyEvent]
) async throws -> RunLoopResult<InteractiveDemoState> {
  try await makeRuntimeHarness(
    terminal: terminal,
    events: events.map { KeyPress($0) }
  )
}

@MainActor
private func makeLifecycleRuntimeHarness(
  terminal: RecordingTerminalHost,
  recorder: RuntimeLifecycleRecorder,
  focusable: Bool = false,
  events: [TimedRuntimeEvent<KeyPress>],
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
    keyHandler: { keyPress, _, stateContainer in
      guard keyPress == KeyPress(.character("t")) else {
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

@MainActor
private func makeLifecycleRuntimeHarness(
  terminal: RecordingTerminalHost,
  recorder: RuntimeLifecycleRecorder,
  focusable: Bool = false,
  events: [TimedRuntimeEvent<KeyEvent>],
  signals: [TimedRuntimeEvent<String>] = []
) async throws -> RunLoopResult<LifecycleRuntimeState> {
  try await makeLifecycleRuntimeHarness(
    terminal: terminal,
    recorder: recorder,
    focusable: focusable,
    events: events.map { event in
      .init(
        delayNanoseconds: event.delayNanoseconds,
        value: KeyPress(event.value)
      )
    },
    signals: signals
  )
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

private struct ToastAutoDismissHarnessView: View {
  let terminalSize: Size

  @State private var isToastPresented = true

  var body: some View {
    Text("Workspace")
      .frame(
        width: terminalSize.width,
        height: terminalSize.height,
        alignment: .topLeading
      )
      .toast(
        "Action performed",
        isPresented: $isToastPresented,
        style: .success,
        duration: 0.01
      )
  }
}

private struct ImperativeAlertPresentationHarnessView: View {
  let terminalSize: Size

  var body: some View {
    EnvironmentReader(\.alertPresentationCoordinator) { coordinator in
      Text("Workspace")
        .frame(
          width: terminalSize.width,
          height: terminalSize.height,
          alignment: .topLeading
        )
        .onAppear {
          coordinator.present(
            PromptPresentationItem(
              id: "imperative-alert",
              title: "Imperative alert",
              descriptor: alertPromptPresentationSpec().descriptor,
              actionPayloads: deferredDeclaredBuilderChildren(
                from: Button("Dismiss") {}
              ),
              messagePayloads: deferredDeclaredBuilderChildren(
                from: Text("Presented after lifecycle commit.")
              ),
              contentPayloads: [],
              dismiss: {}
            )
          )
        }
    }
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

@MainActor
private func renderedFirstScrollViewportRect<V: View>(
  in view: V,
  rootIdentity: Identity,
  terminalSize: Size
) -> Rect? {
  var environmentValues = EnvironmentValues()
  environmentValues.terminalSize = terminalSize

  let artifacts = DefaultRenderer().render(
    view,
    context: .init(
      identity: rootIdentity,
      environmentValues: environmentValues
    ),
    proposal: .init(width: terminalSize.width, height: terminalSize.height)
  )

  return artifacts.semanticSnapshot.scrollRoutes.first?.viewportRect
}

@MainActor
private func renderedScrollViewportRect<V: View>(
  for identity: Identity,
  in view: V,
  rootIdentity: Identity,
  terminalSize: Size
) -> Rect? {
  var environmentValues = EnvironmentValues()
  environmentValues.terminalSize = terminalSize

  let artifacts = DefaultRenderer().render(
    view,
    context: .init(
      identity: rootIdentity,
      environmentValues: environmentValues
    ),
    proposal: .init(width: terminalSize.width, height: terminalSize.height)
  )

  return artifacts.semanticSnapshot.scrollRoutes.first { route in
    route.identity == identity
  }?.viewportRect
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

private struct StatefulImplicitPointerScrollFixture: View {
  @State private var fontNumber = 2

  var body: some View {
    ScrollView(.vertical) {
      EnvironmentReader(\.terminalAppearance) { _ in
        VStack(alignment: .leading, spacing: 0) {
          Stepper("Font", value: $fontNumber, in: 0...5)
          Text("Font \(fontNumber)")

          ForEach(0..<12) { index in
            Text("Row \(index)")
          }
        }
      }
    }
    .id(testIdentity("ImplicitPointerStatefulScrollFixture", "Scroll"))
    .frame(width: 12, height: 5, alignment: .topLeading)
  }
}

private struct TallExternalBindingScrollFixture: View {
  let scrollIdentity: Identity
  let positionBox: LockedBox<ScrollPosition>

  var body: some View {
    ScrollView(
      .vertical,
      position: Binding(
        get: { positionBox.value },
        set: { positionBox.value = $0 }
      )
    ) {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(0..<30) { index in
          Text("Row \(index)")
        }
      }
    }
    .id(scrollIdentity)
    .frame(width: 20, height: 6, alignment: .topLeading)
  }
}

private struct AnimatingTallScrollFixture: View {
  let scrollIdentity: Identity
  let positionBox: LockedBox<ScrollPosition>

  var body: some View {
    ScrollView(
      .vertical,
      position: Binding(
        get: { positionBox.value },
        set: { positionBox.value = $0 }
      )
    ) {
      VStack(alignment: .leading, spacing: 0) {
        PhaseAnimator([RegressionPhase.a, .b, .c]) { phase in
          Text("Phase \(phase.label)")
        } animation: { _ in
          .linear(duration: .milliseconds(100))
        }
        ForEach(0..<25) { index in
          Text("Row \(index)")
        }
      }
    }
    .id(scrollIdentity)
    .frame(width: 24, height: 8, alignment: .topLeading)
  }
}

/// Mirrors the actual gallery animations tab body shape: a
/// `ScrollView` whose outer `.frame(maxWidth: .infinity, maxHeight:
/// .infinity)` modifier expands the viewport to fill the proposed
/// terminal area.  The other regression fixtures pin a tight
/// `.frame(width:height:)` which produces a different layout
/// proposal flow — this fixture exercises the gallery's exact
/// proposal-flow shape.
private struct GalleryShapedAnimatingScrollFixture: View {
  let scrollIdentity: Identity
  let positionBox: LockedBox<ScrollPosition>

  var body: some View {
    ScrollView(
      .vertical,
      position: Binding(
        get: { positionBox.value },
        set: { positionBox.value = $0 }
      )
    ) {
      VStack(alignment: .leading, spacing: 1) {
        PhaseAnimator([RegressionPhase.a, .b, .c]) { phase in
          Text("Phase \(phase.label)")
        } animation: { _ in
          .linear(duration: .milliseconds(100))
        }
        ForEach(0..<40) { index in
          Text("Gallery row \(index)")
        }
      }
      .padding(1)
    }
    .id(scrollIdentity)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct TabHostedTallExternalBindingScrollFixture: View {
  enum TallExternalBindingTab: Hashable {
    case controls
    case logs
  }

  let scrollIdentity: Identity
  let positionBox: LockedBox<ScrollPosition>

  var body: some View {
    TabView(selection: .constant(TallExternalBindingTab.logs)) {
      Tab("Controls", value: TallExternalBindingTab.controls) {
        Text("Controls")
      }

      Tab("Logs", value: TallExternalBindingTab.logs) {
        TallExternalBindingScrollFixture(
          scrollIdentity: scrollIdentity,
          positionBox: positionBox
        )
      }
    }
  }
}

private struct TabHostedGalleryShapedAnimatingScrollFixture: View {
  enum GalleryAnimatingTab: Hashable {
    case controls
    case animations
  }

  let scrollIdentity: Identity
  let positionBox: LockedBox<ScrollPosition>

  var body: some View {
    TabView(selection: .constant(GalleryAnimatingTab.animations)) {
      Tab("Controls", value: GalleryAnimatingTab.controls) {
        Text("Controls")
      }

      Tab("Animations", value: GalleryAnimatingTab.animations) {
        GalleryShapedAnimatingScrollFixture(
          scrollIdentity: scrollIdentity,
          positionBox: positionBox
        )
      }
    }
  }
}

private struct SigwinchLiteralTabOverflowFixture: View {
  var body: some View {
    TabView(selection: .constant("one")) {
      Tab("One", value: "one") {
        Text("One content")
      }

      Tab("Two", value: "two") {
        Text("Two content")
      }

      Tab("Three", value: "three") {
        Text("Three content")
      }

      Tab("Four", value: "four") {
        Text("Four content")
      }
    }
    .tabViewStyle(.literalTabs)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private enum RegressionPhase: Equatable, Sendable {
  case a
  case b
  case c

  var label: String {
    switch self {
    case .a: "A"
    case .b: "B"
    case .c: "C"
    }
  }
}

/// Mirrors the gallery animations tab's **state ownership** shape: the
/// ScrollView receives no explicit `position` binding, so scroll state
/// lives in the ScrollView's own `@State private var internalPosition`.
/// The surrounding view also holds its own `@State` field to mimic the
/// gallery's multiple-@State view shape.
///
/// The earlier gallery regression fixtures passed an *external*
/// `LockedBox<ScrollPosition>` through a `Binding`, which bypasses the
/// internal state-slot dirtying path.  This fixture exercises the
/// internal-state path the gallery actually uses.
private struct InternalStateGalleryShapedFixture: View {
  @State private var unrelatedCounter: Int = 0

  var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 1) {
        PhaseAnimator([RegressionPhase.a, .b, .c]) { phase in
          Text("Phase \(phase.label)")
        } animation: { _ in
          .linear(duration: .milliseconds(100))
        }
        ForEach(0..<40) { index in
          Text("Gallery row \(index)")
        }
        // A hidden tap target so the outer @State field is reachable
        // from input tests; the visible behaviour is identical whether
        // it is present or not.  Keeping it ensures the state slot is
        // actually authored.
        Text("counter \(unrelatedCounter)")
      }
      .padding(1)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct TabHostedInternalStateGalleryFixture: View {
  enum InternalStateGalleryTab: Hashable {
    case controls
    case animations
  }

  // Mirrors the real gallery: the selection is @State-owned (not a
  // constant).  Even without navigating away first, a @State-backed
  // TabView selection exercises a different code path from
  // `.constant(...)` — the selection binding writes go through the
  // parent view's state container, which re-resolves the entire TabView
  // subtree on each write.
  @State private var selection: InternalStateGalleryTab = .animations

  var body: some View {
    TabView(selection: $selection) {
      Tab("Controls", value: InternalStateGalleryTab.controls) {
        Text("Controls")
      }

      Tab("Animations", value: InternalStateGalleryTab.animations) {
        InternalStateGalleryShapedFixture()
      }
    }
  }
}

private struct GalleryLikeScrollFixture: View {
  @State private var fontNumber = 2
  @State private var font: EmbeddedFigletFont = .small
  @State private var taskRuns = 0

  private var fontCount: Int {
    EmbeddedFigletFont.allCases.count
  }

  var body: some View {
    ScrollView(.vertical) {
      EnvironmentReader(\.terminalAppearance) { appearance in
        VStack(alignment: .leading, spacing: 1) {
          VStack(alignment: .leading, spacing: 0) {
            HStack {
              Stepper("", value: $fontNumber)
              Text(font.rawValue)
              Text("Task \(taskRuns)")
            }
            .task(id: fontNumber) {
              taskRuns += 1
              if fontNumber >= 0 && fontNumber < fontCount {
                font = EmbeddedFigletFont.allCases[fontNumber]
              } else {
                fontNumber = 0
              }
            }

            if fontNumber >= 0 && fontNumber < fontCount {
              TextFigure("Gallery", font: font)
                .foregroundStyle(Color.black)
                .padding(1)
                .background(Color.red)
                .padding(1)
            }
          }

          GroupBox("Terminal palette (host)") {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(0..<16) { index in
                let hasColor = appearance.palette[index] != nil
                Text("Color \(index) \(hasColor ? "set" : "missing")")
              }
            }
          }

          GroupBox("Named colors") {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(0..<9) { index in
                Text("Named \(index)")
              }
            }
          }

          GroupBox("Semantic roles") {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(0..<6) { index in
                Text("Role \(index)")
              }
            }
          }
        }
      }
    }
    .id(testIdentity("GalleryLikeScrollFixture", "Scroll"))
    .frame(width: 30, height: 10, alignment: .topLeading)
  }
}

private struct RootAliasGalleryLikeScrollFixture: View {
  @State private var fontNumber = 2
  @State private var font: EmbeddedFigletFont = .small

  private var fontCount: Int {
    EmbeddedFigletFont.allCases.count
  }

  var body: some View {
    ScrollView(.vertical) {
      EnvironmentReader(\.terminalAppearance) { appearance in
        VStack(alignment: .leading, spacing: 1) {
          VStack(alignment: .leading, spacing: 0) {
            HStack {
              Stepper("", value: $fontNumber)
              Text(font.rawValue)
            }
            .task(id: fontNumber) {
              if fontNumber >= 0 && fontNumber < fontCount {
                font = EmbeddedFigletFont.allCases[fontNumber]
              } else {
                fontNumber = 0
              }
            }

            if fontNumber >= 0 && fontNumber < fontCount {
              TextFigure("Gallery", font: font)
                .foregroundStyle(Color.black)
                .padding(1)
                .background(Color.red)
                .padding(1)
            }
          }

          GroupBox("Terminal palette (host)") {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(0..<16) { index in
                let hasColor = appearance.palette[index] != nil
                Text("Color \(index) \(hasColor ? "set" : "missing")")
              }
            }
          }

          GroupBox("Named colors") {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(0..<9) { index in
                Text("Named \(index)")
              }
            }
          }

          GroupBox("Semantic roles") {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(0..<6) { index in
                Text("Role \(index)")
              }
            }
          }
        }
      }
    }
  }
}

private struct LayoutHostedGalleryLikeScrollFixture: View {
  var body: some View {
    WindowHostLayout {
      LayoutHostedGalleryLikeScrollContent()
    }
  }
}

private struct LayoutHostedGalleryLikeScrollContent: View {
  @State private var fontNumber = 2
  @State private var font: EmbeddedFigletFont = .small

  private var fontCount: Int {
    EmbeddedFigletFont.allCases.count
  }

  var body: some View {
    ScrollView(.vertical) {
      EnvironmentReader(\.terminalAppearance) { appearance in
        VStack(alignment: .leading, spacing: 1) {
          VStack(alignment: .leading, spacing: 0) {
            HStack {
              Stepper("", value: $fontNumber)
              Text(font.rawValue)
            }
            .task(id: fontNumber) {
              if fontNumber >= 0 && fontNumber < fontCount {
                font = EmbeddedFigletFont.allCases[fontNumber]
              } else {
                fontNumber = 0
              }
            }

            if fontNumber >= 0 && fontNumber < fontCount {
              TextFigure("Gallery", font: font)
                .foregroundStyle(Color.black)
                .padding(1)
                .background(Color.red)
                .padding(1)
            }
          }

          GroupBox("Terminal palette (host)") {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(0..<16) { index in
                let hasColor = appearance.palette[index] != nil
                Text("Color \(index) \(hasColor ? "set" : "missing")")
              }
            }
          }

          GroupBox("Named colors") {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(0..<9) { index in
                Text("Named \(index)")
              }
            }
          }

          GroupBox("Semantic roles") {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(0..<6) { index in
                Text("Role \(index)")
              }
            }
          }
        }
      }
    }
  }
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
