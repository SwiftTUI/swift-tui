// Adversarial set B, pass 4: the vendored baseline JPEG decoder and its
// runtime image pipeline (381–390).
//
// A JPEG travels from the marker walk through the Huffman bit reader, the
// IDCT, chroma upsampling and colour conversion into the repository's decode
// cache, and from there to Kitty raw-RGBA payloads and the `Image` view's
// unresolved-source issue. The decoder's own error enum, T.81 and libjpeg's
// behaviour are the contracts. These probes feed non-divisible sampling
// ratios, a zero-component scan, an out-of-range quantization selector, a
// stream without its trailer, an EXIF orientation, an unscanned chroma
// plane and a progressive frame, and pin restart handling, lenient marker
// walking and every truncation point. Streams are assembled by hand.
import SwiftTUIVendorJPEG
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: JPEG", .serialized)
struct AdversarialSetBJPEGTests {
  private func unresolvedIssue(for bytes: [UInt8], _ name: String) -> RuntimeIssue? {
    DefaultRenderer().render(
      Image(data: bytes), context: .init(identity: testIdentity("SetBJPEG", name)),
      proposal: .init(width: 8, height: 4)
    ).diagnostics.runtime.issues.first { $0.code == "image.unresolvedSource" }
  }

  // A 3:2 horizontal sampling ratio is not divisible; the decoder says such
  // ratios are rejected, so decoding must throw, not trap in the upsampler.
  @Test func setB381NonDivisibleSamplingRatiosThrowInsteadOfTrapping() async {
    await withKnownIssue(
      "hMax / H truncates 3 / 2 to 1 and the nearest-neighbour upsampler indexes past the Cb plane"
    ) {
      await #expect(processExitsWith: .success) {
        let bytes = SetBJPEG.file(
          width: 24, height: 8,
          components: [
            SetBJPEGComponent(id: 1, h: 3), SetBJPEGComponent(id: 2, h: 2),
            SetBJPEGComponent(id: 3),
          ],
          scans: [SetBJPEGScan(ids: [1, 2, 3], data: SetBJPEG.blocks([0, 0, 0, 0, 0, 0]))])
        let error = SetBJPEG.failure(bytes)
        #expect(error != nil, "decoded without an error")
      }
    }
  }

  // A scan header declaring zero components is invalid (T.81 B.2.3); libjpeg
  // rejects it, so the decoder throws and the repository resolves nothing.
  @Test func setB382ZeroComponentScanIsRejected() {
    let bytes = SetBJPEG.file(
      width: 8, height: 8, components: [SetBJPEGComponent(id: 1)],
      scans: [SetBJPEGScan(ids: [], data: [])])
    withKnownIssue(
      "parseSOS accepts Ns = 0, walks no blocks and returns the zero-filled planes as a black image"
    ) {
      let first = (try? SetBJPEG.luma(bytes))?.first
      #expect(SetBJPEG.failure(bytes) != nil, "decoded; first sample \(String(describing: first))")
      #expect(ImageAssetRepository().decodedImage(for: .embeddedImage(bytes)) == nil)
    }
  }

  // A quantization-table selector of 4 is a table error; the thrown case must
  // not claim that the component's valid sampling factors are invalid.
  @Test func setB383OutOfRangeQuantSelectorIsNotReportedAsASamplingError() throws {
    let bytes = SetBJPEG.file(
      width: 8, height: 8, components: [SetBJPEGComponent(id: 1, tq: 4)],
      scans: [SetBJPEGScan(ids: [1], data: SetBJPEG.blocks([0]))])
    let error = try #require(SetBJPEG.failure(bytes))
    withKnownIssue("parseSOF throws invalidSamplingFactors(H = 1, V = 1) for a Tq outside 0...3") {
      #expect(error != .invalidSamplingFactors(componentID: 1, h: 1, v: 1), "\(error)")
    }
  }

  // A stream whose scan is complete but that lacks the EOI trailer is decoded
  // by libjpeg, stb_image and ImageIO; only the trailer is missing.
  @Test func setB384MissingEOIAfterACompleteScanStillDecodes() throws {
    let complete = SetBJPEG.file(
      width: 8, height: 8, components: [SetBJPEGComponent(id: 1)],
      scans: [SetBJPEGScan(ids: [1], data: SetBJPEG.blocks([800]))])
    let luma = try SetBJPEG.luma(complete)
    #expect(luma == Array(repeating: 228, count: 64), "\(luma)")
    let noTrailer = Array(complete.dropLast(2))
    withKnownIssue("the marker walk after the scan reaches end-of-stream and throws truncated") {
      #expect(
        SetBJPEG.failure(noTrailer) == nil, "\(String(describing: SetBJPEG.failure(noTrailer)))")
      #expect(ImageAssetRepository().decodedImage(for: .embeddedImage(noTrailer)) != nil)
    }
  }

  // An APP1 Exif orientation of 6 means "rotate 90 degrees clockwise to
  // display"; ImageIO and SwiftUI honour it, so a 16×8 file presents as 8×16.
  @Test func setB385ExifOrientationIsApplied() throws {
    let bytes = SetBJPEG.file(
      width: 16, height: 8, components: [SetBJPEGComponent(id: 1)],
      scans: [SetBJPEGScan(ids: [1], data: SetBJPEG.blocks([-800, 1600]))],
      headerSegments: SetBJPEG.exifOrientation(6))
    let decoded = try #require(ImageAssetRepository().decodedImage(for: .embeddedImage(bytes)))
    let reds = decoded.pixels.map(\.red)
    #expect(reds.contains(28) && reds.contains(228), "\(Set(reds))")
    #expect(decoded.encodedFormat == .jpeg)
    withKnownIssue(
      "APP1 segments are skipped unparsed; the orientation tag never reaches the pixels"
    ) {
      #expect(decoded.pixelSize == PixelSize(width: 8, height: 16), "\(decoded.pixelSize)")
    }
  }

  // A three-component frame whose only scan carries Y leaves Cb and Cr
  // undefined; libjpeg's pre-zeroed coefficients give the neutral 128, so the
  // output is grey, never a saturated colour.
  @Test func setB386UnscannedChromaPlanesAreNeutral() throws {
    let bytes = SetBJPEG.file(
      width: 8, height: 8, components: SetBJPEG.ycc,
      scans: [SetBJPEGScan(ids: [1], data: SetBJPEG.blocks([0]))])
    let pixels = try SetBJPEG.pixels(bytes)
    let pixel = try #require(pixels.first)
    withKnownIssue(
      "planes hold zero samples, not zero coefficients, so Cb = Cr = 0 converts to (0, 255, 0)"
    ) {
      let spread = max(pixel.r, pixel.g, pixel.b) - min(pixel.r, pixel.g, pixel.b)
      #expect(spread < 16, "\(pixel)")
    }
  }

  // Progressive JPEGs are the commonest unsupported input and the decoder
  // names the process in its error; the runtime issue for such a source must
  // be distinguishable from one for corrupt bytes of the same length.
  @Test func setB387ProgressiveJPEGIssueNamesTheUnsupportedProcess() throws {
    let progressive = SetBJPEG.file(
      width: 8, height: 8, components: [SetBJPEGComponent(id: 1)],
      scans: [SetBJPEGScan(ids: [1], data: SetBJPEG.blocks([0]))], frameMarker: 0xC2)
    #expect(SetBJPEG.failure(progressive) == .unsupportedProcess(marker: 0xC2))
    var garbage = progressive
    for index in 3..<garbage.count {
      garbage[index] = 0x00
    }
    let progressiveIssue = try #require(unresolvedIssue(for: progressive, "progressive"))
    let garbageIssue = try #require(unresolvedIssue(for: garbage, "garbage"))
    withKnownIssue(
      "decodeImageBytes drops the decoder error with try?, so every bad source gets one message"
    ) {
      let message = progressiveIssue.message.lowercased()
      let named = ["progressive", "sof2", "unsupported"].contains { message.contains($0) }
      #expect(named, "\(progressiveIssue.message)")
      #expect(progressiveIssue.message != garbageIssue.message, "\(progressiveIssue.message)")
    }
  }

  // Restart intervals reset the DC predictor and realign the bit reader at
  // each RSTn: two MCUs that both code +800 both decode to 228, and an
  // out-of-sequence restart index is tolerated as libjpeg tolerates it.
  @Test func setB388RestartIntervalsResetTheDCPredictor() throws {
    func file(marker: UInt8) -> [UInt8] {
      SetBJPEG.file(
        width: 16, height: 8, components: [SetBJPEGComponent(id: 1)],
        scans: [
          SetBJPEGScan(
            ids: [1], data: SetBJPEG.blocks([800]) + [0xFF, marker] + SetBJPEG.blocks([800]))
        ],
        restartInterval: 1)
    }
    let luma = try SetBJPEG.luma(file(marker: 0xD0))
    #expect(luma.count == 128)
    #expect(luma[0] == 228 && luma[8] == 228, "\(luma[0]) \(luma[8])")
    #expect(luma[7 * 16 + 15] == 228, "\(luma[7 * 16 + 15])")
    let skewed = try SetBJPEG.luma(file(marker: 0xD5))
    #expect(skewed[8] == 228, "\(skewed[8])")
  }

  // Fill bytes before a marker, APPn segments whose length field is below 2,
  // a COM segment and bytes after EOI are tolerated as libjpeg tolerates
  // them; a table segment with a short length is a hard error.
  @Test func setB389LenientMarkerWalkingMatchesLibjpeg() throws {
    let noise: [UInt8] =
      [0xFF, 0xE1, 0x00, 0x00] + [0xFF, 0xE2, 0x00, 0x01]
      + SetBJPEG.segment(0xFE, Array("set B".utf8)) + [0xFF, 0xFF, 0xFF]
    let bytes =
      SetBJPEG.file(
        width: 8, height: 8, components: [SetBJPEGComponent(id: 1)],
        scans: [SetBJPEGScan(ids: [1], data: SetBJPEG.blocks([800]))], headerSegments: noise)
      + [UInt8](repeating: 0x42, count: 64)
    let luma = try SetBJPEG.luma(bytes)
    #expect(luma == Array(repeating: 228, count: 64), "\(luma)")
    var shortTable = SetBJPEG.file(
      width: 8, height: 8, components: [SetBJPEGComponent(id: 1)],
      scans: [SetBJPEGScan(ids: [1], data: SetBJPEG.blocks([800]))])
    #expect(shortTable[2] == 0xFF && shortTable[3] == 0xDB)
    shortTable[4] = 0x00
    shortTable[5] = 0x01
    #expect(
      SetBJPEG.failure(shortTable) == .malformedSegment(marker: 0xDB, reason: "length < 2"),
      "\(String(describing: SetBJPEG.failure(shortTable)))")
  }

  // Every proper prefix of at least two bytes of a valid stream fails with
  // `.truncated`, whichever length field, payload or entropy byte the cut
  // lands in; shorter prefixes are `.missingSOI`. Nothing traps.
  @Test func setB390EveryTruncationPointThrowsTruncated() {
    let complete = SetBJPEG.file(
      width: 8, height: 8, components: [SetBJPEGComponent(id: 1)],
      scans: [SetBJPEGScan(ids: [1], data: SetBJPEG.blocks([800]))])
    #expect(SetBJPEG.failure(complete) == nil)
    #expect(SetBJPEG.failure([]) == .missingSOI)
    #expect(SetBJPEG.failure([0xFF]) == .missingSOI)
    var offenders: [(Int, String)] = []
    for length in 2..<complete.count {
      let error = SetBJPEG.failure(Array(complete.prefix(length)))
      if case .truncated? = error { continue }
      offenders.append((length, String(describing: error)))
    }
    #expect(offenders.isEmpty, "\(offenders)")
  }
}

private struct SetBJPEGSource: JPEG.BytestreamSource {
  var bytes: [UInt8]
  var position = 0

  mutating func read(count: Int) -> [UInt8]? {
    guard count >= 0, position + count <= bytes.count else { return nil }
    defer { position += count }
    return Array(bytes[position..<(position + count)])
  }
}

private struct SetBJPEGComponent {
  var id: UInt8
  var h = 1
  var v = 1
  var tq: UInt8 = 0
}

private struct SetBJPEGScan {
  var ids: [UInt8]
  var data: [UInt8]
}

/// MSB-first bit packer with JPEG byte stuffing; `finish` pads with ones.
private struct SetBBitWriter {
  private var bytes: [UInt8] = []
  private var current: UInt32 = 0
  private var count = 0

  mutating func write(_ value: UInt32, bits: Int) {
    var shift = bits
    while shift > 0 {
      shift -= 1
      current = (current << 1) | ((value >> UInt32(shift)) & 1)
      count += 1
      if count == 8 { flush() }
    }
  }

  mutating func finish() -> [UInt8] {
    while count != 0 { write(1, bits: 1) }
    return bytes
  }

  private mutating func flush() {
    bytes.append(UInt8(current))
    if current == 0xFF { bytes.append(0x00) }
    current = 0
    count = 0
  }
}

/// Assembles baseline JPEG streams whose blocks are DC-only. Quantization
/// table 0 is all ones, DC table 0 maps symbols 0...11 to the 4-bit codes
/// 0000...1011 and AC table 0 maps EOB to the 2-bit code 00, so a block whose
/// DC value is `d` decodes to the sample `⌊128.5 + d / 8⌋`.
private enum SetBJPEG {
  static let ycc = [SetBJPEGComponent(id: 1), SetBJPEGComponent(id: 2), SetBJPEGComponent(id: 3)]

  static let flatQuant = segment(0xDB, [0x00] + [UInt8](repeating: 1, count: 64))

  static let dcTable = segment(
    0xC4, [0x00, 0, 0, 0, 12] + [UInt8](repeating: 0, count: 12) + (0...11).map { UInt8($0) })

  static let acTable = segment(
    0xC4, [0x10, 0, 4] + [UInt8](repeating: 0, count: 14) + [0x00, 0xF0, 0x01, 0xF1])

  static func segment(_ marker: UInt8, _ payload: [UInt8]) -> [UInt8] {
    let length = payload.count + 2
    return [0xFF, marker, UInt8(length >> 8), UInt8(length & 0xFF)] + payload
  }

  static func frame(
    width: Int, height: Int, components: [SetBJPEGComponent], marker: UInt8
  ) -> [UInt8] {
    var payload: [UInt8] = [
      8, UInt8(height >> 8), UInt8(height & 0xFF), UInt8(width >> 8), UInt8(width & 0xFF),
      UInt8(components.count),
    ]
    for component in components {
      payload += [component.id, UInt8(component.h << 4 | component.v), component.tq]
    }
    return segment(marker, payload)
  }

  static func scanHeader(ids: [UInt8]) -> [UInt8] {
    var payload: [UInt8] = [UInt8(ids.count)]
    for id in ids {
      payload += [id, 0x00]
    }
    payload += [0x00, 0x3F, 0x00]
    return segment(0xDA, payload)
  }

  /// Entropy-codes DC-only blocks in scan order; each value is the block's DC
  /// difference from its predecessor.
  static func blocks(_ dcDifferences: [Int]) -> [UInt8] {
    var writer = SetBBitWriter()
    for difference in dcDifferences {
      let magnitude = difference.magnitude
      var category = 0
      while (UInt(1) << category) <= magnitude {
        category += 1
      }
      writer.write(UInt32(category), bits: 4)
      if category > 0 {
        let bits = difference >= 0 ? difference : difference + (1 << category) - 1
        writer.write(UInt32(bits), bits: category)
      }
      writer.write(0, bits: 2)
    }
    return writer.finish()
  }

  /// An APP1 Exif segment carrying only a little-endian IFD0 Orientation tag.
  static func exifOrientation(_ value: UInt8) -> [UInt8] {
    segment(
      0xE1,
      [
        0x45, 0x78, 0x69, 0x66, 0x00, 0x00,
        0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00,
        0x01, 0x00,
        0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, value, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
      ])
  }

  static func file(
    width: Int, height: Int, components: [SetBJPEGComponent], scans: [SetBJPEGScan],
    frameMarker: UInt8 = 0xC0, headerSegments: [UInt8] = [], restartInterval: Int? = nil,
    eoi: Bool = true
  ) -> [UInt8] {
    var bytes: [UInt8] = [0xFF, 0xD8] + headerSegments + flatQuant
    bytes += frame(width: width, height: height, components: components, marker: frameMarker)
    bytes += dcTable + acTable
    if let restartInterval {
      bytes += segment(0xDD, [UInt8(restartInterval >> 8), UInt8(restartInterval & 0xFF)])
    }
    for scan in scans {
      bytes += scanHeader(ids: scan.ids) + scan.data
    }
    if eoi { bytes += [0xFF, 0xD9] }
    return bytes
  }

  static func decode(_ bytes: [UInt8]) throws -> JPEG.Image {
    var source = SetBJPEGSource(bytes: bytes)
    return try JPEG.Image.decompress(stream: &source)
  }

  static func pixels(_ bytes: [UInt8]) throws -> [JPEG.RGBA<UInt8>] {
    try decode(bytes).unpack(as: JPEG.RGBA<UInt8>.self)
  }

  static func luma(_ bytes: [UInt8]) throws -> [Int] {
    try pixels(bytes).map { Int($0.r) }
  }

  /// The decoding error for `bytes`, or nil when they decode.
  static func failure(_ bytes: [UInt8]) -> JPEG.DecodingError? {
    do {
      _ = try decode(bytes)
      return nil
    } catch let error as JPEG.DecodingError {
      return error
    } catch {
      return nil
    }
  }
}
