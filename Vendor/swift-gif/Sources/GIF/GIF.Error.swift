extension GIF {
  /// An error raised while encoding indexed GIF data.
  public enum EncodingError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The image had zero width, zero height, or no frames.
    case emptyImage
    /// The logical screen dimensions exceeded GIF's UInt16 limits.
    case dimensionsTooLarge(width: Int, height: Int)
    /// The global color table, including required index padding, exceeded 256 entries.
    case tooManyColors(count: Int)
    /// The background index did not reference the authored global color table.
    case invalidBackgroundIndex(Int)
    /// A frame's bounds were empty or extended outside the logical screen.
    case frameOutOfBounds(left: Int, top: Int, width: Int, height: Int)
    /// A frame did not provide exactly `width * height` indices.
    case invalidIndexCount(expected: Int, actual: Int)
    /// An opaque pixel index referenced no color table entry.
    case colorIndexOutOfBounds(index: Int, paletteSize: Int)
    /// A frame's transparent index was outside GIF's UInt8 range.
    case invalidTransparentIndex(Int)

    public var description: String {
      switch self {
      case .emptyImage:
        return "GIF: empty image (zero size or no frames)"
      case .dimensionsTooLarge(let width, let height):
        return "GIF: dimensions \(width)x\(height) exceed UInt16 limits"
      case .tooManyColors(let count):
        return "GIF: color table requires \(count) entries (maximum 256)"
      case .invalidBackgroundIndex(let index):
        return "GIF: background index \(index) does not reference the color table"
      case .frameOutOfBounds(let left, let top, let width, let height):
        return "GIF: frame at (\(left),\(top)) size \(width)x\(height) is out of bounds"
      case .invalidIndexCount(let expected, let actual):
        return "GIF: frame has \(actual) indices, expected \(expected)"
      case .colorIndexOutOfBounds(let index, let paletteSize):
        return "GIF: color index \(index) outside palette of size \(paletteSize)"
      case .invalidTransparentIndex(let index):
        return "GIF: transparent index \(index) is outside 0...255"
      }
    }
  }

  /// An error raised while decoding a GIF bytestream.
  public enum DecodingError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The stream ended before the decoder finished reading the file.
    case truncated(stage: String)
    /// The file did not start with `GIF87a` or `GIF89a`.
    case invalidSignature([UInt8])
    /// A required block introducer (extension `0x21`, image `0x2C`,
    /// trailer `0x3B`) was missing or out of order.
    case unexpectedBlock(introducer: UInt8, stage: String)
    /// The logical screen had zero width, height, or no frames.
    case emptyImage
    /// LZW: the minimum code size in the image descriptor was outside
    /// the allowed `2...8` range.
    case invalidMinCodeSize(Int)
    /// LZW: the bitstream produced a code outside `0..<dict.count + 1`,
    /// indicating corruption.
    case invalidLZWCode(Int)
    /// LZW: the bitstream contained no clear code at the start, or
    /// finished without an EOI.
    case malformedLZWStream(reason: String)
    /// A frame's bounds extended outside the logical screen.
    case frameOutOfBounds(left: Int, top: Int, width: Int, height: Int)
    /// A frame referenced a color index outside its palette.
    case colorIndexOutOfBounds(index: Int, paletteSize: Int)
    /// A frame had no associated palette (no global, no local).
    case missingPalette

    public var description: String {
      switch self {
      case .truncated(let stage):
        return "GIF stream truncated during \(stage)"
      case .invalidSignature(let bytes):
        let hex = bytes.map { String($0, radix: 16, uppercase: true) }.joined(separator: " ")
        return "GIF: invalid signature [\(hex)]"
      case .unexpectedBlock(let i, let stage):
        return "GIF: unexpected block 0x\(String(i, radix: 16)) during \(stage)"
      case .emptyImage:
        return "GIF: empty image (zero size or no frames)"
      case .invalidMinCodeSize(let n):
        return "GIF: invalid LZW minimum code size \(n) (must be 2...8)"
      case .invalidLZWCode(let c):
        return "GIF: invalid LZW code \(c)"
      case .malformedLZWStream(let r):
        return "GIF: malformed LZW stream — \(r)"
      case .frameOutOfBounds(let l, let t, let w, let h):
        return "GIF: frame at (\(l),\(t)) size \(w)x\(h) is out of logical screen"
      case .colorIndexOutOfBounds(let i, let p):
        return "GIF: color index \(i) outside palette of size \(p)"
      case .missingPalette:
        return "GIF: frame has no global or local palette"
      }
    }
  }
}
