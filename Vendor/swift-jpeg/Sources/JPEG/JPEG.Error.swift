extension JPEG {

  /// An error raised while decoding a JPEG bytestream.
  public enum DecodingError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The stream ended before the decoder finished reading the file.
    case truncated(stage: String)
    /// A required marker was missing or out of order.
    case unexpectedMarker(UInt8, stage: String)
    /// The Start-of-Image marker (`FFD8`) was not found at the head of the stream.
    case missingSOI
    /// The file's frame uses a process this decoder does not support
    /// (e.g. progressive, lossless, arithmetic, hierarchical).
    case unsupportedProcess(marker: UInt8)
    /// The frame uses an unsupported sample precision (only 8-bit is supported).
    case unsupportedPrecision(Int)
    /// A frame component declared an invalid sampling factor.
    case invalidSamplingFactors(componentID: Int, h: Int, v: Int)
    /// A scan referenced a component or table identifier that was never defined.
    case undefinedTable(kind: String, id: Int)
    /// A Huffman table failed to validate (e.g. impossible code lengths).
    case invalidHuffmanTable(reason: String)
    /// A quantization table had an invalid precision or destination.
    case invalidQuantizationTable(reason: String)
    /// A bit-stream value violated the JPEG specification (for example, a
    /// DC magnitude exceeding 11 bits or an AC run exceeding 63).
    case invalidBitstream(reason: String)
    /// A required marker payload was the wrong length.
    case malformedSegment(marker: UInt8, reason: String)
    /// The image declared zero width, zero height, or zero components.
    case emptyImage

    public var description: String {
      switch self {
      case .truncated(let stage):
        return "JPEG stream truncated during \(stage)"
      case .unexpectedMarker(let m, let stage):
        return "JPEG: unexpected marker 0x\(String(m, radix: 16, uppercase: true)) during \(stage)"
      case .missingSOI:
        return "JPEG: missing Start-of-Image marker (FFD8)"
      case .unsupportedProcess(let m):
        return
          "JPEG: unsupported process marker 0xFF\(String(m, radix: 16, uppercase: true)) (only baseline SOF0 is supported)"
      case .unsupportedPrecision(let p):
        return "JPEG: unsupported sample precision \(p) (only 8-bit is supported)"
      case .invalidSamplingFactors(let id, let h, let v):
        return "JPEG: invalid sampling factors for component \(id): H=\(h), V=\(v)"
      case .undefinedTable(let kind, let id):
        return "JPEG: undefined \(kind) table \(id)"
      case .invalidHuffmanTable(let reason):
        return "JPEG: invalid Huffman table: \(reason)"
      case .invalidQuantizationTable(let reason):
        return "JPEG: invalid quantization table: \(reason)"
      case .invalidBitstream(let reason):
        return "JPEG: invalid bitstream: \(reason)"
      case .malformedSegment(let m, let reason):
        return "JPEG: malformed segment 0xFF\(String(m, radix: 16, uppercase: true)): \(reason)"
      case .emptyImage:
        return "JPEG: image has zero width, height, or components"
      }
    }
  }
}
