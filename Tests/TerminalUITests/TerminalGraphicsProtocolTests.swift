import Foundation
import PNG
import Testing

@testable import Core
@testable import TerminalUI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@MainActor
@Suite
struct TerminalGraphicsProtocolTests {
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

  @Test(
    "terminal host emits Kitty RGBA payloads (f=32 with s/v) for non-PNG inputs"
  )
  func terminalHostEmitsKittyRGBAPayloadForNonPNGInputs() throws {
    // Kitty's `f=` only supports PNG (100), RGBA (32), RGB (24). For
    // GIF or JPEG inputs the renderer must serialize the decoded
    // pixels as raw RGBA and tag the payload with `f=32` plus the
    // pixel-size keys `s=` and `v=`. This test pins that contract using
    // the repo's nyan.gif fixture.
    let packageRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let gifURL = packageRoot.appendingPathComponent("nyan.gif")
    let gifBytes = try [UInt8](Data(contentsOf: gifURL))
    // Sanity: nyan.gif logical screen is 70x70.
    #expect(gifBytes.count > 0)

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

    // 70x70 pixels at an 8x16 cell pixel size is roughly ceil(70/8)=9 cells
    // wide and ceil(70/16)=5 cells tall — this drives the intrinsic-size
    // placement that the renderer would compute for an unframed Image.
    let surface = RasterSurface(
      size: .init(width: 20, height: 12),
      lines: Array(repeating: "                    ", count: 12),
      imageAttachments: [
        RasterImageAttachment(
          identity: testIdentity("Root", "Image"),
          bounds: .init(origin: .zero, size: .init(width: 9, height: 5)),
          visibleBounds: nil,
          source: .data(gifBytes),
          resolvedReference: .embeddedImage(gifBytes),
          pixelSize: .init(width: 70, height: 70),
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
    #expect(firstKittyWrite.contains(",s=70,v=70,"))
    #expect(!firstKittyWrite.contains("f=100"))

    // Concatenate every base64 chunk that belongs to the *root frame*
    // transmit (`a=T` + plain `_Gm=` continuations) and verify it
    // decodes to exactly width * height * 4 bytes — proof the first
    // frame is a complete RGBA buffer rather than truncating mid-
    // stream. Animation frames live in separate `a=f` envelopes that
    // we exclude here; their bytes are checked in the animation test.
    let output = controller.writes.joined()
    let graphicsChunks = chunksForKittyProtocol(in: output)
    let rootFrameChunks = graphicsChunks.filter { chunk in
      // a=T = first chunk of root frame; _Gm= without a=f = its
      // continuations. _Gm=...,a=f belongs to additional frames.
      if chunk.contains("_Ga=T,") {
        return true
      }
      return chunk.contains("_Gm=") && !chunk.contains(",a=f;")
    }
    let combined = rootFrameChunks.map(payloadForKittyChunk).joined()
    let decoded = try #require(Data(base64Encoded: combined))
    #expect(decoded.count == 70 * 70 * 4)
  }

  @Test(
    "terminal host transmits all GIF frames and starts kitty animation loop"
  )
  func terminalHostTransmitsAnimationFramesAndStartsLoop() throws {
    // Multi-frame GIFs must surface every frame to kitty via `a=f`
    // (after the initial `a=T` for the root frame), set the root-frame
    // gap via `a=a,r=1,z=...`, and start the animation loop with
    // `a=a,s=3,v=1`. nyan.gif has 12 frames at the GIF89a level.
    let packageRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let gifURL = packageRoot.appendingPathComponent("nyan.gif")
    let gifBytes = try [UInt8](Data(contentsOf: gifURL))

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
          bounds: .init(origin: .zero, size: .init(width: 9, height: 5)),
          visibleBounds: nil,
          source: .data(gifBytes),
          resolvedReference: .embeddedImage(gifBytes),
          pixelSize: .init(width: 70, height: 70),
          isResizable: false,
          scalingMode: .stretch
        )
      ]
    )

    _ = try host.present(surface)
    try host.drainPendingPresentation()

    let output = controller.writes.joined()
    let graphicsChunks = chunksForKittyProtocol(in: output)

    // Each `a=f` first-chunk has the X=1 (replace) composition mode
    // and the f=32 RGBA payload tag. Count distinct first-chunks.
    let additionalFrameStarts = graphicsChunks.filter { chunk in
      chunk.contains("_Ga=f,") && chunk.contains(",X=1,") && chunk.contains(",f=32,")
    }
    // nyan.gif has 12 frames total: 1 root (a=T) + 11 follow-up frames.
    #expect(additionalFrameStarts.count == 11)

    // The root-frame gap control must precede the animation start so
    // the loop honors frame 1's display duration.
    let rootGapCommand = graphicsChunks.first { chunk in
      chunk.contains("_Ga=a,") && chunk.contains(",r=1,") && chunk.contains(",z=")
    }
    #expect(rootGapCommand != nil)

    // Animation start: loop normally (s=3) infinitely (v=1).
    let animationStart = graphicsChunks.first { chunk in
      chunk.contains("_Ga=a,") && chunk.contains(",s=3,") && chunk.contains(",v=1")
    }
    #expect(animationStart != nil)
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
    #expect(updateWrite == "\u{001B}_Ga=d,q=2\u{001B}\\")
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

    // The container background colour (48;2;40;40;40) must show up
    // somewhere — without this, the rest of the surface around the
    // image would be terminal default.
    let bgWrites = controller.writes.filter { write in
      write.contains("48;2;40;40;40")
    }
    #expect(!bgWrites.isEmpty)

    // And critically, the background must extend across the FULL row
    // (10 cells) — including the 6 cells inside the image rectangle.
    // Transparent pixels in the kitty/sixel image rely on those cells
    // already being painted with the container background colour so
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
}

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

private final class GraphicsProtocolMockTerminalController:
  TerminalControlling
{
  private let isTTYValue: Bool
  private let cellPixelSizeValue: Size?
  private let queuedReadResponsesStorage: LockedBox<[[UInt8]]>
  private let writesStorage = LockedBox<[String]>([])

  private(set) var writes: [String] {
    get { writesStorage.value }
    set { writesStorage.value = newValue }
  }

  init(
    isTTY: Bool,
    readResponses: [[UInt8]] = [],
    cellPixelSize: Size? = nil
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

  func windowSize(of _: Int32) throws -> Size {
    .init(width: 80, height: 24)
  }

  func cellPixelSize(of _: Int32) throws -> Size? {
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
    queuedReadResponsesStorage.withLock { queuedReadResponses in
      guard !queuedReadResponses.isEmpty else {
        return []
      }
      return queuedReadResponses.removeFirst()
    }
  }
}
