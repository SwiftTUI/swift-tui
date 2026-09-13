import Foundation
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

struct ImageContentOwnershipTests {
  @Test("STUI-301: colliding sampled byte keys remain exact and retired owners never alias")
  func byteIdentityAndRetirement() throws {
    let repository = ImageContentRepository(maxEntries: 1, maxBytes: 2_000_000)
    let bytes = [UInt8](repeating: 7, count: 4096)
    var changed = bytes
    changed[2048] = 9
    var first: ImageContent? = try #require(repository.content(for: .embeddedImage(bytes)))
    let firstID = try #require(first?.id)
    weak var lifetime = first
    #expect(repository.content(for: .embeddedImage(bytes)) === first)
    let second = try #require(repository.content(for: .embeddedImage(changed)))
    #expect(second.id != firstID)
    #expect(second.bytes[2048] == 9)
    #expect(first?.bytes[2048] == 7)
    first = nil
    #expect(lifetime == nil)
    let reacquired = try #require(repository.content(for: .embeddedImage(bytes)))
    #expect(reacquired.id != firstID)
    #expect(repository.snapshot.entries == 1)
    #expect(repository.snapshot.bytes <= 2_000_000)
    repository.removeAll()
    #expect(repository.snapshot.entries == 0)
    #expect(repository.snapshot.bytes == 0)
  }

  @Test(
    "unchanged file wire frames read once; replacement invalidates content and decoded geometry")
  func fileFramesAndReplacement() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("image.png")
    let original = try makePNGBytes(
      width: 2, height: 1,
      pixels: [rgbaPixel(red: 255, green: 0, blue: 0), rgbaPixel(red: 0, green: 0, blue: 255)])
    try Data(original).write(to: file)
    let contents = ImageContentRepository()
    let repository = ImageAssetRepository(contentRepository: contents)
    let source = ImageSource.fileURL(file.absoluteString)
    let initial = try #require(
      repository.resolve(source, resourceRoots: [], cellPixelSize: .init(width: 1, height: 1)))
    #expect(initial.pixelSize == .init(width: 2, height: 1))
    let attachment = RasterImageAttachment(
      identity: Identity(components: ["picture"]),
      bounds: .init(origin: .zero, size: .init(width: 20, height: 10)), source: source,
      resolvedReference: initial.reference, pixelSize: initial.pixelSize)
    let initialContent = try #require(contents.content(for: attachment))
    let initialID = initialContent.id
    var known: Set<String> = []
    for frame in 0..<100 {
      let encoded = WebSurfaceFrameEncoder.encodeImages(
        [attachment], fallbackBackground: .black,
        knownImageIDs: &known, contentRepository: contents)
      #expect(encoded.count == 1)
      #expect(encoded[0].contains(initialContent.wireID))
      #expect(encoded[0].contains("dataBase64") == (frame == 0))
    }
    #if !os(Windows) && !canImport(WASILibc)
      #expect(contents.snapshot.fileReads == 1)
      #expect(contents.snapshot.fileBytesRead == original.count)
    #endif
    #expect(contents.snapshot.contentBytesHashed == original.count)
    let replacement = try makePNGBytes(
      width: 1, height: 1, pixels: [rgbaPixel(red: 0, green: 255, blue: 0)])
    try Data(replacement).write(to: file, options: .atomic)
    let refreshed = try #require(
      repository.resolve(source, resourceRoots: [], cellPixelSize: .init(width: 1, height: 1)))
    #expect(refreshed.pixelSize == .init(width: 1, height: 1))
    let next = try #require(contents.content(for: attachment))
    #expect(next.id != initialID)
    #expect(next.bytes == replacement)
    let encoded = WebSurfaceFrameEncoder.encodeImages(
      [attachment], fallbackBackground: .black,
      knownImageIDs: &known, contentRepository: contents)
    #expect(encoded[0].contains(next.wireID))
    #expect(encoded[0].contains("dataBase64"))
    try FileManager.default.removeItem(at: file)
    #expect(contents.content(for: attachment) == nil)
    #expect(
      repository.resolve(source, resourceRoots: [], cellPixelSize: .init(width: 1, height: 1))
        == nil)
  }

  @Test("content too large for admission stays usable without exceeding cache ownership bounds")
  func oversizedContent() throws {
    let repository = ImageContentRepository(maxEntries: 2, maxBytes: 1024)
    let bytes = [UInt8](repeating: 0, count: 2048)
    #expect(try #require(repository.content(for: .embeddedImage(bytes))).bytes == bytes)
    #expect(repository.snapshot.entries == 0)
    #expect(repository.snapshot.bytes == 0)
  }
}
