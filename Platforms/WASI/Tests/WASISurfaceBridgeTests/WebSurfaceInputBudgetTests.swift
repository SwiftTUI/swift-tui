@_spi(Runners) import SwiftTUIRuntime
import Testing

@testable import SwiftTUIWASISurfaceBridge

@Suite struct WebSurfaceInputBudgetTests {
  @Test func paragraphGeometryExtensionAcceptsOldRecordsAndClearsSpacing() throws {
    var parser = WebSurfaceInputParser()
    for (command, spacing) in [
      ("geometry:1:80:24:9:21", 0),
      ("geometry:2:80:24:9:21:2", 2), ("geometry:3:80:24:9:21:0", 0),
    ] {
      let records = parser.feedRecords(Array("\u{1E}\(command)\n".utf8))
      #expect(records.count == 1)
      guard case .control(.geometry(let request)) = records.first else {
        Issue.record("Missing paragraph geometry")
        return
      }
      #expect(request.paragraphSpacing == spacing)
    }
    for suffix in ["-1", "0.5", "8193", "2:3", ""] {
      #expect(parser.feedRecords(Array("\u{1E}geometry:4:80:24:9:21:\(suffix)\n".utf8)).isEmpty)
    }
  }

  @Test func cancellationPreservesItsPositionAndGeometryStamp() throws {
    var parser = WebSurfaceInputParser(session: 31)
    let result = parser.feed(
      Array(
        ("\u{1E}mouseGeometry:8:dragged:2.5:3:primary:0:0:0\n"
          + "\u{1E}mouseGeometry:8:cancelled:2.5:3:none:0:0:0\n"
          + "\u{1E}mouseGeometry:8:up:2.5:3:primary:0:0:0\n").utf8))
    #expect(result.events.count == 3)
    guard case .mouse(let event) = result.events[1] else {
      Issue.record("Cancellation lost its place in the pointer stream")
      return
    }
    #expect(event.kind == .cancelled)
    #expect(event.hostGeometryStamp == .init(session: 31, revision: 8))
  }

  @Test func geometryRecordsPreserveOrderRevisionAndValidatedMetrics() throws {
    var parser = WebSurfaceInputParser(session: 31)
    _ = parser.feedRecords(Array("\u{1E}caps:{\"geometryRevisions\":true}\n".utf8))
    let records = parser.feedRecords(
      Array(
        ("\u{1E}geometry:9007199254740991:80:24:9:21\n"
          + "\u{1E}mouseGeometry:9007199254740991:down:1.25:2.5:primary:0:0:0\n"
          + "\u{1E}geometry:2:40:10:100:100\n"
          + "\u{1E}resize:10:10:200:200\n"
          + "\u{1E}mouseGeometry:9007199254740991:up:1.25:2.5:primary:0:0:0\n").utf8))
    #expect(records.count == 4)
    guard case .control(.geometry(let request)) = records[0],
      case .input(.mouse(let down)) = records[1],
      case .input(.mouse(let up)) = records[3]
    else {
      Issue.record("record order changed")
      return
    }
    #expect(request.revision == HostGeometryRequest.maximumRevision)
    #expect(down.hostGeometryStamp == .init(session: 31, revision: request.revision))
    #expect(up.hostGeometryStamp == down.hostGeometryStamp)
    #expect(up.location == down.location)
    #expect(down.location.location == Point(x: 1.25, y: 2.5))
  }

  @Test func malformedGeometryAndNonfinitePointerRecordsAreRefused() {
    var parser = WebSurfaceInputParser()
    for command in [
      "geometry:0:80:24:9:21", "geometry:9007199254740992:80:24:9:21",
      "geometry:1:1025:24:9:21", "geometry:1:80:24:8193:21",
      "geometry:1:80:24:9.5:21", "geometry:1:0:24:9:21",
      "mouseGeometry:0:down:1:1:primary:0:0:0",
      "mouseGeometry:1:down:nan:1:primary:0:0:0",
      "mouseGeometry:1:down:1:inf:primary:0:0:0",
    ] {
      #expect(parser.feedRecords(Array("\u{1E}\(command)\n".utf8)).isEmpty)
    }
  }

  @Test func unterminatedInputIsDiscardedThroughNewlineAndRecovers() {
    var parser = WebSurfaceInputParser()
    _ = parser.feed([0x1E])
    let chunk = [UInt8](repeating: 120, count: 8192)
    for _ in 0..<1024 {
      let result = parser.feed(chunk)
      #expect(result.events.isEmpty && result.controlMessages.isEmpty)
      #expect(parser.bufferedCommandBytes.count < HostWireBudget.recordBytes)
    }
    let result = parser.feed(Array("\u{1E}resize:100:20\n\u{1E}resize:80:24\n".utf8))
    #expect(result.controlMessages.count == 1)
    #expect(result.events.isEmpty)
    #expect(parser.bufferedCommandBytes.isEmpty)
  }

  @Test func oversizedResizeNeverReachesRasterAllocation() {
    var parser = WebSurfaceInputParser()
    for command in ["resize:1025:1", "resize:257:256", "resize:9223372036854775807:2"] {
      #expect(parser.feed(Array("\u{1E}\(command)\n".utf8)).controlMessages.isEmpty)
    }
    #expect(parser.feed(Array("\u{1E}resize:256:256\n".utf8)).controlMessages.count == 1)
  }
}

extension WebSurfaceInputBudgetTests {
  @Test func sharedViewportPointersPreserveBothRevisionsIncludingCanvasZero() {
    for revision in [0, 9] {
      var parser = WebSurfaceInputParser(session: 7)
      let parsed = parser.feed(
        Array("\u{001E}mouseViewport:\(revision):4:down:1.5:2:primary:0:0:0\n".utf8))
      guard case .mouse(let event) = parsed.events.first else {
        Issue.record("Expected a shared viewport pointer")
        continue
      }
      #expect(
        event.hostGeometryStamp
          == .init(session: 7, revision: UInt64(revision), viewportRevision: 4))
    }
    for revision in ["0", "-1", "1.5", "9007199254740992"] {
      var parser = WebSurfaceInputParser(session: 7)
      #expect(
        parser.feed(Array("\u{001E}mouseViewport:0:\(revision):down:1:2:primary:0:0:0\n".utf8))
          .events.isEmpty)
    }
  }
}

// MARK: - Pointer number grammar and bounds (STUI-823, STUI-863, STUI-1229)

extension WebSurfaceInputBudgetTests {
  private func pointerEvent(_ command: String) -> MouseEvent? {
    var parser = WebSurfaceInputParser()
    guard case .mouse(let event)? = parser.feed(Array("\u{1E}\(command)\n".utf8)).events.first
    else { return nil }
    return event
  }

  private func scrollDeltas(_ command: String) -> [Int]? {
    guard case .scrolled(let deltaX, let deltaY)? = pointerEvent(command)?.kind else { return nil }
    return [deltaX, deltaY]
  }

  @Test func pointerCoordinatesUseTheDecimalWireGrammar() {
    // Every spelling JavaScript's String(number) produces, plus the decimal
    // forms the parser has always accepted.
    let accepted: [(String, Double)] = [
      ("1.25", 1.25), ("-0.25", -0.25), ("3", 3), ("1e-7", 1e-7), ("1.5e+3", 1_500),
      ("2E2", 200), ("+1.5", 1.5), ("5.", 5), (".5", 0.5), ("-0", 0),
    ]
    for (spelling, value) in accepted {
      #expect(
        pointerEvent("mouse:moved:\(spelling):2:none:0:0:0")?.location.location
          == Point(x: value, y: 2), "\(spelling)")
    }
    let refused = [
      "0x1p3", "0x10", "0X1P3", "inf", "-infinity", "nan", "NaN", "1_0", " 1", "1 ", "",
      "+", ".", "e5", "1e", "1e+", "1.2.3", "\u{FF11}",
    ]
    for spelling in refused {
      #expect(pointerEvent("mouse:moved:\(spelling):2:none:0:0:0") == nil, "x \(spelling)")
      #expect(pointerEvent("mouse:moved:2:\(spelling):none:0:0:0") == nil, "y \(spelling)")
    }
    #expect(pointerEvent("mouseGeometry:2:moved:0x1p3:1:none:0:0:0") == nil)
    #expect(pointerEvent("mouseViewport:0:4:moved:1:0x1p3:none:0:0:0") == nil)
  }

  @Test func pointerCoordinatesAndDeltasOutsideTheWireBoundAreRefused() {
    #expect(
      pointerEvent("mouse:moved:16777216:-16777216:none:0:0:0")?.location.location
        == Point(x: 16_777_216, y: -16_777_216))
    for spelling in ["16777216.5", "-16777217", "3000000000", "3e9"] {
      #expect(pointerEvent("mouse:moved:\(spelling):0:none:0:0:0") == nil, "x \(spelling)")
      #expect(pointerEvent("mouse:moved:0:\(spelling):none:0:0:0") == nil, "y \(spelling)")
    }
    #expect(
      scrollDeltas("mouse:scrolled:1:1:none:-16777216:16777216:0") == [-16_777_216, 16_777_216])
    #expect(scrollDeltas("mouse:scrolled:1:1:none:+3:-1:0") == [3, -1])
    for delta in [
      "16777217", "-16777217", "9223372036854775807", "-9223372036854775808", "0x10", "1.0",
    ] {
      #expect(scrollDeltas("mouse:scrolled:1:1:none:\(delta):0:0") == nil, "dx \(delta)")
      #expect(scrollDeltas("mouse:scrolled:1:1:none:0:\(delta):0") == nil, "dy \(delta)")
    }
    #expect(pointerEvent("mouseViewport:0:4:scrolled:1:2:none:0:16777217:0") == nil)
  }

  @Test func coordinatesBeyondIntRangeAreRefusedWithoutTrapping() async {
    await #expect(processExitsWith: .success) {
      for spelling in ["1e300", "-1e300", "1.7976931348623157e308", "9223372036854775808"] {
        var parser = WebSurfaceInputParser()
        let x = parser.feed(Array("\u{1E}mouse:down:\(spelling):0:primary:0:0:0\n".utf8))
        let y = parser.feed(Array("\u{1E}mouse:up:0:\(spelling):primary:0:0:0\n".utf8))
        #expect(x.events.isEmpty && y.events.isEmpty, "\(spelling)")
      }
    }
  }
}
