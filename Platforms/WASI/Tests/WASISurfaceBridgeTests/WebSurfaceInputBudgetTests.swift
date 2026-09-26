@_spi(Runners) import SwiftTUIRuntime
import Testing

@testable import SwiftTUIWASISurfaceBridge

@Suite struct WebSurfaceInputBudgetTests {
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
