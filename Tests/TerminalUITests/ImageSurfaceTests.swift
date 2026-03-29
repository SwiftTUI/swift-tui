import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@Suite
struct ImageSurfaceTests {
  @Test("embedded PNG bytes resolve into a raster image attachment")
  func embeddedPNGBytesResolveIntoAttachment() throws {
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
      Image(pngData: pngBytes)
    )
    let attachment = try #require(artifacts.rasterSurface.imageAttachments.first)

    #expect(artifacts.rasterSurface.imageAttachments.count == 1)
    #expect(attachment.source == .pngData(pngBytes))
    #expect(attachment.resolvedReference == .embeddedPNG(pngBytes))
    #expect(attachment.pixelSize == .init(width: 2, height: 2))
    #expect(attachment.bounds.size == .init(width: 1, height: 1))
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
      Image("icons/logo.png")
        .environment(\.imageResourceRoots, [root.path])
    )
    let attachment = try #require(artifacts.rasterSurface.imageAttachments.first)

    #expect(attachment.resolvedReference == .filePath(fileURL.path))
    #expect(attachment.pixelSize == .init(width: 16, height: 16))
    #expect(attachment.bounds.size == .init(width: 2, height: 1))
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
    let pngBytes = try makePNGBytes(
      width: 20,
      height: 10,
      pixels: Array(repeating: rgbaPixel(red: 255, green: 255, blue: 255), count: 200)
    )

    let fitArtifacts = DefaultRenderer().render(
      Image(pngData: pngBytes)
        .scaledToFit()
        .frame(width: 6, height: 4)
    )
    let fillArtifacts = DefaultRenderer().render(
      Image(pngData: pngBytes)
        .scaledToFill()
        .frame(width: 6, height: 4)
    )

    let fitAttachment = try #require(fitArtifacts.rasterSurface.imageAttachments.first)
    let fillAttachment = try #require(fillArtifacts.rasterSurface.imageAttachments.first)

    #expect(fitAttachment.bounds.size == .init(width: 6, height: 3))
    #expect(fillAttachment.bounds.size == .init(width: 8, height: 4))
  }
}
