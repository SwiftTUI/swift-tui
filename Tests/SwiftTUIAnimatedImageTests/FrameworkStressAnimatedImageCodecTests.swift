import SwiftTUI
import SwiftTUIAnimatedImage
import Testing

@MainActor
@Suite(.serialized)
struct FrameworkStressAnimatedImageCodecTests {
  @Test("stress animated image codec 001 billion-Hz playback clamps to one nanosecond")
  func animatedImageCodec001BillionHzPlaybackClampsToOneNanosecond() {
    let sequence = AnimatedImageSequence(frames: [Self.pixelFrame(.red)], framesPerSecond: 1e9)

    #expect(sequence.frameDelays == [.nanoseconds(1)])
  }

  @Test("stress animated image codec 002 fractional frame rate rounds to the nearest nanosecond")
  func animatedImageCodec002FractionalFrameRateRoundsToNearestNanosecond() {
    let sequence = AnimatedImageSequence(frames: [Self.pixelFrame(.red)], framesPerSecond: 24)

    #expect(sequence.frameDelays == [.nanoseconds(41_666_667)])
  }

  @Test("stress animated image codec 003 subnanosecond duration rounds up to one nanosecond")
  func animatedImageCodec003SubnanosecondDurationRoundsUpToOneNanosecond() {
    let sequence = AnimatedImageSequence(
      frames: [Self.pixelFrame(.red)],
      frameDelays: [Duration(secondsComponent: 0, attosecondsComponent: 1)]
    )

    #expect(sequence.frameDelays == [.nanoseconds(1)])
  }

  @Test("stress animated image codec 004 fractional nanosecond duration rounds upward")
  func animatedImageCodec004FractionalNanosecondDurationRoundsUpward() {
    let sequence = AnimatedImageSequence(
      frames: [Self.pixelFrame(.red)],
      frameDelays: [Duration(secondsComponent: 0, attosecondsComponent: 1_000_000_001)]
    )

    #expect(sequence.frameDelays == [.nanoseconds(2)])
  }

  @Test("stress animated image codec 005 enormous duration saturates its public projection")
  func animatedImageCodec005EnormousDurationSaturatesPublicProjection() {
    let sequence = AnimatedImageSequence(
      frames: [Self.pixelFrame(.red)],
      frameDelays: [.seconds(Int64.max)]
    )

    #expect(sequence.frameDelays == [.nanoseconds(Int64.max)])
  }

  @Test("stress animated image codec 006 delay projection remains independent after copying")
  func animatedImageCodec006DelayProjectionRemainsIndependentAfterCopying() {
    let sequence = AnimatedImageSequence(
      frames: [Self.pixelFrame(.red), Self.pixelFrame(.blue)],
      frameDelays: [.milliseconds(20), .milliseconds(40)]
    )
    var projected = sequence.frameDelays
    projected[0] = .seconds(9)

    #expect(sequence.frameDelays == [.milliseconds(20), .milliseconds(40)])
  }

  @Test("stress animated image codec 007 PNG emission preserves the canonical chunk order")
  func animatedImageCodec007PNGEmissionPreservesCanonicalChunkOrder() throws {
    let chunks = try Self.pngChunks(Self.pixelFrame(.red).imageData)

    #expect(chunks.map(\.type) == ["IHDR", "IDAT", "IEND"])
  }

  @Test("stress animated image codec 008 PNG IHDR retains dimensions above one byte")
  func animatedImageCodec008PNGIHDRRetainsDimensionsAboveOneByte() throws {
    let frame = Self.solidFrame(width: 257, height: 3, pixel: .green)
    let ihdr = try #require(Self.pngChunks(frame.imageData).first)

    #expect(Self.uint32(ihdr.data[0..<4]) == 257)
    #expect(Self.uint32(ihdr.data[4..<8]) == 3)
  }

  @Test("stress animated image codec 009 PNG stored scanline preserves authored pixel order")
  func animatedImageCodec009PNGStoredScanlinePreservesAuthoredPixelOrder() throws {
    let frame = AnimatedImageFrame(
      width: 2,
      height: 1,
      pixels: [.red, .blue]
    )
    let idat = try #require(Self.pngChunks(frame.imageData).first { $0.type == "IDAT" })
    let storedPayload = Array(idat.data.dropFirst(7).dropLast(4))

    #expect(storedPayload == [0, 255, 0, 0, 255, 0, 0, 255, 255])
  }

  @Test("stress animated image codec 010 PNG emission splits oversized raw data into stored blocks")
  func animatedImageCodec010PNGEmissionSplitsOversizedRawDataIntoStoredBlocks() throws {
    let frame = Self.solidFrame(width: 16_384, height: 1, pixel: .red)
    let idat = try #require(Self.pngChunks(frame.imageData).first { $0.type == "IDAT" })
    let firstBlockLength = Int(idat.data[3]) | (Int(idat.data[4]) << 8)
    let secondBlockOffset = 2 + 5 + firstBlockLength
    let secondBlockLength =
      Int(idat.data[secondBlockOffset + 1]) | (Int(idat.data[secondBlockOffset + 2]) << 8)

    #expect(firstBlockLength == 65_535)
    #expect(idat.data[secondBlockOffset] == 1)
    #expect(secondBlockLength == 2)
  }

  @Test("stress animated image codec 011 alpha-only pixel changes alter the PNG checksum")
  func animatedImageCodec011AlphaOnlyPixelChangesAlterPNGChecksum() throws {
    let opaque = Self.pixelFrame(.red).imageData
    let translucent = Self.pixelFrame(.init(red: 255, green: 0, blue: 0, alpha: 1)).imageData
    let opaqueIDAT = try #require(Self.pngChunks(opaque).first { $0.type == "IDAT" })
    let translucentIDAT = try #require(Self.pngChunks(translucent).first { $0.type == "IDAT" })

    #expect(opaqueIDAT.crc != translucentIDAT.crc)
  }

  @Test("stress animated image codec 012 opaque GIF pixel round-trips exactly")
  func animatedImageCodec012OpaqueGIFPixelRoundTripsExactly() throws {
    let sequence = Self.sequence(pixels: [.init(red: 23, green: 47, blue: 89)])
    let decoded = try Self.gifRoundTrip(sequence)

    #expect(decoded.frames == sequence.frames)
  }

  @Test("stress animated image codec 013 transparent GIF pixel stays transparent")
  func animatedImageCodec013TransparentGIFPixelStaysTransparent() throws {
    let sequence = Self.sequence(pixels: [.init(red: 200, green: 100, blue: 50, alpha: 0)])
    let decoded = try Self.gifRoundTrip(sequence)

    #expect(decoded.frames[0].pixels[0].alpha == 0)
  }

  @Test("stress animated image codec 014 partial GIF alpha normalizes to opaque")
  func animatedImageCodec014PartialGIFAlphaNormalizesToOpaque() throws {
    let source = AnimatedImagePixel(red: 23, green: 47, blue: 89, alpha: 127)
    let decoded = try Self.gifRoundTrip(Self.sequence(pixels: [source]))

    #expect(decoded.frames[0].pixels == [.init(red: 23, green: 47, blue: 89, alpha: 255)])
  }

  @Test("stress animated image codec 015 GIF frame order survives repeated colors")
  func animatedImageCodec015GIFFrameOrderSurvivesRepeatedColors() throws {
    let frames = [
      Self.pixelFrame(.red),
      Self.pixelFrame(.blue),
      Self.pixelFrame(.red),
      Self.pixelFrame(.green),
    ]
    let sequence = AnimatedImageSequence(
      frames: frames,
      frameDelays: Array(repeating: .milliseconds(20), count: frames.count)
    )
    let decoded = try Self.gifRoundTrip(sequence)

    #expect(decoded.frames == frames)
  }

  @Test("stress animated image codec 016 sub-centisecond GIF delay reaches the decoder floor")
  func animatedImageCodec016SubCentisecondGIFDelayReachesDecoderFloor() throws {
    let sequence = AnimatedImageSequence(
      frames: [Self.pixelFrame(.red)],
      frameDelays: [.milliseconds(1)]
    )
    let decoded = try Self.gifRoundTrip(sequence)

    #expect(decoded.frameDelays == [.milliseconds(20)])
  }

  @Test("stress animated image codec 017 fractional-centisecond GIF delay rounds upward")
  func animatedImageCodec017FractionalCentisecondGIFDelayRoundsUpward() throws {
    let sequence = AnimatedImageSequence(
      frames: [Self.pixelFrame(.red)],
      frameDelays: [.milliseconds(25)]
    )
    let decoded = try Self.gifRoundTrip(sequence)

    #expect(decoded.frameDelays == [.milliseconds(30)])
  }

  @Test("stress animated image codec 018 oversized GIF delay clamps to UInt16 centiseconds")
  func animatedImageCodec018OversizedGIFDelayClampsToUInt16Centiseconds() throws {
    let sequence = AnimatedImageSequence(
      frames: [Self.pixelFrame(.red)],
      frameDelays: [.seconds(10_000)]
    )
    let decoded = try Self.gifRoundTrip(sequence)

    #expect(decoded.frameDelays == [.milliseconds(655_350)])
  }

  @Test("stress animated image codec 019 255 nonblack GIF colors remain lossless")
  func animatedImageCodec019TwoHundredFiftyFiveNonblackGIFColorsRemainLossless() throws {
    let pixels = (1...255).map {
      AnimatedImagePixel(
        red: UInt8($0),
        green: UInt8(255 - $0),
        blue: UInt8(truncatingIfNeeded: $0 * 37)
      )
    }
    let decoded = try Self.gifRoundTrip(Self.sequence(pixels: pixels))

    #expect(decoded.frames[0].pixels == pixels)
  }

  @Test("stress animated image codec 020 255-color GIF including black remains lossless")
  func animatedImageCodec020TwoHundredFiftyFiveColorGIFIncludingBlackRemainsLossless() throws {
    let pixels = (0..<255).map {
      AnimatedImagePixel(
        red: UInt8($0),
        green: UInt8(255 - $0),
        blue: UInt8(truncatingIfNeeded: $0 * 37)
      )
    }
    let decoded = try Self.gifRoundTrip(Self.sequence(pixels: pixels))

    #expect(decoded.frames[0].pixels == pixels)
  }

  @Test("stress animated image codec 021 all 256 opaque GIF palette colors remain lossless")
  func animatedImageCodec021AllTwoHundredFiftySixOpaqueGIFPaletteColorsRemainLossless() throws {
    let pixels = (0...255).map {
      AnimatedImagePixel(
        red: UInt8($0),
        green: UInt8(truncatingIfNeeded: $0 * 73),
        blue: UInt8(truncatingIfNeeded: $0 * 151)
      )
    }
    let decoded = try Self.gifRoundTrip(Self.sequence(pixels: pixels))

    #expect(decoded.frames[0].pixels == pixels)
  }

  @Test("stress animated image codec 022 repeated GIF encoding is byte deterministic")
  func animatedImageCodec022RepeatedGIFEncodingIsByteDeterministic() throws {
    let sequence = Self.sequence(pixels: [.red, .green, .blue])

    #expect(try AnimatedGIF.encode(sequence) == AnimatedGIF.encode(sequence))
  }

  @Test("stress animated image codec 023 loop metadata never changes decoded frame content")
  func animatedImageCodec023LoopMetadataNeverChangesDecodedFrameContent() throws {
    let sequence = Self.sequence(pixels: [.red, .green, .blue])
    let finite = try AnimatedGIF.decode(data: AnimatedGIF.encode(sequence, loopCount: 3))
    let infinite = try AnimatedGIF.decode(data: AnimatedGIF.encode(sequence, loopCount: 0))

    #expect(finite == infinite)
  }

  @Test("stress animated image codec 024 trailing transport bytes do not corrupt GIF decoding")
  func animatedImageCodec024TrailingTransportBytesDoNotCorruptGIFDecoding() throws {
    let sequence = Self.sequence(pixels: [.red, .green, .blue])
    let encoded = try AnimatedGIF.encode(sequence) + [0xCA, 0xFE, 0xBA, 0xBE]
    let decoded = try AnimatedGIF.decode(data: encoded)
    let cleanRoundTrip = try Self.gifRoundTrip(sequence)

    #expect(decoded == cleanRoundTrip)
  }

  @Test("stress animated image codec 025 GIF initializer renders the decoded first frame")
  func animatedImageCodec025GIFInitializerRendersDecodedFirstFrame() throws {
    let sequence = AnimatedImageSequence(
      frames: [Self.pixelFrame(.red), Self.pixelFrame(.blue)],
      frameDelays: [.milliseconds(20), .milliseconds(20)]
    )
    let decoded = try AnimatedGIF.decode(data: AnimatedGIF.encode(sequence))
    let artifacts = try DefaultRenderer().render(
      AnimatedImage(gifData: AnimatedGIF.encode(sequence)))
    let attachment = try #require(artifacts.rasterSurface.imageAttachments.first)

    #expect(attachment.resolvedReference == .embeddedImage(decoded.frames[0].imageData))
  }

  private struct PNGChunk {
    var type: String
    var data: [UInt8]
    var crc: UInt32
  }

  private static func pngChunks(_ bytes: [UInt8]) throws -> [PNGChunk] {
    #expect(Array(bytes.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    var chunks: [PNGChunk] = []
    var offset = 8
    while offset < bytes.count {
      let length = Int(uint32(bytes[offset..<(offset + 4)]))
      let typeStart = offset + 4
      let dataStart = typeStart + 4
      let dataEnd = dataStart + length
      let type = String(decoding: bytes[typeStart..<(typeStart + 4)], as: UTF8.self)
      chunks.append(
        PNGChunk(
          type: type,
          data: Array(bytes[dataStart..<dataEnd]),
          crc: uint32(bytes[dataEnd..<(dataEnd + 4)])
        )
      )
      offset = dataEnd + 4
    }
    return chunks
  }

  private static func uint32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
    bytes.reduce(0) { ($0 << 8) | UInt32($1) }
  }

  private static func gifRoundTrip(_ sequence: AnimatedImageSequence) throws
    -> AnimatedImageSequence
  {
    try AnimatedGIF.decode(data: AnimatedGIF.encode(sequence))
  }

  private static func sequence(pixels: [AnimatedImagePixel]) -> AnimatedImageSequence {
    AnimatedImageSequence(
      frames: [AnimatedImageFrame(width: pixels.count, height: 1, pixels: pixels)],
      frameDelays: [.milliseconds(20)]
    )
  }

  private static func pixelFrame(_ pixel: AnimatedImagePixel) -> AnimatedImageFrame {
    AnimatedImageFrame(width: 1, height: 1, pixels: [pixel])
  }

  private static func solidFrame(
    width: Int,
    height: Int,
    pixel: AnimatedImagePixel
  ) -> AnimatedImageFrame {
    AnimatedImageFrame(
      width: width,
      height: height,
      pixels: Array(repeating: pixel, count: width * height)
    )
  }
}

extension AnimatedImagePixel {
  fileprivate static let red = Self(red: 255, green: 0, blue: 0)
  fileprivate static let green = Self(red: 0, green: 255, blue: 0)
  fileprivate static let blue = Self(red: 0, green: 0, blue: 255)
}
