import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

@Suite
struct TerminalImageKittyPayloadTests {
  // MARK: - Chunked base64 encoding

  @Test(
    "chunked base64 matches Foundation encoding across boundary sizes",
    arguments: [0, 1, 2, 3, 4, 3070, 3071, 3072, 3073, 6144, 6145, 10_000]
  )
  func chunkedBase64MatchesFoundationEncoding(byteCount: Int) {
    let bytes = (0..<byteCount).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }
    let chunks = base64EncodedChunks(bytes)
    #expect(chunks.joined() == Data(bytes).base64EncodedString())
  }

  @Test("chunks respect the kitty size cap and quartet alignment")
  func chunksRespectSizeCapAndQuartetAlignment() {
    // 9000 bytes -> 12000 base64 characters -> 4096 + 4096 + 3808.
    let chunks = base64EncodedChunks([UInt8](repeating: 0xAB, count: 9_000))
    #expect(chunks.count == 3)
    for (index, chunk) in chunks.enumerated() {
      #expect(!chunk.isEmpty)
      #expect(chunk.utf8.count <= kittyPayloadChunkByteLimit)
      if index + 1 < chunks.count {
        #expect(chunk.utf8.count == kittyPayloadChunkByteLimit)
        #expect(chunk.utf8.count.isMultiple(of: 4))
      }
    }
  }

  @Test("an exactly chunk-sized encoding produces one full chunk and no empty tail")
  func exactChunkBoundaryProducesNoEmptyTail() {
    // 3072 bytes encode to exactly 4096 characters.
    let chunks = base64EncodedChunks([UInt8](repeating: 0x11, count: 3_072))
    #expect(chunks.count == 1)
    #expect(chunks[0].utf8.count == kittyPayloadChunkByteLimit)
  }

  @Test("empty payloads produce no chunks and no transmit commands")
  func emptyPayloadsProduceNoTransmitCommands() {
    #expect(base64EncodedChunks([]).isEmpty)
    let payload = KittyPayload(encodedChunks: [], format: .png)
    #expect(
      kittyTransmitAndPlaceCommands(
        payload: payload,
        imageID: 7,
        cellColumns: 1,
        cellRows: 1,
        sourceRect: nil
      ).isEmpty
    )
  }

  // MARK: - RGBA transmit size policy

  @Test("PNG payloads keep their native pixel size")
  func pngPayloadsKeepNativePixelSize() {
    let size = kittyRGBATransmitSize(
      imagePixelSize: .init(width: 4_000, height: 3_000),
      encodedFormat: .png,
      placementCellSize: .init(width: 10, height: 5),
      cellPixelSize: .init(width: 8, height: 16)
    )
    #expect(size.width == 4_000)
    #expect(size.height == 3_000)
  }

  @Test("RGBA transmit size caps at the placement footprint, preserving aspect")
  func rgbaTransmitSizeCapsAtPlacementFootprint() {
    // 40x20 cells at 10x20 px/cell -> a 400x400 target for a 4000x3000
    // source. Scale-to-fill pins the height axis at 400 and keeps the
    // width proportional so neither axis drops below display resolution.
    let size = kittyRGBATransmitSize(
      imagePixelSize: .init(width: 4_000, height: 3_000),
      encodedFormat: .jpeg,
      placementCellSize: .init(width: 40, height: 20),
      cellPixelSize: .init(width: 10, height: 20)
    )
    #expect(size.width == 533)
    #expect(size.height == 400)
  }

  @Test("RGBA transmit size never upscales")
  func rgbaTransmitSizeNeverUpscales() {
    let size = kittyRGBATransmitSize(
      imagePixelSize: .init(width: 32, height: 16),
      encodedFormat: .jpeg,
      placementCellSize: .init(width: 40, height: 20),
      cellPixelSize: .init(width: 10, height: 20)
    )
    #expect(size.width == 32)
    #expect(size.height == 16)
  }

  @Test("unreported cell metrics fall back to the sixel path's 8x16 assumption")
  func unreportedCellMetricsUseAssumedCellSize() {
    // 10x5 cells at the assumed 8x16 -> an 80x80 target from an 800x800 source.
    let size = kittyRGBATransmitSize(
      imagePixelSize: .init(width: 800, height: 800),
      encodedFormat: .jpeg,
      placementCellSize: .init(width: 10, height: 5),
      cellPixelSize: nil
    )
    #expect(size.width == 80)
    #expect(size.height == 80)
  }

  // MARK: - Payload construction

  @Test("JPEG payloads downsample to the requested RGBA output size")
  func jpegPayloadsDownsampleToRequestedOutputSize() throws {
    let image = DecodedImage(
      encodedBytes: [0xFF, 0xD8],
      encodedFormat: .jpeg,
      pixelSize: .init(width: 64, height: 48),
      pixels: (0..<(64 * 48)).map { index in
        RGBAImagePixel(red: index % 256, green: 0, blue: 0, alpha: 5)
      }
    )
    let payload = try #require(
      makeKittyPayload(for: image, rgbaOutputSize: .init(width: 16, height: 12))
    )
    guard case .rgba(let pixelSize) = payload.format else {
      Issue.record("expected an RGBA payload for JPEG input")
      return
    }
    #expect(pixelSize.width == 16)
    #expect(pixelSize.height == 12)
    let decoded = try #require(Data(base64Encoded: payload.encodedChunks.joined()))
    #expect(decoded.count == 16 * 12 * 4)
    // Low-alpha pixels survive the resample: the cell-fallback sampler
    // drops near-transparent pixels, but raw RGBA payloads must not.
    #expect(decoded[3] == 5)
  }

  @Test("JPEG payloads at native size ship the decoded pixels untouched")
  func jpegPayloadsAtNativeSizeShipDecodedPixels() throws {
    let image = DecodedImage(
      encodedBytes: [0xFF, 0xD8],
      encodedFormat: .jpeg,
      pixelSize: .init(width: 2, height: 1),
      pixels: [
        RGBAImagePixel(red: 1, green: 2, blue: 3, alpha: 4),
        RGBAImagePixel(red: 5, green: 6, blue: 7, alpha: 8),
      ]
    )
    let payload = try #require(makeKittyPayload(for: image))
    guard case .rgba(let pixelSize) = payload.format else {
      Issue.record("expected an RGBA payload for JPEG input")
      return
    }
    #expect(pixelSize.width == 2)
    #expect(pixelSize.height == 1)
    let decoded = try #require(Data(base64Encoded: payload.encodedChunks.joined()))
    #expect(Array(decoded) == [1, 2, 3, 4, 5, 6, 7, 8])
  }

  @Test("scaledRGBAPixels preserves fully transparent pixels")
  func scaledRGBAPixelsPreservesTransparentPixels() {
    let image = DecodedImage(
      encodedBytes: [0xFF, 0xD8],
      encodedFormat: .jpeg,
      pixelSize: .init(width: 4, height: 4),
      pixels: (0..<16).map { _ in RGBAImagePixel(red: 9, green: 9, blue: 9, alpha: 0) }
    )
    let scaled = scaledRGBAPixels(from: image, outputSize: .init(width: 2, height: 2))
    #expect(scaled.count == 4)
    #expect(scaled.allSatisfy { $0.alpha == 0 })
  }

  // MARK: - Image id geometry coupling

  @Test("downsampled RGBA transmissions mint distinct kitty image ids")
  func downsampledTransmissionsMintDistinctImageIDs() {
    let reference = ImageAssetReference.embeddedImage([1, 2, 3])
    let nativeID = kittyImageID(reference: reference)
    let scaledID = kittyImageID(
      reference: reference,
      rgbaTransmitSize: .init(width: 320, height: 200)
    )
    let otherScaleID = kittyImageID(
      reference: reference,
      rgbaTransmitSize: .init(width: 640, height: 400)
    )
    #expect(nativeID != scaledID)
    #expect(scaledID != otherScaleID)
    #expect(
      kittyVariantImageID(variantID: "v1")
        != kittyVariantImageID(
          variantID: "v1",
          rgbaTransmitSize: .init(width: 320, height: 200)
        )
    )
  }
}
