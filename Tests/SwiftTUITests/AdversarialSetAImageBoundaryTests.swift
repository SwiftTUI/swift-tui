import Foundation
import Testing

@testable import SwiftTUIAnimatedImage
@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime

@Suite
struct AdversarialSetAImageBoundaryTests {
  @Test func setA326NestedPixelMutationInvalidatesOnlyTheChangedSequenceCache() throws {
    // Hypothesis: a nested pixel write bypasses frame-array observers and leaves a warm PNG stale.
    let original = AnimatedImageSequence(
      frames: [Self.frame([Self.red, Self.blue])], framesPerSecond: 10)
    let before = original.encodedImageData(at: 0)
    var edited = original
    edited.frames[0].pixels[1].green = 93
    let decoded = try Self.decode(edited.encodedImageData(at: 0))
    #expect(decoded.pixels[1] == RGBAImagePixel(red: 0, green: 93, blue: 255, alpha: 255))
    #expect(original.encodedImageData(at: 0) == before)
    #expect(original.frames[0].pixels[1] == Self.blue)
  }

  @Test func setA327TransparencyInALaterGIFFrameDoesNotEraseEarlierBlack() throws {
    // Hypothesis: global transparency reservation incorrectly turns an earlier opaque black index clear.
    let frames = [Self.frame([Self.black, Self.red]), Self.frame([Self.clear, Self.blue])]
    let decoded = try Self.gifRoundTrip(frames)
    #expect(decoded.frames[0].pixels == frames[0].pixels)
    #expect(decoded.frames[1].pixels[0].alpha == 0)
    #expect(decoded.frames[1].pixels[1] == Self.blue)
  }

  @Test func setA328GIFDisposalCannotLeaveGhostsInPrecomposedTransparentFrames() throws {
    // Hypothesis: consecutive sparse full frames inherit pixels from the preceding frame during disposal.
    let frames = [
      Self.frame([Self.red, Self.clear, Self.clear]),
      Self.frame([Self.clear, Self.blue, Self.clear]),
      Self.frame([Self.clear, Self.clear, Self.green]),
    ]
    let decoded = try Self.gifRoundTrip(frames)
    #expect(
      decoded.frames.map { $0.pixels.map(\.alpha) } == [[255, 0, 0], [0, 255, 0], [0, 0, 255]])
    #expect(decoded.frames[2].pixels[2] == Self.green)
  }

  @Test func setA329FullGIFPaletteNeverQuantizesOpaqueBlackIntoTransparency() throws {
    // Hypothesis: nearest-color fallback searches the reserved transparent entry when all slots are used.
    let reds = (1...255).map { AnimatedImagePixel(red: UInt8($0), green: 0, blue: 0) }
    let decoded = try Self.gifRoundTrip([Self.frame([Self.clear] + reds + [Self.black])])
    #expect(decoded.frames[0].pixels[0].alpha == 0)
    // The nearest admissible opaque color is (1,0,0); reserved transparent black is closer but invalid.
    #expect(decoded.frames[0].pixels.last == AnimatedImagePixel(red: 1, green: 0, blue: 0))
  }

  @Test func setA330AnimatedPNGDecodesAcrossDeflateAndScanlineBoundaries() throws {
    // Hypothesis: a stored-deflate boundary splitting a pixel/row corrupts a later scanline or its alpha.
    let width = 16_383
    let pixels = (0..<(width * 2)).map { index in
      AnimatedImagePixel(
        red: UInt8(index % 251), green: UInt8(index / width), blue: 173,
        alpha: UInt8(index % 256))
    }
    let frame = AnimatedImageFrame(width: width, height: 2, pixels: pixels)
    let decoded = try Self.decode(frame.imageData)
    #expect(decoded.pixelSize == PixelSize(width: width, height: 2))
    #expect(decoded.pixels.count == pixels.count)
    let mismatch = zip(decoded.pixels, pixels).enumerated().first {
      $0.element.0 != Self.runtimePixel($0.element.1)
    }?.offset
    #expect(mismatch == nil)
  }

  @Test func setA331PNGDecoderRejectsCorruptionWithoutPoisoningTheValidSource() throws {
    // Hypothesis: PNG integrity failure is accepted or cached under another same-sized encoded image.
    let bytes = Self.frame([Self.red, Self.blue]).imageData
    let repository = ImageAssetRepository(contentRepository: ImageContentRepository())
    var corrupted = bytes
    // First IDAT is after signature + 25-byte IHDR; change a pixel without updating CRC/Adler-32.
    corrupted[49] ^= 0x01
    #expect(repository.decodedImage(for: .embeddedImage(corrupted)) == nil)
    let valid = try #require(repository.decodedImage(for: .embeddedImage(bytes)))
    #expect(valid.pixels == [Self.runtimePixel(Self.red), Self.runtimePixel(Self.blue)])
    #expect(repository.occupancy().decodedCount == 1)
  }

  @Test func setA332AssetResolutionSeparatesCellMetricsButSharesDecodedPixels() throws {
    // Hypothesis: a resolution-cache hit reuses intrinsic cell geometry from a different host's metrics.
    let bytes = Self.frame(Array(repeating: Self.red, count: 17), width: 17).imageData
    let repository = ImageAssetRepository(contentRepository: ImageContentRepository())
    let first = try #require(
      repository.resolve(
        .data(bytes), resourceRoots: [], cellPixelSize: .init(width: 8, height: 16)))
    let second = try #require(
      repository.resolve(
        .data(bytes), resourceRoots: [], cellPixelSize: .init(width: 16, height: 8)))
    let again = try #require(
      repository.resolve(
        .data(bytes), resourceRoots: [], cellPixelSize: .init(width: 8, height: 16)))
    #expect(first.intrinsicCellSize == CellSize(width: 3, height: 1))
    #expect(second.intrinsicCellSize == CellSize(width: 2, height: 1))
    #expect(again == first)
    #expect(repository.occupancy().decodedCount == 1)
    #expect(repository.occupancy().resolutionCount == 2)
  }

  @Test func setA333ResourceRootOrderRemainsAuthoritativeAfterCacheWarmup() throws {
    // Hypothesis: named-image resolution keys omit ordered roots and return a previously preferred asset.
    let directory = try Self.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = directory.appendingPathComponent("first")
    let second = directory.appendingPathComponent("second")
    try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
    try Data(Self.frame([Self.red]).imageData).write(to: first.appendingPathComponent("same.png"))
    try Data(Self.frame([Self.blue, Self.green]).imageData).write(
      to: second.appendingPathComponent("same.png"))
    let repository = ImageAssetRepository(contentRepository: ImageContentRepository())
    let a = try #require(
      repository.resolve(
        .path("same.png"), resourceRoots: [first.path, second.path],
        cellPixelSize: .init(width: 1, height: 1)))
    let b = try #require(
      repository.resolve(
        .path("same.png"), resourceRoots: [second.path, first.path],
        cellPixelSize: .init(width: 1, height: 1)))
    #expect(a.pixelSize == PixelSize(width: 1, height: 1))
    #expect(b.pixelSize == PixelSize(width: 2, height: 1))
    #expect(b.reference == .filePath(second.appendingPathComponent("same.png").path))
  }

  @Test func setA334FileURLDecodesEscapedFilenameExactlyOnce() throws {
    // Hypothesis: percent decoding treats '+' as space or decodes a literal '%20' for a second time.
    let directory = try Self.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("plus+literal%20 snow 雪 🖼.png")
    let bytes = Self.frame([Self.green]).imageData
    try Data(bytes).write(to: file)
    let repository = ImageAssetRepository(contentRepository: ImageContentRepository())
    // Exercise both the content reader and the resource-root existence probe.
    // Windows must preserve UTF-16 filenames independently of the active code page.
    for source in [
      ImageSource.path(file.path), .fileURL(file.absoluteString), .path(file.lastPathComponent),
    ] {
      let asset = try #require(
        repository.resolve(
          source, resourceRoots: [directory.path], cellPixelSize: .init(width: 1, height: 1))
      )
      #expect(asset.reference == .filePath(file.path))
      #expect(try #require(repository.decodedImage(for: asset.reference)).encodedBytes == bytes)
    }
  }

  @Test func setA335ResolverClosureDoesNotKeepItsRepositoryAlive() throws {
    // Hypothesis: the public resolver captures the repository strongly, retaining its decoded assets forever.
    var repository: ImageAssetRepository? = ImageAssetRepository(
      contentRepository: ImageContentRepository())
    weak let lifetime = repository
    let resolver = try #require(repository).resolver()
    let bytes = Self.frame([Self.red]).imageData
    #expect(try resolver(.data(bytes), [], .init(width: 1, height: 1)) != nil)
    repository = nil
    #expect(lifetime == nil)
    #expect(try resolver(.data(bytes), [], .init(width: 1, height: 1)) == nil)
  }

  @Test func setA336FileAndEmbeddedContentHaveTheSameTransportIdentity() throws {
    // Hypothesis: transport fingerprints accidentally include acquisition path rather than encoded content.
    let directory = try Self.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("image.png")
    let bytes = Self.frame([Self.red, Self.green, Self.blue]).imageData
    try Data(bytes).write(to: file)
    let contents = ImageContentRepository()
    let fromFile = try #require(contents.content(for: .filePath(file.path)))
    let embedded = try #require(contents.content(for: .embeddedImage(bytes)))
    #expect(fromFile.wireID == embedded.wireID)
    #expect(kittyImageID(content: fromFile) == kittyImageID(content: embedded))
    #expect(fromFile.bytes == embedded.bytes)
  }

  @Test func setA337RetainedContentRemainsUsableAfterRepositoryReset() throws {
    // Hypothesis: retiring repository entries invalidates externally retained bytes or reuses owner identity.
    let contents = ImageContentRepository()
    let bytes = Self.frame([Self.blue]).imageData
    let retained = try #require(contents.content(for: .embeddedImage(bytes)))
    contents.removeAll()
    let reacquired = try #require(contents.content(for: .embeddedImage(bytes)))
    #expect(retained.id != reacquired.id)
    #expect(retained.wireID == reacquired.wireID)
    #expect(
      try #require(ImageAssetRepository().decodedImage(for: retained)).pixels == [
        Self.runtimePixel(Self.blue)
      ])
  }

  @Test func setA338WarmResolutionSurvivesIndependentDecodedCacheEviction() throws {
    // Hypothesis: an admitted resolution silently depends on a decoded-cache entry that can be evicted alone.
    let repository = ImageAssetRepository(
      decodedCachePolicy: .init(maxEntries: 1, maxBytes: 4096),
      contentRepository: ImageContentRepository())
    let bytes = Self.frame([Self.red, Self.blue]).imageData
    let first = try #require(
      repository.resolve(.data(bytes), resourceRoots: [], cellPixelSize: .init(width: 1, height: 1))
    )
    _ = try #require(
      repository.decodedImage(for: .embeddedImage(Self.frame([Self.green]).imageData)))
    let again = try #require(
      repository.resolve(.data(bytes), resourceRoots: [], cellPixelSize: .init(width: 1, height: 1))
    )
    #expect(again == first)
    #expect(
      try #require(repository.decodedImage(for: again.reference)).pixels == [
        Self.runtimePixel(Self.red), Self.runtimePixel(Self.blue),
      ])
    #expect(repository.occupancy().decodedCount == 1)
  }

  @Test func setA339RectangularNearestNeighborSamplingUsesPixelCentersOnBothAxes() {
    // Hypothesis: non-square resampling chooses pixel edges or confuses row stride with output width.
    let source = Self.image(
      width: 5, height: 3,
      pixels: (0..<15).map { RGBAImagePixel(red: $0, green: 0, blue: 0, alpha: 255) })
    let pixels = scaledRGBAPixels(from: source, outputSize: .init(width: 2, height: 2))
    #expect(pixels.map(\.red) == [1, 3, 11, 13])
  }

  @Test func setA340CellFallbackThresholdDoesNotLeakIntoRawRGBASampling() {
    // Hypothesis: the cell-fallback alpha cutoff incorrectly discards raw terminal pixels near transparency.
    let source = Self.image(
      width: 4, height: 1,
      pixels: [0, 15, 16, 255].map { RGBAImagePixel(red: 29, green: 71, blue: 103, alpha: $0) })
    let raw = scaledRGBAPixels(from: source, outputSize: source.pixelSize)
    let cells = scaledPixels(from: source, outputSize: source.pixelSize)
    #expect(raw.map(\.alpha) == [0, 15, 16, 255])
    #expect(cells.map { $0?.alpha } == [nil, nil, 16, 255])
    #expect(raw[0].red == 29)
  }

  @Test func setA341TransparentGapBlocksDitherErrorPropagation() {
    // Hypothesis: quantization error is carried through absent pixels into a disconnected image island.
    let gray = RGBAImagePixel(red: 120, green: 120, blue: 120, alpha: 255)
    let output = floydSteinbergQuantizedIndices(
      pixels: [gray, nil, gray], size: .init(width: 3, height: 1), palette: [.black, .white])
    #expect(output == [0, nil, 0])
    let connected = floydSteinbergQuantizedIndices(
      pixels: [gray, gray], size: .init(width: 2, height: 1), palette: [.black, .white])
    #expect(connected == [0, 1])
  }

  @Test func setA342KittyDownsamplingCannotUndersampleTheLongPlacementAxis() {
    // Hypothesis: using the smaller scale ratio saves bytes but loses required resolution in a tall placement.
    let size = kittyRGBATransmitSize(
      imagePixelSize: .init(width: 1200, height: 800), encodedFormat: .jpeg,
      placementCellSize: .init(width: 5, height: 10), cellPixelSize: .init(width: 8, height: 16))
    #expect(size == PixelSize(width: 240, height: 160))
    let cappedByNativeHeight = kittyRGBATransmitSize(
      imagePixelSize: .init(width: 1200, height: 80), encodedFormat: .jpeg,
      placementCellSize: .init(width: 5, height: 10), cellPixelSize: .init(width: 8, height: 16))
    #expect(cappedByNativeHeight == PixelSize(width: 1200, height: 80))
  }

  @Test func setA343DecodedOnlyBlendCanReachKittyWithoutAnEncodedPNG() throws {
    // Hypothesis: lazy PNG elimination leaves a valid decoded blend unusable because transport demands bytes.
    let compositor = ImageBlendCompositor()
    let attachment = Self.blended(bytes: Self.frame([Self.red]).imageData, destination: .white)
    let variant = try #require(
      compositor.decodedVariant(for: attachment, fallbackBackground: .black))
    #expect(variant.image.encodedBytes.isEmpty)
    let payload = try #require(makeKittyPayload(for: variant.image, preferRawRGBA: true))
    #expect(payload.format == .rgba(pixelSize: .init(width: 1, height: 1)))
    #expect(try Self.payloadBytes(payload) == [255, 0, 0, 255])
  }

  @Test func setA344KittyRawResizeKeepsRowOrderAndAuthoredAlpha() throws {
    // Hypothesis: raw serialization resamples colors correctly but transposes rows or forces alpha opaque.
    let source = Self.image(
      width: 2, height: 2,
      pixels: [
        RGBAImagePixel(red: 1, green: 2, blue: 3, alpha: 4),
        RGBAImagePixel(red: 5, green: 6, blue: 7, alpha: 8),
        RGBAImagePixel(red: 9, green: 10, blue: 11, alpha: 12),
        RGBAImagePixel(red: 13, green: 14, blue: 15, alpha: 16),
      ])
    let payload = try #require(
      makeKittyPayload(for: source, rgbaOutputSize: .init(width: 1, height: 2), preferRawRGBA: true)
    )
    #expect(try Self.payloadBytes(payload) == [5, 6, 7, 8, 13, 14, 15, 16])
    #expect(payload.format == .rgba(pixelSize: .init(width: 1, height: 2)))
  }

  @Test func setA345KittyClipCoordinatesReferToTheTransmittedPixelSize() throws {
    // Hypothesis: after raw downsampling, a clipped placement still uses native-pixel crop coordinates.
    let bytes = Self.frame([Self.red]).imageData
    let bounds = CellRect(origin: .init(x: 3, y: 4), size: .init(width: 6, height: 4))
    let attachment = RasterImageAttachment(
      identity: Identity(components: ["crop"]), bounds: bounds,
      visibleBounds: .init(origin: .init(x: 5, y: 5), size: .init(width: 3, height: 2)),
      source: .data(bytes), pixelSize: .init(width: 600, height: 400))
    let transmitted = kittyRGBATransmitSize(
      imagePixelSize: .init(width: 600, height: 400), encodedFormat: .jpeg,
      placementCellSize: bounds.size, cellPixelSize: .init(width: 10, height: 10))
    let placement = try #require(kittyPlacement(for: attachment, imagePixelSize: transmitted))
    #expect(transmitted == PixelSize(width: 60, height: 40))
    #expect(placement.origin == CellPoint(x: 5, y: 5))
    #expect(placement.sourceRect == KittySourceRect(x: 20, y: 10, width: 30, height: 20))
    #expect(placement.cellColumns == 3 && placement.cellRows == 2)
  }

  @Test func setA346SharedBlendPixelsCannotReuseAnotherAttachmentsIdentity() throws {
    // Hypothesis: a content/geometry cache hit returns presentation metadata belonging to the first owner.
    let compositor = ImageBlendCompositor()
    var first = Self.blended(bytes: Self.frame([Self.red]).imageData, destination: .white)
    first.identity = Identity(components: ["first"])
    var second = first
    second.identity = Identity(components: ["second"])
    let a = try #require(compositor.decodedVariant(for: first, fallbackBackground: .black))
    let b = try #require(compositor.decodedVariant(for: second, fallbackBackground: .black))
    #expect(a.image.pixels == b.image.pixels)
    #expect(a.attachment.identity == first.identity)
    // Pixel sharing is valid; the cached presentation must still describe the current owner.
    do {
      #expect(b.attachment.identity == second.identity)
      #expect(a.id == b.id)
      #expect(compositor.cacheSnapshot().entryCount == 1)
      #expect(compositor.cacheSnapshot().decodedHits == 1)
    }
  }

  @Test func setA347BlendCacheIncludesFallbackBehindUnpaintedCells() throws {
    // Hypothesis: backdrop signatures match for empty cells, causing a changed host background to reuse pixels.
    let compositor = ImageBlendCompositor()
    let attachment = Self.blended(bytes: Self.frame([Self.clear]).imageData, destination: nil)
    let a = try #require(
      compositor.decodedVariant(
        for: attachment, fallbackBackground: Color(red: 1, green: 0, blue: 0)))
    let b = try #require(
      compositor.decodedVariant(
        for: attachment, fallbackBackground: Color(red: 0, green: 0, blue: 1)))
    #expect(a.image.pixels == [Self.runtimePixel(Self.red)])
    #expect(b.image.pixels == [Self.runtimePixel(Self.blue)])
    #expect(a.id != b.id)
  }

  @Test func setA348LazyBlendPNGUpgradePreservesPixelAndCacheIdentity() throws {
    // Hypothesis: asking for encoded output after decoded output blends a second time or replaces its identity.
    let compositor = ImageBlendCompositor()
    let translucent = AnimatedImagePixel(red: 255, green: 0, blue: 0, alpha: 128)
    let attachment = Self.blended(
      bytes: Self.frame([translucent]).imageData, destination: .blue, mode: .normal)
    let first = try #require(compositor.decodedVariant(for: attachment, fallbackBackground: .black))
    let encoded = try #require(
      compositor.encodedPNGPayload(for: attachment, fallbackBackground: .black))
    let last = try #require(compositor.decodedVariant(for: attachment, fallbackBackground: .black))
    #expect(try Self.decode(encoded.bytes).pixels == first.image.pixels)
    #expect(last.image.pixels == first.image.pixels)
    #expect(encoded.id == first.id && last.id == first.id)
    let encodedAgain = try #require(
      compositor.encodedPNGPayload(for: attachment, fallbackBackground: .black))
    #expect(encodedAgain == encoded)
    #expect(compositor.cacheSnapshot().entryCount == 1)
  }

  @Test func setA349CroppedBlendSamplesTheOriginalImageCoordinates() throws {
    // Hypothesis: blending a clipped image rescales the entire source into the surviving cells.
    let frame = Self.frame([Self.red, Self.green, Self.blue, Self.black])
    let fullBounds = CellRect(origin: .init(x: 7, y: 2), size: .init(width: 4, height: 1))
    var attachment = Self.blended(bytes: frame.imageData, destination: .white, bounds: fullBounds)
    attachment.visibleBounds = .init(origin: .init(x: 8, y: 2), size: .init(width: 2, height: 1))
    let variant = try #require(
      ImageBlendCompositor().decodedVariant(for: attachment, fallbackBackground: .black))
    #expect(variant.image.pixelSize == PixelSize(width: 2, height: 1))
    #expect(variant.image.pixels == [Self.runtimePixel(Self.green), Self.runtimePixel(Self.blue)])
    #expect(variant.attachment.bounds == attachment.visibleBounds)
  }

  @Test func setA350PostGroupBlendFlattensSourceAlphaBeforeApplyingBlendMode() throws {
    // Hypothesis: multiplying the translucent image before flattening its group's white backdrop changes color.
    let bounds = CellRect(origin: .zero, size: .init(width: 1, height: 1))
    var attachment = Self.blended(
      bytes: Self.frame([AnimatedImagePixel(red: 255, green: 0, blue: 0, alpha: 128)]).imageData,
      destination: Color(red: 0, green: 1, blue: 0))
    attachment.compositing = RasterImageCompositing(
      blendMode: .multiply,
      destinationBackdrop: .init(
        bounds: bounds, cells: [.init(backgroundColor: Color(red: 0, green: 1, blue: 0))]),
      sourceBackdrop: .init(bounds: bounds, cells: [.init(backgroundColor: .white)]),
      cellPixelSize: .init(width: 1, height: 1), backdropSignature: 901)
    let pixels = try #require(
      ImageBlendCompositor().decodedVariant(for: attachment, fallbackBackground: .black)
    ).image.pixels
    // Linear light: red-over-white contributes 127/255 green, then multiplies opaque green.
    #expect(pixels == [RGBAImagePixel(red: 0, green: 187, blue: 0, alpha: 255)])
  }

  private static let red = AnimatedImagePixel(red: 255, green: 0, blue: 0)
  private static let green = AnimatedImagePixel(red: 0, green: 255, blue: 0)
  private static let blue = AnimatedImagePixel(red: 0, green: 0, blue: 255)
  private static let black = AnimatedImagePixel(red: 0, green: 0, blue: 0)
  private static let clear = AnimatedImagePixel(red: 0, green: 0, blue: 0, alpha: 0)

  private static func frame(_ pixels: [AnimatedImagePixel], width: Int? = nil) -> AnimatedImageFrame
  {
    let width = width ?? pixels.count
    return AnimatedImageFrame(width: width, height: pixels.count / width, pixels: pixels)
  }

  private static func runtimePixel(_ pixel: AnimatedImagePixel) -> RGBAImagePixel {
    RGBAImagePixel(
      red: Int(pixel.red), green: Int(pixel.green), blue: Int(pixel.blue), alpha: Int(pixel.alpha))
  }

  private static func gifRoundTrip(_ frames: [AnimatedImageFrame]) throws -> AnimatedImageSequence {
    try AnimatedGIF.decode(
      data: AnimatedGIF.encode(AnimatedImageSequence(frames: frames, framesPerSecond: 10)))
  }

  private static func decode(_ bytes: [UInt8]) throws -> DecodedImage {
    try #require(
      ImageAssetRepository(contentRepository: ImageContentRepository()).decodedImage(
        for: .embeddedImage(bytes)))
  }

  private static func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private static func image(width: Int, height: Int, pixels: [RGBAImagePixel]) -> DecodedImage {
    DecodedImage(
      encodedBytes: [], encodedFormat: .png, pixelSize: .init(width: width, height: height),
      pixels: pixels)
  }

  private static func payloadBytes(_ payload: KittyPayload) throws -> [UInt8] {
    Array(try #require(Data(base64Encoded: payload.encodedChunks.joined())))
  }

  private static func blended(
    bytes: [UInt8], destination: Color?, mode: BlendMode = .multiply,
    bounds: CellRect = .init(origin: .zero, size: .init(width: 1, height: 1))
  ) -> RasterImageAttachment {
    RasterImageAttachment(
      identity: Identity(components: ["image-boundary"]), bounds: bounds,
      source: .data(bytes), resolvedReference: .embeddedImage(bytes),
      cellPixelSize: .init(width: 1, height: 1),
      compositing: .init(
        blendMode: mode,
        destinationBackdrop: .init(
          bounds: bounds,
          cells: Array(
            repeating: .init(backgroundColor: destination),
            count: bounds.size.width * bounds.size.height)),
        cellPixelSize: .init(width: 1, height: 1), backdropSignature: 900))
  }
}
