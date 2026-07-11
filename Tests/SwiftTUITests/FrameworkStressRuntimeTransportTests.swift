import Synchronization
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime

@MainActor
@Suite("SwiftTUI runtime and transport stress behavior", .serialized)
struct FrameworkStressRuntimeTransportTests {}

// MARK: - Attempt 001: scroll-location alternation

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 001 alternating scroll locations keep event boundaries")
  func runtimeTransport001AlternatingScrollLocationsKeepEventBoundaries() {
    // Hypothesis: a scroll burst that returns to an earlier cell can merge across
    // the intervening location and apply deltas to the wrong hit-test target.
    let first = MouseEvent(
      kind: .scrolled(deltaX: 0, deltaY: 1),
      location: .init(x: 2, y: 3)
    )
    let second = MouseEvent(
      kind: .scrolled(deltaX: 0, deltaY: 2),
      location: .init(x: 8, y: 3)
    )
    let third = MouseEvent(
      kind: .scrolled(deltaX: 0, deltaY: 3),
      location: .init(x: 2, y: 3)
    )

    #expect(
      coalescedInputEvents([.mouse(first), .mouse(second), .mouse(third)]) == [
        .mouse(first), .mouse(second), .mouse(third),
      ]
    )
  }
}

// MARK: - Attempt 023: disjoint damage-range ordering

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 023 disjoint damage ranges retain both ordered edits")
  func runtimeTransport023DisjointDamageRangesRetainBothOrderedEdits() {
    // Hypothesis: normalizing disjoint ranges supplied in reverse order can
    // discard one edit or render the later column before the earlier column.
    let planner = TerminalPresentationPlanner(capabilityProfile: .previewUnicode)
    let previousSurface = RasterSurface(
      size: .init(width: 10, height: 1),
      lines: ["abcdefghij"]
    )
    let currentSurface = RasterSurface(
      size: .init(width: 10, height: 1),
      lines: ["abXdefgYij"]
    )
    let damage = PresentationDamage(
      textRows: [.init(row: 0, columnRanges: [7..<8, 2..<3])]
    )

    let plan = planner.plan(
      previousSurface: previousSurface,
      currentSurface: currentSurface,
      damage: damage
    )

    #expect(plan.strategy == .incremental)
    #expect(
      plan.spanUpdates == [
        .init(row: 0, column: 2, renderedSpan: "X", cellsChanged: 1),
        .init(row: 0, column: 7, renderedSpan: "Y", cellsChanged: 1),
      ]
    )
    #expect(plan.linesTouched == 1)
    #expect(plan.cellsChanged == 2)
  }
}

// MARK: - Attempt 024: targeted graphics replay selection

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 024 text damage replays only intersecting kitty image")
  func runtimeTransport024TextDamageReplaysOnlyIntersectingKittyImage() {
    // Hypothesis: a narrow text edit can replay every unchanged kitty image,
    // or select an image from a different row band because bounds are stale.
    let planner = TerminalPresentationPlanner(
      capabilityProfile: .previewUnicode,
      graphicsCapabilities: .init(
        supportedProtocols: [.kitty],
        preferredProtocol: .kitty
      )
    )
    let topImage = RasterImageAttachment(
      identity: testIdentity("TopImage"),
      bounds: .init(
        origin: .init(x: 0, y: 0),
        size: .init(width: 2, height: 2)
      ),
      source: .path("top.png"),
      resolvedReference: .filePath("/tmp/top.png"),
      pixelSize: .init(width: 16, height: 32)
    )
    let bottomImage = RasterImageAttachment(
      identity: testIdentity("BottomImage"),
      bounds: .init(
        origin: .init(x: 5, y: 3),
        size: .init(width: 2, height: 2)
      ),
      source: .path("bottom.png"),
      resolvedReference: .filePath("/tmp/bottom.png"),
      pixelSize: .init(width: 16, height: 32)
    )
    let previousSurface = RasterSurface(
      size: .init(width: 8, height: 5),
      lines: ["aaaaaaaa", "bbbbbbbb", "cccccccc", "dddddddd", "eeeeeeee"],
      imageAttachments: [topImage, bottomImage]
    )
    let currentSurface = RasterSurface(
      size: .init(width: 8, height: 5),
      lines: ["aaaaaaaa", "bbbbbbbb", "cccccccc", "dddddddd", "eeeeXeee"],
      imageAttachments: [topImage, bottomImage]
    )

    let plan = planner.plan(
      previousSurface: previousSurface,
      currentSurface: currentSurface,
      damage: .init(
        textRows: [.init(row: 4, columnRanges: [4..<5])]
      )
    )

    #expect(plan.strategy == .incremental)
    #expect(
      plan.graphicsReplay
        == .init(scope: .targeted, attachmentsToReplay: [bottomImage])
    )
    #expect(plan.spanUpdates == [.init(row: 4, column: 4, renderedSpan: "X", cellsChanged: 1)])
    #expect(plan.cellsChanged == 1)
  }
}

// MARK: - Attempt 025: shrink-regrow baseline handoff

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 025 shrink and regrow converge without stale clears")
  func runtimeTransport025ShrinkAndRegrowConvergeWithoutStaleClears() {
    // Hypothesis: clearing a shortened row can poison the next diff baseline,
    // causing regrown text to be skipped or the old clear to repeat forever.
    let planner = TerminalPresentationPlanner(capabilityProfile: .previewUnicode)
    let original = RasterSurface(
      size: .init(width: 10, height: 1),
      lines: ["abcdefghij"]
    )
    let shrunken = RasterSurface(
      size: .init(width: 10, height: 1),
      lines: ["abc"]
    )
    let regrown = RasterSurface(
      size: .init(width: 10, height: 1),
      lines: ["abcWXYZhij"]
    )

    let shrinkPlan = planner.plan(
      previousSurface: original,
      currentSurface: shrunken
    )
    #expect(
      shrinkPlan.spanUpdates == [
        .init(row: 0, column: 3, renderedSpan: "       ", cellsChanged: 7)
      ]
    )

    let regrowPlan = planner.plan(
      previousSurface: shrunken,
      currentSurface: regrown
    )
    #expect(
      regrowPlan.spanUpdates == [
        .init(row: 0, column: 3, renderedSpan: "WXYZhij", cellsChanged: 7)
      ]
    )

    let convergedPlan = planner.plan(
      previousSurface: regrown,
      currentSurface: regrown,
      damage: .init(
        textRows: [.init(row: 0, columnRanges: [3..<10])]
      )
    )
    #expect(convergedPlan.strategy == .incremental)
    #expect(convergedPlan.rowBatches.isEmpty)
    #expect(convergedPlan.cellsChanged == 0)
  }
}

// MARK: - Attempt 022: stale damage on equal surfaces

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 022 stale damage hints emit no terminal work")
  func runtimeTransport022StaleDamageHintsEmitNoTerminalWork() {
    // Hypothesis: a retained dirty range can repaint unchanged cells forever
    // even after the committed surface has converged.
    let planner = TerminalPresentationPlanner(capabilityProfile: .previewUnicode)
    let surface = RasterSurface(
      size: .init(width: 12, height: 3),
      lines: ["alpha", "bravo", "charlie"]
    )
    let damage = PresentationDamage(
      textRows: [.init(row: 1, columnRanges: [1..<5])]
    )

    for _ in 0..<24 {
      let plan = planner.plan(
        previousSurface: surface,
        currentSurface: surface,
        damage: damage
      )
      #expect(plan.strategy == .incremental)
      #expect(plan.rowBatches.isEmpty)
      #expect(plan.linesTouched == 0)
      #expect(plan.cellsChanged == 0)
    }
  }
}

// MARK: - Attempt 021: finish with pending mouse cluster

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 021 finish flushes one coalesced mouse cluster")
  func runtimeTransport021FinishFlushesOneCoalescedMouseCluster() async throws {
    // Hypothesis: finishing while a manual mouse flush is armed can close the
    // continuation first, losing the final pointer cluster.
    let reader = InjectedTerminalInputReader(mouseFlushScheduling: .manual)
    let stream = reader.inputEvents()
    let task = Task {
      var events: [InputEvent] = []
      for await event in stream {
        events.append(event)
      }
      return events
    }
    let location = Point(x: 6, y: 4)
    for delta in 1...8 {
      reader.send(
        .mouse(
          .init(kind: .scrolled(deltaX: 0, deltaY: delta), location: location)
        )
      )
    }
    reader.finish()

    let event = try #require(await task.value.first)
    guard case .mouse(let mouse) = event,
      case .scrolled(let deltaX, let deltaY) = mouse.kind
    else {
      Issue.record("expected the pending scroll cluster at finish")
      return
    }
    #expect(deltaX == 0)
    #expect(deltaY == 36)
    #expect(mouse.location.cell == CellPoint(x: 6, y: 4))
  }
}

// MARK: - Attempt 020: direct-handler handoff

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 020 direct handler handoff partitions event ownership")
  func runtimeTransport020DirectHandlerHandoffPartitionsEventOwnership() async {
    // Hypothesis: installing and clearing the direct event path can duplicate
    // buffered events or strand the first event returned to stream delivery.
    let reader = InjectedTerminalInputReader()
    let buffered: [InputEvent] = [.key(.character("a")), .key(.character("b"))]
    reader.send(buffered)

    let directEvents = Mutex<[InputEvent]>([])
    let drained = reader.installDirectHandler { event in
      directEvents.withLock { $0.append(event) }
    }
    reader.send([.key(.character("c")), .key(.character("d"))])
    reader.clearDirectHandler()

    let task = Task {
      var events: [InputEvent] = []
      for await event in reader.inputEvents() {
        events.append(event)
      }
      return events
    }
    reader.send(.key(.character("e")))
    reader.finish()

    #expect(drained == buffered)
    #expect(directEvents.withLock { $0 } == [.key(.character("c")), .key(.character("d"))])
    #expect(await task.value == [.key(.character("e"))])
  }
}

// MARK: - Attempt 019: stream continuation replacement

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 019 latest input stream owns subsequent events")
  func runtimeTransport019LatestInputStreamOwnsSubsequentEvents() async {
    // Hypothesis: replacing a stream continuation can leave delivery attached
    // to the retained older stream or let its teardown clear the newer owner.
    let reader = InjectedTerminalInputReader()
    let staleStream = reader.inputEvents()
    let latestStream = reader.inputEvents()
    let task = Task {
      var events: [InputEvent] = []
      for await event in latestStream {
        events.append(event)
      }
      return events
    }

    reader.send([.key(.character("n")), .key(.character("e")), .key(.character("w"))])
    reader.finish()

    #expect(
      await task.value == [
        .key(.character("n")), .key(.character("e")), .key(.character("w")),
      ]
    )
    _ = staleStream
  }
}

// MARK: - Attempt 018: pre-subscription event retention

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 018 pre-subscription events retain exact order")
  func runtimeTransport018PreSubscriptionEventsRetainExactOrder() async {
    // Hypothesis: installing the first stream after mixed events arrived can
    // drain only the last kind or reorder buffered key and paste payloads.
    let reader = InjectedTerminalInputReader()
    let expected: [InputEvent] = [
      .key(.character("a")),
      .paste(.init(content: "payload")),
      .key(.character("z")),
    ]
    reader.send(expected)

    let task = Task {
      var events: [InputEvent] = []
      for await event in reader.inputEvents() {
        events.append(event)
      }
      return events
    }
    reader.finish()

    #expect(await task.value == expected)
  }
}

// MARK: - Attempt 017: false paste-end prefix

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 017 false paste end prefix survives split terminator")
  func runtimeTransport017FalsePasteEndPrefixSurvivesSplitTerminator() {
    // Hypothesis: a payload suffix resembling the end marker can be truncated
    // when the real terminator is completed by a later read.
    var parser = TerminalInputParser()
    let first = "\u{001B}[200~alpha \u{001B}[20"
    let second = "x omega\u{001B}[201~"

    #expect(parser.feed(Array(first.utf8)).isEmpty)
    #expect(
      parser.feed(Array(second.utf8)) == [
        .paste(.init(content: "alpha \u{001B}[20x omega"))
      ]
    )
  }
}

// MARK: - Attempt 016: split pixel mouse envelope

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 016 split pixel mouse envelope keeps subcell precision")
  func runtimeTransport016SplitPixelMouseEnvelopeKeepsSubcellPrecision() {
    // Hypothesis: buffering an incomplete SGR-Pixels coordinate can fall back
    // to cell precision when the final coordinate arrives in another read.
    let metrics = CellPixelMetrics(width: 8, height: 16, source: .reported)
    var parser = TerminalInputParser(
      mouseCoordinateMode: .pixels(metrics: metrics, source: .terminalPixels)
    )

    #expect(parser.feed(Array("\u{001B}[<0;17;".utf8)).isEmpty)
    #expect(
      parser.feed(Array("33M".utf8)) == [
        .mouse(
          .init(
            kind: .down(.primary),
            location: .subCell(
              location: .init(x: 2, y: 2),
              source: .terminalPixels,
              metrics: metrics,
              rawPixel: .init(x: 16, y: 32)
            )
          )
        )
      ]
    )
  }
}

// MARK: - Attempt 015: malformed CSI recovery

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 015 malformed CSI leaves following unicode scalar intact")
  func runtimeTransport015MalformedCSILeavesFollowingUnicodeScalarIntact() {
    // Hypothesis: consuming an unsupported CSI envelope can overrun its final
    // byte and discard the first multibyte scalar that follows it.
    var parser = TerminalInputParser()
    let malformed = Array("\u{001B}[999;999z".utf8)
    let unicode = Array("界".utf8)

    let events = parser.feed(malformed + unicode)
    #expect(events.last == .key(.character("界")))
    #expect(events.filter { $0 == .key(.character("界")) }.count == 1)
  }
}

// MARK: - Attempt 014: split CSI modifier envelope

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 014 split modified key envelope preserves trailing input")
  func runtimeTransport014SplitModifiedKeyEnvelopePreservesTrailingInput() {
    // Hypothesis: a CSI modifier sequence paused after its separator can consume
    // the next key when the terminal completes the envelope in a later read.
    var parser = TerminalInputParser()

    #expect(parser.feed(Array("\u{001B}[1;".utf8)).isEmpty)
    #expect(
      parser.feed(Array("5Aq".utf8)) == [
        .key(KeyPress(.arrowUp, modifiers: .ctrl)),
        .key(.character("q")),
      ]
    )
  }
}

// MARK: - Attempt 013: alternating multibyte scalars

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 013 bytewise unicode scalars preserve input order")
  func runtimeTransport013BytewiseUnicodeScalarsPreserveInputOrder() {
    // Hypothesis: completing one split UTF-8 scalar can consume the lead byte
    // of the next scalar or reorder the following ASCII key.
    var parser = TerminalInputParser()
    var events: [InputEvent] = []

    for byte in Array("é界q".utf8) {
      events.append(contentsOf: parser.feed([byte]))
    }

    #expect(
      events == [
        .key(.character("é")),
        .key(.character("界")),
        .key(.character("q")),
      ]
    )
  }
}

// MARK: - Attempt 012: terminal-looking bytes inside paste

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 012 paste payload keeps embedded terminal envelopes inert")
  func runtimeTransport012PastePayloadKeepsEmbeddedTerminalEnvelopesInert() {
    // Hypothesis: once bracketed paste starts, an embedded mouse or key CSI
    // envelope can escape paste mode and dispatch as live terminal input.
    var parser = TerminalInputParser()
    let content = "before\u{001B}[<0;5;7M\u{001B}[1;5Aafter"
    let events = parser.feed(
      Array("\u{001B}[200~\(content)\u{001B}[201~".utf8)
    )

    #expect(events == [.paste(.init(content: content))])
  }
}

// MARK: - Attempt 011: bytewise bracketed paste framing

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 011 bytewise bracketed paste emits one payload")
  func runtimeTransport011BytewiseBracketedPasteEmitsOnePayload() {
    // Hypothesis: a start or end marker fragmented at every byte boundary can
    // leak escape bytes as keys or split one paste into multiple events.
    var parser = TerminalInputParser()
    let bytes = Array("\u{001B}[200~alpha beta\u{001B}[201~".utf8)
    var events: [InputEvent] = []

    for byte in bytes {
      events.append(contentsOf: parser.feed([byte]))
    }

    withKnownIssue("A bytewise bracketed-paste envelope leaks its framing as key events") {
      #expect(events == [.paste(.init(content: "alpha beta"))])
    }
  }
}

// MARK: - Attempt 010: event-pump drain and regrow

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 010 repeated empty drains preserve later batches")
  func runtimeTransport010RepeatedEmptyDrainsPreserveLaterBatches() throws {
    // Hypothesis: removing the final batch and then draining empty can leave the
    // buffer in a state where the next pointer cluster is lost or mis-merged.
    let buffer = EventPumpBuffer()

    for generation in 0..<32 {
      #expect(buffer.drain().isEmpty)
      #expect(!buffer.hasPendingEvents())
      #expect(
        buffer.enqueue(
          .input(
            .mouse(
              .init(kind: .moved, location: .init(x: Double(generation), y: 2))
            )
          )
        )
      )
      let event = try #require(buffer.drain().first)
      guard case .input(.mouse(let mouse)) = event else {
        Issue.record("expected a pointer event after empty drain generation \(generation)")
        return
      }
      #expect(mouse.location.cell == CellPoint(x: generation, y: 2))
      #expect(!buffer.hasPendingEvents())
    }
  }
}

// MARK: - Attempt 009: signal boundary inside pointer traffic

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 009 signal keeps pointer batches on both sides")
  func runtimeTransport009SignalKeepsPointerBatchesOnBothSides() throws {
    // Hypothesis: a signal inserted during a pointer burst can be appended to
    // the pointer batch or allow motion on both sides to coalesce together.
    let buffer = EventPumpBuffer()
    _ = buffer.enqueue(.input(.mouse(.init(kind: .moved, location: .init(x: 1, y: 1)))))
    _ = buffer.enqueue(.input(.mouse(.init(kind: .moved, location: .init(x: 2, y: 1)))))
    _ = buffer.enqueue(.signal("SIGWINCH"))
    _ = buffer.enqueue(.input(.mouse(.init(kind: .moved, location: .init(x: 8, y: 1)))))
    _ = buffer.enqueue(.input(.mouse(.init(kind: .moved, location: .init(x: 9, y: 1)))))

    let before = try #require(buffer.drain().first)
    let signal = try #require(buffer.drain().first)
    let after = try #require(buffer.drain().first)

    guard case .input(.mouse(let beforeMouse)) = before,
      case .signal(let name) = signal,
      case .input(.mouse(let afterMouse)) = after
    else {
      Issue.record("expected pointer, signal, pointer batch ordering")
      return
    }
    #expect(beforeMouse.location.cell == CellPoint(x: 2, y: 1))
    #expect(name == "SIGWINCH")
    #expect(afterMouse.location.cell == CellPoint(x: 9, y: 1))
    #expect(buffer.drain().isEmpty)
  }
}

// MARK: - Attempt 008: event-pump wake ownership

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 008 event pump wakes once per pending batch")
  func runtimeTransport008EventPumpWakesOncePerPendingBatch() throws {
    // Hypothesis: an in-place pointer merge can report a new batch wake, or a
    // later key batch can fail to wake because the pointer batch already did.
    let buffer = EventPumpBuffer()

    #expect(
      buffer.enqueue(
        .input(.mouse(.init(kind: .moved, location: .init(x: 1, y: 1))))
      )
    )
    #expect(
      !buffer.enqueue(
        .input(.mouse(.init(kind: .moved, location: .init(x: 5, y: 1))))
      )
    )
    #expect(buffer.enqueue(.input(.key(.character("q")))))

    let firstBatch = buffer.drain()
    let firstEvent = try #require(firstBatch.first)
    guard case .input(.mouse(let mouse)) = firstEvent else {
      Issue.record("expected a merged pointer event")
      return
    }
    #expect(firstBatch.count == 1)
    #expect(mouse.location.cell == CellPoint(x: 5, y: 1))

    let secondBatch = buffer.drain()
    guard case .input(.key(let key))? = secondBatch.first else {
      Issue.record("expected a key in the second batch")
      return
    }
    #expect(secondBatch.count == 1)
    #expect(key == KeyPress(.character("q")))
    #expect(!buffer.hasPendingEvents())
  }
}

// MARK: - Attempt 007: click boundary inside motion traffic

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 007 click edges prevent motion merging across activation")
  func runtimeTransport007ClickEdgesPreventMotionMergingAcrossActivation() {
    // Hypothesis: noncoalescible down/up events can flush without resetting the
    // pending move, letting the post-click position replace the pre-click one.
    let events = coalescedInputEvents([
      .mouse(.init(kind: .moved, location: .init(x: 1, y: 0))),
      .mouse(.init(kind: .moved, location: .init(x: 2, y: 0))),
      .mouse(.init(kind: .down(.primary), location: .init(x: 2, y: 0))),
      .mouse(.init(kind: .up(.primary), location: .init(x: 2, y: 0))),
      .mouse(.init(kind: .moved, location: .init(x: 9, y: 0))),
      .mouse(.init(kind: .moved, location: .init(x: 10, y: 0))),
    ])

    #expect(
      events == [
        .mouse(.init(kind: .moved, location: .init(x: 2, y: 0))),
        .mouse(.init(kind: .down(.primary), location: .init(x: 2, y: 0))),
        .mouse(.init(kind: .up(.primary), location: .init(x: 2, y: 0))),
        .mouse(.init(kind: .moved, location: .init(x: 10, y: 0))),
      ]
    )
  }
}

// MARK: - Attempt 006: drop boundary inside hover traffic

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 006 drop keeps surrounding hover runs ordered")
  func runtimeTransport006DropKeepsSurroundingHoverRunsOrdered() {
    // Hypothesis: a file drop can be appended into a coalescible hover batch,
    // causing pre-drop motion to be replaced by post-drop motion.
    let drop: InputEvent = .drop(
      paths: ["/tmp/one", "/tmp/two"],
      context: .init(location: .init(x: 3, y: 3), modifiers: .alt)
    )
    let events = coalescedInputEvents([
      .mouse(.init(kind: .moved, location: .init(x: 1, y: 1))),
      .mouse(.init(kind: .moved, location: .init(x: 2, y: 1))),
      drop,
      .mouse(.init(kind: .moved, location: .init(x: 7, y: 1))),
      .mouse(.init(kind: .moved, location: .init(x: 8, y: 1))),
    ])

    #expect(
      events == [
        .mouse(.init(kind: .moved, location: .init(x: 2, y: 1))),
        drop,
        .mouse(.init(kind: .moved, location: .init(x: 8, y: 1))),
      ]
    )
  }
}

// MARK: - Attempt 005: paste boundary inside pointer traffic

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 005 paste keeps surrounding scroll bursts ordered")
  func runtimeTransport005PasteKeepsSurroundingScrollBurstsOrdered() {
    // Hypothesis: paste delivery can flush only one side of a coalesced pointer
    // burst, allowing scroll deltas to cross the non-pointer event.
    let location = Point(x: 5, y: 4)
    let events = coalescedInputEvents([
      .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 1), location: location)),
      .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 2), location: location)),
      .paste(.init(content: "payload")),
      .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 4), location: location)),
      .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 8), location: location)),
    ])

    #expect(
      events == [
        .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 3), location: location)),
        .paste(.init(content: "payload")),
        .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 12), location: location)),
      ]
    )
  }
}

// MARK: - Attempt 004: dragged-button transition

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 004 drag button changes preserve separate runs")
  func runtimeTransport004DragButtonChangesPreserveSeparateRuns() {
    // Hypothesis: high-rate drag compression can merge primary and secondary
    // button ownership and deliver the later route to the earlier recognizer.
    let events = coalescedInputEvents([
      .mouse(.init(kind: .dragged(.primary), location: .init(x: 1, y: 2))),
      .mouse(.init(kind: .dragged(.primary), location: .init(x: 3, y: 2))),
      .mouse(.init(kind: .dragged(.secondary), location: .init(x: 4, y: 2))),
      .mouse(.init(kind: .dragged(.secondary), location: .init(x: 6, y: 2))),
    ])

    #expect(
      events == [
        .mouse(.init(kind: .dragged(.primary), location: .init(x: 3, y: 2))),
        .mouse(.init(kind: .dragged(.secondary), location: .init(x: 6, y: 2))),
      ]
    )
  }
}

// MARK: - Attempt 003: pointer modifier boundary

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 003 pointer modifier changes split coalesced runs")
  func runtimeTransport003PointerModifierChangesSplitCoalescedRuns() {
    // Hypothesis: moved events can merge across a modifier transition and erase
    // the last unmodified location or the first modified event.
    let events = coalescedInputEvents([
      .mouse(.init(kind: .moved, location: .init(x: 1, y: 1))),
      .mouse(.init(kind: .moved, location: .init(x: 2, y: 1))),
      .mouse(.init(kind: .moved, location: .init(x: 3, y: 1), modifiers: .shift)),
      .mouse(.init(kind: .moved, location: .init(x: 4, y: 1), modifiers: .shift)),
    ])

    #expect(
      events == [
        .mouse(.init(kind: .moved, location: .init(x: 2, y: 1))),
        .mouse(.init(kind: .moved, location: .init(x: 4, y: 1), modifiers: .shift)),
      ]
    )
  }
}

// MARK: - Attempt 002: zero-sum scroll coalescing

extension FrameworkStressRuntimeTransportTests {
  @Test("stress runtime transport 002 opposing scroll deltas retain one ordered event")
  func runtimeTransport002OpposingScrollDeltasRetainOneOrderedEvent() {
    // Hypothesis: opposite deltas at one cell can cancel by dropping the event
    // entirely, allowing later batches to cross what should remain a boundary.
    let location = Point(x: 4, y: 2)
    let events = coalescedInputEvents([
      .mouse(.init(kind: .scrolled(deltaX: 3, deltaY: -4), location: location)),
      .mouse(.init(kind: .scrolled(deltaX: -3, deltaY: 4), location: location)),
    ])

    #expect(
      events == [
        .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 0), location: location))
      ]
    )
  }
}
