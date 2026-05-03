import Foundation
import Testing

@testable import Core
@testable import SwiftTUI
@testable import View

@MainActor
@Suite
struct ImageSurfaceTests {
  @Test("embedded PNG bytes resolve into a raster image attachment")
  func embeddedImageBytesResolveIntoAttachment() throws {
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

    let artifacts = DefaultRenderer().render(
      Image(data: pngBytes)
    )
    let attachment = try #require(artifacts.rasterSurface.imageAttachments.first)

    #expect(artifacts.rasterSurface.imageAttachments.count == 1)
    #expect(attachment.source == .data(pngBytes))
    #expect(attachment.resolvedReference == .embeddedImage(pngBytes))
    #expect(attachment.pixelSize == .init(width: 2, height: 2))
    #expect(attachment.bounds.size == .init(width: 1, height: 1))
  }

  @Test("embedded GIF bytes do not resolve through the core Image surface")
  func embeddedGIFBytesDoNotResolveThroughCoreImageSurface() {
    let artifacts = DefaultRenderer().render(
      Image(data: Self.singlePixelGIF)
    )

    #expect(artifacts.rasterSurface.imageAttachments.isEmpty)
  }

  @Test("named image resources resolve through explicit imageResourceRoots")
  func namedImageResourcesResolveThroughEnvironmentRoots() throws {
    let pngBytes = try makePNGBytes(
      width: 16,
      height: 16,
      pixels: Array(repeating: rgbaPixel(red: 255, green: 255, blue: 255), count: 256)
    )
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let nested = root.appendingPathComponent("icons", isDirectory: true)
    let fileURL = nested.appendingPathComponent("logo.png")

    try FileManager.default.createDirectory(
      at: nested,
      withIntermediateDirectories: true
    )
    try Data(pngBytes).write(to: fileURL)
    defer {
      try? FileManager.default.removeItem(at: root)
    }

    let artifacts = DefaultRenderer().render(
      Image(path: "icons/logo.png")
        .environment(\.imageResourceRoots, [root.path])
    )
    let attachment = try #require(artifacts.rasterSurface.imageAttachments.first)

    #expect(attachment.resolvedReference == .filePath(fileURL.path))
    #expect(attachment.pixelSize == .init(width: 16, height: 16))
    #expect(attachment.bounds.size == .init(width: 2, height: 1))
  }

  @Test("Label supports SwiftUI-style image convenience")
  func labelImageConvenienceResolvesThroughEnvironmentRoots() throws {
    let pngBytes = try makePNGBytes(
      width: 16,
      height: 16,
      pixels: Array(repeating: rgbaPixel(red: 255, green: 255, blue: 255), count: 256)
    )
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let nested = root.appendingPathComponent("icons", isDirectory: true)
    let fileURL = nested.appendingPathComponent("label.png")

    try FileManager.default.createDirectory(
      at: nested,
      withIntermediateDirectories: true
    )
    try Data(pngBytes).write(to: fileURL)
    defer {
      try? FileManager.default.removeItem(at: root)
    }

    let artifacts = DefaultRenderer().render(
      Label("Brand", image: Image(path: "icons/label.png"))
        .environment(\.imageResourceRoots, [root.path]),
      context: .init(identity: testIdentity("Label", "Image"))
    )
    let attachment = try #require(artifacts.rasterSurface.imageAttachments.first)

    #expect(artifacts.rasterSurface.imageAttachments.count == 1)
    #expect(attachment.resolvedReference == .filePath(fileURL.path))
    #expect(resolvedNodeLabelText(from: artifacts.resolvedTree) == "Brand")
  }

  @Test("file URL images percent decode local paths without Foundation in the runtime")
  func fileURLImagesPercentDecodeLocalPaths() throws {
    let pngBytes = try makePNGBytes(
      width: 8,
      height: 8,
      pixels: Array(repeating: rgbaPixel(red: 0, green: 0, blue: 0), count: 64)
    )
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileURL = root.appendingPathComponent("space image.png")

    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    try Data(pngBytes).write(to: fileURL)
    defer {
      try? FileManager.default.removeItem(at: root)
    }

    let artifacts = DefaultRenderer().render(
      Image(fileURL: fileURL.absoluteString)
    )
    let attachment = try #require(artifacts.rasterSurface.imageAttachments.first)

    #expect(attachment.resolvedReference == .filePath(fileURL.path))
    #expect(attachment.pixelSize == .init(width: 8, height: 8))
    #expect(attachment.bounds.size == .init(width: 1, height: 1))
  }

  @Test("scaledToFit and scaledToFill preserve image aspect ratios during layout")
  func scaledToFitAndFillPreserveAspectRatios() throws {
    // 32x32 pixels is a multiple of the 8x16 default cell grid, so the
    // pixel-space aspect math used for .scaledToFit() / .scaledToFill()
    // produces exact integer cell counts with no rounding drift.
    //
    // In terminal pixels the source is square (32x32), and we lay it out
    // in a 6x2 frame that measures 48x32 pixels. That frame is 3:2 in
    // pixels, so a fit collapses to the height axis and a fill expands
    // beyond the width axis.
    let pngBytes = try makePNGBytes(
      width: 32,
      height: 32,
      pixels: Array(repeating: rgbaPixel(red: 255, green: 255, blue: 255), count: 32 * 32)
    )

    let fitArtifacts = DefaultRenderer().render(
      Image(data: pngBytes)
        .scaledToFit()
        .frame(width: 6, height: 2)
    )
    let fillArtifacts = DefaultRenderer().render(
      Image(data: pngBytes)
        .scaledToFill()
        .frame(width: 6, height: 2)
    )

    let fitAttachment = try #require(fitArtifacts.rasterSurface.imageAttachments.first)
    let fillAttachment = try #require(fillArtifacts.rasterSurface.imageAttachments.first)

    // Fit: 32x32 pixels into 48x32 pixel frame → min(1.5, 1.0) = 1.0 →
    // 32x32 target pixels → 4x2 cells. Letterboxed horizontally.
    #expect(fitAttachment.bounds.size == .init(width: 4, height: 2))
    // Fill: max(1.5, 1.0) = 1.5 → 48x48 target pixels → 6x3 cells.
    // Overflows the frame vertically (the extra cell row is clipped by
    // the parent frame).
    #expect(fillAttachment.bounds.size == .init(width: 6, height: 3))
  }

  private static let singlePixelGIF: [UInt8] = [
    0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00,
    0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0x21, 0xf9, 0x04, 0x00, 0x0a,
    0x00, 0x00, 0x00, 0x2c, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
    0x00, 0x02, 0x02, 0x44, 0x01, 0x00, 0x3b,
  ]
}
