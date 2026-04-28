import Foundation

/// Errors thrown while encoding a `GIFDocument` into GIF89a bytes.
public enum GIFEncoderError: Error, Equatable {
  case dimensionsTooLarge(width: Int, height: Int)
  case tooManyColors(count: Int)
}

/// Minimal GIF89a encoder.
///
/// The encoder is intentionally narrow: it produces files with a single
/// global color table, every frame disposing to background, and a
/// Netscape 2.0 looping extension when `loopCount != 1`. This matches
/// what the editor itself authors and is enough to round-trip files
/// produced here through the vendored `swift-gif` decoder.
public enum GIFEncoder {

  /// Encodes a flattened document into GIF89a bytes.
  ///
  /// `flattenedFrames[i]` is the result of `document.flatten(frameIndex: i)`,
  /// passed in by the caller so callers that want to do their own
  /// flattening (e.g. with effects on top) don't pay twice.
  public static func encode(
    document: GIFDocument,
    flattenedFrames: [PixelBuffer]? = nil
  ) throws -> [UInt8] {
    precondition(!document.frames.isEmpty, "document must have at least one frame")
    if document.size.width > 0xFFFF || document.size.height > 0xFFFF {
      throw GIFEncoderError.dimensionsTooLarge(
        width: document.size.width, height: document.size.height
      )
    }

    let flat =
      flattenedFrames ?? (0..<document.frames.count).map { document.flatten(frameIndex: $0) }
    precondition(flat.count == document.frames.count)

    let palette = paddedPalette(from: document.palette)
    if palette.count > 256 {
      throw GIFEncoderError.tooManyColors(count: palette.count)
    }

    var output: [UInt8] = []
    output.reserveCapacity(1024 + document.size.area * document.frames.count)

    writeHeader(into: &output)
    writeLogicalScreenDescriptor(
      width: document.size.width,
      height: document.size.height,
      paletteSize: palette.count,
      backgroundIndex: 0,
      into: &output
    )
    writePalette(palette, into: &output)

    if document.frames.count > 1 || document.loopCount != 1 {
      writeNetscapeLoopExtension(loopCount: document.loopCount, into: &output)
    }

    for (frame, flattened) in zip(document.frames, flat) {
      writeFrame(
        frame,
        flattened: flattened,
        documentSize: document.size,
        paletteSize: palette.count,
        into: &output
      )
    }

    output.append(0x3B)  // trailer
    return output
  }

  // MARK: Block writers

  private static func writeHeader(into out: inout [UInt8]) {
    // "GIF89a"
    out.append(contentsOf: [0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
  }

  private static func writeLogicalScreenDescriptor(
    width: Int,
    height: Int,
    paletteSize: Int,
    backgroundIndex: PaletteIndex,
    into out: inout [UInt8]
  ) {
    appendUInt16LE(UInt16(width), into: &out)
    appendUInt16LE(UInt16(height), into: &out)
    let gctSize = paletteSizeBits(paletteSize) - 1  // GIF stores N-1
    // packed: [GCT flag (1) | color resolution (3) | sort flag (1) | gct size (3)]
    let packed: UInt8 =
      0b1000_0000  // GCT present
      | (0b111 << 4)  // color resolution = 7 (8-bit)
      | UInt8(gctSize & 0b111)
    out.append(packed)
    out.append(backgroundIndex)
    out.append(0)  // pixel aspect ratio (0 = none)
  }

  private static func writePalette(_ palette: [EditorColor], into out: inout [UInt8]) {
    for color in palette {
      out.append(color.red)
      out.append(color.green)
      out.append(color.blue)
    }
  }

  private static func writeNetscapeLoopExtension(loopCount: Int, into out: inout [UInt8]) {
    // 0x21 0xFF 0x0B "NETSCAPE2.0" 0x03 0x01 lo hi 0x00
    out.append(contentsOf: [0x21, 0xFF, 0x0B])
    out.append(contentsOf: Array("NETSCAPE2.0".utf8))
    out.append(0x03)  // sub-block size
    out.append(0x01)  // sub-block id
    appendUInt16LE(UInt16(clamping: loopCount), into: &out)
    out.append(0x00)  // block terminator
  }

  private static func writeFrame(
    _ frame: EditorFrame,
    flattened: PixelBuffer,
    documentSize: PixelSize,
    paletteSize: Int,
    into out: inout [UInt8]
  ) {
    // Graphic Control Extension. We always declare the transparent
    // index so any `nil` pixels in the flattened buffer become real
    // GIF transparency rather than a bogus opaque palette slot.
    out.append(contentsOf: [0x21, 0xF9, 0x04])
    let disposalBits = frame.disposal.rawValue & 0b111
    let packed: UInt8 = (disposalBits << 2) | 0b0000_0001  // transparent flag set
    out.append(packed)
    appendUInt16LE(UInt16(clamping: max(0, frame.delayCentiseconds)), into: &out)
    out.append(ColorPalette.transparentSlot)  // transparent color index
    out.append(0x00)  // block terminator

    // Image descriptor.
    out.append(0x2C)
    appendUInt16LE(0, into: &out)  // left
    appendUInt16LE(0, into: &out)  // top
    appendUInt16LE(UInt16(documentSize.width), into: &out)
    appendUInt16LE(UInt16(documentSize.height), into: &out)
    out.append(0x00)  // packed: no LCT, no interlace

    // Lower-bound the LZW initial code size at 2 (GIF spec) regardless
    // of how few colors the palette actually has.
    let bits = max(2, paletteSizeBits(paletteSize))
    out.append(UInt8(bits))

    // Map flattened pixels to palette indices, with `nil` going to the
    // reserved transparent slot.
    var indexed = [UInt8](repeating: 0, count: flattened.pixels.count)
    for (i, p) in flattened.pixels.enumerated() {
      indexed[i] = p ?? ColorPalette.transparentSlot
    }

    let compressed = LZWEncoder.encode(indices: indexed, minCodeSize: bits)
    writeAsSubBlocks(compressed, into: &out)
  }

  // MARK: Helpers

  /// Pads the document palette to the next power-of-two slot count with
  /// duplicates of slot 0. GIF requires 2^N slots.
  private static func paddedPalette(from palette: ColorPalette) -> [EditorColor] {
    let entries = palette.colors
    let bits = paletteSizeBits(entries.count)
    let target = 1 << bits
    if entries.count == target { return entries }
    return entries + Array(repeating: entries[0], count: target - entries.count)
  }

  /// Number of bits N such that `2^N >= count`, clamped to `[1, 8]`.
  private static func paletteSizeBits(_ count: Int) -> Int {
    var n = 1
    while (1 << n) < count {
      n += 1
      if n >= 8 { break }
    }
    return n
  }

  private static func appendUInt16LE(_ value: UInt16, into out: inout [UInt8]) {
    out.append(UInt8(value & 0xFF))
    out.append(UInt8((value >> 8) & 0xFF))
  }

  /// Splits a flat byte stream into GIF "sub-blocks": each starts with a
  /// 1-byte length (0..255), terminated by an empty (0-length) block.
  private static func writeAsSubBlocks(_ bytes: [UInt8], into out: inout [UInt8]) {
    var offset = 0
    while offset < bytes.count {
      let chunk = min(255, bytes.count - offset)
      out.append(UInt8(chunk))
      out.append(contentsOf: bytes[offset..<(offset + chunk)])
      offset += chunk
    }
    out.append(0x00)  // block terminator
  }
}
