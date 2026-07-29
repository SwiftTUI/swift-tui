import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

@Suite
struct ImageAssetRepositoryTests {
  @Test("resolution cache defaults to 512 entries and 128 MiB")
  func resolutionCacheDefaultPolicy() {
    #expect(ImageAssetCachePolicy.resolutionDefault.maxEntries == 512)
    #expect(ImageAssetCachePolicy.resolutionDefault.maxBytes == 128 * 1_024 * 1_024)
  }

  @Test("decoded cache defaults to 64 entries and 128 MiB")
  func decodedCacheDefaultPolicy() {
    #expect(ImageAssetCachePolicy.decodedDefault.maxEntries == 64)
    #expect(ImageAssetCachePolicy.decodedDefault.maxBytes == 128 * 1_024 * 1_024)
  }

  @Test("decoded cache evicts the least-recently-used entry by byte cost")
  func decodedCacheByteEviction() throws {
    let repository = ImageAssetRepository(
      decodedCachePolicy: .init(maxEntries: 64, maxBytes: 15)
    )
    let firstReference = ImageAssetReference.namedResource("first")
    let secondReference = ImageAssetReference.namedResource("second")

    #expect(repository.storeDecodedImage(image(width: 2), for: firstReference))
    #expect(repository.storeDecodedImage(image(width: 2), for: secondReference))

    #expect(repository.decodedImage(for: firstReference) == nil)
    _ = try #require(repository.decodedImage(for: secondReference))
    let occupancy = repository.occupancy()
    #expect(occupancy.decodedCount == 1)
    #expect(occupancy.decodedApproxBytes == 9)
  }

  @Test("decoded cache evicts the least-recently-used entry by entry count")
  func decodedCacheEntryEviction() throws {
    let repository = ImageAssetRepository(
      decodedCachePolicy: .init(maxEntries: 2, maxBytes: .max)
    )
    let firstReference = ImageAssetReference.namedResource("first")
    let secondReference = ImageAssetReference.namedResource("second")
    let thirdReference = ImageAssetReference.namedResource("third")

    #expect(repository.storeDecodedImage(image(), for: firstReference))
    #expect(repository.storeDecodedImage(image(), for: secondReference))
    _ = try #require(repository.decodedImage(for: firstReference))
    #expect(repository.storeDecodedImage(image(), for: thirdReference))

    _ = try #require(repository.decodedImage(for: firstReference))
    #expect(repository.decodedImage(for: secondReference) == nil)
    _ = try #require(repository.decodedImage(for: thirdReference))
    #expect(repository.occupancy().decodedCount == 2)
  }

  @Test("decoded cache replacement subtracts the prior entry cost")
  func decodedCacheReplacementCost() throws {
    let repository = ImageAssetRepository(
      decodedCachePolicy: .init(maxEntries: 4, maxBytes: 100)
    )
    let replacedReference = ImageAssetReference.namedResource("replaced")
    let retainedReference = ImageAssetReference.namedResource("retained")

    #expect(repository.storeDecodedImage(image(width: 1), for: replacedReference))
    #expect(repository.storeDecodedImage(image(width: 2), for: retainedReference))
    #expect(
      repository.storeDecodedImage(
        image(width: 3, encodedByteCount: 2),
        for: replacedReference
      )
    )

    let replacement = try #require(repository.decodedImage(for: replacedReference))
    #expect(replacement.pixelSize == .init(width: 3, height: 1))
    let occupancy = repository.occupancy()
    #expect(occupancy.decodedCount == 2)
    #expect(occupancy.decodedApproxBytes == 23)
  }

  @Test("decoded cache rejects overflowing dimensions and oversized entries")
  func decodedCacheRejectsOversizedImages() {
    let repository = ImageAssetRepository(
      decodedCachePolicy: .init(maxEntries: 4, maxBytes: 8)
    )
    let overflowing = DecodedImage(
      encodedBytes: [],
      encodedFormat: .png,
      pixelSize: .init(width: .max, height: 2),
      pixels: []
    )

    #expect(
      !repository.storeDecodedImage(
        overflowing,
        for: .namedResource("overflowing")
      )
    )
    #expect(
      !repository.storeDecodedImage(
        image(width: 2),
        for: .namedResource("oversized")
      )
    )
    #expect(repository.occupancy().decodedCount == 0)
    #expect(repository.occupancy().decodedApproxBytes == 0)
  }

  @Test("repeated references occupy and charge one decoded entry")
  func decodedCacheRepeatedReference() throws {
    let pngBytes = try makePNGBytes(
      width: 2,
      height: 1,
      pixels: [
        rgbaPixel(red: 255, green: 0, blue: 0),
        rgbaPixel(red: 0, green: 255, blue: 0),
      ]
    )
    let repository = ImageAssetRepository()
    let reference = ImageAssetReference.embeddedImage(pngBytes)

    _ = try #require(repository.decodedImage(for: reference))
    let firstOccupancy = repository.occupancy()
    _ = try #require(repository.decodedImage(for: reference))

    #expect(repository.occupancy().decodedCount == 1)
    #expect(repository.occupancy().decodedApproxBytes == firstOccupancy.decodedApproxBytes)
    #expect(firstOccupancy.decodedApproxBytes == pngBytes.count + 8)
  }

  @Test("resolution cache evicts by retained encoded-byte cost")
  func resolutionCacheByteEviction() throws {
    let firstBytes = try makePNGBytes(
      width: 1,
      height: 1,
      pixels: [rgbaPixel(red: 255, green: 0, blue: 0)]
    )
    let secondBytes = try makePNGBytes(
      width: 1,
      height: 1,
      pixels: [rgbaPixel(red: 0, green: 255, blue: 0)]
    )
    let oneEntryCost = max(firstBytes.count, secondBytes.count) * 2
    let repository = ImageAssetRepository(
      resolutionCachePolicy: .init(maxEntries: 8, maxBytes: oneEntryCost),
      decodedCachePolicy: .init(maxEntries: 8, maxBytes: .max)
    )

    _ = try #require(
      repository.resolve(
        .data(firstBytes),
        resourceRoots: [],
        cellPixelSize: .init(width: 8, height: 16)
      )
    )
    _ = try #require(
      repository.resolve(
        .data(secondBytes),
        resourceRoots: [],
        cellPixelSize: .init(width: 8, height: 16)
      )
    )

    let occupancy = repository.occupancy()
    #expect(occupancy.resolutionCount == 1)
    #expect(occupancy.resolutionApproxBytes <= oneEntryCost)
  }

  @Test("oversized resolution payload renders but is not cached")
  func oversizedResolutionIsNotCached() throws {
    let pngBytes = try makePNGBytes(
      width: 1,
      height: 1,
      pixels: [rgbaPixel(red: 255, green: 0, blue: 0)]
    )
    let repository = ImageAssetRepository(
      resolutionCachePolicy: .init(maxEntries: 8, maxBytes: pngBytes.count),
      decodedCachePolicy: .init(maxEntries: 8, maxBytes: .max)
    )

    _ = try #require(
      repository.resolve(
        .data(pngBytes),
        resourceRoots: [],
        cellPixelSize: .init(width: 8, height: 16)
      )
    )

    #expect(repository.occupancy().resolutionCount == 0)
    #expect(repository.occupancy().resolutionApproxBytes == 0)
  }

  private func image(
    width: Int = 1,
    height: Int = 1,
    encodedByteCount: Int = 1
  ) -> DecodedImage {
    DecodedImage(
      encodedBytes: Array(repeating: 1, count: encodedByteCount),
      encodedFormat: .png,
      pixelSize: .init(width: width, height: height),
      pixels: Array(
        repeating: RGBAImagePixel(red: 1, green: 2, blue: 3, alpha: 4),
        count: width * height
      )
    )
  }
}
