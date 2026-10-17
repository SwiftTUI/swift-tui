// Adversarial set B, pass 4: the WASI surface bridge (341–350).
//
// The bridge frames the web-surface wire: RS-introduced, newline-terminated
// control records mixed with raw terminal bytes on the way in, and the shared
// JSON surface records on the way out. The host wire contract fixes the
// framing grammar, the admission budgets, the capability dependencies and the
// delta baseline rules. These probes feed the encoder a surface shorter than
// its declared height and a non-finite style opacity, feed the parser negative
// resize fields, a control record whose newline never arrived, invalid UTF-8
// in percent-encoded text and an un-negotiated geometry record, split an
// escape sequence across a pull read, and pin the pull byte budget, an empty
// clipboard record and a partial capability declaration.
//
// Excluded from Windows builds like the sibling suites: the pull and clipboard
// probes drive the reader and transport through pipe file descriptors.
#if !os(Windows)

  import Foundation
  @_spi(Runners) import SwiftTUI
  @_spi(Runners) import SwiftTUIRuntime
  import Testing

  @testable import SwiftTUIWASISurfaceBridge

  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #elseif canImport(Musl)
    import Musl
  #endif

  @MainActor
  @Suite("Adversarial set B: WASI bridge", .serialized)
  struct AdversarialSetBWASIBridgeTests {
    // A delta for a surface whose cell rows stop short of its declared height
    // does not trap on the missing row: admission allows cells.count <= height,
    // so the encoder has to tolerate the shape it admitted.
    @Test func setB341DeltaOnASurfaceShorterThanItsHeightDoesNotTrap() async throws {
      let full = try SetBDecoded.surface(WebSurfaceFrameEncoder.encode(SetBSurfaces.short()))
      #expect(full["height"] as? Int == 3, "\(full)")
      #expect((full["rows"] as? [Any])?.count == 2, "\(full)")
      await withKnownIssue(
        "encodeDelta indexes surface.cells by a damage row that validate bounded only by height"
      ) {
        await #expect(processExitsWith: .success) {
          var state = HostWireCapabilities(acceptsDeltaFrames: true)
            .negotiatedEncodingState(epochID: 1)
          let short = RasterSurface(
            size: CellSize(width: 2, height: 3),
            cells: [
              [RasterCell(character: "a"), RasterCell(character: "b")],
              [RasterCell(character: "c"), RasterCell(character: "d")],
            ])
          _ = WebSurfaceFrameEncoder.encode(short, damage: nil, state: &state)
          _ = WebSurfaceFrameEncoder.encode(
            short, damage: PresentationDamage(dirtyRows: [2]), state: &state)
        }
      }
    }

    // A style whose opacity is not finite never reaches the wire as an invalid
    // JSON number: the record parses, or the frame is refused outright.
    @Test func setB342NonFiniteStyleOpacityNeverShipsAsInvalidJSON() throws {
      let encoded = WebSurfaceFrameEncoder.encode(SetBSurfaces.styled(opacity: -.infinity))
      let parsed = try? JSONSerialization.jsonObject(
        with: Data(SetBDecoded.payload(encoded).utf8))
      withKnownIssue("HostWireStyleTable interpolates style.opacity verbatim, so -inf is emitted") {
        #expect(
          parsed != nil || encoded == HostWireBudget.rejectionRecord, "\(encoded.prefix(160))")
      }
      let unset = try SetBDecoded.surface(
        WebSurfaceFrameEncoder.encode(SetBSurfaces.styled(opacity: .nan)))
      #expect((unset["styles"] as? [Any])?.count == 2, "\(unset)")
      let finite = try SetBDecoded.surface(
        WebSurfaceFrameEncoder.encode(SetBSurfaces.styled(opacity: 0.5)))
      let styles = try #require(finite["styles"] as? [Any])
      #expect((styles.last as? [String: Any])?["opacity"] as? Double == 0.5, "\(styles)")
    }

    // A resize whose dimensions or cell pitch fall outside the admitted range
    // is refused like a geometry record, not clamped up to one.
    @Test func setB343OutOfRangeResizeFieldsAreRefusedNotClamped() {
      var parser = WebSurfaceInputParser()
      #expect(
        parser.feed(Array("\u{1E}resize:80:24\n".utf8)).controlMessages == [
          .resize(.init(width: 80, height: 24), cellPixelSize: nil)
        ])
      #expect(parser.feed(Array("\u{1E}resize:1025:24\n".utf8)).controlMessages.isEmpty)
      #expect(parser.feed(Array("\u{1E}geometry:1:-5:24:9:21\n".utf8)).controlMessages.isEmpty)
      let negativeWidth = parser.feed(Array("\u{1E}resize:-5:24\n".utf8)).controlMessages
      let negativeHeight = parser.feed(Array("\u{1E}resize:80:-1\n".utf8)).controlMessages
      let negativePitch = parser.feed(Array("\u{1E}resize:80:24:-9:-21\n".utf8)).controlMessages
      withKnownIssue("parseResizeCommand applies max(1, value) before the budget check") {
        #expect(negativeWidth.isEmpty, "\(negativeWidth)")
        #expect(negativeHeight.isEmpty, "\(negativeHeight)")
        #expect(
          negativePitch.isEmpty
            || negativePitch == [.resize(.init(width: 80, height: 24), cellPixelSize: nil)],
          "\(negativePitch)")
      }
    }

    // A record separator inside a control record whose newline never arrived
    // starts a new record: the orphaned fragment is dropped, the next record
    // is honoured, and its bytes never surface as pasted text.
    @Test func setB344AnIntroducerInsideAnUnterminatedRecordResyncsFraming() {
      var parser = WebSurfaceInputParser()
      let events = parser.feed(Array("\u{1E}paste:hello\u{1E}key:return:0\n".utf8)).events
      let pastes = SetBWire.pasteContents(events)
      let controls = parser.feed(
        Array("\u{1E}resize:80\u{1E}resize:100:30\n".utf8)
      ).controlMessages
      withKnownIssue("the buffered command absorbs the second introducer and parses as one") {
        #expect(events.contains(.key(.init(.return))), "\(events)")
        #expect(!pastes.contains { $0.contains("\u{1E}") }, "\(pastes)")
        #expect(
          controls == [.resize(.init(width: 100, height: 30), cellPixelSize: nil)], "\(controls)")
      }
      #expect(parser.feed(Array("\u{1E}key:return:0\n".utf8)).events == [.key(.init(.return))])
    }

    // Percent-encoded text that is not valid UTF-8 is refused on the key and
    // paste records exactly as the accessibility record refuses it.
    @Test func setB345InvalidUTF8InPercentEncodedTextIsRefusedOnEveryRecord() {
      var parser = WebSurfaceInputParser()
      #expect(parser.feed(Array("\u{1E}accessibility:t:setValue:text:%FF\n".utf8)).events.isEmpty)
      #expect(
        parser.feed(Array("\u{1E}paste:caf%C3%A9\n".utf8)).events == [
          .paste(.init(content: "café"))
        ])
      let paste = parser.feed(Array("\u{1E}paste:%FF\n".utf8)).events
      let key = parser.feed(Array("\u{1E}key:character:%C3:0\n".utf8)).events
      withKnownIssue("the parser's percent decoder uses String(decoding:) and substitutes U+FFFD") {
        #expect(paste.isEmpty, "\(paste)")
        #expect(key.isEmpty, "\(key)")
      }
    }

    // A geometry record on a transport that never negotiated geometry
    // revisions is ignored consistently: the parser's pointer metrics keep
    // following the legacy resize path the transport still applies.
    @Test func setB346UnnegotiatedGeometryKeepsParserAndTransportMetricsAligned() throws {
      var parser = WebSurfaceInputParser()
      let transport = WebSurfaceTransport(
        surfaceSize: .init(width: 80, height: 24), renderStyle: .init(appearance: .fallback))
      let records = parser.feedRecords(
        Array(
          ("\u{1E}geometry:1:80:24:9:21\n" + "\u{1E}resize:100:30:10:22\n"
            + "\u{1E}mouse:moved:1.5:1.5:none:0:0:0\n").utf8))
      var geometryApplied = false
      var mouse: MouseEvent?
      for record in records {
        switch record {
        case .control(.geometry(let request)):
          geometryApplied = transport.updateGeometry(request)
        case .control(.resize(let size, cellPixelSize: let pixel)):
          transport.updateSurfaceSize(size, cellPixelSize: pixel)
        case .input(.mouse(let event)):
          mouse = event
        default:
          break
        }
      }
      let event = try #require(mouse, "\(records)")
      #expect(!geometryApplied)
      #expect(transport.surfaceSize == CellSize(width: 100, height: 30))
      let reported = PointerPrecision.subCell(
        source: .webPixels, metrics: .init(width: 10, height: 22, source: .reported))
      #expect(transport.pointerInputCapabilities.precision == reported)
      withKnownIssue(
        "the parser latches the un-negotiated geometry's pitch and stops tracking resize metrics"
      ) {
        #expect(event.location.precision == transport.pointerInputCapabilities.precision)
      }
    }

    // An escape sequence that straddles a 4 KiB pull read is still one key:
    // the read boundary is an implementation detail, not a flush point.
    @Test func setB347AnEscapeSequenceSplitAcrossAPullReadStaysOneKey() throws {
      let bytes = [UInt8](repeating: 0x78, count: 4095) + [0x1B, 0x5B, 0x41]
      var parser = WebSurfaceInputParser()
      #expect(parser.feed(bytes).events.last == .key(.init(.arrowUp)))
      let pipe = try SetBPipe()
      defer { pipe.release() }
      let reader = WebSurfaceInputReader(fileDescriptor: pipe.readEnd)
      let recorder = SetBPullRecorder()
      reader.installPullDelivery(recorder.sink)
      defer { reader.uninstallPullDelivery() }
      try pipe.write(bytes)
      let delivered = reader.pullPendingInput()
      #expect(recorder.keys.prefix(4095).allSatisfy { $0 == .character("x") })
      withKnownIssue("feedRecords flushes the byte parser per read, committing the ESC as Escape") {
        #expect(delivered == 4096, "\(delivered)")
        #expect(recorder.keys.last == .arrowUp, "\(recorder.keys.suffix(3))")
      }
    }

    // One pull reads exactly maximumBytesPerPull and leaves the remainder for
    // the next pull: the boundary byte is neither lost nor read twice.
    @Test func setB348OnePullStopsExactlyAtItsByteBudget() throws {
      let budget = WebSurfaceInputReader.maximumBytesPerPull
      let pipe = try SetBPipe()
      defer { pipe.release() }
      let reader = WebSurfaceInputReader(fileDescriptor: pipe.readEnd)
      let recorder = SetBPullRecorder()
      reader.installPullDelivery(recorder.sink)
      defer { reader.uninstallPullDelivery() }
      try pipe.write([UInt8](repeating: 0x61, count: budget) + [0x62])
      #expect(reader.pullPendingInput() == budget)
      #expect(recorder.keys.count == budget)
      #expect(recorder.sourceBytes == budget)
      #expect(reader.pullPendingInput() == 1)
      #expect(recorder.keys.last == .character("b"))
      #expect(recorder.sourceBytes == budget + 1)
      #expect(reader.pullPendingInput() == 0)
      #expect(recorder.inputEndedReports == 0)
    }

    // An empty clipboard write is still a clipboard record (adjacent to
    // STUI-732 on the Android bridge): the browser clears its clipboard
    // instead of keeping stale text.
    @Test func setB349AnEmptyClipboardWriteEmitsAnEmptyRecord() throws {
      let pipe = Pipe()
      let transport = WebSurfaceTransport(
        surfaceSize: .init(width: 2, height: 1),
        outputFileDescriptor: pipe.fileHandleForWriting.fileDescriptor,
        renderStyle: .init(appearance: .fallback))
      let admitted = try transport.writeClipboard("")
      pipe.fileHandleForWriting.closeFile()
      let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      pipe.fileHandleForReading.closeFile()
      #expect(admitted)
      #expect(output == "\u{1E}clipboard:{\"text\":\"\"}\n", "\(output.debugDescription)")
      #expect(WebSurfaceFrameEncoder.encodeClipboard("") != HostWireBudget.rejectionRecord)
    }

    // A declaration of sharedViewport without geometryRevisions is inert: no
    // viewportRevision and no geometryRevision reach the record, while the
    // same frame under the full pair carries both.
    @Test func setB350SharedViewportWithoutGeometryRevisionsIsInert() throws {
      var frame = SemanticHostFrame(
        sequence: 3, raster: SetBSurfaces.plain(), semantics: SemanticSnapshot(),
        focusedIdentity: nil)
      frame.hostGeometryStamp = HostGeometryStamp(session: 0, revision: 2, viewportRevision: 5)
      var partial = HostWireCapabilities(sharedViewport: true).negotiatedEncodingState(epochID: 9)
      #expect(!partial.sharedViewportEnabled && !partial.geometryRevisionsEnabled)
      let inert = try SetBDecoded.surface(WebSurfaceFrameEncoder.encode(frame, state: &partial))
      #expect(inert["viewportRevision"] == nil && inert["geometryRevision"] == nil, "\(inert)")
      #expect(inert["epoch"] as? Int == 9)
      var both = HostWireCapabilities(geometryRevisions: true, sharedViewport: true)
        .negotiatedEncodingState(epochID: 10)
      let stamped = try SetBDecoded.surface(WebSurfaceFrameEncoder.encode(frame, state: &both))
      #expect(stamped["geometryRevision"] as? Int == 2, "\(stamped)")
      #expect(stamped["viewportRevision"] as? Int == 5, "\(stamped)")
      let declared = HostWireCapabilities.fromDeclarationJSON(
        #"{"sharedViewport":true,"future":{"nested":[1,{"x":null}]}}"#)
      #expect(declared == HostWireCapabilities(sharedViewport: true))
    }
  }

  // MARK: - Fixtures

  private enum SetBSurfaces {
    static func plain() -> RasterSurface {
      RasterSurface(size: CellSize(width: 2, height: 1), lines: ["ok"])
    }

    static func short() -> RasterSurface {
      RasterSurface(
        size: CellSize(width: 2, height: 3),
        cells: [
          [RasterCell(character: "a"), RasterCell(character: "b")],
          [RasterCell(character: "c"), RasterCell(character: "d")],
        ])
    }

    static func styled(opacity: Double) -> RasterSurface {
      RasterSurface(
        size: CellSize(width: 1, height: 1),
        cells: [[RasterCell(character: "x", style: ResolvedTextStyle(opacity: opacity))]])
    }
  }

  private struct SetBWireError: Error {}

  private enum SetBDecoded {
    static func payload(_ output: String) throws -> String {
      let prefix = "\u{1E}surface:"
      let line = output.trimmingCharacters(in: .newlines)
      guard line.hasPrefix(prefix) else { throw SetBWireError() }
      return String(line.dropFirst(prefix.count))
    }

    static func surface(_ output: String) throws -> [String: Any] {
      let decoded = try JSONSerialization.jsonObject(with: Data(payload(output).utf8))
      return try #require(decoded as? [String: Any], "\(output.prefix(160))")
    }
  }

  private enum SetBWire {
    static func pasteContents(_ events: [InputEvent]) -> [String] {
      events.compactMap { event in
        if case .paste(let paste) = event { return paste.content }
        return nil
      }
    }
  }

  @MainActor
  private final class SetBPullRecorder {
    private(set) var keys: [KeyEvent] = []
    private(set) var sourceBytes = 0
    private(set) var inputEndedReports = 0

    var sink: InputPullDeliverySink {
      InputPullDeliverySink(
        deliver: { [self] event in
          if case .key(let press) = event { keys.append(press.key) }
        },
        inputEnded: { [self] in inputEndedReports += 1 },
        recordSourceRead: { [self] bytes, _ in sourceBytes += bytes })
    }
  }

  /// A pipe with both ends non-blocking, so a write the kernel cannot buffer
  /// fails the test instead of hanging it.
  private struct SetBPipe {
    let readEnd: Int32
    let writeEnd: Int32

    init() throws {
      var descriptors: [Int32] = [-1, -1]
      try #require(unsafe pipe(&descriptors) == 0)
      readEnd = descriptors[0]
      writeEnd = descriptors[1]
      for descriptor in descriptors {
        let flags = fcntl(descriptor, F_GETFL)
        try #require(fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0)
      }
    }

    func write(_ bytes: [UInt8]) throws {
      var offset = 0
      while offset < bytes.count {
        let written = bytes.withUnsafeBytes { buffer -> Int in
          guard let baseAddress = buffer.baseAddress else { return 0 }
          let next = unsafe baseAddress.advanced(by: offset)
          return unsafe webSurfaceWrite(writeEnd, next, bytes.count - offset)
        }
        try #require(written > 0, "the pipe refused \(bytes.count - offset) bytes")
        offset += written
      }
    }

    func release() {
      _ = close(readEnd)
      _ = close(writeEnd)
    }
  }

#endif
