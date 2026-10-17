import Testing

@testable import SwiftTUIAnimatedImage

@MainActor
@Suite(.serialized)
struct AdversarialSetAAnimatedCodecTests {
  @Test func setA876PreviousDisposalRestoresTheActualPostBackgroundCanvas() throws {
    // Hypothesis: mixed background/previous disposal restores a snapshot from before the background clear.
    let bytes = gif(
      width: 2,
      blocks:
        control(disposal: 1) + frame(width: 2, indices: [1, 1])
        + control(disposal: 2) + frame(indices: [2])
        + control(disposal: 3) + frame(left: 1, indices: [3])
        + control(transparent: 0) + frame(indices: [0]))
    let decoded = try AnimatedGIF.decode(data: bytes)
    try #require(decoded.frames.count == 4)
    #expect(decoded.frames[2].pixels == [black, blue])
    do {
      #expect(decoded.frames[3].pixels == [black, red])
    }
  }

  @Test func setA877PlainTextConsumesItsOwnGraphicsControlExtension() throws {
    // Hypothesis: skipping a graphic Plain Text block leaks its pending delay into the following image.
    // GIF89a sections 23/25: Plain Text is a graphic rendering block and consumes the preceding GCE.
    let plainText: [UInt8] = [0x21, 0x01, 12, 0, 0, 0, 0, 1, 0, 1, 0, 1, 1, 1, 0, 1, 65, 0]
    let decoded = try AnimatedGIF.decode(
      data: gif(
        blocks:
          control(delay: 47) + plainText + frame(indices: [1])))
    do {
      #expect(decoded.frameDelays == [.milliseconds(100)])
    }
    #expect(decoded.frames[0].pixels == [red])
  }

  @Test func setA878CommentDoesNotConsumePendingGraphicsControl() throws {
    // Hypothesis: a non-rendering comment resets timing before the controlled image arrives.
    let comment: [UInt8] = [0x21, 0xFE, 3, 0x21, 0x2C, 0x3B, 0]
    let decoded = try AnimatedGIF.decode(
      data: gif(
        blocks:
          control(delay: 31) + comment + frame(indices: [2])))
    #expect(decoded.frameDelays == [.milliseconds(310)])
    #expect(decoded.frames[0].pixels == [green])
  }

  @Test func setA879ApplicationPayloadDoesNotBecomeAnImageOrConsumeTiming() throws {
    // Hypothesis: an unrecognized application payload is scanned as top-level introducers or clears the GCE.
    let app = application("NOTALOOP1.0", payload: [0x2C, 0x21, 0x3B, 0xF9])
    let decoded = try AnimatedGIF.decode(
      data: gif(
        blocks:
          control(delay: 23) + app + frame(indices: [3])))
    #expect(decoded.frames.count == 1)
    #expect(decoded.frameDelays == [.milliseconds(230)])
  }

  @Test func setA880GraphicsControlStateExpiresAfterOneImage() throws {
    // Hypothesis: an image without a GCE inherits the previous image's transparency and delay.
    let decoded = try AnimatedGIF.decode(
      data: gif(
        blocks:
          control(delay: 9, transparent: 0) + frame(indices: [0]) + frame(indices: [0])))
    try #require(decoded.frames.count == 2)
    #expect(decoded.frames[0].pixels[0].alpha == 0)
    #expect(decoded.frames[1].pixels == [black])
    #expect(decoded.frameDelays == [.milliseconds(90), .milliseconds(100)])
  }

  @Test func setA881LocalPaletteCannotReplaceTheNextFramesGlobalPalette() throws {
    // Hypothesis: local palette state persists after its descriptor and recolors a later global index.
    let local: [UInt8] = [0, 0, 0, 255, 255, 255, 0, 255, 0, 0, 0, 255]
    let decoded = try AnimatedGIF.decode(
      data: gif(
        blocks:
          frame(indices: [1], localPalette: local) + frame(indices: [1])))
    try #require(decoded.frames.count == 2)
    #expect(decoded.frames[0].pixels == [.init(red: 255, green: 255, blue: 255)])
    #expect(decoded.frames[1].pixels == [red])
  }

  @Test func setA882LocalOnlyImageLeavesItsUnpaintedLogicalScreenTransparent() throws {
    // Hypothesis: absence of a global color table fills off-frame pixels with local palette entry zero.
    let decoded = try AnimatedGIF.decode(
      data: gif(
        width: 3, global: false,
        blocks: frame(left: 1, indices: [1], localPalette: palette)))
    #expect(decoded.frames[0].pixels.map(\.alpha) == [0, 255, 0])
    #expect(decoded.frames[0].pixels[1] == red)
  }

  @Test func setA883InterlacedOddHeightRetainsEveryRowAndColumn() throws {
    // Hypothesis: short interlace passes shift source rows when the image height is not a multiple of eight.
    let rows: [UInt8] = [0, 1, 2, 3, 1, 2, 3, 0, 2]
    let passOrder = [0, 8, 4, 2, 6, 1, 3, 5, 7]
    let encoded = passOrder.flatMap { [rows[$0], UInt8(3) - rows[$0]] }
    let decoded = try AnimatedGIF.decode(
      data: gif(
        width: 2, height: 9,
        blocks: frame(width: 2, height: 9, indices: encoded, interlaced: true)))
    let colors = [black, red, green, blue]
    #expect(decoded.frames[0].pixels == rows.flatMap { [colors[Int($0)], colors[3 - Int($0)]] })
  }

  @Test func setA884LZWBitCodesSpanIndependentSubblocks() throws {
    // Hypothesis: splitting compressed data at byte boundaries resets the LZW bit reservoir.
    let indices: [UInt8] = [3, 1, 2, 0, 2, 1, 3]
    let decoded = try AnimatedGIF.decode(
      data: gif(
        width: 7,
        blocks: frame(width: 7, indices: indices, splitBytes: true)))
    #expect(decoded.frames[0].pixels == indices.map { [black, red, green, blue][Int($0)] })
  }

  @Test func setA885LZWForwardDictionaryReferenceExpandsPreviousPlusFirstByte() throws {
    // Hypothesis: the valid KwKwK code equal to the next dictionary slot is rejected or expanded incorrectly.
    let decoded = try AnimatedGIF.decode(
      data: gif(
        width: 3,
        blocks: frame(width: 3, indices: [], codes: [4, 1, 6, 5])))
    #expect(decoded.frames[0].pixels == [red, red, red])
  }

  @Test func setA886ClearCodeResetsThePreviousDictionaryReferenceMidImage() throws {
    // Hypothesis: a second clear retains the previous prefix and synthesizes a cross-reset dictionary entry.
    let decoded = try AnimatedGIF.decode(
      data: gif(
        width: 5,
        blocks: frame(width: 5, indices: [], codes: [4, 1, 6, 4, 2, 3, 5])))
    #expect(decoded.frames[0].pixels == [red, red, red, green, blue])
  }

  @Test func setA887OutOfBoundsDescriptorThrowsBeforeCompositing() {
    // Hypothesis: descriptor offsets are ignored during validation and escape the logical-screen pixel buffer.
    #expect(throws: (any Error).self) {
      try AnimatedGIF.decode(data: gif(blocks: frame(left: 1, indices: [1])))
    }
  }

  @Test func setA888TransparentIndexOutsidePaletteDoesNotRequireAColorLookup() throws {
    // Hypothesis: an out-of-palette transparent marker is rejected before transparency can suppress lookup.
    let decoded = try AnimatedGIF.decode(
      data: gif(
        blocks:
          control(transparent: 7) + frame(indices: [7], codeSize: 3)))
    #expect(decoded.frames[0].pixels[0].alpha == 0)
  }

  @Test func setA889OpaqueIndexOutsidePaletteFailsInsteadOfBecomingClear() {
    // Hypothesis: malformed opaque palette references silently become transparent during compositing.
    #expect(throws: (any Error).self) {
      try AnimatedGIF.decode(data: gif(blocks: frame(indices: [7], codeSize: 3)))
    }
  }

  @Test func setA890TruncatedImageSubblockIsRejectedAtItsDeclaredLength() {
    // Hypothesis: incomplete data subblocks are accepted because enough LZW output was already decoded.
    var bytes = gif(blocks: frame(indices: [1]))
    bytes.removeLast(2)
    bytes.append(contentsOf: [20, 0x44])
    #expect(throws: (any Error).self) { try AnimatedGIF.decode(data: bytes) }
  }

  @Test func setA891ContainerWithNoImagesThrowsInsteadOfConstructingAnEmptySequence() {
    // Hypothesis: a header/trailer-only file reaches the sequence initializer's nonempty-frame precondition.
    #expect(throws: (any Error).self) { try AnimatedGIF.decode(data: gif(blocks: [])) }
  }

  @Test func setA892InvalidMinimumCodeSizeIsRejectedBeforeBitShifting() {
    // Hypothesis: external code size 255 reaches integer shifts or dictionary allocation before validation.
    var block = frame(indices: [1])
    block[10] = 255
    #expect(throws: (any Error).self) { try AnimatedGIF.decode(data: gif(blocks: block)) }
  }

  @Test func setA893UnrecognizedLoopApplicationCannotSpoofRepeatMetadata() throws {
    // Hypothesis: any application subblock beginning with 01 is misinterpreted as Netscape repeat metadata.
    let decoded = try AnimatedGIF.decode(
      data: gif(
        blocks:
          application("UNRELATED00", payload: [1, 17, 0]) + frame(indices: [1])))
    #expect(decoded.loopCount == nil)
  }

  @Test func setA894GIF87HeaderStillDecodesWithoutGraphicsExtensions() throws {
    // Hypothesis: version dispatch accidentally requires a GIF89a header even for a plain 87a image.
    var bytes = gif(blocks: frame(indices: [2]))
    bytes[4] = 0x37
    let decoded = try AnimatedGIF.decode(data: bytes)
    #expect(decoded.frames[0].pixels == [green])
    #expect(decoded.loopCount == nil)
  }

  @Test func setA895AlternateLoopIdentifierKeepsHighByteOfRepeatCount() throws {
    // Hypothesis: ANIMEXTS loop metadata is ignored or its two-byte count is truncated to the low byte.
    let decoded = try AnimatedGIF.decode(
      data: gif(
        blocks:
          application("ANIMEXTS1.0", payload: [1, 2, 1]) + frame(indices: [3])))
    #expect(decoded.loopCount == 258)
  }

  @Test func setA896AlreadyCancelledPlaybackPublishesNoInitialFrame() async {
    // Hypothesis: initial-frame publication happens before the playback owner's cancellation check.
    let source = sequence(delays: [.milliseconds(20), .milliseconds(30)])
    let task = Task { @MainActor in
      var published: [Int] = []
      await AnimatedImagePlayback.run(source, onFrame: { published.append($0) }, sleep: { _ in })
      return published
    }
    task.cancel()
    #expect(await task.value.isEmpty)
  }

  @Test func setA897PlaybackRetainsSaturatedUnsignedDelayBeyondPublicProjection() async {
    // Hypothesis: playback routes a saturated delay through the signed public Duration projection and halves the wait.
    let source = sequence(delays: [.seconds(Int64.max), .milliseconds(20)])
    var delays: [UInt64] = []
    await AnimatedImagePlayback.run(
      source, onFrame: { _ in },
      sleep: { delay in
        delays.append(delay)
        throw ClockStopped.stop
      })
    #expect(delays == [UInt64.max])
    #expect(source.frameDelays[0] == .nanoseconds(Int64.max))
  }

  @Test func setA898ClockFailureHoldsTheLastPublishedFrameWithoutRestart() async {
    // Hypothesis: a non-cancellation sleep error is swallowed and advances or restarts a finite sequence.
    let source = sequence(delays: [.milliseconds(20), .milliseconds(30)])
    var frames: [Int] = []
    var sleeps = 0
    await AnimatedImagePlayback.run(
      source, onFrame: { frames.append($0) },
      sleep: { _ in
        sleeps += 1
        if sleeps == 2 { throw ClockStopped.stop }
      })
    #expect(frames == [0, 1])
    #expect(sleeps == 2)
  }

  @Test func setA899SingleFrameFiniteRepeatsNeverScheduleRedundantTicks() async {
    // Hypothesis: large finite repeat metadata creates a sleep loop even though a one-frame image is static.
    let source = AnimatedImageSequence(frames: [pixel(red)], framesPerSecond: 10, loopCount: 65_535)
    var frames: [Int] = []
    await AnimatedImagePlayback.run(
      source, onFrame: { frames.append($0) },
      sleep: { _ in
        Issue.record("A static sequence must not schedule a clock tick")
        throw ClockStopped.stop
      })
    #expect(frames == [0])
  }

  @Test func setA900PaletteOverflowUsesAllRGBChannelsForNearestColor() throws {
    // Hypothesis: quantization chooses a palette neighbor by one channel or index instead of squared RGB distance.
    let colors = (0..<256).map { AnimatedImagePixel(red: UInt8($0), green: UInt8($0), blue: 0) }
    let extra = AnimatedImagePixel(red: 100, green: 104, blue: 0)
    let source = AnimatedImageSequence(
      frames: [
        .init(width: 257, height: 1, pixels: colors + [extra])
      ], framesPerSecond: 10)
    let decoded = try AnimatedGIF.decode(data: AnimatedGIF.encode(source))
    #expect(Array(decoded.frames[0].pixels.prefix(256)) == colors)
    #expect(decoded.frames[0].pixels.last == colors[102])
  }

  private enum ClockStopped: Error { case stop }
  private var black: AnimatedImagePixel { .init(red: 0, green: 0, blue: 0) }
  private var red: AnimatedImagePixel { .init(red: 255, green: 0, blue: 0) }
  private var green: AnimatedImagePixel { .init(red: 0, green: 255, blue: 0) }
  private var blue: AnimatedImagePixel { .init(red: 0, green: 0, blue: 255) }
  private var palette: [UInt8] { [0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255] }
  private func pixel(_ color: AnimatedImagePixel) -> AnimatedImageFrame {
    .init(width: 1, height: 1, pixels: [color])
  }
  private func sequence(delays: [Duration]) -> AnimatedImageSequence {
    .init(frames: [pixel(red), pixel(blue)], frameDelays: delays, loopCount: nil)
  }
  private func word(_ value: Int) -> [UInt8] { [UInt8(value & 255), UInt8((value >> 8) & 255)] }
  private func gif(width: Int = 1, height: Int = 1, global: Bool = true, blocks: [UInt8]) -> [UInt8]
  {
    Array("GIF89a".utf8) + word(width) + word(height) + [global ? 0x81 : 0, 0, 0]
      + (global ? palette : []) + blocks + [0x3B]
  }
  private func control(disposal: UInt8 = 1, delay: Int = 0, transparent: UInt8? = nil) -> [UInt8] {
    [0x21, 0xF9, 4, (disposal << 2) | (transparent == nil ? 0 : 1)] + word(delay)
      + [transparent ?? 0, 0]
  }
  private func application(_ name: String, payload: [UInt8]) -> [UInt8] {
    [0x21, 0xFF, UInt8(name.utf8.count)] + Array(name.utf8)
      + [UInt8(payload.count)] + payload + [0]
  }
  // Independent literal fixtures deliberately reset between pixels: no production encoder shares the oracle.
  private func frame(
    left: Int = 0, top: Int = 0, width: Int = 1, height: Int = 1,
    indices: [UInt8], localPalette: [UInt8]? = nil, interlaced: Bool = false,
    splitBytes: Bool = false, codes: [Int]? = nil, codeSize: Int = 2
  ) -> [UInt8] {
    let clear = 1 << codeSize
    let values = codes ?? (indices.flatMap { [clear, Int($0)] } + [clear + 1])
    var packed: [UInt8] = []
    var bits = 0
    var buffer = 0
    for code in values {
      buffer |= code << bits
      bits += codeSize + 1
      while bits >= 8 {
        packed.append(UInt8(buffer & 255))
        buffer >>= 8
        bits -= 8
      }
    }
    if bits > 0 { packed.append(UInt8(buffer & 255)) }
    var result: [UInt8] = [0x2C] + word(left) + word(top) + word(width) + word(height)
    result.append((localPalette == nil ? 0 : 0x81) | (interlaced ? 0x40 : 0))
    result += localPalette ?? []
    result.append(UInt8(codeSize))
    if splitBytes {
      result += packed.flatMap { [UInt8(1), $0] }
    } else {
      result += [UInt8(packed.count)] + packed
    }
    return result + [0]
  }
}
