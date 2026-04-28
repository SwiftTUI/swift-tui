extension GIF {

  /// Disposal method from the Graphics Control Extension.
  public enum Disposal: UInt8, Sendable, Equatable {
    case unspecified = 0
    case keep = 1
    case background = 2
    case previous = 3
  }

  /// One decoded frame.
  public struct Frame: Sendable {
    /// Frame bounds within the logical screen.
    public let left: Int
    public let top: Int
    public let width: Int
    public let height: Int
    /// 256-entry-or-fewer palette (R, G, B), drawn from the local or
    /// global color table.
    public let palette: [(r: UInt8, g: UInt8, b: UInt8)]
    /// Row-major palette indices, length `width * height`.
    public let indices: [UInt8]
    /// Optional transparent palette index (if a Graphics Control
    /// Extension declared one for this frame).
    public let transparentIndex: Int?
    /// 1/100 second delay before the next frame is shown. Zero for
    /// non-animated GIFs.
    public let delayCentiseconds: Int
    /// What to do with this frame's region before painting the next.
    public let disposal: Disposal
  }

  /// Stateful GIF decoder. Loads the entire bytestream and parses blocks
  /// in sequence until the trailer is reached.
  struct Decoder {
    var bytes: [UInt8]
    var pos: Int = 0

    // Logical screen state.
    var screenWidth: Int = 0
    var screenHeight: Int = 0
    var globalPalette: [(r: UInt8, g: UInt8, b: UInt8)] = []
    var backgroundIndex: Int = 0
    var hasGlobalColorTable: Bool = false

    // Pending GCE state — applies to the *next* image descriptor.
    var pendingTransparentIndex: Int? = nil
    var pendingDelay: Int = 0
    var pendingDisposal: Disposal = .unspecified

    // Decoded frames.
    var frames: [Frame] = []

    init(bytes: [UInt8]) {
      self.bytes = bytes
    }

    mutating func decode() throws(GIF.DecodingError) -> (
      screenWidth: Int,
      screenHeight: Int,
      backgroundColor: (r: UInt8, g: UInt8, b: UInt8)?,
      frames: [Frame]
    ) {
      try parseHeader()
      try parseLogicalScreenDescriptor()

      blocks: while pos < bytes.count {
        let introducer = try readByte(stage: "block introducer")
        switch introducer {
        case 0x3B:
          break blocks  // trailer
        case 0x21:
          try parseExtensionBlock()
        case 0x2C:
          try parseImageDescriptor()
        default:
          // Some encoders sprinkle stray padding bytes. Skip.
          continue
        }
      }

      guard !frames.isEmpty else {
        throw .emptyImage
      }

      let bg: (r: UInt8, g: UInt8, b: UInt8)?
      if hasGlobalColorTable, backgroundIndex < globalPalette.count {
        bg = globalPalette[backgroundIndex]
      } else {
        bg = nil
      }

      return (screenWidth, screenHeight, bg, frames)
    }

    // MARK: byte/word helpers

    mutating func readByte(stage: String) throws(GIF.DecodingError) -> UInt8 {
      guard pos < bytes.count else { throw .truncated(stage: stage) }
      let b = bytes[pos]
      pos += 1
      return b
    }

    mutating func readUInt16LE(stage: String) throws(GIF.DecodingError) -> Int {
      guard pos + 2 <= bytes.count else { throw .truncated(stage: stage) }
      let v = Int(bytes[pos]) | (Int(bytes[pos + 1]) << 8)
      pos += 2
      return v
    }

    mutating func readBytes(count: Int, stage: String) throws(GIF.DecodingError) -> [UInt8] {
      guard pos + count <= bytes.count else { throw .truncated(stage: stage) }
      let slice = Array(bytes[pos..<(pos + count)])
      pos += count
      return slice
    }

    // MARK: header / LSD

    mutating func parseHeader() throws(GIF.DecodingError) {
      let sig = try readBytes(count: 6, stage: "signature")
      // Accept GIF87a and GIF89a.
      let g87 = [UInt8]([0x47, 0x49, 0x46, 0x38, 0x37, 0x61])
      let g89 = [UInt8]([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
      if sig != g87 && sig != g89 {
        throw .invalidSignature(sig)
      }
    }

    mutating func parseLogicalScreenDescriptor() throws(GIF.DecodingError) {
      screenWidth = try readUInt16LE(stage: "logical screen width")
      screenHeight = try readUInt16LE(stage: "logical screen height")
      let packed = try readByte(stage: "logical screen packed flags")
      backgroundIndex = Int(try readByte(stage: "background color index"))
      _ = try readByte(stage: "pixel aspect ratio")  // ignored

      let gctFlag = (packed & 0b1000_0000) != 0
      // bits 6-4: color resolution (ignored)
      // bit 3: sort flag (ignored)
      let gctSizeBits = Int(packed & 0b0000_0111) + 1
      if gctFlag {
        hasGlobalColorTable = true
        let entries = 1 << gctSizeBits
        globalPalette = try readPalette(entries: entries, stage: "global color table")
      }
    }

    mutating func readPalette(entries: Int, stage: String) throws(GIF.DecodingError)
      -> [(r: UInt8, g: UInt8, b: UInt8)]
    {
      let raw = try readBytes(count: entries * 3, stage: stage)
      var out: [(UInt8, UInt8, UInt8)] = []
      out.reserveCapacity(entries)
      for i in 0..<entries {
        out.append((raw[i * 3], raw[i * 3 + 1], raw[i * 3 + 2]))
      }
      return out
    }

    // MARK: extensions

    mutating func parseExtensionBlock() throws(GIF.DecodingError) {
      let label = try readByte(stage: "extension label")
      switch label {
      case 0xF9:  // GCE
        try parseGraphicsControlExtension()
      case 0xFE, 0xFF, 0x01:  // Comment, App, Plain Text
        try skipSubBlocks(stage: "extension body")
      default:
        try skipSubBlocks(stage: "unknown extension body")
      }
    }

    mutating func parseGraphicsControlExtension() throws(GIF.DecodingError) {
      // Block size byte (always 4), then 4 data bytes, then 0 terminator.
      let blockSize = try readByte(stage: "GCE block size")
      guard blockSize == 4 else {
        // Non-conforming but try to recover.
        try skipSubBlocks(stage: "GCE")
        return
      }
      let packed = try readByte(stage: "GCE packed flags")
      let delay = try readUInt16LE(stage: "GCE delay")
      let transparent = try readByte(stage: "GCE transparent index")
      // Trailing 0 terminator.
      _ = try readByte(stage: "GCE terminator")

      let disposalCode = (packed >> 2) & 0b0000_0111
      let userInputFlag = (packed & 0b0000_0010) != 0
      _ = userInputFlag
      let transparentFlag = (packed & 0b0000_0001) != 0

      pendingDisposal = Disposal(rawValue: disposalCode) ?? .unspecified
      pendingDelay = delay
      pendingTransparentIndex = transparentFlag ? Int(transparent) : nil
    }

    /// Reads sub-blocks until a zero-length block terminator and discards
    /// their contents.
    mutating func skipSubBlocks(stage: String) throws(GIF.DecodingError) {
      while true {
        let n = try readByte(stage: stage)
        if n == 0 { return }
        guard pos + Int(n) <= bytes.count else {
          throw .truncated(stage: stage)
        }
        pos += Int(n)
      }
    }

    /// Reads sub-blocks until the zero terminator and concatenates them.
    mutating func readSubBlocks(stage: String) throws(GIF.DecodingError) -> [UInt8] {
      var out: [UInt8] = []
      while true {
        let n = Int(try readByte(stage: stage))
        if n == 0 { return out }
        let chunk = try readBytes(count: n, stage: stage)
        out.append(contentsOf: chunk)
      }
    }

    // MARK: image descriptor

    mutating func parseImageDescriptor() throws(GIF.DecodingError) {
      let left = try readUInt16LE(stage: "image left")
      let top = try readUInt16LE(stage: "image top")
      let width = try readUInt16LE(stage: "image width")
      let height = try readUInt16LE(stage: "image height")
      let packed = try readByte(stage: "image packed flags")

      guard width > 0, height > 0 else {
        // Empty frame — consume LZW payload to stay aligned.
        _ = try readByte(stage: "lzw min code size")
        try skipSubBlocks(stage: "image data (empty frame)")
        resetGCEState()
        return
      }
      guard left + width <= screenWidth, top + height <= screenHeight else {
        throw .frameOutOfBounds(left: left, top: top, width: width, height: height)
      }

      let lctFlag = (packed & 0b1000_0000) != 0
      let interlaced = (packed & 0b0100_0000) != 0
      // bit 5: sort flag (ignored)
      let lctSizeBits = Int(packed & 0b0000_0111) + 1

      let palette: [(r: UInt8, g: UInt8, b: UInt8)]
      if lctFlag {
        palette = try readPalette(
          entries: 1 << lctSizeBits,
          stage: "local color table"
        )
      } else if hasGlobalColorTable {
        palette = globalPalette
      } else {
        throw .missingPalette
      }

      // LZW-coded image data.
      let minCodeSize = Int(try readByte(stage: "lzw min code size"))
      let compressed = try readSubBlocks(stage: "image data sub-blocks")
      let raw = try LZW.decode(
        bytes: compressed,
        minCodeSize: minCodeSize,
        expectedCount: width * height
      )

      // Validate output length and indices.
      guard raw.count >= width * height else {
        throw .truncated(stage: "LZW image data (got \(raw.count), expected \(width * height))")
      }
      let trimmed = Array(raw.prefix(width * height))

      // Validate indices: any value beyond the palette is a corruption.
      for v in trimmed {
        if Int(v) >= palette.count {
          if let t = pendingTransparentIndex, Int(v) == t {
            // Transparent index may exceed palette size; that's fine.
            continue
          }
          throw .colorIndexOutOfBounds(index: Int(v), paletteSize: palette.count)
        }
      }

      let pixels =
        interlaced
        ? deinterlace(indices: trimmed, width: width, height: height)
        : trimmed

      frames.append(
        Frame(
          left: left,
          top: top,
          width: width,
          height: height,
          palette: palette,
          indices: pixels,
          transparentIndex: pendingTransparentIndex,
          delayCentiseconds: pendingDelay,
          disposal: pendingDisposal
        ))

      resetGCEState()
    }

    mutating func resetGCEState() {
      pendingTransparentIndex = nil
      pendingDelay = 0
      pendingDisposal = .unspecified
    }

    /// Deinterlaces a 4-pass-encoded GIF image into row-major order.
    ///
    /// The four passes (per the GIF89a spec):
    ///   1. rows 0, 8, 16, 24...  (every 8th, starting at 0)
    ///   2. rows 4, 12, 20, 28... (every 8th, starting at 4)
    ///   3. rows 2, 6, 10, 14...  (every 4th, starting at 2)
    ///   4. rows 1, 3, 5, 7...    (every 2nd, starting at 1)
    func deinterlace(indices: [UInt8], width: Int, height: Int) -> [UInt8] {
      var out = [UInt8](repeating: 0, count: width * height)
      let passes: [(start: Int, stride: Int)] = [
        (0, 8), (4, 8), (2, 4), (1, 2),
      ]
      var srcRow = 0
      for pass in passes {
        var dstRow = pass.start
        while dstRow < height {
          let src = srcRow * width
          let dst = dstRow * width
          for c in 0..<width {
            out[dst + c] = indices[src + c]
          }
          srcRow += 1
          dstRow += pass.stride
        }
      }
      return out
    }
  }
}
