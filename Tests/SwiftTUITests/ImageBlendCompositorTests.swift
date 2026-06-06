import PNG
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIProfiling
@testable import SwiftTUIRuntime

@Suite(.serialized)
struct ImageBlendCompositorTests {
  @Test("direct image blend precomposes source pixels over destination backdrop")
  func directImageBlendPrecomposesSourcePixelsOverDestinationBackdrop() throws {
    let source = Color(red: 1, green: 0, blue: 0)
    let destination = Color(red: 0, green: 0, blue: 1)
    let pngBytes = try makePNGBytes(
      width: 1,
      height: 1,
      pixels: [rgbaPixel(red: 255, green: 0, blue: 0)]
    )
    let attachment = blendedAttachment(
      pngBytes: pngBytes,
      compositing: imageCompositing(
        blendMode: .multiply,
        destination: destination
      )
    )

    let variant = try #require(
      ImageBlendCompositor().decodedVariant(
        for: attachment,
        fallbackBackground: .black
      )
    )

    #expect(variant.attachment.bounds == attachment.visibleBounds)
    #expect(variant.image.pixelSize == .init(width: 1, height: 1))
    #expect(
      variant.image.pixels
        == [expectedPixel(source.composited(over: destination, mode: .multiply))]
    )
  }

  @Test("transparent source pixels preserve the captured destination backdrop")
  func transparentSourcePixelsPreserveCapturedDestinationBackdrop() throws {
    let source = Color(red: 1, green: 0, blue: 0, alpha: 0)
    let destination = Color(red: 0, green: 0, blue: 1)
    let pngBytes = try makePNGBytes(
      width: 1,
      height: 1,
      pixels: [rgbaPixel(red: 255, green: 0, blue: 0, alpha: 0)]
    )
    let attachment = blendedAttachment(
      pngBytes: pngBytes,
      compositing: imageCompositing(
        blendMode: .multiply,
        destination: destination
      )
    )

    let variant = try #require(
      ImageBlendCompositor().decodedVariant(
        for: attachment,
        fallbackBackground: .black
      )
    )

    #expect(
      variant.image.pixels
        == [expectedPixel(source.composited(over: destination, mode: .multiply))]
    )
  }

  @Test("post-group image blend flattens source backdrop before blending with destination")
  func postGroupImageBlendFlattensSourceBackdropBeforeDestinationBlend() throws {
    let source = Color(red: 1, green: 0, blue: 0, alpha: 0)
    let sourceBackdrop = Color(red: 0, green: 0, blue: 1)
    let destination = Color(red: 1, green: 0, blue: 0)
    let pngBytes = try makePNGBytes(
      width: 1,
      height: 1,
      pixels: [rgbaPixel(red: 255, green: 0, blue: 0, alpha: 0)]
    )
    let attachment = blendedAttachment(
      pngBytes: pngBytes,
      compositing: imageCompositing(
        blendMode: .multiply,
        destination: destination,
        source: sourceBackdrop
      )
    )

    let variant = try #require(
      ImageBlendCompositor().decodedVariant(
        for: attachment,
        fallbackBackground: .black
      )
    )

    let flattenedSource = source.composited(over: sourceBackdrop)
    #expect(
      variant.image.pixels
        == [expectedPixel(flattenedSource.composited(over: destination, mode: .multiply))]
    )
  }

  @Test("repeated decoded requests hit one compositor cache entry")
  func repeatedDecodedRequestsHitOneCacheEntry() throws {
    let pngBytes = try makePNGBytes(
      width: 1,
      height: 1,
      pixels: [rgbaPixel(red: 255, green: 0, blue: 0)]
    )
    let attachment = blendedAttachment(
      pngBytes: pngBytes,
      compositing: imageCompositing(
        blendMode: .multiply,
        destination: .blue
      )
    )
    let compositor = ImageBlendCompositor(cachePolicy: cachePolicy(maxEntries: 4))

    _ = try #require(compositor.decodedVariant(for: attachment, fallbackBackground: .black))
    let afterMiss = compositor.cacheSnapshot()
    _ = try #require(compositor.decodedVariant(for: attachment, fallbackBackground: .black))
    let afterHit = compositor.cacheSnapshot()

    #expect(afterMiss.entryCount == 1)
    #expect(afterMiss.decodedMisses == 1)
    #expect(afterMiss.decodedHits == 0)
    #expect(afterHit.entryCount == 1)
    #expect(afterHit.decodedMisses == 1)
    #expect(afterHit.decodedHits == 1)
  }

  @Test("LRU eviction bounds unique backdrop variants")
  func lruEvictionBoundsUniqueBackdropVariants() throws {
    let pngBytes = try makePNGBytes(
      width: 1,
      height: 1,
      pixels: [rgbaPixel(red: 255, green: 0, blue: 0)]
    )
    let compositor = ImageBlendCompositor(cachePolicy: cachePolicy(maxEntries: 2))

    _ = try #require(
      compositor.decodedVariant(
        for: backdropVariant(pngBytes: pngBytes, background: .blue, signature: 1),
        fallbackBackground: .black
      )
    )
    _ = try #require(
      compositor.decodedVariant(
        for: backdropVariant(pngBytes: pngBytes, background: .red, signature: 2),
        fallbackBackground: .black
      )
    )
    _ = try #require(
      compositor.decodedVariant(
        for: backdropVariant(pngBytes: pngBytes, background: .green, signature: 3),
        fallbackBackground: .black
      )
    )
    let afterEviction = compositor.cacheSnapshot()

    _ = try #require(
      compositor.decodedVariant(
        for: backdropVariant(pngBytes: pngBytes, background: .blue, signature: 1),
        fallbackBackground: .black
      )
    )
    let afterReRequest = compositor.cacheSnapshot()

    #expect(afterEviction.entryCount == 2)
    #expect(afterEviction.evictionCount == 1)
    #expect(afterReRequest.entryCount == 2)
    #expect(afterReRequest.evictionCount == 2)
    #expect(afterReRequest.decodedMisses == 4)
  }

  @Test("encoded and decoded requests share one compositor cache entry")
  func encodedAndDecodedRequestsShareOneCacheEntry() throws {
    let pngBytes = try makePNGBytes(
      width: 1,
      height: 1,
      pixels: [rgbaPixel(red: 255, green: 0, blue: 0)]
    )
    let attachment = blendedAttachment(
      pngBytes: pngBytes,
      compositing: imageCompositing(
        blendMode: .multiply,
        destination: .blue
      )
    )
    let compositor = ImageBlendCompositor(cachePolicy: cachePolicy(maxEntries: 4))

    let payload = try #require(
      compositor.encodedPNGPayload(for: attachment, fallbackBackground: .black)
    )
    let afterEncoded = compositor.cacheSnapshot()
    let variant = try #require(
      compositor.decodedVariant(for: attachment, fallbackBackground: .black)
    )
    let afterDecoded = compositor.cacheSnapshot()
    let repeatedPayload = try #require(
      compositor.encodedPNGPayload(for: attachment, fallbackBackground: .black)
    )
    let afterEncodedHit = compositor.cacheSnapshot()

    #expect(afterEncoded.entryCount == 1)
    #expect(afterEncoded.decodedPixelBytes == 0)
    #expect(afterEncoded.encodedMisses == 1)
    #expect(afterDecoded.entryCount == 1)
    #expect(afterDecoded.decodedPixelBytes > 0)
    #expect(afterDecoded.decodedMisses == 1)
    #expect(variant.image.encodedBytes == payload.bytes)
    #expect(repeatedPayload == payload)
    #expect(afterEncodedHit.entryCount == 1)
    #expect(afterEncodedHit.encodedHits == 1)
  }

  @Test("oversize current entry is retained while older variants are evicted")
  func oversizeCurrentEntryIsRetainedWhileOlderVariantsAreEvicted() throws {
    let pngBytes = try makePNGBytes(
      width: 2,
      height: 2,
      pixels: Array(repeating: rgbaPixel(red: 255, green: 0, blue: 0), count: 4)
    )
    let bounds = CellRect(origin: .zero, size: .init(width: 2, height: 2))
    let compositor = ImageBlendCompositor(
      cachePolicy: cachePolicy(maxEntries: 8, maxDecodedPixels: 1)
    )

    _ = try #require(
      compositor.decodedVariant(
        for: backdropVariant(
          pngBytes: pngBytes,
          background: .blue,
          signature: 1,
          bounds: bounds
        ),
        fallbackBackground: .black
      )
    )
    let afterFirstOversize = compositor.cacheSnapshot()
    _ = try #require(
      compositor.decodedVariant(
        for: backdropVariant(
          pngBytes: pngBytes,
          background: .red,
          signature: 2,
          bounds: bounds
        ),
        fallbackBackground: .black
      )
    )
    let afterSecondOversize = compositor.cacheSnapshot()

    #expect(afterFirstOversize.entryCount == 1)
    #expect(afterFirstOversize.evictionCount == 0)
    #expect(afterSecondOversize.entryCount == 1)
    #expect(afterSecondOversize.evictionCount == 1)
    #expect(afterSecondOversize.decodedPixelBytes > 0)
  }

  @MainActor
  @Test("memory metric reports compositor occupancy and eviction counters")
  func memoryMetricReportsCompositorOccupancyAndEvictionCounters() throws {
    let pngBytes = try makePNGBytes(
      width: 1,
      height: 1,
      pixels: [rgbaPixel(red: 255, green: 0, blue: 0)]
    )
    let compositor = ImageBlendCompositor(cachePolicy: cachePolicy(maxEntries: 1))

    _ = try #require(
      compositor.decodedVariant(
        for: backdropVariant(pngBytes: pngBytes, background: .blue, signature: 1),
        fallbackBackground: .black
      )
    )
    _ = try #require(
      compositor.decodedVariant(
        for: backdropVariant(pngBytes: pngBytes, background: .red, signature: 2),
        fallbackBackground: .black
      )
    )
    let cacheSnapshot = compositor.cacheSnapshot()

    let metric = try #require(
      MemoryMetricCollector().collect().first { snapshot in
        snapshot.name == "ImageBlendCompositor.variants"
          && snapshot.count == cacheSnapshot.entryCount
          && snapshot.detail?["evictions"] == cacheSnapshot.evictionCount
          && snapshot.detail?["decodedMisses"] == cacheSnapshot.decodedMisses
      }
    )

    #expect(metric.approxBytes == cacheSnapshot.totalApproxBytes)
    #expect(metric.detail?["encodedBytes"] == cacheSnapshot.encodedBytes)
    #expect(metric.detail?["decodedPixelBytes"] == cacheSnapshot.decodedPixelBytes)
  }

  @Test("frame-like source and backdrop churn remains bounded by policy")
  func frameLikeSourceAndBackdropChurnRemainsBoundedByPolicy() throws {
    let frames = try [
      makePNGBytes(width: 1, height: 1, pixels: [rgbaPixel(red: 255, green: 0, blue: 0)]),
      makePNGBytes(width: 1, height: 1, pixels: [rgbaPixel(red: 0, green: 255, blue: 0)]),
      makePNGBytes(width: 1, height: 1, pixels: [rgbaPixel(red: 0, green: 0, blue: 255)]),
      makePNGBytes(width: 1, height: 1, pixels: [rgbaPixel(red: 255, green: 255, blue: 0)]),
    ]
    let backgrounds: [Color] = [.blue, .red, .green, .black]
    let compositor = ImageBlendCompositor(cachePolicy: cachePolicy(maxEntries: 2))

    for index in frames.indices {
      _ = try #require(
        compositor.decodedVariant(
          for: backdropVariant(
            pngBytes: frames[index],
            background: backgrounds[index],
            signature: UInt64(index + 1)
          ),
          fallbackBackground: .black
        )
      )
    }
    let snapshot = compositor.cacheSnapshot()

    #expect(snapshot.entryCount == 2)
    #expect(snapshot.evictionCount == 2)
    #expect(snapshot.decodedMisses == frames.count)
  }
}

private func expectedPixel(
  _ color: Color
) -> RGBAImagePixel {
  let converted = color.converted(to: .sRGB, gamutMapping: .clip)
  return RGBAImagePixel(
    red: byte(from: converted.red),
    green: byte(from: converted.green),
    blue: byte(from: converted.blue),
    alpha: byte(from: converted.alpha)
  )
}

private func byte(
  from component: Double
) -> Int {
  Int((max(0.0, min(1.0, component)) * 255.0).rounded())
}

private func blendedAttachment(
  pngBytes: [UInt8],
  compositing: RasterImageCompositing,
  bounds: CellRect = CellRect(origin: .zero, size: .init(width: 1, height: 1))
) -> RasterImageAttachment {
  RasterImageAttachment(
    identity: testIdentity("Root", "Image"),
    bounds: bounds,
    source: .data(pngBytes),
    resolvedReference: .embeddedImage(pngBytes),
    pixelSize: .init(width: bounds.size.width, height: bounds.size.height),
    cellPixelSize: .init(width: 1, height: 1),
    compositing: compositing
  )
}

private func imageCompositing(
  blendMode: BlendMode,
  destination: Color,
  source: Color? = nil,
  bounds: CellRect = CellRect(origin: .zero, size: .init(width: 1, height: 1)),
  signature: UInt64? = nil
) -> RasterImageCompositing {
  let destinationBackdrop = RasterImageBackdrop(
    bounds: bounds,
    cells: Array(
      repeating: .init(backgroundColor: destination),
      count: bounds.size.width * bounds.size.height
    )
  )
  let sourceBackdrop = source.map { color in
    RasterImageBackdrop(
      bounds: bounds,
      cells: Array(
        repeating: .init(backgroundColor: color),
        count: bounds.size.width * bounds.size.height
      )
    )
  }
  return RasterImageCompositing(
    blendMode: blendMode,
    destinationBackdrop: destinationBackdrop,
    sourceBackdrop: sourceBackdrop,
    cellPixelSize: .init(width: 1, height: 1),
    backdropSignature: signature ?? (source == nil ? 1 : 2)
  )
}

private func backdropVariant(
  pngBytes: [UInt8],
  background: Color,
  signature: UInt64,
  bounds: CellRect = CellRect(origin: .zero, size: .init(width: 1, height: 1))
) -> RasterImageAttachment {
  blendedAttachment(
    pngBytes: pngBytes,
    compositing: imageCompositing(
      blendMode: .multiply,
      destination: background,
      bounds: bounds,
      signature: signature
    ),
    bounds: bounds
  )
}

private func cachePolicy(
  maxEntries: Int,
  maxDecodedPixels: Int = Int.max,
  maxEncodedBytes: Int = Int.max
) -> ImageBlendCompositorCachePolicy {
  ImageBlendCompositorCachePolicy(
    maxEntries: maxEntries,
    maxDecodedPixels: maxDecodedPixels,
    maxEncodedBytes: maxEncodedBytes
  )
}
