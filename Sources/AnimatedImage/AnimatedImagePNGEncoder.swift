enum AnimatedImagePNGEncoder {
  static func encode(
    frame: AnimatedImageFrame
  ) -> [UInt8] {
    var raw: [UInt8] = []
    raw.reserveCapacity(frame.pixelSize.height * (1 + frame.pixelSize.width * 4))
    for row in 0..<frame.pixelSize.height {
      raw.append(0)
      for col in 0..<frame.pixelSize.width {
        let pixel = frame.pixels[row * frame.pixelSize.width + col]
        raw.append(pixel.red)
        raw.append(pixel.green)
        raw.append(pixel.blue)
        raw.append(pixel.alpha)
      }
    }

    var output: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    output.append(
      contentsOf: pngChunk(
        type: "IHDR",
        data: ihdrData(width: frame.pixelSize.width, height: frame.pixelSize.height)
      )
    )
    output.append(contentsOf: pngChunk(type: "IDAT", data: zlibStream(of: raw)))
    output.append(contentsOf: pngChunk(type: "IEND", data: []))
    return output
  }

  private static func ihdrData(
    width: Int,
    height: Int
  ) -> [UInt8] {
    var data: [UInt8] = []
    data.reserveCapacity(13)
    data.append(contentsOf: bigEndianUInt32(UInt32(width)))
    data.append(contentsOf: bigEndianUInt32(UInt32(height)))
    data.append(8)
    data.append(6)
    data.append(0)
    data.append(0)
    data.append(0)
    return data
  }

  private static func pngChunk(
    type: String,
    data: [UInt8]
  ) -> [UInt8] {
    var output: [UInt8] = []
    output.reserveCapacity(8 + data.count + 4)
    output.append(contentsOf: bigEndianUInt32(UInt32(data.count)))
    let typeBytes = Array(type.utf8)
    output.append(contentsOf: typeBytes)
    output.append(contentsOf: data)
    output.append(contentsOf: bigEndianUInt32(crc32(typeBytes + data)))
    return output
  }

  private static func zlibStream(
    of raw: [UInt8]
  ) -> [UInt8] {
    var output: [UInt8] = [0x78, 0x01]

    let maxBlock = 65_535
    var index = 0
    while index < raw.count {
      let remaining = raw.count - index
      let count = min(remaining, maxBlock)
      let isFinal = index + count == raw.count
      output.append(isFinal ? 0x01 : 0x00)
      let length = UInt16(count)
      output.append(UInt8(length & 0xFF))
      output.append(UInt8((length >> 8) & 0xFF))
      let inverseLength = ~length
      output.append(UInt8(inverseLength & 0xFF))
      output.append(UInt8((inverseLength >> 8) & 0xFF))
      output.append(contentsOf: raw[index..<(index + count)])
      index += count
    }

    if raw.isEmpty {
      output.append(contentsOf: [0x01, 0x00, 0x00, 0xFF, 0xFF])
    }

    output.append(contentsOf: bigEndianUInt32(adler32(raw)))
    return output
  }

  private static func bigEndianUInt32(
    _ value: UInt32
  ) -> [UInt8] {
    [
      UInt8((value >> 24) & 0xFF),
      UInt8((value >> 16) & 0xFF),
      UInt8((value >> 8) & 0xFF),
      UInt8(value & 0xFF),
    ]
  }

  private static func crc32(
    _ bytes: [UInt8]
  ) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in bytes {
      crc ^= UInt32(byte)
      for _ in 0..<8 {
        let mask = UInt32(0) &- (crc & 1)
        crc = (crc >> 1) ^ (0xEDB8_8320 & mask)
      }
    }
    return crc ^ 0xFFFF_FFFF
  }

  private static func adler32(
    _ bytes: [UInt8]
  ) -> UInt32 {
    var a: UInt32 = 1
    var b: UInt32 = 0
    let modulus: UInt32 = 65_521
    for byte in bytes {
      a = (a + UInt32(byte)) % modulus
      b = (b + a) % modulus
    }
    return (b << 16) | a
  }
}
