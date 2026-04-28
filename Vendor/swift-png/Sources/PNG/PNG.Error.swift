extension PNG {

  /// An error raised while decoding a PNG bytestream.
  public enum DecodingError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The stream ended before the decoder finished reading the file.
    case truncated(stage: String)
    /// The 8-byte PNG signature was missing or wrong.
    case invalidSignature([UInt8])
    /// A required chunk (`IHDR`, `IEND`, `IDAT` for non-palette types,
    /// `PLTE` for color type 3) was missing.
    case missingChunk(type: String)
    /// A chunk's CRC-32 trailer did not match the chunk data.
    case invalidChunkCRC(type: String)
    /// `IHDR` declared a color type / bit-depth combination that PNG does
    /// not allow (RFC 2083 §11.2.2).
    case invalidColorTypeBitDepth(colorType: UInt8, bitDepth: UInt8)
    /// `IHDR` declared an unsupported compression, filter, or interlace
    /// method.
    case unsupportedMethod(field: String, value: UInt8)
    /// The image declared zero width or zero height.
    case emptyImage
    /// The PLTE chunk was malformed (length not a multiple of three, or
    /// out of bounds for the bit depth).
    case invalidPalette(reason: String)
    /// A scanline filter byte was outside the legal range `0...4`.
    case invalidFilterType(UInt8)
    /// A `tRNS` chunk had a length inconsistent with the image's color
    /// type.
    case invalidTransparency(reason: String)
    /// The zlib/DEFLATE stream embedded in the IDAT chunks was malformed.
    case invalidDeflateStream(reason: String)
    /// The zlib stream's Adler-32 checksum did not match the inflated
    /// data.
    case invalidAdler32

    public var description: String {
      switch self {
      case .truncated(let stage):
        return "PNG stream truncated during \(stage)"
      case .invalidSignature(let bytes):
        let hex = bytes.map { String($0, radix: 16, uppercase: true) }.joined(separator: " ")
        return "PNG: invalid signature [\(hex)]"
      case .missingChunk(let t):
        return "PNG: required chunk '\(t)' is missing"
      case .invalidChunkCRC(let t):
        return "PNG: chunk '\(t)' has an invalid CRC"
      case .invalidColorTypeBitDepth(let ct, let bd):
        return "PNG: invalid color type \(ct) / bit depth \(bd) combination"
      case .unsupportedMethod(let field, let value):
        return "PNG: unsupported \(field) method \(value)"
      case .emptyImage:
        return "PNG: image has zero width or height"
      case .invalidPalette(let reason):
        return "PNG: invalid PLTE chunk: \(reason)"
      case .invalidFilterType(let f):
        return "PNG: invalid scanline filter type \(f) (must be 0...4)"
      case .invalidTransparency(let reason):
        return "PNG: invalid tRNS chunk: \(reason)"
      case .invalidDeflateStream(let reason):
        return "PNG: invalid DEFLATE stream: \(reason)"
      case .invalidAdler32:
        return "PNG: zlib Adler-32 checksum mismatch"
      }
    }
  }
}
