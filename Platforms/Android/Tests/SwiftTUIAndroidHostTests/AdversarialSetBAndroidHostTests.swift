// Adversarial set B, pass 4: the Android host bridge (351–360).
//
// `AndroidHostSceneHost` retains a hosted scene behind the `swift_tui_android_*`
// C ABI: frames are encoded only when the client copies them, damage
// accumulates across skipped polls, clipboard writes are drained once, and
// semantic actions are queued through the shared input reader. These probes
// sit beside the host-wire contract and the lifecycle the Kotlin side drives:
// an over-budget clipboard write, a NUL and non-BMP clipboard round trip,
// semantic actions sent before start and after stop, a frame the encoder
// refuses, damage that names rows outside the grid or only a wide glyph's
// continuation column, a resize between a size query and its copy, and a
// stop/start cycle on one handle.
#if !os(Windows)

  import Foundation
  import SwiftTUIAndroidHost
  @_spi(Testing) import SwiftTUICore
  @_spi(Runners) import SwiftTUIRuntime
  import Testing

  @MainActor
  @Suite("Adversarial set B: Android host", .serialized, .timeLimit(.minutes(1)))
  struct AdversarialSetBAndroidHostTests {
    // A clipboard write larger than the host-wire record budget is refused at
    // admission (returns false) instead of being reported as a multi-megabyte
    // pending payload (adjacent to STUI-732).
    @Test func setB351OverBudgetClipboardWriteIsRefused() throws {
      let host = try AndroidHostSceneHost(app: SetBStaticApp())
      let big = String(repeating: "a", count: HostWireBudget.recordBytes + 1)
      let accepted = try host.surface.writeClipboard(big)
      do {
        #expect(!accepted)
        #expect(setBClipboardSize(host) == 0)
      }
      #expect(try host.surface.writeClipboard("small"))
      #expect(setBClipboardSize(host) == 5)
      let copy = setBClipboardCopy(host, capacity: 5)
      #expect(copy.returned == 5)
      #expect(copy.bytes == Array("small".utf8))
      #expect(setBClipboardSize(host) == 0)
    }

    // The clipboard slot holds the latest write only, a copy is byte-exact for
    // NUL and non-BMP scalars, and the drain happens exactly once.
    @Test func setB352ClipboardKeepsTheLatestWriteByteExact() throws {
      let host = try AndroidHostSceneHost(app: SetBStaticApp())
      #expect(try host.surface.writeClipboard("first"))
      #expect(try host.surface.writeClipboard("a\u{0}b\u{1F600}"))
      let expected: [UInt8] = [0x61, 0x00, 0x62, 0xF0, 0x9F, 0x98, 0x80]
      #expect(setBClipboardSize(host) == expected.count)
      let copy = setBClipboardCopy(host, capacity: expected.count)
      #expect(copy.returned == expected.count)
      #expect(copy.bytes == expected)
      #expect(setBClipboardSize(host) == 0)
      #expect(setBClipboardCopy(host, capacity: 8).returned == 0)
    }

    // After `stop()` a semantic action is no longer queued anywhere, so the ABI
    // reports 0 rather than promising a response in the next frame.
    @Test func setB353AccessibilityActionAfterStopIsNotReportedAsQueued() async throws {
      let host = try AndroidHostSceneHost(app: SetBStaticApp())
      let handle = AndroidHostHandleRegistry.register(host)
      defer { swift_tui_android_destroy(handle) }
      swift_tui_android_start(handle)
      _ = await host.surface.waitForFrame()
      await Task.yield()
      #expect(setBAction(handle, "\u{1E}accessibility:1:nope:activate\n") == 1)
      try await setBStopAndSettle(host)
      let framesAfterStop = await setBFrames(host).count
      let queued = setBAction(handle, "\u{1E}accessibility:9:nope:activate\n")
      do {
        #expect(queued == 0)
      }
      let framesLater = await setBFrames(host).count
      #expect(framesLater == framesAfterStop)
      #expect(host.focusPresentation == .none)
    }

    // A semantic action queued before `start()` is delivered once the scene
    // runs: a frame carries its response, correlated by request id.
    @Test func setB354AccessibilityActionBeforeStartIsAnsweredAfterStart() async throws {
      let host = try AndroidHostSceneHost(app: SetBCounterApp())
      let handle = AndroidHostHandleRegistry.register(host)
      defer { swift_tui_android_destroy(handle) }
      #expect(setBAction(handle, "\u{1E}accessibility:7:nope:activate\n") == 1)
      swift_tui_android_start(handle)
      let answered = await host.surface.waitForFrame { frame in
        frame.semantics.accessibilityActionResponse?.requestID == 7
      }
      let response = answered.semantics.accessibilityActionResponse
      #expect(response?.result == .staleTarget, "\(String(describing: response))")
      #expect(response?.target == "nope")
      swift_tui_android_stop(handle)
    }

    // A frame the encoder refuses is served as the budget rejection record,
    // the refusal is reported through `latestEncodingErrorDescription`, and
    // the next admitted frame is a full keyframe at the next generation.
    @Test func setB355BudgetRejectionIsReportedAndRekeyframes() async throws {
      let host = try AndroidHostSceneHost(app: SetBStaticApp())
      let handle = AndroidHostHandleRegistry.register(host)
      defer { swift_tui_android_destroy(handle) }
      try #require(host.declareCapabilities(json: "{\"acceptsDeltaFrames\":true}"))
      try await setBPresent(host, sequence: 1, cells: setBCells(["A"]))
      let keyframe = try setBCopyRecord(handle)
      #expect(keyframe["gen"] as? Int == 1)
      let zalgo = Character("e" + String(repeating: "\u{301}", count: 130))
      try #require(String(zalgo).utf8.count > HostWireBudget.cellTextBytes)
      try await setBPresent(
        host, sequence: 2, cells: [[RasterCell(character: zalgo)]],
        damage: setBRowDamage(0, [0..<1]))
      let required = setBSizeQuery(handle)
      try #require(required > 0)
      let rejected = setBCopy(handle, capacity: required)
      let text = String(decoding: rejected.bytes, as: UTF8.self)
      #expect(rejected.returned == required)
      #expect(text.hasPrefix("\u{001E}runtimeIssue:"), "\(text.prefix(80))")
      #expect(text.contains("surface.budgetExceeded"), "\(text.prefix(160))")
      #expect(host.consumedFrameEncodeCount == 2)
      do {
        #expect(host.latestEncodingErrorDescription != nil)
      }
      try await setBPresent(
        host, sequence: 3, cells: setBCells(["B"]), damage: setBRowDamage(0, [0..<1]))
      let repaired = try setBCopyRecord(handle)
      #expect(repaired["encoding"] == nil, "\(repaired)")
      #expect(repaired["gen"] as? Int == 2)
      #expect(setBRowText(repaired) == ["B"])
      #expect(host.consumedFrameEncodeCount == 3)
    }

    // Damage that names only rows outside the grid cannot stand for "nothing
    // changed": the changed row must still reach the client, as a full frame
    // or as a delta row, not as an empty delta.
    @Test func setB356OutOfGridDamageStillShipsTheChangedRow() async throws {
      let host = try AndroidHostSceneHost(app: SetBStaticApp())
      let handle = AndroidHostHandleRegistry.register(host)
      defer { swift_tui_android_destroy(handle) }
      try #require(host.declareCapabilities(json: "{\"acceptsDeltaFrames\":true}"))
      try await setBPresent(host, sequence: 1, cells: setBCells(["ab"]))
      let keyframe = try setBCopyRecord(handle)
      #expect(setBRowText(keyframe) == ["ab"])
      try await setBPresent(
        host, sequence: 2, cells: setBCells(["xy"]), damage: setBRowDamage(5, [0..<2]))
      let record = try setBCopyRecord(handle)
      let shipped: [String]
      if record["encoding"] as? String == "delta" {
        shipped = setBDeltaRowCells(record).values.map { cells in
          cells.compactMap { $0[1] as? String }.joined()
        }
      } else {
        shipped = setBRowText(record)
      }
      do {
        #expect(shipped.contains("xy"), "\(record)")
      }
    }

    // A damage hint naming only a wide glyph's continuation column still
    // re-transmits the whole lead cell with its span, and the hint is forwarded
    // verbatim (the wire does not widen it to the lead like the terminal does).
    @Test func setB357ContinuationOnlyDamageRetransmitsTheLeadCell() async throws {
      let host = try AndroidHostSceneHost(app: SetBStaticApp())
      let handle = AndroidHostHandleRegistry.register(host)
      defer { swift_tui_android_destroy(handle) }
      try #require(host.declareCapabilities(json: "{\"acceptsDeltaFrames\":true}"))
      func wide(_ glyph: Character) -> [[RasterCell]] {
        [
          [
            RasterCell(character: "A"),
            RasterCell(character: glyph, spanWidth: 2),
            RasterCell(character: " ", spanWidth: 0, continuationLeadX: 1),
          ]
        ]
      }
      try await setBPresent(host, sequence: 1, cells: wide("界"))
      let keyframe = try setBCopyRecord(handle)
      #expect(setBRowText(keyframe) == ["A界"])
      try await setBPresent(
        host, sequence: 2, cells: wide("宽"), damage: setBRowDamage(0, [2..<3]))
      let record = try setBCopyRecord(handle)
      #expect(record["encoding"] as? String == "delta", "\(record)")
      let cells = setBDeltaRowCells(record)[0] ?? []
      #expect(setBCellTuples(cells) == ["0:A:1", "1:宽:2"], "\(cells)")
      let textRows = (record["damage"] as? [String: Any])?["textRows"] as? [[Any]]
      let ranges = textRows?.first?.dropFirst().first as? [[Int]]
      #expect(ranges == [[2, 3]], "\(String(describing: textRows))")
    }

    // A resize between a size query and its copy does not change what the copy
    // delivers: the measured bytes are served, and the next record is a full
    // frame at the new grid because the delta baseline no longer matches.
    @Test func setB358ResizeBetweenSizeQueryAndCopyServesTheMeasuredBytes() async throws {
      let host = try AndroidHostSceneHost(app: SetBStaticApp())
      let handle = AndroidHostHandleRegistry.register(host)
      defer { swift_tui_android_destroy(handle) }
      try #require(host.declareCapabilities(json: "{\"acceptsDeltaFrames\":true}"))
      try await setBPresent(host, sequence: 1, cells: setBCells(["ABC"]))
      let measured = setBSizeQuery(handle)
      try #require(measured > 0)
      host.resize(columns: 2, rows: 1, cellPixelWidth: 8, cellPixelHeight: 16)
      #expect(host.surfaceSize == CellSize(width: 2, height: 1))
      try await setBPresent(
        host, sequence: 2, cells: setBCells(["XY"]), damage: setBRowDamage(0, [0..<2]))
      let copy = setBCopy(handle, capacity: measured)
      #expect(copy.returned == measured)
      let first = try setBSurfaceObject(copy.bytes)
      #expect(first["sequence"] as? Int == 1)
      #expect(first["width"] as? Int == 3)
      #expect(setBRowText(first) == ["ABC"])
      let second = try setBCopyRecord(handle)
      #expect(second["sequence"] as? Int == 2)
      #expect(second["encoding"] == nil, "\(second)")
      #expect(second["width"] as? Int == 2)
      #expect(second["gen"] as? Int == 2)
      #expect(setBRowText(second) == ["XY"])
    }

    // `stop()` then `start()` on the same handle resumes the scene: a semantic
    // action sent after the restart changes the UI as it did before the stop.
    @Test func setB359StopThenStartResumesInput() async throws {
      let host = try AndroidHostSceneHost(app: SetBCounterApp())
      let handle = AndroidHostHandleRegistry.register(host)
      defer { swift_tui_android_destroy(handle) }
      swift_tui_android_start(handle)
      let initial = await host.surface.waitForFrame { frame in
        frame.semantics.accessibilityNodes.contains { $0.label == "Add" }
      }
      let target = try #require(
        initial.semantics.accessibilityNodes.first { $0.label == "Add" }?.actionTarget)
      let encoded = try #require(
        target.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
      try #require(setBAction(handle, "\u{1E}accessibility:1:\(encoded):activate\n") == 1)
      _ = await host.surface.waitForFrame { $0.raster.lines.joined().contains("Count 1") }
      try await setBStopAndSettle(host)
      let before = await setBFrames(host).count
      swift_tui_android_start(handle)
      let restarted = await host.surface.waitForFrames { $0.count > before }
      #expect(
        restarted.last?.raster.lines.joined().contains("Count 0") == true,
        "\(restarted.last?.raster.lines.joined() ?? "no frame")")
      try #require(setBAction(handle, "\u{1E}accessibility:2:\(encoded):activate\n") == 1)
      // The restarted loop's end is the ordered signal: a healthy loop handles
      // the queued action and flushes its frame before `stopAndWait` returns;
      // a dead one has already exited, so the history after this point is
      // complete either way.
      let exitReason = try await host.session.stopAndWait()
      await Task.yield()
      let afterRestart = await setBFrames(host).dropFirst(restarted.count)
      let changed = afterRestart.contains { frame in
        frame.semantics.accessibilityActionResponse?.requestID == 2
          || frame.raster.lines.joined().contains("Count 1")
      }
      do {
        #expect(
          changed, "exit \(String(describing: exitReason)), frames \(afterRestart.count)")
      }
    }

    // After a stop/resize/start cycle the first copied record describes the
    // restarted scene's frame (the new grid width), not the bytes cached for
    // the frame consumed before the stop.
    @Test func setB360RecordAfterRestartReflectsTheRestartedFrame() async throws {
      let host = try AndroidHostSceneHost(app: SetBStaticApp())
      let handle = AndroidHostHandleRegistry.register(host)
      defer { swift_tui_android_destroy(handle) }
      swift_tui_android_start(handle)
      _ = await host.surface.waitForFrame()
      await Task.yield()
      let consumedBefore = try setBCopyRecord(handle)
      let consumedSequence = try #require(host.latestFrame?.sequence)
      let widthBefore = consumedBefore["width"] as? Int
      #expect(widthBefore != 40, "\(String(describing: widthBefore))")
      try await setBStopAndSettle(host)
      host.resize(columns: 40, rows: 10, cellPixelWidth: 8, cellPixelHeight: 16)
      let before = await setBFrames(host).count
      swift_tui_android_start(handle)
      let restarted = await host.surface.waitForFrames { $0.count > before }
      await Task.yield()
      #expect(
        restarted.last?.raster.size.width == 40,
        "\(String(describing: restarted.last?.raster.size))")
      let afterRestart = try setBCopyRecord(handle)
      let detail =
        "width \(String(describing: afterRestart["width"])), consumed sequence "
        + "\(consumedSequence), restarted sequence "
        + "\(String(describing: host.latestFrame?.sequence))"
      do {
        #expect(afterRestart["width"] as? Int == 40, "\(detail)")
      }
    }
  }

  private struct SetBStaticApp: App {
    var body: some Scene {
      WindowGroup("SetB Android") {
        Text("SetB static")
      }
    }
  }

  @MainActor
  private struct SetBCounterApp: App {
    var body: some Scene {
      WindowGroup("SetB Counter") {
        SetBCounterView()
      }
    }
  }

  @MainActor
  private struct SetBCounterView: View {
    @State private var count = 0

    var body: some View {
      VStack {
        Text("Count \(count)")
        Button("Add") { count += 1 }
      }
    }
  }

  // The surface's frame history (32 frames) is the signal source: `waitForFrames`
  // with `{ _ in true }` returns it immediately and serves as the frame counter.
  @MainActor
  private func setBFrames(_ host: AndroidHostSceneHost) async -> [SemanticHostFrame] {
    await host.surface.waitForFrames { _ in true }
  }

  // Stops the session, waits for its run loop, then lets the host's own task
  // clear its run handle so a later `start()` is not ignored by its guard.
  @MainActor
  private func setBStopAndSettle(_ host: AndroidHostSceneHost) async throws {
    host.stop()
    _ = try await host.session.stopAndWait()
    for _ in 0..<8 {
      await Task.yield()
    }
  }

  @MainActor
  private func setBPresent(
    _ host: AndroidHostSceneHost,
    sequence: UInt64,
    cells: [[RasterCell]],
    damage: PresentationDamage? = nil
  ) async throws {
    let width = cells.first?.count ?? 0
    _ = try host.surface.present(
      SemanticHostFrame(
        sequence: sequence,
        raster: RasterSurface(size: .init(width: width, height: cells.count), cells: cells),
        semantics: SemanticSnapshot(),
        focusedIdentity: nil,
        rasterDamage: damage
      )
    )
    await Task.yield()
  }

  private func setBCells(_ lines: [String]) -> [[RasterCell]] {
    lines.map { line in line.map { RasterCell(character: $0) } }
  }

  private func setBRowDamage(_ row: Int, _ ranges: [Range<Int>]) -> PresentationDamage {
    PresentationDamage(textRows: [.init(row: row, columnRanges: ranges)])
  }

  private func setBSizeQuery(_ handle: Int64) -> Int32 {
    swift_tui_android_copy_latest_frame(handle, nil, 0)
  }

  private func setBCopy(_ handle: Int64, capacity: Int32) -> (returned: Int32, bytes: [UInt8]) {
    var bytes = [UInt8](repeating: 0, count: Int(max(0, capacity)))
    let returned = bytes.withUnsafeMutableBufferPointer { buffer in
      unsafe swift_tui_android_copy_latest_frame(handle, buffer.baseAddress, capacity)
    }
    return (returned, bytes)
  }

  private func setBCopyRecord(_ handle: Int64) throws -> [String: Any] {
    let required = setBSizeQuery(handle)
    try #require(required > 0)
    let copy = setBCopy(handle, capacity: required)
    try #require(copy.returned == required)
    return try setBSurfaceObject(copy.bytes)
  }

  private func setBSurfaceObject(_ bytes: [UInt8]) throws -> [String: Any] {
    let prefix = Array("\u{001E}surface:".utf8)
    try #require(
      bytes.starts(with: prefix) && bytes.last == 0x0A,
      "\(String(decoding: bytes.prefix(80), as: UTF8.self))")
    let payload = Data(bytes[prefix.count..<(bytes.count - 1)])
    return try #require(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
  }

  private func setBRowText(_ record: [String: Any]) -> [String] {
    guard let rows = record["rows"] as? [[Any]] else {
      return []
    }
    return rows.map { row in
      row.compactMap { ($0 as? [Any])?[1] as? String }.joined()
    }
  }

  private func setBDeltaRowCells(_ record: [String: Any]) -> [Int: [[Any]]] {
    var result: [Int: [[Any]]] = [:]
    for pair in record["deltaRows"] as? [[Any]] ?? [] {
      guard pair.count == 2, let row = pair[0] as? Int, let cells = pair[1] as? [[Any]] else {
        continue
      }
      result[row] = cells
    }
    return result
  }

  private func setBCellTuples(_ cells: [[Any]]) -> [String] {
    cells.map { cell in
      let column = cell.count > 0 ? (cell[0] as? Int ?? -1) : -1
      let text = cell.count > 1 ? (cell[1] as? String ?? "?") : "?"
      let span = cell.count > 2 ? (cell[2] as? Int ?? -1) : -1
      return "\(column):\(text):\(span)"
    }
  }

  private func setBAction(_ handle: Int64, _ command: String) -> Int32 {
    Array(command.utf8).withUnsafeBufferPointer {
      unsafe swift_tui_android_accessibility_action(handle, $0.baseAddress, Int32($0.count))
    }
  }

  private func setBClipboardSize(_ host: AndroidHostSceneHost) -> Int {
    unsafe host.copyPendingClipboardText(to: nil, capacity: 0)
  }

  private func setBClipboardCopy(
    _ host: AndroidHostSceneHost,
    capacity: Int
  ) -> (returned: Int, bytes: [UInt8]) {
    var bytes = [UInt8](repeating: 0, count: capacity)
    let returned = bytes.withUnsafeMutableBufferPointer { buffer in
      unsafe host.copyPendingClipboardText(to: buffer.baseAddress, capacity: capacity)
    }
    return (returned, bytes)
  }

#endif
