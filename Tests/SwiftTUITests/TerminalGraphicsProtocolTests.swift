import Foundation
import PNG
import SwiftTUIAnimatedImage
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@MainActor
@Suite
struct TerminalGraphicsProtocolTests {
  @Test("graphics probes read the input descriptor only while the reader is suspended")
  func graphicsProbesReadOnlyWhileInputReaderSuspended() throws {
    // F42: the probe's blocking reads race the live InputReader's dispatch
    // source for the same input fd; whoever wins eats the terminal's reply.
    // With a suspension gate wired, EVERY probe read must happen inside a
    // suspension window so the reply cannot be consumed by the reader.
    let gate = SpyInputSuspensionGate()
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      readResponses: [Array("\u{001B}[?62;4c".utf8)]
    )
    let readsTotal = LockedBox(0)
    let readsSuspended = LockedBox(0)
    controller.onRead = {
      readsTotal.withLock { $0 += 1 }
      if gate.isSuspended {
        readsSuspended.withLock { $0 += 1 }
      }
    }
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .trueColor,
      environment: ["TERM": "xterm"]
    )
    host.inputSuspensionGate = gate

    _ = host.resolvedGraphicsCapabilities(probingProtocols: true)

    #expect(gate.engagements >= 1, "the probe must engage the suspension gate")
    let total = readsTotal.value
    #expect(total > 0, "the probe should have read the input descriptor")
    #expect(
      readsSuspended.value == total,
      "every probe read must happen while the live input reader is suspended (\(readsSuspended.value)/\(total) were)"
    )
  }

  @Test("terminal host enables SGR-Pixels after live mode-query support")
  func terminalHostEnablesSGRPixelsAfterLiveModeQuerySupport() throws {
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      readResponses: [Array("\u{001B}[?1016;2$y".utf8)],
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .trueColor,
      environment: ["TERM": "unknown"]
    )

    try host.enableRawMode()

    #expect(
      host.pointerInputCapabilities.precision
        == .subCell(
          source: .terminalPixels,
          metrics: CellPixelMetrics(width: 8, height: 16, source: .reported)
        )
    )

    try host.disableRawMode()

    let output = controller.writes.joined()
    #expect(output.contains("\u{001B}[?1016$p"))
    #expect(output.contains("\u{001B}[?1006h\u{001B}[?1016h\u{001B}[?1002h"))
    #expect(output.contains("\u{001B}[?1002l\u{001B}[?1016l\u{001B}[?1006l"))
  }

  @Test("terminal host uses documented matrix when live mode query is inconclusive")
  func terminalHostUsesDocumentedMatrixWhenLiveModeQueryIsInconclusive() throws {
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .trueColor,
      environment: ["TERM": "xterm-kitty"]
    )

    try host.enableRawMode()
    #expect(
      host.pointerInputCapabilities.precision
        == .subCell(
          source: .terminalPixels,
          metrics: CellPixelMetrics(width: 8, height: 16, source: .reported)
        )
    )
    try host.disableRawMode()

    let output = controller.writes.joined()
    #expect(output.contains("\u{001B}[?1016$p"))
    #expect(output.contains("\u{001B}[?1016h"))
  }

  @Test("live-probe-only policy does not use documented matrix fallback")
  func liveProbeOnlyPolicyDoesNotUseDocumentedMatrixFallback() throws {
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .trueColor,
      environment: ["TERM": "xterm-kitty"],
      mouseInputResolution: .automatic(.liveProbeOnly)
    )

    try host.enableRawMode()
    #expect(host.pointerInputCapabilities.precision == .cell)
    #expect(host.pointerInputCapabilities.supportsHover)
    try host.disableRawMode()

    let output = controller.writes.joined()
    #expect(output.contains("\u{001B}[?1016$p"))
    #expect(!output.contains("\u{001B}[?1016h"))
  }

  @Test("unsupported live mode-query response suppresses matrix fallback")
  func unsupportedLiveModeQueryResponseSuppressesMatrixFallback() throws {
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      readResponses: [Array("\u{001B}[?1016;0$y".utf8)],
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .trueColor,
      environment: ["TERM": "xterm-kitty"]
    )

    try host.enableRawMode()
    #expect(host.pointerInputCapabilities.precision == .cell)
    try host.disableRawMode()

    #expect(!controller.writes.joined().contains("\u{001B}[?1016h"))
  }

  @Test("terminal host cell-only policy never emits SGR-Pixels")
  func terminalHostCellOnlyPolicyNeverEmitsSGRPixels() throws {
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .trueColor,
      environment: ["TERM": "xterm-kitty"],
      mouseInputResolution: .preResolved(.cell)
    )

    try host.enableRawMode()
    #expect(host.pointerInputCapabilities.precision == .cell)
    #expect(host.pointerInputCapabilities.supportsHover)
    try host.disableRawMode()

    let output = controller.writes.joined()
    #expect(!output.contains("\u{001B}[?1016$p"))
    #expect(!output.contains("\u{001B}[?1016h"))
  }

  @Test("terminal host pre-resolved SGR-Pixels skips probing and reported metrics")
  func terminalHostPreResolvedSGRPixelsSkipsProbingAndReportedMetrics() throws {
    let metrics = CellPixelMetrics(width: 9, height: 18, source: .reported)
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      cellPixelSize: nil
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .trueColor,
      environment: ["TERM": "unknown"],
      mouseInputResolution: .preResolved(.sgrPixels(metrics: metrics))
    )

    try host.enableRawMode()
    #expect(
      host.pointerInputCapabilities.precision
        == .subCell(source: .terminalPixels, metrics: metrics)
    )
    try host.disableRawMode()

    let output = controller.writes.joined()
    #expect(!output.contains("\u{001B}[?1016$p"))
    #expect(output.contains("\u{001B}[?1016h"))
  }

  @Test("terminal host pre-resolved disabled mouse input emits no mouse modes")
  func terminalHostPreResolvedDisabledMouseInputEmitsNoMouseModes() throws {
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .trueColor,
      environment: ["TERM": "xterm-kitty"],
      mouseInputResolution: .preResolved(.disabled)
    )

    try host.setPointerHoverEnabled(true)
    try host.enableRawMode()
    #expect(host.pointerInputCapabilities.precision == .cell)
    #expect(!host.pointerInputCapabilities.supportsHover)
    try host.disableRawMode()

    let output = controller.writes.joined()
    #expect(!output.contains("\u{001B}[?1016$p"))
    #expect(!output.contains("\u{001B}[?1006h"))
    #expect(!output.contains("\u{001B}[?1002h"))
  }

  @Test("documented matrix fallback is suppressed inside terminal multiplexers")
  func documentedMatrixFallbackIsSuppressedInsideTerminalMultiplexers() throws {
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .trueColor,
      environment: [
        "TERM": "xterm-kitty",
        "TMUX": "/tmp/tmux-501/default,1,0",
      ]
    )

    try host.enableRawMode()
    #expect(host.pointerInputCapabilities.precision == .cell)
    try host.disableRawMode()

    #expect(!controller.writes.joined().contains("\u{001B}[?1016h"))
  }

  @Test("terminal host enables all-motion mode only when hover is active")
  func terminalHostEnablesAllMotionOnlyForHover() throws {
    let controller = GraphicsProtocolMockTerminalController(isTTY: true)
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .trueColor
    )

    try host.enableRawMode()
    try host.disableRawMode()
    #expect(!controller.writes.joined().contains("1003"))

    let hoverController = GraphicsProtocolMockTerminalController(isTTY: true)
    let hoverHost = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: hoverController,
      capabilityProfile: .trueColor
    )
    try hoverHost.setPointerHoverEnabled(true)
    try hoverHost.enableRawMode()
    try hoverHost.disableRawMode()

    let output = hoverController.writes.joined()
    #expect(output.contains("\u{001B}[?1006h\u{001B}[?1002h\u{001B}[?1003h"))
    #expect(output.contains("\u{001B}[?1003l\u{001B}[?1002l\u{001B}[?1006l"))
  }

  @Test("terminal host restores button-event reporting after hover turns off")
  func terminalHostRestoresButtonEventReportingAfterHoverTurnsOff() throws {
    let controller = GraphicsProtocolMockTerminalController(isTTY: true)
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .trueColor
    )

    try host.enableRawMode()
    try host.setPointerHoverEnabled(true)
    try host.setPointerHoverEnabled(false)
    try host.disableRawMode()

    let output = controller.writes.joined()
    #expect(output.contains("\u{001B}[?1006h\u{001B}[?1002h\u{001B}[?1003h"))
    #expect(output.contains("\u{001B}[?1003l\u{001B}[?1006h\u{001B}[?1002h"))
  }

  @Test("terminal host force-pixel policy overrides tmux safety default")
  func terminalHostForcePixelPolicyOverridesTMUXSafetyDefault() throws {
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .trueColor,
      environment: [
        "TERM": "tmux-256color",
        "TMUX": "/tmp/tmux-501/default,1,0",
      ],
      pointerPrecisionPolicy: .forceTerminalPixels
    )

    try host.enableRawMode()
    try host.disableRawMode()

    #expect(controller.writes.joined().contains("\u{001B}[?1016h"))
  }

  @Test(
    "terminal host emits Kitty PNG payloads when Kitty graphics are available")
  func terminalHostEmitsKittyPayloads() throws {
    let kittyQueryID = stableIdentifier(from: Array("stui-kitty-query".utf8))
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      readResponses: [
        Array("\u{001B}_Gi=\(kittyQueryID);OK\u{001B}\\".utf8),
        [],
      ],
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 20, height: 5),
      controller: controller,
      capabilityProfile: .trueColor
    )

    let pngBytes = try makePNGBytes(
      width: 2,
      height: 2,
      pixels: [
        rgbaPixel(red: 255, green: 0, blue: 0),
        rgbaPixel(red: 255, green: 0, blue: 0),
        rgbaPixel(red: 0, green: 0, blue: 255),
        rgbaPixel(red: 0, green: 0, blue: 255),
      ]
    )
    let surface = RasterSurface(
      size: .init(width: 4, height: 2),
      lines: ["    ", "    "],
      imageAttachments: [
        makeRasterImageAttachment(
          pngBytes: pngBytes,
          pixelSize: .init(width: 2, height: 2),
          bounds: .init(origin: .zero, size: .init(width: 3, height: 2))
        )
      ]
    )

    _ = try host.present(surface)
    try host.drainPendingPresentation()

    let kittyWrite = try #require(
      controller.writes.first { write in
        write.contains("_Ga=T")
      }
    )

    // Transmit-and-display header: action T, quiet mode 2, direct transmission,
    // PNG format, cursor pinned, with explicit cell rectangle and image id.
    #expect(kittyWrite.contains("_Ga=T,q=2,t=d,f=100,C=1,"))
    #expect(kittyWrite.contains(",c=3,r=2,"))
    // The image id is derived from the source reference.
    #expect(kittyWrite.contains(",i="))
    // Single-chunk transmissions must terminate with m=0.
    #expect(kittyWrite.contains(",m=0;"))
    // The raw RGBA direct path should no longer be used.
    #expect(!kittyWrite.contains("f=32"))
    #expect(!kittyWrite.contains(",S="))
    #expect(!kittyWrite.contains("z=-1"))
    #expect(!kittyWrite.contains(",p="))
    // Confirm we move the cursor to the attachment origin before placing the image.
    #expect(kittyWrite.contains("\u{001B}7"))
    #expect(kittyWrite.contains("\u{001B}[1;1H"))
    #expect(kittyWrite.contains("\u{001B}8"))
    // And that Sixel was not emitted instead.
    #expect(
      !controller.writes.contains { write in
        write.contains("\u{001B}P0;1;0q")
      }
    )
  }

  @Test("Kitty blended image variants replay by backdrop-aware image id")
  func kittyBlendedImageVariantsReplayByBackdropAwareImageID() throws {
    let renderer = TerminalImageRenderer(repository: ImageAssetRepository())
    let graphicsCapabilities = TerminalGraphicsCapabilities(
      supportedProtocols: [.kitty],
      preferredProtocol: .kitty,
      cellPixelSize: .init(width: 1, height: 1)
    )
    let pngBytes = try makePNGBytes(
      width: 1,
      height: 1,
      pixels: [rgbaPixel(red: 255, green: 0, blue: 0)]
    )
    var transmittedKittyImages: Set<UInt32> = []

    let firstWrite = renderer.graphicsWriteSteps(
      for: [
        blendedRasterImageAttachment(
          pngBytes: pngBytes,
          background: .blue,
          signature: 1
        )
      ],
      capabilityProfile: .trueColor,
      graphicsCapabilities: graphicsCapabilities,
      fallbackBackground: .black,
      transmittedKittyImages: &transmittedKittyImages
    ).joined()
    let stableBackdropWrite = renderer.graphicsWriteSteps(
      for: [
        blendedRasterImageAttachment(
          pngBytes: pngBytes,
          background: .blue,
          signature: 1
        )
      ],
      capabilityProfile: .trueColor,
      graphicsCapabilities: graphicsCapabilities,
      fallbackBackground: .black,
      transmittedKittyImages: &transmittedKittyImages
    ).joined()
    let changedBackdropWrite = renderer.graphicsWriteSteps(
      for: [
        blendedRasterImageAttachment(
          pngBytes: pngBytes,
          background: .red,
          signature: 2
        )
      ],
      capabilityProfile: .trueColor,
      graphicsCapabilities: graphicsCapabilities,
      fallbackBackground: .black,
      transmittedKittyImages: &transmittedKittyImages
    ).joined()

    #expect(firstWrite.contains("_Ga=T,q=2,t=d,f=32,C=1,c=1,r=1,"))
    #expect(!firstWrite.contains("_Ga=p"))
    // Blended variants ship as raw RGBA (f=32) with explicit pixel-size keys,
    // never as PNG (f=100) — the terminal skips a PNG decode per frame.
    #expect(firstWrite.contains(",s=1,v=1"))
    #expect(!firstWrite.contains("f=100"))
    #expect(stableBackdropWrite.contains("_Ga=p,q=2,C=1,c=1,r=1,i="))
    #expect(!stableBackdropWrite.contains("_Ga=T"))
    #expect(changedBackdropWrite.contains("_Ga=T,q=2,t=d,f=32,C=1,c=1,r=1,"))
  }

  @Test("Kitty blended image variants replay when backdrop glyph changes")
  func kittyBlendedImageVariantsReplayWhenBackdropGlyphChanges() throws {
    let renderer = TerminalImageRenderer(repository: ImageAssetRepository())
    let graphicsCapabilities = TerminalGraphicsCapabilities(
      supportedProtocols: [.kitty],
      preferredProtocol: .kitty,
      cellPixelSize: .init(width: 1, height: 1)
    )
    let pngBytes = try makePNGBytes(
      width: 1,
      height: 1,
      pixels: [rgbaPixel(red: 255, green: 0, blue: 0)]
    )
    var transmittedKittyImages: Set<UInt32> = []

    let firstWrite = renderer.graphicsWriteSteps(
      for: [
        blendedRasterImageAttachment(
          pngBytes: pngBytes,
          background: nil,
          foreground: .blue,
          glyph: "A",
          signature: 1
        )
      ],
      capabilityProfile: .trueColor,
      graphicsCapabilities: graphicsCapabilities,
      fallbackBackground: .black,
      transmittedKittyImages: &transmittedKittyImages
    ).joined()
    let stableGlyphWrite = renderer.graphicsWriteSteps(
      for: [
        blendedRasterImageAttachment(
          pngBytes: pngBytes,
          background: nil,
          foreground: .blue,
          glyph: "A",
          signature: 1
        )
      ],
      capabilityProfile: .trueColor,
      graphicsCapabilities: graphicsCapabilities,
      fallbackBackground: .black,
      transmittedKittyImages: &transmittedKittyImages
    ).joined()
    let changedGlyphWrite = renderer.graphicsWriteSteps(
      for: [
        blendedRasterImageAttachment(
          pngBytes: pngBytes,
          background: nil,
          foreground: .blue,
          glyph: "B",
          signature: 2
        )
      ],
      capabilityProfile: .trueColor,
      graphicsCapabilities: graphicsCapabilities,
      fallbackBackground: .black,
      transmittedKittyImages: &transmittedKittyImages
    ).joined()

    #expect(firstWrite.contains("_Ga=T,q=2,t=d,f=32,C=1,c=1,r=1,"))
    #expect(stableGlyphWrite.contains("_Ga=p,q=2,C=1,c=1,r=1,i="))
    #expect(!stableGlyphWrite.contains("_Ga=T"))
    #expect(changedGlyphWrite.contains("_Ga=T,q=2,t=d,f=32,C=1,c=1,r=1,"))
  }

  @Test("Kitty blended image replay survives renderer compositor eviction")
  func kittyBlendedImageReplaySurvivesRendererCompositorEviction() throws {
    let renderer = TerminalImageRenderer(
      repository: ImageAssetRepository(),
      blendCompositorCachePolicy: ImageBlendCompositorCachePolicy(
        maxEntries: 2,
        maxDecodedPixels: Int.max,
        maxEncodedBytes: Int.max
      )
    )
    let graphicsCapabilities = TerminalGraphicsCapabilities(
      supportedProtocols: [.kitty],
      preferredProtocol: .kitty,
      cellPixelSize: .init(width: 1, height: 1)
    )
    let pngBytes = try makePNGBytes(
      width: 1,
      height: 1,
      pixels: [rgbaPixel(red: 255, green: 0, blue: 0)]
    )
    var transmittedKittyImages: Set<UInt32> = []

    for index in 0..<3 {
      let write = renderer.graphicsWriteSteps(
        for: [
          blendedRasterImageAttachment(
            pngBytes: pngBytes,
            background: index == 0 ? .blue : index == 1 ? .red : .green,
            signature: UInt64(index + 1)
          )
        ],
        capabilityProfile: .trueColor,
        graphicsCapabilities: graphicsCapabilities,
        fallbackBackground: .black,
        transmittedKittyImages: &transmittedKittyImages
      ).joined()

      #expect(write.contains("_Ga=T,q=2,t=d,f=32,C=1,c=1,r=1,"))
    }

    let snapshot = renderer.imageBlendCacheSnapshot()
    #expect(snapshot.entryCount == 2)
    #expect(snapshot.evictionCount == 1)
    #expect(transmittedKittyImages.count == 3)
  }

  /// Drives `variantCount` distinct blended kitty variants through `renderer`
  /// (each a unique payload-cache key) and returns the resulting kitty payload
  /// occupancy. Shared by the bounded-payload-cache tests below.
  private func renderDistinctKittyVariants(
    _ variantCount: Int,
    through renderer: TerminalImageRenderer
  ) throws -> Int {
    let graphicsCapabilities = TerminalGraphicsCapabilities(
      supportedProtocols: [.kitty],
      preferredProtocol: .kitty,
      cellPixelSize: .init(width: 1, height: 1)
    )
    let pngBytes = try makePNGBytes(
      width: 1,
      height: 1,
      pixels: [rgbaPixel(red: 255, green: 0, blue: 0)]
    )
    var transmittedKittyImages: Set<UInt32> = []

    for index in 0..<variantCount {
      let write = renderer.graphicsWriteSteps(
        for: [
          blendedRasterImageAttachment(
            pngBytes: pngBytes,
            background: .blue,
            signature: UInt64(index + 1)
          )
        ],
        capabilityProfile: .trueColor,
        graphicsCapabilities: graphicsCapabilities,
        fallbackBackground: .black,
        transmittedKittyImages: &transmittedKittyImages
      ).joined()
      // Each distinct variant must build and transmit a fresh payload.
      #expect(write.contains("_Ga=T,q=2,t=d,f=32,C=1,c=1,r=1,"))
    }

    return renderer.occupancy().kitty
  }

  @Test("Renderer payload cache evicts least-recently-used variants past the entry cap")
  func rendererPayloadCacheEvictsPastEntryCap() throws {
    let renderer = TerminalImageRenderer(
      repository: ImageAssetRepository(),
      payloadCachePolicy: TerminalImageRendererCachePolicy(
        maxEntriesPerKind: 2,
        maxApproxBytesPerKind: Int.max
      )
    )
    // Three distinct variants were transmitted, but the bounded kitty payload
    // cache retains at most `maxEntriesPerKind` (2) — the oldest was evicted.
    #expect(try renderDistinctKittyVariants(3, through: renderer) == 2)
  }

  @Test("Renderer payload byte budget caps each kind to the freshest entry")
  func rendererPayloadByteBudgetCapsToFreshestEntry() throws {
    let renderer = TerminalImageRenderer(
      repository: ImageAssetRepository(),
      payloadCachePolicy: TerminalImageRendererCachePolicy(
        maxEntriesPerKind: Int.max,
        maxApproxBytesPerKind: 0
      )
    )
    // Every stored payload exceeds the zero-byte budget, so each store evicts
    // all but the just-written (protected) entry — never zero.
    #expect(try renderDistinctKittyVariants(3, through: renderer) == 1)
  }

  @Test("Default renderer payload policy retains every variant for a small workload")
  func defaultRendererPayloadPolicyRetainsSmallWorkload() throws {
    // The gate-safe guarantee: under the default policy a handful of variants
    // sit far below the budget, so nothing evicts and behavior is unchanged.
    let renderer = TerminalImageRenderer(repository: ImageAssetRepository())
    #expect(try renderDistinctKittyVariants(3, through: renderer) == 3)
  }

  @Test(
    "terminal host emits Kitty RGBA payloads (f=32 with s/v) for non-PNG inputs"
  )
  func terminalHostEmitsKittyRGBAPayloadForNonPNGInputs() throws {
    // Kitty's `f=` only supports PNG (100), RGBA (32), RGB (24). For
    // JPEG inputs the renderer must serialize the decoded pixels as raw
    // RGBA and tag the payload with `f=32` plus the pixel-size keys
    // `s=` and `v=`.
    let jpegBytes = onePixelWhiteJPEG

    let kittyQueryID = stableIdentifier(from: Array("stui-kitty-query".utf8))
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      readResponses: [
        Array("\u{001B}_Gi=\(kittyQueryID);OK\u{001B}\\".utf8),
        [],
      ],
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 20, height: 12),
      controller: controller,
      capabilityProfile: .trueColor
    )

    let surface = RasterSurface(
      size: .init(width: 20, height: 12),
      lines: Array(repeating: "                    ", count: 12),
      imageAttachments: [
        RasterImageAttachment(
          identity: testIdentity("Root", "Image"),
          bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
          visibleBounds: nil,
          source: .data(jpegBytes),
          resolvedReference: .embeddedImage(jpegBytes),
          pixelSize: .init(width: 1, height: 1),
          isResizable: false,
          scalingMode: .stretch
        )
      ]
    )

    _ = try host.present(surface)
    try host.drainPendingPresentation()

    let firstKittyWrite = try #require(
      controller.writes.first { write in
        write.contains("_Ga=T")
      }
    )

    // The transmit-and-display header must declare RGBA, not PNG, and
    // must carry the source pixel dimensions kitty needs to deserialize
    // the buffer.
    #expect(firstKittyWrite.contains("_Ga=T,q=2,t=d,f=32,C=1,"))
    #expect(firstKittyWrite.contains(",s=1,v=1,"))
    #expect(!firstKittyWrite.contains("f=100"))

    // Concatenate every base64 chunk and verify it decodes to exactly
    // width * height * 4 bytes.
    let output = controller.writes.joined()
    let graphicsChunks = chunksForKittyProtocol(in: output)
    let rootFrameChunks = graphicsChunks.filter { chunk in
      if chunk.contains("_Ga=T,") {
        return true
      }
      return chunk.contains("_Gm=")
    }
    let combined = rootFrameChunks.map(payloadForKittyChunk).joined()
    let decoded = try #require(Data(base64Encoded: combined))
    #expect(decoded.count == 4)
  }

  @Test("Kitty rendering transmits every decoded GIF frame as a distinct embedded image")
  func kittyRenderingTransmitsEveryDecodedGIFFrame() throws {
    let sequence = try AnimatedGIF.decode(
      contentsOf: repoFixturePath("Fixtures/AnimatedImage/nyan.gif"))
    let renderer = TerminalImageRenderer(repository: ImageAssetRepository())
    let graphicsCapabilities = TerminalGraphicsCapabilities(
      supportedProtocols: [.kitty],
      preferredProtocol: .kitty,
      cellPixelSize: .init(width: 8, height: 16)
    )
    var transmittedKittyImages: Set<UInt32> = []
    var writeSteps: [String] = []

    for (index, frame) in sequence.frames.enumerated() {
      let attachment = makeRasterImageAttachment(
        pngBytes: frame.imageData,
        pixelSize: frame.pixelSize,
        bounds: .init(origin: .zero, size: .init(width: 9, height: 5)),
        identity: testIdentity("Root", "NyanFrame\(index)")
      )
      writeSteps.append(
        contentsOf: renderer.graphicsWriteSteps(
          for: [attachment],
          capabilityProfile: .trueColor,
          graphicsCapabilities: graphicsCapabilities,
          fallbackBackground: .black,
          transmittedKittyImages: &transmittedKittyImages
        )
      )
    }

    let output = writeSteps.joined()
    #expect(sequence.frames.count == 12)
    #expect(countOccurrences(of: "_Ga=T", in: output) == sequence.frames.count)
    #expect(!output.contains("_Ga=p"))
  }

  @Test("kitty image placement crops source pixels for negative scroll offsets")
  func kittyImagePlacementCropsSourcePixelsForNegativeScrollOffsets() throws {
    let kittyQueryID = stableIdentifier(from: Array("stui-kitty-query".utf8))
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      readResponses: [
        Array("\u{001B}_Gi=\(kittyQueryID);OK\u{001B}\\".utf8),
        [],
      ],
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 20, height: 5),
      controller: controller,
      capabilityProfile: .trueColor
    )

    let pngBytes = try makePNGBytes(
      width: 4,
      height: 4,
      pixels: Array(repeating: rgbaPixel(red: 255, green: 255, blue: 255), count: 16)
    )

    final class ScrollBox {
      var position = ScrollPosition.zero
    }

    let box = ScrollBox()
    let view = ScrollView(
      .vertical,
      showsIndicators: false,
      position: Binding(
        get: { box.position },
        set: { box.position = $0 }
      )
    ) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Top ")
        Image(data: pngBytes)
          .resizable()
          .frame(width: 4, height: 4)
        Text("Tail")
      }
    }
    .frame(width: 4, height: 3, alignment: .topLeading)

    box.position.scrollBy(y: 2)
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("Root"))
    )
    let attachment = try #require(artifacts.rasterSurface.imageAttachments.first)

    #expect(
      attachment.bounds == .init(origin: .init(x: 0, y: -1), size: .init(width: 4, height: 4)))
    #expect(attachment.visibleBounds == .init(origin: .zero, size: .init(width: 4, height: 3)))

    _ = try host.present(artifacts.rasterSurface)
    try host.drainPendingPresentation()

    let kittyWrite = try #require(
      controller.writes.first { write in
        write.contains("_Ga=T")
      }
    )

    #expect(kittyWrite.contains("\u{001B}[1;1H"))
    #expect(kittyWrite.contains(",c=4,r=3,"))
    #expect(!kittyWrite.contains(",c=4,r=4,"))
    #expect(kittyWrite.contains(",x=0,y=1,w=4,h=3,"))
  }

  @Test("terminal host chunks Kitty PNG payloads that exceed the single-chunk limit")
  func terminalHostChunksLargeKittyPayloads() throws {
    let kittyQueryID = stableIdentifier(from: Array("stui-kitty-query".utf8))
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      readResponses: [
        Array("\u{001B}_Gi=\(kittyQueryID);OK\u{001B}\\".utf8),
        [],
      ],
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .trueColor
    )

    // Noise-filled 128x128 image: genuine PRNG entropy defeats PNG filters
    // (Sub/Up/Paeth) so the compressed payload is reliably large enough to
    // span at least three 4 KiB base64 chunks — first, at least one `m=1`
    // continuation, and the `m=0` terminator.
    var rng: UInt64 = 0x9E37_79B9_7F4A_7C15
    func nextByte() -> UInt8 {
      rng ^= rng &<< 13
      rng ^= rng &>> 7
      rng ^= rng &<< 17
      return UInt8(truncatingIfNeeded: rng)
    }
    var pixels: [PNG.RGBA<UInt8>] = []
    pixels.reserveCapacity(128 * 128)
    for _ in 0..<(128 * 128) {
      pixels.append(
        rgbaPixel(
          red: nextByte(),
          green: nextByte(),
          blue: nextByte(),
          alpha: 255
        )
      )
    }

    let pngBytes = try makePNGBytes(
      width: 128,
      height: 128,
      pixels: pixels
    )
    let surface = RasterSurface(
      size: .init(width: 40, height: 20),
      lines: Array(repeating: String(repeating: " ", count: 40), count: 20),
      imageAttachments: [
        makeRasterImageAttachment(
          pngBytes: pngBytes,
          pixelSize: .init(width: 128, height: 128),
          bounds: .init(origin: .zero, size: .init(width: 40, height: 20))
        )
      ]
    )

    _ = try host.present(surface)
    try host.drainPendingPresentation()

    let output = controller.writes.joined()

    // The first chunk must carry the full control data including the PNG
    // format key and the 40x20 cell rectangle.
    #expect(output.contains("_Ga=T,q=2,t=d,f=100,C=1,c=40,r=20,"))
    // The first chunk must advertise that more chunks follow (m=1).
    #expect(output.contains(",m=1;"))
    // Continuation chunks must use only the `m` key.
    #expect(output.contains("\u{001B}_Gm=1;"))
    // The final chunk must close the stream with m=0.
    #expect(output.contains("\u{001B}_Gm=0;"))

    // Every graphics chunk must fit inside the 4096-byte payload limit that
    // the Kitty spec sets on the base64 data per escape code.
    let graphicsChunks = chunksForKittyProtocol(in: output)
    #expect(graphicsChunks.count >= 2)
    for (index, chunk) in graphicsChunks.enumerated() {
      let payload = payloadForKittyChunk(chunk)
      #expect(payload.count <= 4096, "chunk payload exceeded 4096 bytes: \(payload.count)")
      let isLastChunk = index == graphicsChunks.count - 1
      if !isLastChunk {
        #expect(payload.count % 4 == 0, "non-final chunk payload must be a multiple of 4")
      }
    }
  }

  @Test("terminal host emits Sixel payloads when Kitty is unavailable but Sixel is supported")
  func terminalHostEmitsSixelPayloads() throws {
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      readResponses: [
        Array("\u{001B}[?4;1c".utf8),
        Array("\u{001B}[?1;0;16S".utf8),
        Array("\u{001B}[?2;0;640;480S".utf8),
      ],
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 20, height: 5),
      controller: controller,
      capabilityProfile: .ansi256
    )

    let pngBytes = try makePNGBytes(
      width: 2,
      height: 2,
      pixels: [
        rgbaPixel(red: 255, green: 0, blue: 0),
        rgbaPixel(red: 0, green: 255, blue: 0),
        rgbaPixel(red: 0, green: 0, blue: 255),
        rgbaPixel(red: 255, green: 255, blue: 255),
      ]
    )
    let surface = RasterSurface(
      size: .init(width: 2, height: 1),
      imageAttachments: [
        makeRasterImageAttachment(
          pngBytes: pngBytes,
          pixelSize: .init(width: 2, height: 2),
          bounds: .init(origin: .zero, size: .init(width: 1, height: 1))
        )
      ]
    )

    _ = try host.present(surface)
    try host.drainPendingPresentation()

    #expect(
      controller.writes.contains { write in
        write.contains("\u{001B}P0;1;0q")
      }
    )
  }

  @Test(
    "ANSI fallback compositor uses half block cells and terminal colors when graphics protocols are unavailable"
  )
  func ansiFallbackCompositorUsesHalfBlocks() throws {
    let controller = GraphicsProtocolMockTerminalController(isTTY: false)
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 10, height: 4),
      controller: controller,
      capabilityProfile: .ansi16
    )

    let pngBytes = try makePNGBytes(
      width: 1,
      height: 2,
      pixels: [
        rgbaPixel(red: 255, green: 0, blue: 0),
        rgbaPixel(red: 0, green: 0, blue: 255),
      ]
    )
    let surface = RasterSurface(
      size: .init(width: 1, height: 1),
      imageAttachments: [
        makeRasterImageAttachment(
          pngBytes: pngBytes,
          pixelSize: .init(width: 1, height: 2),
          bounds: .init(origin: .zero, size: .init(width: 1, height: 1))
        )
      ]
    )

    _ = try host.present(surface)
    try host.drainPendingPresentation()

    #expect(
      controller.writes == [
        "\u{001B}[2J\u{001B}[1;1H\u{001B}[91;104m▀\u{001B}[0m"
      ]
    )
  }

  @Test("stable Kitty image attachments replay only the rows touched by incremental text")
  func stableKittyImageAttachmentsReplayOnlyTheRowsTouchedByIncrementalText() throws {
    let kittyQueryID = stableIdentifier(from: Array("stui-kitty-query".utf8))
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      readResponses: [
        Array("\u{001B}_Gi=\(kittyQueryID);OK\u{001B}\\".utf8),
        [],
      ],
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 10, height: 4),
      controller: controller,
      capabilityProfile: .trueColor
    )

    let pngBytes = try makePNGBytes(
      width: 2,
      height: 2,
      pixels: [
        rgbaPixel(red: 255, green: 255, blue: 255),
        rgbaPixel(red: 255, green: 255, blue: 255),
        rgbaPixel(red: 255, green: 255, blue: 255),
        rgbaPixel(red: 255, green: 255, blue: 255),
      ]
    )
    let leadingAttachment = makeRasterImageAttachment(
      pngBytes: pngBytes,
      pixelSize: .init(width: 2, height: 2),
      bounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1, height: 1)),
      identity: testIdentity("Root", "LeadingImage")
    )
    let trailingAttachment = makeRasterImageAttachment(
      pngBytes: pngBytes,
      pixelSize: .init(width: 2, height: 2),
      bounds: .init(origin: .init(x: 3, y: 1), size: .init(width: 1, height: 1)),
      identity: testIdentity("Root", "TrailingImage")
    )
    let initialSurface = RasterSurface(
      size: .init(width: 4, height: 2),
      lines: ["foo ", "bar "],
      imageAttachments: [leadingAttachment, trailingAttachment]
    )
    let updatedSurface = RasterSurface(
      size: .init(width: 4, height: 2),
      lines: ["fOo ", "bar "],
      imageAttachments: [leadingAttachment, trailingAttachment]
    )

    _ = try host.present(initialSurface)
    try host.drainPendingPresentation()
    let writesBeforeIncrementalUpdate = controller.writes.count

    let metrics = try host.present(updatedSurface)
    try host.drainPendingPresentation()
    let incrementalWrites = Array(controller.writes.dropFirst(writesBeforeIncrementalUpdate))

    #expect(incrementalWrites.count == 1)
    let incrementalWrite = try #require(incrementalWrites.first)
    #expect(incrementalWrite.contains("\u{001B}[1;2HO"))
    #expect(metrics.strategy == .incremental)
    #expect(metrics.cellsChanged == 1)
    #expect(metrics.graphicsReplayScope == .targeted)
    #expect(metrics.graphicsAttachmentsReplayed == 1)
    #expect(metrics.editOperationLowering == .none)
    #expect(countOccurrences(of: "_Ga=p,q=2,C=1,c=1,r=1,i=", in: incrementalWrite) == 1)
    #expect(incrementalWrite.contains("\u{001B}[1;1H"))
    #expect(!incrementalWrite.contains("\u{001B}[2;4H"))
    #expect(!incrementalWrite.contains("_Ga=T"))
    #expect(!incrementalWrite.contains("\u{001B}P0;1;0q"))
  }

  @Test(
    "Kitty graphics full replay preserves incremental text planning when attachment bounds change")
  func kittyGraphicsFullReplayPreservesIncrementalTextPlanningWhenAttachmentBoundsChange() throws {
    let kittyQueryID = stableIdentifier(from: Array("stui-kitty-query".utf8))
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      readResponses: [
        Array("\u{001B}_Gi=\(kittyQueryID);OK\u{001B}\\".utf8),
        [],
      ],
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 10, height: 4),
      controller: controller,
      capabilityProfile: .trueColor
    )

    let pngBytes = try makePNGBytes(
      width: 2,
      height: 2,
      pixels: [
        rgbaPixel(red: 255, green: 255, blue: 255),
        rgbaPixel(red: 255, green: 255, blue: 255),
        rgbaPixel(red: 255, green: 255, blue: 255),
        rgbaPixel(red: 255, green: 255, blue: 255),
      ]
    )
    let initialAttachment = makeRasterImageAttachment(
      pngBytes: pngBytes,
      pixelSize: .init(width: 2, height: 2),
      bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
      identity: testIdentity("Root", "Image")
    )
    let movedAttachment = makeRasterImageAttachment(
      pngBytes: pngBytes,
      pixelSize: .init(width: 2, height: 2),
      bounds: .init(origin: .init(x: 0, y: 1), size: .init(width: 1, height: 1)),
      identity: testIdentity("Root", "Image")
    )
    let initialSurface = RasterSurface(
      size: .init(width: 4, height: 2),
      lines: ["    ", "    "],
      imageAttachments: [initialAttachment]
    )
    let updatedSurface = RasterSurface(
      size: .init(width: 4, height: 2),
      lines: ["    ", "    "],
      imageAttachments: [movedAttachment]
    )

    _ = try host.present(initialSurface)
    try host.drainPendingPresentation()
    let writesBeforeFullRepaintUpdate = controller.writes.count

    let metrics = try host.present(updatedSurface)
    try host.drainPendingPresentation()
    let updateWrites = Array(controller.writes.dropFirst(writesBeforeFullRepaintUpdate))

    #expect(metrics.strategy == .incremental)
    #expect(metrics.graphicsReplayScope == .full)
    #expect(metrics.graphicsAttachmentsReplayed == 1)
    #expect(updateWrites.count == 1)
    let updateWrite = try #require(updateWrites.first)
    #expect(!updateWrite.contains("\u{001B}[2J"))
    #expect(updateWrite.contains("\u{001B}_Ga=d,q=2\u{001B}\\"))
    #expect(updateWrite.contains("_Ga=p,q=2,C=1,c=1,r=1,i="))
  }

  @Test("Kitty graphics full replay deletes removed attachments without forcing a text repaint")
  func kittyGraphicsFullReplayDeletesRemovedAttachmentsWithoutTextRepaint() throws {
    let kittyQueryID = stableIdentifier(from: Array("stui-kitty-query".utf8))
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      readResponses: [
        Array("\u{001B}_Gi=\(kittyQueryID);OK\u{001B}\\".utf8),
        [],
      ],
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 10, height: 4),
      controller: controller,
      capabilityProfile: .trueColor
    )

    let pngBytes = try makePNGBytes(
      width: 2,
      height: 2,
      pixels: [
        rgbaPixel(red: 255, green: 255, blue: 255),
        rgbaPixel(red: 255, green: 255, blue: 255),
        rgbaPixel(red: 255, green: 255, blue: 255),
        rgbaPixel(red: 255, green: 255, blue: 255),
      ]
    )
    let attachment = makeRasterImageAttachment(
      pngBytes: pngBytes,
      pixelSize: .init(width: 2, height: 2),
      bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
      identity: testIdentity("Root", "Image")
    )
    let initialSurface = RasterSurface(
      size: .init(width: 4, height: 1),
      lines: ["    "],
      imageAttachments: [attachment]
    )
    let updatedSurface = RasterSurface(
      size: .init(width: 4, height: 1),
      lines: ["    "]
    )

    _ = try host.present(initialSurface)
    try host.drainPendingPresentation()
    let transmittedID = try #require(
      kittyTransmitImageID(in: Array(controller.writes).joined())
    )
    let writesBeforeUpdate = controller.writes.count

    let metrics = try host.present(updatedSurface)
    try host.drainPendingPresentation()
    let updateWrites = Array(controller.writes.dropFirst(writesBeforeUpdate))

    #expect(metrics.strategy == .incremental)
    #expect(metrics.cellsChanged == 0)
    #expect(metrics.graphicsReplayScope == .full)
    #expect(metrics.graphicsAttachmentsReplayed == 0)
    #expect(updateWrites.count == 1)
    let updateWrite = try #require(updateWrites.first)
    // The placement delete still fires, and the removed image's stored pixel
    // data is now freed (`d=I`) instead of leaking in the terminal's store.
    #expect(updateWrite.contains("\u{001B}_Ga=d,q=2\u{001B}\\"))
    #expect(updateWrite.contains("\u{001B}_Ga=d,d=I,i=\(transmittedID),q=2\u{001B}\\"))
  }

  @Test("Kitty blended-image backdrop animation frees the superseded variant's stored data")
  func kittyBlendedBackdropAnimationFreesSupersededVariantData() throws {
    let kittyQueryID = stableIdentifier(from: Array("stui-kitty-query".utf8))
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      readResponses: [
        Array("\u{001B}_Gi=\(kittyQueryID);OK\u{001B}\\".utf8),
        [],
      ],
      cellPixelSize: .init(width: 1, height: 1)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 4, height: 1),
      controller: controller,
      capabilityProfile: .trueColor
    )

    let pngBytes = try makePNGBytes(
      width: 1,
      height: 1,
      pixels: [rgbaPixel(red: 255, green: 0, blue: 0)]
    )
    func blendedSurface(
      signature: UInt64,
      background: Color
    ) -> RasterSurface {
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["    "],
        imageAttachments: [
          blendedRasterImageAttachment(
            pngBytes: pngBytes,
            background: background,
            signature: signature
          )
        ]
      )
    }

    _ = try host.present(blendedSurface(signature: 1, background: .blue))
    try host.drainPendingPresentation()
    let firstVariantID = try #require(
      kittyTransmitImageID(in: Array(controller.writes).joined())
    )
    let writesBeforeUpdate = controller.writes.count

    // The content behind the blended image changed: a new blended variant is
    // minted under a fresh kitty image id, so the previous variant's stored
    // pixels must be freed or the terminal accumulates one image per frame.
    _ = try host.present(blendedSurface(signature: 2, background: .green))
    try host.drainPendingPresentation()
    let updateWrite = Array(controller.writes.dropFirst(writesBeforeUpdate)).joined()
    let secondVariantID = try #require(kittyTransmitImageID(in: updateWrite))

    #expect(secondVariantID != firstVariantID)
    #expect(updateWrite.contains("\u{001B}_Ga=d,d=I,i=\(firstVariantID),q=2\u{001B}\\"))
    #expect(!updateWrite.contains("d=I,i=\(secondVariantID)"))
  }

  @Test("resident kitty image data survives a dropped frame so recovery can free it")
  func residentKittyImageDataSurvivesDroppedFrame() {
    var session = TerminalPresentationSession()
    session.transmittedKittyImages = [10, 20]
    session.residentKittyImageData = [10, 20]

    // A dropped frame invalidates on-screen placements (force a re-transmit) but
    // the terminal still holds the pixel data — so it stays freeable.
    session.markDroppedFrame()
    #expect(session.forceFullRepaint)
    #expect(session.transmittedKittyImages.isEmpty)
    #expect(session.residentKittyImageData == [10, 20])

    // A dropped queued frame (invalidateRetainedState) behaves the same.
    var invalidated = TerminalPresentationSession()
    invalidated.transmittedKittyImages = [10]
    invalidated.residentKittyImageData = [10]
    invalidated.invalidateRetainedState()
    #expect(invalidated.transmittedKittyImages.isEmpty)
    #expect(invalidated.residentKittyImageData == [10])

    // A full session reset drops the record (fresh writer / unknown store).
    session.reset()
    #expect(session.residentKittyImageData.isEmpty)
    #expect(session.transmittedKittyImages.isEmpty)
  }

  @Test("recovery repaint after a dropped frame frees kitty image data the drop left resident")
  func recoveryRepaintFreesResidentDataAfterDrop() throws {
    let renderer = TerminalImageRenderer(repository: ImageAssetRepository())
    let graphicsCapabilities = TerminalGraphicsCapabilities(
      supportedProtocols: [.kitty],
      preferredProtocol: .kitty,
      cellPixelSize: .init(width: 1, height: 1)
    )
    let pngBytes = try makePNGBytes(
      width: 1,
      height: 1,
      pixels: [rgbaPixel(red: 255, green: 0, blue: 0)]
    )
    let surface = RasterSurface(
      size: .init(width: 4, height: 1),
      lines: ["    "],
      imageAttachments: [
        blendedRasterImageAttachment(pngBytes: pngBytes, background: .blue, signature: 1)
      ]
    )
    let builder = TerminalHostPresentationEmissionBuilder(
      capabilityProfile: .trueColor,
      usesTerminalEditOperations: false,
      imageRenderer: renderer,
      fallbackBackground: .black,
      terminalBackgroundColor: nil
    )

    // Post-drop recovery state: placements cleared (so the frame re-transmits),
    // but an image the terminal still holds (999_999) is recorded as resident.
    var transmitted: Set<UInt32> = []
    var resident: Set<UInt32> = [999_999]
    let emission = builder.build(
      for: surface,
      plan: TerminalPresentationPlan.fullRepaint(surfaceSize: surface.size),
      graphicsCapabilities: graphicsCapabilities,
      transmittedKittyImages: &transmitted,
      residentKittyImageData: &resident
    )

    let transmittedID = try #require(kittyTransmitImageID(in: emission.output))
    #expect(transmittedID != 999_999)
    // The orphan left resident by the drop is freed; the live image is not.
    #expect(emission.output.contains("\u{001B}_Ga=d,d=I,i=999999,q=2\u{001B}\\"))
    #expect(!emission.output.contains("d=I,i=\(transmittedID)"))
    #expect(resident == [transmittedID])
    #expect(transmitted == [transmittedID])
  }

  @Test("kitty image placement crops bottom overflow so it does not paint over sibling regions")
  func kittyImagePlacementCropsBottomOverflow() throws {
    // When an ancestor (e.g. a ScrollView clip rect, or a safeAreaInset
    // toolbar) trims the bottom of an image, the rasterizer reports a
    // visibleBounds whose height is smaller than the logical bounds. The
    // host must shrink the kitty placement (c/r) to the visible rect AND
    // crop the source pixels proportionally — otherwise the image paints
    // into cells that were just rendered for whatever lives below
    // (toolbar text, a footer, etc).
    let kittyQueryID = stableIdentifier(from: Array("stui-kitty-query".utf8))
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      readResponses: [
        Array("\u{001B}_Gi=\(kittyQueryID);OK\u{001B}\\".utf8),
        [],
      ],
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 10, height: 4),
      controller: controller,
      capabilityProfile: .trueColor
    )

    let pngBytes = try makePNGBytes(
      width: 4,
      height: 4,
      pixels: Array(repeating: rgbaPixel(red: 255, green: 255, blue: 255), count: 16)
    )
    let surface = RasterSurface(
      size: .init(width: 4, height: 3),
      lines: ["    ", "    ", "    "],
      imageAttachments: [
        makeRasterImageAttachment(
          pngBytes: pngBytes,
          pixelSize: .init(width: 4, height: 4),
          bounds: .init(origin: .init(x: 0, y: 1), size: .init(width: 4, height: 4)),
          visibleBounds: .init(origin: .init(x: 0, y: 1), size: .init(width: 4, height: 2))
        )
      ]
    )

    _ = try host.present(surface)
    try host.drainPendingPresentation()

    let kittyWrite = try #require(
      controller.writes.first { write in
        write.contains("_Ga=T")
      }
    )

    // Cursor is parked at the top-left of the visible bounds.
    #expect(kittyWrite.contains("\u{001B}[2;1H"))
    // Placement matches the visible rect, not the (taller) logical rect.
    #expect(kittyWrite.contains(",c=4,r=2,"))
    #expect(!kittyWrite.contains(",c=4,r=4,"))
    // Source rect crops the bottom half of the image: 2 visible rows of 4
    // logical rows → keep the top half (h=2 of 4 source pixels). The top
    // and left edges aren't clipped, so x=0,y=0,w=4 are unchanged.
    #expect(kittyWrite.contains(",x=0,y=0,w=4,h=2,"))
  }

  @Test("kitty image placement crops right-edge overflow with a source rect")
  func kittyImagePlacementCropsRightEdgeOverflow() throws {
    let kittyQueryID = stableIdentifier(from: Array("stui-kitty-query".utf8))
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      readResponses: [
        Array("\u{001B}_Gi=\(kittyQueryID);OK\u{001B}\\".utf8),
        [],
      ],
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 10, height: 4),
      controller: controller,
      capabilityProfile: .trueColor
    )

    let pngBytes = try makePNGBytes(
      width: 4,
      height: 4,
      pixels: Array(repeating: rgbaPixel(red: 255, green: 255, blue: 255), count: 16)
    )
    let surface = RasterSurface(
      size: .init(width: 3, height: 4),
      lines: ["   ", "   ", "   ", "   "],
      imageAttachments: [
        makeRasterImageAttachment(
          pngBytes: pngBytes,
          pixelSize: .init(width: 4, height: 4),
          bounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 4, height: 4)),
          visibleBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 2, height: 4))
        )
      ]
    )

    _ = try host.present(surface)
    try host.drainPendingPresentation()

    let kittyWrite = try #require(
      controller.writes.first { write in
        write.contains("_Ga=T")
      }
    )

    #expect(kittyWrite.contains(",c=2,r=4,"))
    #expect(kittyWrite.contains(",x=0,y=0,w=2,h=4,"))
  }

  @Test(
    "graphics protocols preserve background colors in image area cells so transparent pixels show the immediate container background"
  )
  func graphicsProtocolsPreserveBackgroundColorsInImageArea() throws {
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      readResponses: [
        Array("\u{001B}[?4;1c".utf8),
        Array("\u{001B}[?1;0;16S".utf8),
        Array("\u{001B}[?2;0;640;480S".utf8),
      ],
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 10, height: 3),
      controller: controller,
      capabilityProfile: .trueColor
    )

    let pngBytes = try makePNGBytes(
      width: 2,
      height: 2,
      pixels: [
        rgbaPixel(red: 255, green: 0, blue: 0),
        rgbaPixel(red: 255, green: 0, blue: 0),
        rgbaPixel(red: 0, green: 0, blue: 255),
        rgbaPixel(red: 0, green: 0, blue: 255),
      ]
    )

    // Build a surface where image area cells have background colors,
    // mimicking ZStack { RoundedRectangle.fill(); Image() }. The cell
    // background must survive into the rendered output, otherwise
    // transparent pixels in the kitty/sixel image reveal the terminal's
    // default surface color instead of the immediate container background.
    let bgStyle = ResolvedTextStyle(
      backgroundColor: .init(
        red: 40.0 / 255.0,
        green: 40.0 / 255.0,
        blue: 40.0 / 255.0
      )
    )
    var cells: [[RasterCell]] = []
    for _ in 0..<3 {
      var row: [RasterCell] = []
      for _ in 0..<10 {
        row.append(RasterCell(character: " ", style: bgStyle))
      }
      cells.append(row)
    }

    let surface = RasterSurface(
      size: .init(width: 10, height: 3),
      cells: cells,
      imageAttachments: [
        makeRasterImageAttachment(
          pngBytes: pngBytes,
          pixelSize: .init(width: 2, height: 2),
          bounds: .init(
            origin: .init(x: 2, y: 0),
            size: .init(width: 6, height: 3)
          )
        )
      ]
    )

    _ = try host.present(surface)
    try host.drainPendingPresentation()

    // A graphics-protocol image command should be emitted.
    #expect(
      controller.writes.contains { $0.contains("\u{001B}P0;1;0q") }
    )

    // The container background color (48;2;40;40;40) must show up
    // somewhere — without this, the rest of the surface around the
    // image would be terminal default.
    let bgWrites = controller.writes.filter { write in
      write.contains("48;2;40;40;40")
    }
    #expect(!bgWrites.isEmpty)

    // And critically, the background must extend across the FULL row
    // (10 cells) — including the 6 cells inside the image rectangle.
    // Transparent pixels in the kitty/sixel image rely on those cells
    // already being painted with the container background color so
    // the image's see-through regions inherit it.
    let fullRowBg = String(repeating: " ", count: 10)
    let fullRowBgWrites = controller.writes.filter { write in
      write.contains("48;2;40;40;40") && write.contains(fullRowBg)
    }
    #expect(!fullRowBgWrites.isEmpty)
  }

  @Test(
    "fallback dithered overlay does not paint outside its visible rect onto sibling regions"
  )
  func fallbackDitheredOverlayDoesNotPaintOutsideVisibleRect() throws {
    // No graphics protocol available — the renderer takes the
    // ANSI half-block fallback path. This used to paint the full
    // logical bounds, which let a clipped image overflow into
    // adjacent siblings (e.g. the toolbar reserved by safeAreaInset).
    let controller = GraphicsProtocolMockTerminalController(isTTY: false)
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 4, height: 4),
      controller: controller,
      capabilityProfile: .trueColor
    )

    let pngBytes = try makePNGBytes(
      width: 4,
      height: 4,
      pixels: Array(repeating: rgbaPixel(red: 255, green: 0, blue: 0), count: 16)
    )
    // The image's logical bounds claim 4 rows but the parent only made
    // 2 rows visible (rows 0..<2). Rows 2..<4 are reserved for a
    // sibling region — the fallback overlay must NOT paint there.
    let surface = RasterSurface(
      size: .init(width: 4, height: 4),
      lines: ["    ", "    ", "....", "...."],
      imageAttachments: [
        makeRasterImageAttachment(
          pngBytes: pngBytes,
          pixelSize: .init(width: 4, height: 4),
          bounds: .init(origin: .zero, size: .init(width: 4, height: 4)),
          visibleBounds: .init(origin: .zero, size: .init(width: 4, height: 2))
        )
      ]
    )

    _ = try host.present(surface)
    try host.drainPendingPresentation()

    // Cell row 2 (the "....") must remain intact — the fallback overlay
    // must not have replaced its dots with half-block image cells.
    let combined = controller.writes.joined()
    #expect(combined.contains("...."))
  }

  @Test(
    "fallback dithered overlay clips horizontally to visibleBounds"
  )
  func fallbackDitheredOverlayClipsHorizontallyToVisibleBounds() throws {
    let controller = GraphicsProtocolMockTerminalController(isTTY: false)
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 4, height: 2),
      controller: controller,
      capabilityProfile: .trueColor
    )

    let pngBytes = try makePNGBytes(
      width: 4,
      height: 4,
      pixels: Array(repeating: rgbaPixel(red: 255, green: 0, blue: 0), count: 16)
    )
    // Image claims columns 0..<4 but only columns 0..<2 are visible.
    // Columns 2..<4 are reserved for a sibling — must not be painted.
    let surface = RasterSurface(
      size: .init(width: 4, height: 2),
      lines: ["..XX", "..XX"],
      imageAttachments: [
        makeRasterImageAttachment(
          pngBytes: pngBytes,
          pixelSize: .init(width: 4, height: 4),
          bounds: .init(origin: .zero, size: .init(width: 4, height: 2)),
          visibleBounds: .init(origin: .zero, size: .init(width: 2, height: 2))
        )
      ]
    )

    _ = try host.present(surface)
    try host.drainPendingPresentation()

    // The 'XX' siblings in columns 2..<4 must remain — the fallback
    // overlay must not have replaced them with half-block image cells.
    let combined = controller.writes.joined()
    #expect(combined.contains("XX"))
  }

  @Test(
    "kitty support probe still detects kitty when the terminal's first read poll comes back empty"
  )
  func kittySupportProbeIsRobustAgainstSlowFirstResponse() throws {
    // Reproduces the original non-determinism: same kitty terminal,
    // but the first read poll returns 0 bytes (the response just hasn't
    // arrived in the first 40ms window). The probe must keep polling
    // until the DA synchronizer arrives instead of giving up after one
    // empty poll, otherwise kitty silently goes undetected and the app
    // permanently falls back to the dithered half-block path for the
    // entire session.
    let kittyQueryID = stableIdentifier(from: Array("stui-kitty-query".utf8))
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      readResponses: [
        // First poll: nothing yet — terminal is still composing the response.
        [],
        // Second poll: the kitty OK + DA primary attributes arrive.
        Array("\u{001B}_Gi=\(kittyQueryID);OK\u{001B}\\\u{001B}[?62;c".utf8),
      ],
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 4, height: 2),
      controller: controller,
      capabilityProfile: .trueColor
    )

    let pngBytes = try makePNGBytes(
      width: 2,
      height: 2,
      pixels: Array(repeating: rgbaPixel(red: 255, green: 0, blue: 0), count: 4)
    )
    let surface = RasterSurface(
      size: .init(width: 4, height: 2),
      lines: ["    ", "    "],
      imageAttachments: [
        makeRasterImageAttachment(
          pngBytes: pngBytes,
          pixelSize: .init(width: 2, height: 2),
          bounds: .init(origin: .zero, size: .init(width: 3, height: 2))
        )
      ]
    )

    _ = try host.present(surface)
    try host.drainPendingPresentation()

    // Kitty payload must be transmitted, NOT the dithered half-block
    // fallback. If this fails, the probe is once again giving up on
    // the first empty poll.
    #expect(
      controller.writes.contains { write in
        write.contains("_Ga=T") && write.contains("f=100")
      }
    )
  }

  @Test(
    "kitty support probe waits for Kitty response when DA arrives first"
  )
  func kittySupportProbeWaitsForKittyResponseWhenDAArrivesFirst() throws {
    // Some terminals answer the piggybacked primary-device-attributes query
    // before the Kitty graphics query. Returning as soon as DA is visible
    // permanently caches "no Kitty" for the session and leaves image tabs on
    // the half-block fallback path.
    let kittyQueryID = stableIdentifier(from: Array("stui-kitty-query".utf8))
    let controller = GraphicsProtocolMockTerminalController(
      isTTY: true,
      readResponses: [
        Array("\u{001B}[?62;c".utf8),
        Array("\u{001B}_Gi=\(kittyQueryID);OK\u{001B}\\".utf8),
      ],
      cellPixelSize: .init(width: 8, height: 16)
    )
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 4, height: 2),
      controller: controller,
      capabilityProfile: .trueColor
    )

    let pngBytes = try makePNGBytes(
      width: 2,
      height: 2,
      pixels: Array(repeating: rgbaPixel(red: 255, green: 0, blue: 0), count: 4)
    )
    let surface = RasterSurface(
      size: .init(width: 4, height: 2),
      lines: ["    ", "    "],
      imageAttachments: [
        makeRasterImageAttachment(
          pngBytes: pngBytes,
          pixelSize: .init(width: 2, height: 2),
          bounds: .init(origin: .zero, size: .init(width: 3, height: 2))
        )
      ]
    )

    _ = try host.present(surface)
    try host.drainPendingPresentation()

    #expect(
      controller.writes.contains { write in
        write.contains("_Ga=T") && write.contains("f=100")
      }
    )
  }
}

private let onePixelWhiteJPEG: [UInt8] = [
  0xFF, 0xD8,
  0xFF, 0xE0, 0x00, 0x10,
  0x4A, 0x46, 0x49, 0x46, 0x00,
  0x01, 0x01,
  0x00,
  0x00, 0x01, 0x00, 0x01,
  0x00, 0x00,
  0xFF, 0xDB, 0x00, 0x43, 0x00,
  0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
  0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
  0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
  0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
  0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
  0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
  0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
  0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
  0xFF, 0xDB, 0x00, 0x43, 0x01,
  0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
  0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
  0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
  0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
  0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
  0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
  0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
  0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
  0xFF, 0xC0, 0x00, 0x11, 0x08,
  0x00, 0x01, 0x00, 0x01,
  0x03,
  0x01, 0x11, 0x00,
  0x02, 0x11, 0x01,
  0x03, 0x11, 0x01,
  0xFF, 0xC4, 0x00, 0x14, 0x00,
  0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00,
  0xFF, 0xC4, 0x00, 0x14, 0x01,
  0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00,
  0xFF, 0xC4, 0x00, 0x14, 0x10,
  0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00,
  0xFF, 0xC4, 0x00, 0x14, 0x11,
  0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00,
  0xFF, 0xDA, 0x00, 0x0C, 0x03,
  0x01, 0x00,
  0x02, 0x11,
  0x03, 0x11,
  0x00, 0x3F, 0x00,
  0b00000011,
  0xFF, 0xD9,
]

/// Extracts every `ESC _G ... ESC \` escape sequence from a flattened terminal
/// write stream.
private func chunksForKittyProtocol(in output: String) -> [String] {
  let startMarker: [Character] = ["\u{001B}", "_", "G"]
  let endMarker: [Character] = ["\u{001B}", "\\"]
  let characters = Array(output)
  var results: [String] = []
  var index = 0
  while index < characters.count {
    guard hasPrefix(characters, at: index, prefix: startMarker) else {
      index += 1
      continue
    }
    var scan = index + startMarker.count
    while scan < characters.count, !hasPrefix(characters, at: scan, prefix: endMarker) {
      scan += 1
    }
    guard scan < characters.count else {
      break
    }
    let endIndex = scan + endMarker.count
    results.append(String(characters[index..<endIndex]))
    index = endIndex
  }
  return results
}

private func hasPrefix(
  _ characters: [Character],
  at offset: Int,
  prefix: [Character]
) -> Bool {
  guard offset + prefix.count <= characters.count else {
    return false
  }
  for i in 0..<prefix.count where characters[offset + i] != prefix[i] {
    return false
  }
  return true
}

/// Returns the payload portion (between `;` and `ESC \`) of a Kitty escape code.
private func payloadForKittyChunk(_ chunk: String) -> String {
  guard let semicolon = chunk.firstIndex(of: ";") else {
    return ""
  }
  // Drop the trailing `ESC \` terminator, which is always the last two chars.
  let payloadStart = chunk.index(after: semicolon)
  let trailerLength = 2
  guard chunk.distance(from: payloadStart, to: chunk.endIndex) >= trailerLength else {
    return ""
  }
  let payloadEnd = chunk.index(chunk.endIndex, offsetBy: -trailerLength)
  return String(chunk[payloadStart..<payloadEnd])
}

private func countOccurrences(of needle: String, in haystack: String) -> Int {
  guard !needle.isEmpty else {
    return 0
  }

  let needleCharacters = Array(needle)
  let haystackCharacters = Array(haystack)
  guard haystackCharacters.count >= needleCharacters.count else {
    return 0
  }

  var count = 0
  for start in 0...(haystackCharacters.count - needleCharacters.count) {
    if hasPrefix(haystackCharacters, at: start, prefix: needleCharacters) {
      count += 1
    }
  }
  return count
}

private func blendedRasterImageAttachment(
  pngBytes: [UInt8],
  background: Color?,
  foreground: Color? = nil,
  glyph: Character? = nil,
  spanWidth: Int = 1,
  signature: UInt64
) -> RasterImageAttachment {
  let bounds = CellRect(origin: .zero, size: .init(width: 1, height: 1))
  var attachment = makeRasterImageAttachment(
    pngBytes: pngBytes,
    pixelSize: .init(width: 1, height: 1),
    bounds: bounds,
    identity: testIdentity("Root", "BlendedImage")
  )
  attachment.cellPixelSize = .init(width: 1, height: 1)
  attachment.compositing = RasterImageCompositing(
    blendMode: .multiply,
    destinationBackdrop: RasterImageBackdrop(
      bounds: bounds,
      cells: [
        .init(
          backgroundColor: background,
          foregroundColor: foreground,
          glyph: glyph,
          spanWidth: spanWidth
        )
      ]
    ),
    cellPixelSize: .init(width: 1, height: 1),
    backdropSignature: signature
  )
  return attachment
}

/// Extracts the `i=<id>` image id from the first kitty transmit-and-place
/// (`a=T`) control block in `output`, or nil if none is present.
private func kittyTransmitImageID(
  in output: String
) -> UInt32? {
  guard let transmitRange = output.range(of: "_Ga=T") else {
    return nil
  }
  let afterTransmit = output[transmitRange.upperBound...]
  // Control data runs up to the first `;`, which separates it from the payload.
  guard let terminator = afterTransmit.firstIndex(of: ";") else {
    return nil
  }
  let controlData = afterTransmit[..<terminator]
  guard let idRange = controlData.range(of: "i=") else {
    return nil
  }
  return UInt32(controlData[idRange.upperBound...].prefix { $0.isNumber })
}

private func repoFixturePath(
  _ name: String
) -> String {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent(name)
    .path
}

private final class GraphicsProtocolMockTerminalController:
  TerminalControlling
{
  private let isTTYValue: Bool
  private let cellPixelSizeValue: PixelSize?
  private let queuedReadResponsesStorage: LockedBox<[[UInt8]]>
  private let writesStorage = LockedBox<[String]>([])
  private let onReadStorage = LockedBox<(@Sendable () -> Void)?>(nil)

  /// Observes every `read(from:maxBytes:timeoutMilliseconds:)` call, so a
  /// test can assert WHEN the probe reads (e.g. only while the live input
  /// reader is suspended — F42).
  var onRead: (@Sendable () -> Void)? {
    get { onReadStorage.value }
    set { onReadStorage.value = newValue }
  }

  private(set) var writes: [String] {
    get { writesStorage.value }
    set { writesStorage.value = newValue }
  }

  init(
    isTTY: Bool,
    readResponses: [[UInt8]] = [],
    cellPixelSize: PixelSize? = nil
  ) {
    isTTYValue = isTTY
    cellPixelSizeValue = cellPixelSize
    queuedReadResponsesStorage = LockedBox(readResponses)
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
    cellPixelSizeValue
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
    onReadStorage.value?()
    return queuedReadResponsesStorage.withLock { queuedReadResponses in
      guard !queuedReadResponses.isEmpty else {
        return []
      }
      return queuedReadResponses.removeFirst()
    }
  }
}

/// Spy `TerminalInputSuspending`: records engagements and exposes whether a
/// suspension window is currently open, so probe reads can assert they only
/// happen inside one (F42).
private final class SpyInputSuspensionGate: TerminalInputSuspending {
  private let state = LockedBox<(engagements: Int, depth: Int)>((0, 0))

  var engagements: Int { state.value.engagements }
  var isSuspended: Bool { state.value.depth > 0 }

  func withInputSuspended<T>(_ body: () throws -> T) rethrows -> T {
    state.withLock {
      $0.engagements += 1
      $0.depth += 1
    }
    defer { state.withLock { $0.depth -= 1 } }
    return try body()
  }
}
