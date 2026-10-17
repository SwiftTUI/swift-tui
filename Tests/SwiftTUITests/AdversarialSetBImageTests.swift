// Adversarial set B, pass 3: images (271–280).
//
// An image travels from decoder to placement to one of three terminal
// routes (Kitty, Sixel, fallback cells) and to occlusion by later cells. The
// register ratifies that clip shapes clip image placements, that the scaled
// modifiers imply resizable, and that an unresolvable source measures zero
// with a runtime issue. These probes clip an image on the Sixel route, put
// transparent and black pixels through the two fallback painters, occlude
// with whitespace, order the scaling modifiers, decode a NUL-truncated file
// URL, replay GIF disposal, quantize two near colours, and pin the decoder
// edges and placement crops.
import Foundation
import SwiftTUIAnimatedImage
import SwiftTUIVendorPNG
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: images", .serialized)
struct AdversarialSetBImageTests {
  private func render<V: View>(_ view: V, _ name: String, width: Int, height: Int) -> RenderSnapshot
  {
    DefaultRenderer().render(
      view, context: .init(identity: testIdentity("SetBImage", name)),
      proposal: .init(width: width, height: height))
  }

  private func sixelRegisters(in output: String) -> Set<[Int]> {
    var registers = Set<[Int]>()
    var remainder = output[...]
    while let hash = remainder.firstIndex(of: "#") {
      let after = remainder[remainder.index(after: hash)...]
      let fields = after.prefix { $0.isNumber || $0 == ";" }
      let parts = fields.split(separator: ";").compactMap { Int($0) }
      if parts.count == 5, parts[1] == 2 { registers.insert(Array(parts[2...])) }
      remainder = after
    }
    return registers
  }

  private func sixel(
    _ attachment: RasterImageAttachment, cellPixel: PixelSize = .init(width: 8, height: 16)
  ) -> String {
    var sent: Set<UInt32> = []
    return TerminalImageRenderer(repository: ImageAssetRepository()).graphicsWriteSteps(
      for: [attachment], capabilityProfile: .trueColor,
      graphicsCapabilities: .init(
        supportedProtocols: [.sixel], preferredProtocol: .sixel, cellPixelSize: cellPixel),
      fallbackBackground: .black, transmittedKittyImages: &sent
    ).joined()
  }

  // A clipped image on the Sixel route is cropped to its visible cells, not
  // squeezed into them.
  @Test func setB271SixelCropsAClippedImage() throws {
    let png = try makePNGBytes(
      width: 2, height: 1,
      pixels: [rgbaPixel(red: 255, green: 0, blue: 0), rgbaPixel(red: 0, green: 0, blue: 255)])
    let attachment = makeRasterImageAttachment(
      pngBytes: png, pixelSize: .init(width: 2, height: 1),
      bounds: .init(origin: .zero, size: .init(width: 2, height: 1)),
      visibleBounds: .init(origin: .zero, size: .init(width: 1, height: 1)))
    let registers = sixelRegisters(in: sixel(attachment))
    withKnownIssue(
      "the Sixel payload rescales the whole image into the visible rect instead of cropping it"
    ) {
      #expect(!registers.contains { $0[2] > 50 }, "blue register present: \(registers)")
    }
    #expect(registers.contains { $0[0] > 50 }, "red register present: \(registers)")
  }

  // The half-block fallback keeps the container background under a
  // transparent half and composites a translucent pixel over it.
  @Test func setB272HalfBlockFallbackKeepsTheContainerBackground() throws {
    let png = try makePNGBytes(
      width: 1, height: 2,
      pixels: [
        rgbaPixel(red: 255, green: 0, blue: 0), rgbaPixel(red: 0, green: 0, blue: 0, alpha: 0),
      ])
    let attachment = makeRasterImageAttachment(
      pngBytes: png, pixelSize: .init(width: 1, height: 2),
      bounds: .init(origin: .zero, size: .init(width: 1, height: 1)))
    let surface = RasterSurface(
      size: .init(width: 1, height: 1),
      cells: [[RasterCell(character: " ", style: .init(backgroundColor: Color(hexRGB: 0x0000FF)))]],
      imageAttachments: [attachment])
    let prepared = TerminalImageRenderer(repository: ImageAssetRepository()).preparedSurface(
      for: surface, capabilityProfile: .trueColor, graphicsCapabilities: .none,
      fallbackBackground: .black)
    let cell = prepared.cells[0][0]
    #expect(cell.character == "▀", "\(cell)")
    #expect(cell.style?.foregroundColor?.red ?? 0 > 0.9, "\(String(describing: cell.style))")
    withKnownIssue(
      "a transparent half yields a foreground-only style, dropping the cell's own background (adjacent to STUI-1024)"
    ) {
      #expect(cell.style?.backgroundColor?.blue ?? 0 > 0.9, "\(String(describing: cell.style))")
    }
  }

  // Opaque black pixels cover the glyph beneath them on the ASCII fallback.
  @Test func setB273ASCIIFallbackCoversGlyphsUnderBlackPixels() throws {
    let png = try makePNGBytes(width: 1, height: 1, pixels: [rgbaPixel(red: 0, green: 0, blue: 0)])
    let attachment = makeRasterImageAttachment(
      pngBytes: png, pixelSize: .init(width: 1, height: 1),
      bounds: .init(origin: .zero, size: .init(width: 1, height: 1)))
    let surface = RasterSurface(
      size: .init(width: 1, height: 1), cells: [[RasterCell(character: "X")]],
      imageAttachments: [attachment])
    let prepared = TerminalImageRenderer(repository: ImageAssetRepository()).preparedSurface(
      for: surface, capabilityProfile: .previewASCII, graphicsCapabilities: .none,
      fallbackBackground: .black)
    withKnownIssue(
      "the darkest ramp glyph is a blank with no style, which the overlay treats as invisible and skips"
    ) {
      #expect(prepared.cells[0][0].character == " ", "\(prepared.cells[0][0])")
    }
    let white = try makePNGBytes(
      width: 1, height: 1, pixels: [rgbaPixel(red: 255, green: 255, blue: 255)])
    let whiteAttachment = makeRasterImageAttachment(
      pngBytes: white, pixelSize: .init(width: 1, height: 1),
      bounds: .init(origin: .zero, size: .init(width: 1, height: 1)))
    let whiteSurface = RasterSurface(
      size: .init(width: 1, height: 1), cells: [[RasterCell(character: "X")]],
      imageAttachments: [whiteAttachment])
    let whitePrepared = TerminalImageRenderer(repository: ImageAssetRepository()).preparedSurface(
      for: whiteSurface, capabilityProfile: .previewASCII, graphicsCapabilities: .none,
      fallbackBackground: .black)
    #expect(whitePrepared.cells[0][0].character != "X", "\(whitePrepared.cells[0][0])")
  }

  // Whitespace-only text painted over an image occludes nothing.
  @Test func setB274WhitespaceTextDoesNotOccludeAnImage() throws {
    let png = try makePNGBytes(
      width: 1, height: 1, pixels: [rgbaPixel(red: 255, green: 0, blue: 0)])
    let spaces = render(
      ZStack(alignment: .topLeading) {
        Image(data: png).resizable().frame(width: 3, height: 3)
        Text("   ")
      }, "spaces", width: 3, height: 3)
    let attachment = try #require(spaces.rasterSurface.imageAttachments.first)
    withKnownIssue(
      "space clusters record paint fragments, so a blank text occludes the image's first row"
    ) {
      #expect(
        attachment.unoccludedVisibleBounds == nil,
        "\(String(describing: attachment.unoccludedVisibleBounds))")
    }
    let glyph = render(
      ZStack(alignment: .topLeading) {
        Image(data: png).resizable().frame(width: 3, height: 3)
        Text("X")
      }, "glyph", width: 3, height: 3)
    let occluded = try #require(glyph.rasterSurface.imageAttachments.first)
    #expect(occluded.unoccludedVisibleBounds != nil, "a real glyph trims the image")
  }

  // `scaledToFit()` is not cancelled by a later `resizable()`: the aspect
  // ratio is kept.
  @Test func setB275ResizableAfterScaledToFitKeepsTheAspectRatio() throws {
    let png = try makePNGBytes(
      width: 32, height: 32,
      pixels: Array(repeating: rgbaPixel(red: 255, green: 0, blue: 0), count: 1024))
    let fit = render(
      Image(data: png).scaledToFit().frame(width: 6, height: 2), "fit", width: 6, height: 2)
    let fitBounds = try #require(fit.rasterSurface.imageAttachments.first?.bounds)
    #expect(fitBounds.size == CellSize(width: 4, height: 2), "\(fitBounds)")
    let reordered = render(
      Image(data: png).scaledToFit().resizable().frame(width: 6, height: 2), "reordered", width: 6,
      height: 2)
    let reorderedBounds = try #require(reordered.rasterSurface.imageAttachments.first?.bounds)
    withKnownIssue("resizable() resets the scaling mode to stretch") {
      #expect(reorderedBounds.size == CellSize(width: 4, height: 2), "\(reorderedBounds)")
    }
  }

  // A file URL with an encoded NUL names no file; it is not truncated to the
  // path before the NUL.
  @Test func setB276EncodedNULInAFileURLResolvesNothing() throws {
    let png = try makePNGBytes(
      width: 1, height: 1, pixels: [rgbaPixel(red: 255, green: 0, blue: 0)])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "setB276-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let real = directory.appendingPathComponent("real.png")
    try Data(png).write(to: real)
    let spoofed = directory.absoluteString + "real.png%00.txt"
    let snapshot = render(Image(fileURLString: spoofed), "nul", width: 4, height: 2)
    let codes = snapshot.diagnostics.runtime.issues.map(\.code)
    withKnownIssue("percent decoding emits a NUL and the C open call sees only the prefix path") {
      #expect(
        snapshot.rasterSurface.imageAttachments.allSatisfy { $0.bounds.size.width == 0 },
        "\(snapshot.rasterSurface.imageAttachments.map(\.bounds))")
      #expect(codes.contains("image.unresolvedSource"), "\(codes)")
    }
    let genuine = render(Image(fileURLString: real.absoluteString), "genuine", width: 4, height: 2)
    #expect(genuine.rasterSurface.imageAttachments.first?.bounds.size.width == 1)
  }

  // GIF "restore to previous" restores the canvas as it was before that
  // frame, including the effect of an earlier "restore to background".
  @Test func setB277GIFRestoreToPreviousUsesThePreFrameCanvas() throws {
    let gif = SetBGIFBuilder.sequence(frames: [
      .init(left: 0, width: 2, indices: [0, 0], disposal: 0),
      .init(left: 1, width: 1, indices: [1], disposal: 2),
      .init(left: 0, width: 1, indices: [0], disposal: 3),
      .init(left: 0, width: 1, indices: [0], disposal: 0),
    ])
    let sequence = try AnimatedGIF.decode(data: gif)
    try #require(sequence.frames.count == 4, "\(sequence.frames.count)")
    let red = sequence.frames[0].pixels[0]
    #expect(sequence.frames[1].pixels[1] != red, "frame 1 draws blue at x = 1")
    withKnownIssue(
      "restore-to-previous reinstates the snapshot taken before the background-disposed frame (STUI-1010)"
    ) {
      #expect(sequence.frames[3].pixels[1] != red, "\(sequence.frames[3].pixels)")
    }
  }

  // Two distinct dark greys stay distinct under a 256-register Sixel budget.
  @Test func setB278SixelKeepsTwoNearColoursDistinct() throws {
    let png = try makePNGBytes(
      width: 2, height: 1,
      pixels: [rgbaPixel(red: 0, green: 0, blue: 0), rgbaPixel(red: 15, green: 15, blue: 15)])
    let attachment = makeRasterImageAttachment(
      pngBytes: png, pixelSize: .init(width: 2, height: 1),
      bounds: .init(origin: .zero, size: .init(width: 2, height: 1)))
    let registers = sixelRegisters(in: sixel(attachment, cellPixel: .init(width: 1, height: 1)))
    withKnownIssue("the adaptive palette buckets colours by 16 and averages each bucket") {
      #expect(registers.count == 2, "\(registers)")
    }
    let far = try makePNGBytes(
      width: 2, height: 1,
      pixels: [rgbaPixel(red: 0, green: 0, blue: 0), rgbaPixel(red: 255, green: 255, blue: 255)])
    let farAttachment = makeRasterImageAttachment(
      pngBytes: far, pixelSize: .init(width: 2, height: 1),
      bounds: .init(origin: .zero, size: .init(width: 2, height: 1)))
    #expect(
      sixelRegisters(in: sixel(farAttachment, cellPixel: .init(width: 1, height: 1))).count == 2)
  }

  // Broken image data measures zero with one unresolved-source issue and
  // never traps.
  @Test func setB279BrokenImageDataIsReportedNotTrapped() throws {
    let png = try makePNGBytes(
      width: 2, height: 2, pixels: Array(repeating: rgbaPixel(red: 1, green: 2, blue: 3), count: 4))
    for (name, bytes) in [
      ("truncated", Array(png.prefix(png.count / 2))), ("garbage", [0x89, 0x50, 0x4E, 0x47, 0x00]),
      ("empty", []),
    ] {
      let snapshot = render(Image(data: bytes), name, width: 4, height: 2)
      let issues = snapshot.diagnostics.runtime.issues.filter {
        $0.code == "image.unresolvedSource"
      }
      #expect(issues.count == 1, "\(name): \(snapshot.diagnostics.runtime.issues.map(\.code))")
      #expect(
        snapshot.measuredTree.measuredSize == .zero,
        "\(name): \(snapshot.measuredTree.measuredSize)")
    }
    let good = render(Image(data: png), "intact", width: 4, height: 2)
    #expect(good.diagnostics.runtime.issues.filter { $0.code == "image.unresolvedSource" }.isEmpty)
    #expect(
      good.measuredTree.measuredSize == CellSize(width: 1, height: 1),
      "\(good.measuredTree.measuredSize)")
  }

  // A zero-height fit measures zero, and a horizontal scroll viewport crops
  // the placement to its visible cells.
  @Test func setB280ZeroHeightFitAndScrollCropsAgreeWithTheirPlacement() throws {
    let square = try makePNGBytes(
      width: 32, height: 32,
      pixels: Array(repeating: rgbaPixel(red: 9, green: 9, blue: 9), count: 1024))
    let flat = render(Image(data: square).scaledToFit(), "flat", width: 4, height: 0)
    #expect(flat.measuredTree.measuredSize == .zero, "\(flat.measuredTree.measuredSize)")
    var sent: Set<UInt32> = []
    let steps = TerminalImageRenderer(repository: ImageAssetRepository()).graphicsWriteSteps(
      for: flat.rasterSurface.imageAttachments, capabilityProfile: .trueColor,
      graphicsCapabilities: .init(
        supportedProtocols: [.kitty], preferredProtocol: .kitty,
        cellPixelSize: .init(width: 8, height: 16)),
      fallbackBackground: .black, transmittedKittyImages: &sent)
    #expect(steps.isEmpty, "\(steps.count)")

    let strip = try makePNGBytes(
      width: 4, height: 1, pixels: Array(repeating: rgbaPixel(red: 1, green: 1, blue: 1), count: 4))
    let scrolled = render(
      ScrollView(.horizontal) { Image(data: strip).resizable().frame(width: 20, height: 1) }
        .scrollIndicators(.hidden),
      "scrolled", width: 5, height: 1)
    let attachment = try #require(scrolled.rasterSurface.imageAttachments.first)
    #expect(attachment.bounds.size == CellSize(width: 20, height: 1), "\(attachment.bounds)")
    #expect(
      attachment.visibleBounds.size == CellSize(width: 5, height: 1), "\(attachment.visibleBounds)")
  }
}

/// Builds a two-pixel-wide GIF89a with a four-entry global colour table
/// (red, blue, green, black) and one-row frames encoded by hand.
private enum SetBGIFBuilder {
  struct Frame {
    var left: Int
    var width: Int
    var indices: [Int]
    var disposal: Int
  }

  static func sequence(frames: [Frame]) -> [UInt8] {
    var bytes: [UInt8] = Array("GIF89a".utf8)
    bytes += [0x02, 0x00, 0x01, 0x00, 0xF1, 0x02, 0x00]
    bytes += [0xFF, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00]
    for frame in frames {
      bytes += [0x21, 0xF9, 0x04, UInt8(frame.disposal << 2), 0x0A, 0x00, 0x00, 0x00]
      bytes += [
        0x2C, UInt8(frame.left), 0x00, 0x00, 0x00, UInt8(frame.width), 0x00, 0x01, 0x00, 0x00,
      ]
      bytes += [0x02]
      let a = frame.indices[0]
      if frame.indices.count == 1 {
        bytes += [0x02, UInt8(0x44 | (a << 3)), 0x01, 0x00]
      } else {
        let b = frame.indices[1]
        bytes += [0x02, UInt8(4 | (a << 3) | ((b & 3) << 6)), UInt8((b >> 2) | 0x0A), 0x00]
      }
    }
    bytes += [0x3B]
    return bytes
  }
}
