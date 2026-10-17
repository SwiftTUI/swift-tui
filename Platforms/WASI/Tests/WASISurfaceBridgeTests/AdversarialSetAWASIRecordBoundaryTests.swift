@_spi(Runners) import SwiftTUIRuntime
import Testing

@testable import SwiftTUIWASISurfaceBridge

@Suite(.serialized, .timeLimit(.minutes(1)))
struct AdversarialSetAWASIRecordBoundaryTests {
  @Test func setA951RawEscapeCannotMoveAcrossAControlRecordBarrier() {
    // Hypothesis: the control-record parser leaves a pending terminal Escape buffered until after a resize command.
    var parser = WebSurfaceInputParser()
    let records = parser.feedRecords(Array("\u{1B}\u{1E}resize:11:7\nx".utf8))
    #expect(
      records == [
        .input(.key(.init(.escape))),
        .control(.resize(.init(width: 11, height: 7), cellPixelSize: nil)),
        .input(.key(.init(.character("x")))),
      ])
    #expect(parser.bufferedCommandBytes.isEmpty)
  }

  @Test func setA952AFragmentedControlRecordDecodesItsMultibytePayloadExactlyOnce() {
    // Hypothesis: chunk boundaries within percent escapes are decoded eagerly or leak partial control bytes into terminal input.
    let bytes = Array("\u{1E}paste:%E6%BC%A2%F0%9F%91%A9%E2%80%8D%F0%9F%92%BB\n".utf8)
    for split in 1..<bytes.count {
      var parser = WebSurfaceInputParser()
      let partial = parser.feedRecords(Array(bytes[..<split]))
      #expect(partial.isEmpty)
      let completed = parser.feedRecords(Array(bytes[split...]))
      #expect(completed == [.input(.paste(.init(content: "漢👩‍💻")))])
      let empty = parser.feedRecords([])
      #expect(empty.isEmpty)
      #expect(parser.bufferedCommandBytes.isEmpty)
    }
  }

  @Test func setA953RejectedGeometryDoesNotConsumeItsRevisionNumber() throws {
    // Hypothesis: parsing an invalid newer geometry advances the revision latch before validating its dimensions.
    var parser = WebSurfaceInputParser(session: 953)
    let rejected = parser.feedRecords(command("geometry:8:0:24:9:18"))
    #expect(rejected.isEmpty)
    let accepted = parser.feedRecords(command("geometry:8:80:24:9:18"))
    try #require(accepted.count == 1)
    guard case .control(.geometry(let geometry)) = accepted[0] else {
      Issue.record("Valid geometry with the rejected revision was not accepted")
      return
    }
    #expect(geometry.revision == 8)
    #expect(geometry.size == .init(width: 80, height: 24))
  }

  @Test func setA954AStaleGeometryCannotReplaceTheCurrentPointerMetrics() throws {
    // Hypothesis: an old geometry is suppressed as a control message but still overwrites the parser's subcell metric cache.
    var parser = WebSurfaceInputParser(session: 954)
    _ = parser.feedRecords(Array("\u{1E}caps:{\"geometryRevisions\":true}\n".utf8))
    _ = parser.feedRecords(command("geometry:9:80:24:10:20"))
    let stale = parser.feedRecords(command("geometry:8:80:24:30:40"))
    #expect(stale.isEmpty)
    let mouse = try mouse(parser.feedRecords(command("mouseGeometry:9:down:1.5:2.5:primary:0:0:0")))
    #expect(mouse.location.rawPixel == .init(x: 15, y: 50))
    #expect(mouse.hostGeometryStamp == .init(session: 954, revision: 9))
  }

  @Test func setA955AcceptedGeometryPreventsLegacyResizeFromReplacingMetrics() throws {
    // Hypothesis: a legacy resize arriving after geometry negotiation changes the coordinate system of stamped input.
    var parser = WebSurfaceInputParser(session: 955)
    _ = parser.feedRecords(Array("\u{1E}caps:{\"geometryRevisions\":true}\n".utf8))
    _ = parser.feedRecords(command("geometry:3:80:24:10:20"))
    let legacy = parser.feedRecords(command("resize:40:12:30:40"))
    #expect(
      legacy == [
        .control(.resize(.init(width: 40, height: 12), cellPixelSize: .init(width: 30, height: 40)))
      ])
    let mouse = try mouse(parser.feedRecords(command("mouseGeometry:3:down:1.5:2.5:primary:0:0:0")))
    #expect(mouse.location.rawPixel == .init(x: 15, y: 50))
  }

  @Test func setA956LegacyResizeWithoutMetricsReturnsPointerPrecisionToEstimated() throws {
    // Hypothesis: the optional metrics of a legacy resize are merged with the old declaration instead of replacing it.
    var parser = WebSurfaceInputParser()
    _ = parser.feedRecords(command("resize:80:24:10:20"))
    let before = try mouse(parser.feedRecords(command("mouse:moved:1.5:2.5:none:0:0:0")))
    #expect(before.location.rawPixel == .init(x: 15, y: 50))
    _ = parser.feedRecords(command("resize:80:24"))
    let after = try mouse(parser.feedRecords(command("mouse:moved:1.5:2.5:none:0:0:0")))
    #expect(after.location.rawPixel == nil)
    #expect(after.location.precision == .subCell(source: .webPixels, metrics: .estimated))
    #expect(after.location.location == before.location.location)
  }

  @Test func setA957OversizedCommandDiscardEndsAtItsFirstNewline() {
    // Hypothesis: overflow recovery restarts at an embedded record separator or keeps discarding the next valid input record.
    var parser = WebSurfaceInputParser()
    _ = parser.feedRecords([0x1E])
    let oversized = parser.feedRecords([UInt8](repeating: 120, count: HostWireBudget.recordBytes))
    #expect(oversized.isEmpty)
    #expect(parser.bufferedCommandBytes.isEmpty)
    let recovered = parser.feedRecords(Array("\u{1E}key:return:0\nq\u{1E}key:tab:0\n".utf8))
    #expect(recovered == [.input(.key(.init(.character("q")))), .input(.key(.init(.tab)))])
  }

  @Test func setA958EscapedRecordSeparatorsAndNewlinesRemainPasteData() {
    // Hypothesis: percent-decoded paste text is fed back through control framing and injects a resize instead of one paste event.
    var parser = WebSurfaceInputParser()
    let records = parser.feedRecords(command("paste:before%1Eresize%3A1%3A1%0Aafter%00end"))
    #expect(records == [.input(.paste(.init(content: "before\u{1E}resize:1:1\nafter\0end")))])
    #expect(parser.bufferedCommandBytes.isEmpty)
  }

  @Test func setA959MalformedPercentEscapeDropsOnlyItsOwnRecord() {
    // Hypothesis: rejecting a malformed escape leaves decoding or framing state that consumes the next command.
    var parser = WebSurfaceInputParser()
    let records = parser.feedRecords(command("paste:bad%Q0") + command("paste:good%25value"))
    #expect(records == [.input(.paste(.init(content: "good%value")))])
    #expect(parser.bufferedCommandBytes.isEmpty)
  }

  @Test func setA960CharacterRecordsPreserveAnExtendedGrapheme() {
    // Hypothesis: a decoded key record is truncated to one Unicode scalar instead of one Swift Character.
    var parser = WebSurfaceInputParser()
    let records = parser.feedRecords(command("key:character:%F0%9F%91%A9%E2%80%8D%F0%9F%92%BB:0"))
    #expect(records == [.input(.key(.init(.character("👩‍💻"))))])
  }

  @Test func setA961FunctionKeyRecordsKeepTheirModifierBitset() {
    // Hypothesis: the named-function-key fallback loses modifiers or accepts out-of-range names as ordinary characters.
    var parser = WebSurfaceInputParser()
    let records = parser.feedRecords(
      command("key:f24:7") + command("key:f25:0") + command("key:f1:0"))
    #expect(
      records == [
        .input(.key(.init(.functionKey(24), modifiers: [.shift, .alt, .ctrl]))),
        .input(.key(.init(.functionKey(1)))),
      ])
  }

  @Test func setA962ViewportPointerStampsKeepBothRevisionAxesAndTheSession() throws {
    // Hypothesis: the shared-viewport record shifts positional fields and conflates canvas revision zero with the viewport revision.
    var parser = WebSurfaceInputParser(session: 962)
    let mouse = try mouse(
      parser.feedRecords(command("mouseViewport:0:17:dragged:2.25:3.5:secondary:0:0:3")))
    #expect(mouse.kind == .dragged(.secondary))
    #expect(mouse.location.location == .init(x: 2.25, y: 3.5))
    #expect(mouse.modifiers == .init(rawValue: 3))
    #expect(mouse.hostGeometryStamp == .init(session: 962, revision: 0, viewportRevision: 17))
  }

  private func command(_ value: String) -> [UInt8] { Array("\u{1E}\(value)\n".utf8) }

  private func mouse(_ records: [WebSurfaceInputRecord]) throws -> MouseEvent {
    try #require(records.count == 1)
    guard case .input(.mouse(let event)) = records[0] else {
      throw WASIRecordBoundaryError.expectedMouse
    }
    return event
  }
}

private enum WASIRecordBoundaryError: Error { case expectedMouse }
