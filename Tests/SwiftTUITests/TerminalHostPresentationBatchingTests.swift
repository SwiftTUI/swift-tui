import Dispatch
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUIRuntime

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@MainActor
@Suite
struct TerminalHostPresentationBatchingTests {
  @Test("terminal host batches a full repaint into one write")
  func fullRepaintBatchesWrites() throws {
    let controller = PresentationWriteCountingController(isTTY: true)
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .previewUnicode
    )

    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 2),
        lines: ["ABCD", "EFGH"]
      )
    )
    try host.drainPendingPresentation()

    #expect(controller.writes.count == 1)
    #expect(controller.writes.first == "\u{001B}[2J\u{001B}[1;1HABCD\u{001B}[2;1HEFGH")
  }

  @Test("terminal host wraps full repaints in synchronized output when supported")
  func fullRepaintUsesSynchronizedOutputWhenSupported() throws {
    let controller = PresentationWriteCountingController(isTTY: true)
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .init(
        glyphLevel: .unicode,
        colorLevel: .none,
        emitsStyleEscapeSequences: false,
        supportsSynchronizedOutput: true
      )
    )

    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["ABCD"]
      )
    )
    try host.drainPendingPresentation()

    #expect(controller.writes == ["\u{001B}[?2026h\u{001B}[2J\u{001B}[1;1HABCD\u{001B}[?2026l"])
  }

  @Test("terminal host batches incremental spans into one write")
  func incrementalUpdatesBatchedIntoOneWrite() throws {
    let controller = PresentationWriteCountingController(isTTY: true)
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .previewUnicode
    )

    _ = try host.present(
      RasterSurface(
        size: .init(width: 8, height: 1),
        lines: ["alpha"]
      )
    )
    try host.drainPendingPresentation()
    let writesBeforeUpdate = controller.writes.count

    _ = try host.present(
      RasterSurface(
        size: .init(width: 8, height: 1),
        lines: ["alpXa"]
      )
    )
    try host.drainPendingPresentation()

    let incrementalWrites = Array(controller.writes.dropFirst(writesBeforeUpdate))

    #expect(incrementalWrites == ["\u{001B}[1;4HX"])
  }

  @Test("terminal host batches multi-span row updates behind one row anchor")
  func multiSpanRowUpdatesBatchBehindOneAnchor() throws {
    let controller = PresentationWriteCountingController(isTTY: true)
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .previewUnicode
    )

    _ = try host.present(
      RasterSurface(
        size: .init(width: 8, height: 1),
        lines: ["abcd1234"]
      )
    )
    try host.drainPendingPresentation()
    let writesBeforeUpdate = controller.writes.count

    _ = try host.present(
      RasterSurface(
        size: .init(width: 8, height: 1),
        lines: ["abXd12Y4"]
      )
    )
    try host.drainPendingPresentation()

    let incrementalWrites = Array(controller.writes.dropFirst(writesBeforeUpdate))

    #expect(incrementalWrites == ["\u{001B}[1;3HX\u{001B}[3CY"])
  }

  @Test("terminal host queues accessibility cursor focus behind pending presentation")
  func accessibilityCursorFocusQueuesBehindPendingPresentation() async throws {
    let controller = BlockingPresentationWriteController(isTTY: true)
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .previewUnicode
    )

    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["ABCD"]
      )
    )
    await controller.waitForBlockedWriteToStart()

    try host.presentAccessibilityCursorFocus(at: .init(x: 2, y: 0))

    controller.unblockWrite()
    try host.drainPendingPresentation()

    #expect(
      controller.writes == [
        "\u{001B}[2J\u{001B}[1;1HABCD",
        "\u{001B}[1;3H\u{001B}[?25h",
      ]
    )
  }

  @Test("terminal host damage-aware presentation batches only hinted rows")
  func damageAwareUpdatesBatchOnlyHintedRows() throws {
    let controller = PresentationWriteCountingController(isTTY: true)
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .previewUnicode
    )

    _ = try host.present(
      RasterSurface(
        size: .init(width: 8, height: 2),
        lines: ["same", "beta"]
      )
    )
    try host.drainPendingPresentation()
    let writesBeforeUpdate = controller.writes.count

    let damageAwareHost: any DamageAwarePresentationSurface = host
    _ = try damageAwareHost.present(
      RasterSurface(
        size: .init(width: 8, height: 2),
        lines: ["same", "beXa"]
      ),
      damage: .init(dirtyRows: [1])
    )
    try host.drainPendingPresentation()

    let incrementalWrites = Array(controller.writes.dropFirst(writesBeforeUpdate))
    #expect(incrementalWrites == ["\u{001B}[2;3HX"])
  }

  @Test("terminal host lowers trailing tail clears into erase-to-end-of-line when enabled")
  func trailingTailClearsLowerIntoEraseToEndOfLineWhenEnabled() throws {
    let controller = PresentationWriteCountingController(isTTY: true)
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .previewUnicode
    )

    _ = try host.present(
      RasterSurface(
        size: .init(width: 8, height: 1),
        lines: ["alphabet"]
      )
    )
    try host.drainPendingPresentation()
    let writesBeforeUpdate = controller.writes.count

    _ = try host.present(
      RasterSurface(
        size: .init(width: 8, height: 1),
        lines: ["alph"]
      )
    )
    try host.drainPendingPresentation()

    let incrementalWrites = Array(controller.writes.dropFirst(writesBeforeUpdate))
    #expect(incrementalWrites == ["\u{001B}[1;5H\u{001B}[K"])
  }

  @Test("terminal host keeps literal tail clears when edit-op lowering is disabled")
  func trailingTailClearsStayLiteralWhenEditOpLoweringIsDisabled() throws {
    let controller = PresentationWriteCountingController(isTTY: true)
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .previewUnicode,
      usesTerminalEditOperations: false
    )

    _ = try host.present(
      RasterSurface(
        size: .init(width: 8, height: 1),
        lines: ["alphabet"]
      )
    )
    try host.drainPendingPresentation()
    let writesBeforeUpdate = controller.writes.count

    _ = try host.present(
      RasterSurface(
        size: .init(width: 8, height: 1),
        lines: ["alph"]
      )
    )
    try host.drainPendingPresentation()

    let incrementalWrites = Array(controller.writes.dropFirst(writesBeforeUpdate))
    #expect(incrementalWrites == ["\u{001B}[1;5H    "])
  }

  // Expectation history: before the F180 dropped-frame recovery redesign,
  // superseding a queued frame forced full repaints — this test used to
  // expect "\u{001B}[2J\u{001B}[1;1HABAA" as the second write and a
  // .fullRepaint recovery for "WXYZ". Recovery now diffs against the last
  // surface actually written (the blocked "AAAA" repaint), so the dropped
  // "BAAA" never influences the emitted bytes.
  @Test("terminal host drops stale pending frames and recovers with an incremental diff")
  func droppedPendingFramesRecoverWithAnIncrementalDiff() async throws {
    let controller = BlockingPresentationWriteController(isTTY: true)
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .previewUnicode
    )

    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["AAAA"]
      )
    )
    await controller.waitForBlockedWriteToStart()

    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["BAAA"]
      )
    )
    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["ABAA"]
      )
    )

    controller.unblockWrite()
    try host.drainPendingPresentation()

    #expect(
      controller.writes == [
        "\u{001B}[2J\u{001B}[1;1HAAAA",
        "\u{001B}[1;2HB",
      ]
    )

    let metrics = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["WXYZ"]
      )
    )
    try host.drainPendingPresentation()

    #expect(metrics.strategy == .incremental)
    #expect(
      controller.writes.last == "\u{001B}[1;1HWXYZ"
    )
  }

  // Expectation history: this test used to expect the present replacing a
  // queued frame to full repaint immediately ("\u{001B}[2J\u{001B}[1;1HCCCD").
  // After the F180 redesign the replacement diffs against the last written
  // surface ("BBBB", whose write is blocked in flight but committed), so the
  // dropped "CCCC" costs nothing on the wire.
  @Test(
    "terminal host recovers with an incremental diff when the current submit replaces a queued frame"
  )
  func replacingQueuedFrameRecoversWithAnIncrementalDiff() async throws {
    let controller = BlockingPresentationWriteController(
      isTTY: true,
      blocksFirstWrite: false
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .previewUnicode
    )

    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["AAAA"]
      )
    )
    try host.drainPendingPresentation()

    controller.armBlockNextWrite()
    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["BBBB"]
      )
    )
    await controller.waitForBlockedWriteToStart()

    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["CCCC"]
      )
    )
    let metrics = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["CCCD"]
      )
    )

    controller.unblockWrite()
    try host.drainPendingPresentation()

    #expect(metrics.strategy == .incremental)
    #expect(
      controller.writes == [
        "\u{001B}[2J\u{001B}[1;1HAAAA",
        "\u{001B}[1;1HBBBB",
        "\u{001B}[1;1HCCCD",
      ]
    )
  }

  // Expectation history: recovery after a drop used to be a full repaint, and
  // this test pinned its synchronized-output wrapping
  // ("\u{001B}[?2026h\u{001B}[2J…"). Recovery is now an ordinary incremental
  // diff, which — per the standing emission policy — is never wrapped; the
  // synchronized wrap remains pinned for genuine full repaints by
  // "terminal host wraps full repaints in synchronized output when supported".
  @Test("drop recovery diffs stay incremental under synchronized-output terminals")
  func dropRecoveryDiffsStayIncrementalUnderSynchronizedOutputTerminals() async throws {
    let controller = BlockingPresentationWriteController(isTTY: true)
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .init(
        glyphLevel: .unicode,
        colorLevel: .none,
        emitsStyleEscapeSequences: false,
        supportsSynchronizedOutput: true
      )
    )

    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["AAAA"]
      )
    )
    await controller.waitForBlockedWriteToStart()

    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["BAAA"]
      )
    )
    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["ABAA"]
      )
    )

    controller.unblockWrite()
    try host.drainPendingPresentation()

    let metrics = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["WXYZ"]
      )
    )
    try host.drainPendingPresentation()

    #expect(metrics.strategy == .incremental)
    #expect(
      controller.writes.last == "\u{001B}[1;1HWXYZ"
    )
  }

  @Test("dropped-frame recovery diffs against the last written surface")
  func droppedFrameRecoveryDiffsAgainstLastWrittenSurface() async throws {
    let controller = BlockingPresentationWriteController(
      isTTY: true,
      blocksFirstWrite: false
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .previewUnicode
    )

    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["AAAA"]
      )
    )
    try host.drainPendingPresentation()

    controller.armBlockNextWrite()
    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["AABA"]
      )
    )
    await controller.waitForBlockedWriteToStart()

    // Queued behind the blocked write; superseded below without ever reaching
    // the terminal.
    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["AABC"]
      )
    )
    // The recovery diff must target the last WRITTEN surface ("AABA"), not the
    // dropped "AABC": cell 0 differs from both, but cell 3 matches the dropped
    // frame and NOT the written one — a diff against the dropped frame would
    // strand cell 3 at "A" on the real screen.
    let metrics = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["XABC"]
      )
    )

    controller.unblockWrite()
    try host.drainPendingPresentation()

    #expect(metrics.strategy == .incremental)
    #expect(
      controller.writes == [
        "\u{001B}[2J\u{001B}[1;1HAAAA",
        "\u{001B}[1;3HB",
        "\u{001B}[1;1HX\u{001B}[2CC",
      ]
    )
  }

  @Test("a stale damage hint is ignored after a dropped frame")
  func staleDamageHintIsIgnoredAfterDroppedFrame() async throws {
    let controller = BlockingPresentationWriteController(
      isTTY: true,
      blocksFirstWrite: false
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .previewUnicode
    )

    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 2),
        lines: ["CAAA", "BBBB"]
      )
    )
    try host.drainPendingPresentation()

    controller.armBlockNextWrite()
    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 2),
        lines: ["CAAA", "BBBZ"]
      )
    )
    await controller.waitForBlockedWriteToStart()

    // This frame changes row 0 only, and is dropped before it is written.
    let damageAwareHost: any DamageAwarePresentationSurface = host
    _ = try damageAwareHost.present(
      RasterSurface(
        size: .init(width: 4, height: 2),
        lines: ["CAXA", "BBBZ"]
      ),
      damage: .init(dirtyRows: [0])
    )
    // The pipeline computes damage against the frame it last presented — the
    // DROPPED one — so the row-1-only hint is stale: row 0 still shows the
    // written "CAAA" and must be repaired too.
    let metrics = try damageAwareHost.present(
      RasterSurface(
        size: .init(width: 4, height: 2),
        lines: ["CAXA", "BBXZ"]
      ),
      damage: .init(dirtyRows: [1])
    )

    controller.unblockWrite()
    try host.drainPendingPresentation()

    #expect(metrics.strategy == .incremental)
    #expect(
      controller.writes.last == "\u{001B}[1;3HX\u{001B}[2;3HX"
    )
  }

  @Test("pending accessibility cursor focus keeps the next present incremental")
  func pendingAccessibilityCursorFocusKeepsNextPresentIncremental() async throws {
    let controller = BlockingPresentationWriteController(
      isTTY: true,
      blocksFirstWrite: false
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .previewUnicode
    )

    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["AAAA"]
      )
    )
    try host.drainPendingPresentation()

    controller.armBlockNextWrite()
    try host.presentAccessibilityCursorFocus(at: .init(x: 2, y: 0))
    await controller.waitForBlockedWriteToStart()
    // With the first focus write blocked in flight, a second supplemental
    // frame sits in the queue when the next present arrives. Supplemental
    // output carries no cell content — it must not degrade the presentation.
    try host.presentAccessibilityCursorFocus(at: .init(x: 1, y: 0))

    let metrics = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["AABA"]
      )
    )

    controller.unblockWrite()
    try host.drainPendingPresentation()

    #expect(metrics.strategy == .incremental)
    #expect(controller.writes.last == "\u{001B}[1;3HB")
  }

  @Test("kitty images transmitted only in a dropped frame are retransmitted on recovery")
  func kittyImagesFromDroppedFramesAreRetransmittedOnRecovery() async throws {
    let controller = BlockingPresentationWriteController(
      isTTY: true,
      blocksFirstWrite: false
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .trueColor
    )
    host.capabilityProbe.cachedGraphicsCapabilities = .init(
      supportedProtocols: [.kitty],
      preferredProtocol: .kitty,
      cellPixelSize: .init(width: 8, height: 16)
    )
    host.capabilityProbe.hasProbedGraphicsCapabilities = true

    let imageX = try makePNGBytes(
      width: 2,
      height: 2,
      pixels: [
        rgbaPixel(red: 255, green: 0, blue: 0),
        rgbaPixel(red: 255, green: 0, blue: 0),
        rgbaPixel(red: 0, green: 0, blue: 255),
        rgbaPixel(red: 0, green: 0, blue: 255),
      ]
    )
    let imageY = try makePNGBytes(
      width: 2,
      height: 2,
      pixels: [
        rgbaPixel(red: 0, green: 255, blue: 0),
        rgbaPixel(red: 0, green: 255, blue: 0),
        rgbaPixel(red: 255, green: 255, blue: 0),
        rgbaPixel(red: 255, green: 255, blue: 0),
      ]
    )
    let attachmentX = makeRasterImageAttachment(
      pngBytes: imageX,
      pixelSize: .init(width: 2, height: 2),
      bounds: .init(origin: .zero, size: .init(width: 2, height: 1))
    )
    let attachmentY = makeRasterImageAttachment(
      pngBytes: imageY,
      pixelSize: .init(width: 2, height: 2),
      bounds: .init(origin: .init(x: 0, y: 1), size: .init(width: 2, height: 1)),
      identity: testIdentity("Root", "ImageY")
    )

    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 2),
        lines: ["    ", "    "],
        imageAttachments: [attachmentX]
      )
    )
    try host.drainPendingPresentation()

    controller.armBlockNextWrite()
    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 2),
        lines: ["z   ", "    "],
        imageAttachments: [attachmentX]
      )
    )
    await controller.waitForBlockedWriteToStart()

    // This frame transmits image Y for the first time — and is dropped, so
    // the terminal never receives Y's pixel data.
    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 2),
        lines: ["z   ", "    "],
        imageAttachments: [attachmentX, attachmentY]
      )
    )
    let metrics = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 2),
        lines: ["z   ", "    "],
        imageAttachments: [attachmentX, attachmentY]
      )
    )

    controller.unblockWrite()
    try host.drainPendingPresentation()

    #expect(metrics.strategy == .incremental)
    let recoveryWrite = try #require(controller.writes.last)
    // Image X reached the terminal in the first frame: re-place by id.
    #expect(recoveryWrite.contains("_Ga=p"))
    // Image Y's data only ever rode the dropped frame: it must be
    // re-transmitted, not placed by id.
    #expect(recoveryWrite.contains("_Ga=T"))
  }
}

private final class PresentationWriteCountingController: TerminalControlling {
  private let isTTYValue: Bool
  private let writesStorage = LockedBox<[String]>([])

  private(set) var writes: [String] {
    get { writesStorage.value }
    set { writesStorage.value = newValue }
  }

  init(isTTY: Bool) {
    isTTYValue = isTTY
  }

  func isATTY(_: Int32) -> Bool {
    isTTYValue
  }

  func getAttributes(from _: Int32) throws -> termios {
    termios()
  }

  func setAttributes(_: termios, on _: Int32) throws {}

  func windowSize(of _: Int32) throws -> CellSize {
    .init(width: 80, height: 24)
  }

  func cellPixelSize(of _: Int32) throws -> PixelSize? {
    nil
  }

  func getFileStatusFlags(of _: Int32) throws -> Int32 {
    0
  }

  func setFileStatusFlags(_: Int32, on _: Int32) throws {}

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

private final class BlockingPresentationWriteController: TerminalControlling {
  private let isTTYValue: Bool
  /// Fired (synchronously, from the blocking sync `write`) once the gate has
  /// entered its blocked state, so the test can await it directly instead of
  /// blocking a cooperative-pool thread on a semaphore.
  private let blockedWriteStartedEvent = AsyncEvent()
  // A genuine *synchronous* thread block: `write` is a sync method that must
  // stall its own thread until `unblockWrite()`. A semaphore is the correct
  // primitive — not the async-bridge anti-pattern.
  private let releaseBlockedWrite = DispatchSemaphore(value: 0)
  private let shouldBlockNextWriteStorage: LockedBox<Bool>
  private let writesStorage = LockedBox<[String]>([])

  private(set) var writes: [String] {
    get { writesStorage.value }
    set { writesStorage.value = newValue }
  }

  init(
    isTTY: Bool,
    blocksFirstWrite: Bool = true
  ) {
    isTTYValue = isTTY
    shouldBlockNextWriteStorage = LockedBox(blocksFirstWrite)
  }

  func isATTY(_: Int32) -> Bool {
    isTTYValue
  }

  func getAttributes(from _: Int32) throws -> termios {
    termios()
  }

  func setAttributes(_: termios, on _: Int32) throws {}

  func windowSize(of _: Int32) throws -> CellSize {
    .init(width: 80, height: 24)
  }

  func cellPixelSize(of _: Int32) throws -> PixelSize? {
    nil
  }

  func getFileStatusFlags(of _: Int32) throws -> Int32 {
    0
  }

  func setFileStatusFlags(_: Int32, on _: Int32) throws {}

  func write(_ output: String, to _: Int32) throws {
    let shouldBlockFirstWrite = shouldBlockNextWriteStorage.withLock { state in
      let shouldBlock = state
      if state {
        state = false
      }
      return shouldBlock
    }

    if shouldBlockFirstWrite {
      blockedWriteStartedEvent.fire()
      // No timeout: the test thread releases this deterministically. A blocking
      // wait without a clock cannot flake under CI load.
      releaseBlockedWrite.wait()
    }

    writesStorage.withLock { $0.append(output) }
  }

  func read(
    from _: Int32,
    maxBytes _: Int,
    timeoutMilliseconds _: Int
  ) throws -> [UInt8] {
    []
  }

  func waitForBlockedWriteToStart() async {
    await blockedWriteStartedEvent.wait()
  }

  func armBlockNextWrite() {
    shouldBlockNextWriteStorage.withLock { state in
      state = true
    }
  }

  func unblockWrite() {
    releaseBlockedWrite.signal()
  }
}
