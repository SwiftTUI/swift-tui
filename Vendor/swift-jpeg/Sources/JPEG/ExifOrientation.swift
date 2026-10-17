extension JPEG.Decoder {
  /// Exif IFD0 Orientation (SHORT, count 1). Invalid optional metadata is
  /// ignored; segment truncation remains a stream error. Offsets are relative
  /// to the TIFF header, never the outer JPEG stream.
  mutating func parseAPP1Exif() throws(JPEG.DecodingError) {
    let length = try readUInt16BE()
    guard length >= 2 else { return }
    let count = length - 2
    guard count <= bytes.count - pos else { throw .truncated(stage: "APP1 segment") }
    let payload = Array(bytes[pos..<(pos + count)])
    pos += count
    guard payload.starts(with: [0x45, 0x78, 0x69, 0x66, 0, 0]) else { return }
    if let orientation = JPEG.exifOrientation(in: Array(payload.dropFirst(6))) {
      exifOrientation = orientation
    }
  }
}

extension JPEG {
  static func exifOrientation(in tiff: [UInt8]) -> Int? {
    guard tiff.count >= 8 else { return nil }
    let little: Bool
    if tiff[0] == 0x49 && tiff[1] == 0x49 {
      little = true
    } else if tiff[0] == 0x4D && tiff[1] == 0x4D {
      little = false
    } else {
      return nil
    }
    func word(_ index: Int) -> UInt16 {
      little
        ? UInt16(tiff[index]) | UInt16(tiff[index + 1]) << 8
        : UInt16(tiff[index]) << 8 | UInt16(tiff[index + 1])
    }
    func long(_ index: Int) -> UInt32 {
      little
        ? UInt32(word(index)) | UInt32(word(index + 2)) << 16
        : UInt32(word(index)) << 16 | UInt32(word(index + 2))
    }
    guard word(2) == 42, let offset = Int(exactly: long(4)),
      offset >= 8, offset <= tiff.count - 2
    else { return nil }
    let count = Int(word(offset))
    let start = offset + 2
    guard count <= (tiff.count - start) / 12 else { return nil }
    for index in 0..<count {
      let entry = start + index * 12
      guard word(entry) == 0x0112 else { continue }
      guard word(entry + 2) == 3, long(entry + 4) == 1 else { return nil }
      let value = Int(word(entry + 8))
      return (1...8).contains(value) ? value : nil
    }
    return nil
  }
}

extension JPEG.Decoded {
  /// CIPA Exif Orientation maps encoded rows and columns to visual axes.
  /// https://www.cipa.jp/std/documents/e/DC-X008-Translation-2019-E.pdf, Figure 12.
  func oriented(_ orientation: Int) -> Self {
    guard (2...8).contains(orientation) else { return self }
    let swapsAxes = orientation >= 5
    let newWidth = swapsAxes ? height : width
    let newHeight = swapsAxes ? width : height
    let planes = components.map { plane in
      var result = [UInt8](repeating: 0, count: plane.count)
      for y in 0..<height {
        for x in 0..<width {
          let destination: (x: Int, y: Int)
          switch orientation {
          case 2: destination = (width - 1 - x, y)
          case 3: destination = (width - 1 - x, height - 1 - y)
          case 4: destination = (x, height - 1 - y)
          case 5: destination = (y, x)
          case 6: destination = (height - 1 - y, x)
          case 7: destination = (height - 1 - y, width - 1 - x)
          default: destination = (y, width - 1 - x)
          }
          result[destination.y * newWidth + destination.x] = plane[y * width + x]
        }
      }
      return result
    }
    return Self(
      width: newWidth, height: newHeight, components: planes,
      componentIDs: componentIDs, isAdobeYCCK: isAdobeYCCK, isAdobeRGB: isAdobeRGB)
  }
}
