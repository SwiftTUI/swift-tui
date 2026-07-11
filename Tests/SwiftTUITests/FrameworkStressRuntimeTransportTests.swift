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
        .mouse(first), .mouse(second), .mouse(third)
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
