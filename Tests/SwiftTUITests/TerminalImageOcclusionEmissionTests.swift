import SwiftTUIVendorPNG
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// End-to-end pin for the palette-over-image break: kitty placements float
/// above every text cell, so when a frame's attachments gain an occlusion
/// trim (a presentation was painted over the image), the host must delete
/// the visible placements and re-place only the unoccluded rect — or
/// nothing at all when the image is fully covered.
@MainActor
@Suite
struct TerminalImageOcclusionEmissionTests {
  @Test("an occlusion trim replays placements cropped, deleting the stale ones")
  func occlusionTrimReplaysPlacementsCropped() throws {
    let kittyQueryID = stableIdentifier(from: Array("stui-kitty-query".utf8))
    let controller = OcclusionEmissionMockTerminalController(
      readResponses: [
        Array("\u{001B}_Gi=\(kittyQueryID);OK\u{001B}\\".utf8),
        [],
      ]
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
    let attachment = makeRasterImageAttachment(
      pngBytes: pngBytes,
      pixelSize: .init(width: 2, height: 2),
      bounds: .init(origin: .zero, size: .init(width: 3, height: 2))
    )

    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 2),
        lines: ["    ", "    "],
        imageAttachments: [attachment]
      )
    )
    try host.drainPendingPresentation()
    #expect(
      controller.writes.contains { $0.contains("_Ga=T") },
      "the first frame must transmit and place the image"
    )

    // A palette row now covers the image's bottom row; rasterization would
    // have recorded that as an occlusion trim on the same attachment.
    var trimmedAttachment = attachment
    trimmedAttachment.unoccludedVisibleBounds = CellRect(
      origin: .zero, size: .init(width: 3, height: 1))
    let writesBeforeTrim = controller.writes.count
    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 2),
        lines: ["    ", "pal "],
        imageAttachments: [trimmedAttachment]
      )
    )
    try host.drainPendingPresentation()
    let trimWrites = controller.writes[writesBeforeTrim...]

    #expect(
      trimWrites.contains { $0.contains("\u{001B}_Ga=d,q=2\u{001B}\\") },
      "the stale full-height placement must be deleted"
    )
    let replacement = try #require(
      trimWrites.first { $0.contains("_Ga=p") || $0.contains("_Ga=T") },
      "the unoccluded rows must be re-placed"
    )
    #expect(replacement.contains(",c=3,r=1,"))

    // The palette now covers the image entirely: placements are deleted and
    // nothing is re-placed.
    var coveredAttachment = attachment
    coveredAttachment.unoccludedVisibleBounds = CellRect(origin: .zero, size: .zero)
    let writesBeforeCover = controller.writes.count
    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 2),
        lines: ["pal ", "pal "],
        imageAttachments: [coveredAttachment]
      )
    )
    try host.drainPendingPresentation()
    let coverWrites = controller.writes[writesBeforeCover...]

    #expect(
      coverWrites.contains { $0.contains("\u{001B}_Ga=d,q=2\u{001B}\\") },
      "covering the image must delete its placement"
    )
    #expect(
      !coverWrites.contains { $0.contains("_Ga=p") || $0.contains("_Ga=T") },
      "a fully covered image must not be re-placed"
    )
  }

  @Test("a sheet presented over an image trims its attachment in the composed pipeline")
  func sheetOverImageTrimsAttachmentInComposedPipeline() throws {
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

    let artifacts = DefaultRenderer().render(
      Image(data: pngBytes)
        .resizable()
        .frame(width: 42, height: 10)
        .sheet(isPresented: .constant(true)) {
          Text("Palette")
        }
        .frame(width: 42, height: 10, alignment: .topLeading),
      context: .init(identity: testIdentity("SheetOverImage")),
      proposal: .init(width: 42, height: 10)
    )

    let attachment = try #require(artifacts.rasterSurface.imageAttachments.first)
    let unoccluded = try #require(
      attachment.unoccludedVisibleBounds,
      "the sheet's surface cells must occlude the image beneath it"
    )
    let visibleArea = attachment.visibleBounds.size.width * attachment.visibleBounds.size.height
    let unoccludedArea = unoccluded.size.width * unoccluded.size.height
    #expect(unoccludedArea < visibleArea)
  }
}

private final class OcclusionEmissionMockTerminalController: TerminalControlling {
  private let queuedReadResponsesStorage: LockedBox<[[UInt8]]>
  private let writesStorage = LockedBox<[String]>([])

  var writes: [String] {
    writesStorage.value
  }

  init(readResponses: [[UInt8]]) {
    queuedReadResponsesStorage = LockedBox(readResponses)
  }

  func isATTY(_: Int32) -> Bool {
    true
  }

  func getAttributes(from _: Int32) throws -> termios {
    termios()
  }

  func setAttributes(_: termios, on _: Int32) throws {}

  func windowSize(of _: Int32) throws -> CellSize {
    .init(width: 80, height: 24)
  }

  func cellPixelSize(of _: Int32) throws -> PixelSize? {
    .init(width: 8, height: 16)
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
