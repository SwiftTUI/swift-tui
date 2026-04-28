extension GIF {
  /// A GIF frame backed by palette indices.
  public struct IndexedFrame: Sendable {
    /// Frame bounds within the logical screen.
    public let left: Int
    public let top: Int
    public let width: Int
    public let height: Int
    /// Row-major palette indices, length `width * height`.
    public let indices: [UInt8]
    /// Optional transparent palette index for this frame.
    public let transparentIndex: Int?
    /// 1/100 second delay before the next frame is shown.
    public let delayCentiseconds: Int
    /// What to do with this frame's region before painting the next.
    public let disposal: Disposal

    public init(
      left: Int = 0,
      top: Int = 0,
      width: Int,
      height: Int,
      indices: [UInt8],
      transparentIndex: Int? = nil,
      delayCentiseconds: Int = 0,
      disposal: Disposal = .unspecified
    ) {
      self.left = left
      self.top = top
      self.width = width
      self.height = height
      self.indices = indices
      self.transparentIndex = transparentIndex
      self.delayCentiseconds = delayCentiseconds
      self.disposal = disposal
    }
  }

  /// A GIF image backed by a single global color table.
  public struct IndexedImage: Sendable {
    /// Logical-screen size.
    public let size: (x: Int, y: Int)
    /// Authored global color table. GIF encoding pads this to a power of two.
    public let globalColorTable: [(r: UInt8, g: UInt8, b: UInt8)]
    /// Logical-screen background color index.
    public let backgroundIndex: Int
    /// Netscape loop count. Zero means infinite.
    public let loopCount: Int
    /// Frames in source order.
    public let frames: [IndexedFrame]

    public init(
      size: (x: Int, y: Int),
      globalColorTable: [(r: UInt8, g: UInt8, b: UInt8)],
      backgroundIndex: Int = 0,
      loopCount: Int = 0,
      frames: [IndexedFrame]
    ) {
      self.size = size
      self.globalColorTable = globalColorTable
      self.backgroundIndex = backgroundIndex
      self.loopCount = loopCount
      self.frames = frames
    }
  }

  /// GIF89a encoder for indexed-color images.
  public enum Encoder {
    /// Encodes an indexed image into GIF89a bytes.
    public static func encode(_ image: GIF.IndexedImage) throws(GIF.EncodingError) -> [UInt8] {
      let palette = try paddedGlobalColorTable(for: image)
      var output: [UInt8] = []
      let pixelCount = image.frames.reduce(0) { $0 + $1.indices.count }
      output.reserveCapacity(1024 + pixelCount)

      writeHeader(into: &output)
      writeLogicalScreenDescriptor(
        width: image.size.x,
        height: image.size.y,
        colorTableCount: palette.count,
        backgroundIndex: image.backgroundIndex,
        into: &output
      )
      writePalette(palette, into: &output)

      if image.frames.count > 1 || image.loopCount != 1 {
        writeNetscapeLoopExtension(loopCount: image.loopCount, into: &output)
      }

      let minCodeSize = max(2, colorTableSizeBits(palette.count))
      for frame in image.frames {
        try writeFrame(
          frame,
          minCodeSize: minCodeSize,
          into: &output
        )
      }

      output.append(0x3B)
      return output
    }

    // MARK: Validation

    private static func paddedGlobalColorTable(
      for image: GIF.IndexedImage
    ) throws(GIF.EncodingError) -> [(r: UInt8, g: UInt8, b: UInt8)] {
      guard image.size.x > 0, image.size.y > 0, !image.frames.isEmpty else {
        throw .emptyImage
      }
      guard image.size.x <= 0xFFFF, image.size.y <= 0xFFFF else {
        throw .dimensionsTooLarge(width: image.size.x, height: image.size.y)
      }
      guard !image.globalColorTable.isEmpty else {
        throw .tooManyColors(count: 0)
      }
      guard image.backgroundIndex >= 0, image.backgroundIndex < image.globalColorTable.count else {
        throw .invalidBackgroundIndex(image.backgroundIndex)
      }

      var requiredColorCount = image.globalColorTable.count
      for frame in image.frames {
        try validateFrame(frame, logicalScreenSize: image.size)
        if let transparentIndex = frame.transparentIndex {
          guard (0...255).contains(transparentIndex) else {
            throw .invalidTransparentIndex(transparentIndex)
          }
          requiredColorCount = max(requiredColorCount, transparentIndex + 1)
        }
        for index in frame.indices {
          let intIndex = Int(index)
          let isTransparentIndex = frame.transparentIndex == intIndex
          if !isTransparentIndex, intIndex >= image.globalColorTable.count {
            throw .colorIndexOutOfBounds(
              index: intIndex,
              paletteSize: image.globalColorTable.count
            )
          }
          requiredColorCount = max(requiredColorCount, intIndex + 1)
        }
      }

      guard requiredColorCount <= 256 else {
        throw .tooManyColors(count: requiredColorCount)
      }

      let bits = colorTableSizeBits(requiredColorCount)
      let target = 1 << bits
      if image.globalColorTable.count == target {
        return image.globalColorTable
      }
      let padColor = image.globalColorTable.last ?? (0, 0, 0)
      return image.globalColorTable
        + Array(repeating: padColor, count: target - image.globalColorTable.count)
    }

    private static func validateFrame(
      _ frame: GIF.IndexedFrame,
      logicalScreenSize: (x: Int, y: Int)
    ) throws(GIF.EncodingError) {
      guard
        frame.width > 0, frame.height > 0,
        frame.left >= 0, frame.top >= 0,
        frame.left + frame.width <= logicalScreenSize.x,
        frame.top + frame.height <= logicalScreenSize.y
      else {
        throw .frameOutOfBounds(
          left: frame.left,
          top: frame.top,
          width: frame.width,
          height: frame.height
        )
      }
      let expectedCount = frame.width * frame.height
      guard frame.indices.count == expectedCount else {
        throw .invalidIndexCount(
          expected: expectedCount,
          actual: frame.indices.count
        )
      }
    }

    // MARK: Block writers

    private static func writeHeader(into out: inout [UInt8]) {
      out.append(contentsOf: [0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
    }

    private static func writeLogicalScreenDescriptor(
      width: Int,
      height: Int,
      colorTableCount: Int,
      backgroundIndex: Int,
      into out: inout [UInt8]
    ) {
      appendUInt16LE(UInt16(width), into: &out)
      appendUInt16LE(UInt16(height), into: &out)
      let sizeBits = colorTableSizeBits(colorTableCount) - 1
      let packed: UInt8 =
        0b1000_0000
        | (0b111 << 4)
        | UInt8(sizeBits & 0b111)
      out.append(packed)
      out.append(UInt8(backgroundIndex))
      out.append(0)
    }

    private static func writePalette(
      _ palette: [(r: UInt8, g: UInt8, b: UInt8)],
      into out: inout [UInt8]
    ) {
      for color in palette {
        out.append(color.r)
        out.append(color.g)
        out.append(color.b)
      }
    }

    private static func writeNetscapeLoopExtension(loopCount: Int, into out: inout [UInt8]) {
      out.append(contentsOf: [0x21, 0xFF, 0x0B])
      out.append(contentsOf: Array("NETSCAPE2.0".utf8))
      out.append(0x03)
      out.append(0x01)
      appendUInt16LE(UInt16(clamping: loopCount), into: &out)
      out.append(0x00)
    }

    private static func writeFrame(
      _ frame: GIF.IndexedFrame,
      minCodeSize: Int,
      into out: inout [UInt8]
    ) throws(GIF.EncodingError) {
      out.append(contentsOf: [0x21, 0xF9, 0x04])
      let disposalBits = frame.disposal.rawValue & 0b111
      let transparentFlag: UInt8 = frame.transparentIndex == nil ? 0 : 0b0000_0001
      out.append((disposalBits << 2) | transparentFlag)
      appendUInt16LE(UInt16(clamping: max(0, frame.delayCentiseconds)), into: &out)
      out.append(UInt8(frame.transparentIndex ?? 0))
      out.append(0x00)

      out.append(0x2C)
      appendUInt16LE(UInt16(frame.left), into: &out)
      appendUInt16LE(UInt16(frame.top), into: &out)
      appendUInt16LE(UInt16(frame.width), into: &out)
      appendUInt16LE(UInt16(frame.height), into: &out)
      out.append(0x00)

      out.append(UInt8(minCodeSize))
      let compressed = GIF.LZW.encode(indices: frame.indices, minCodeSize: minCodeSize)
      writeAsSubBlocks(compressed, into: &out)
    }

    // MARK: Helpers

    private static func colorTableSizeBits(_ count: Int) -> Int {
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

    private static func writeAsSubBlocks(_ bytes: [UInt8], into out: inout [UInt8]) {
      var offset = 0
      while offset < bytes.count {
        let chunk = min(255, bytes.count - offset)
        out.append(UInt8(chunk))
        out.append(contentsOf: bytes[offset..<(offset + chunk)])
        offset += chunk
      }
      out.append(0x00)
    }
  }
}
