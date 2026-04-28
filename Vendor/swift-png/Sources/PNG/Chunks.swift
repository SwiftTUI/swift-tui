extension PNG {

  /// The 8-byte signature at the head of every PNG file:
  /// `89 50 4E 47 0D 0A 1A 0A`.
  static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

  /// A single PNG chunk.
  ///
  /// Chunks have the form `length | type (4 bytes ASCII) | data | crc32`.
  /// The length is the size of `data` only — the type field is included
  /// in the CRC calculation, but not in `length`.
  struct Chunk {
    /// The four ASCII bytes that name this chunk (e.g. `IHDR`, `IDAT`).
    let type: [UInt8]
    /// The chunk's payload. May be empty.
    let data: [UInt8]

    /// The four ASCII bytes interpreted as a string for diagnostics.
    var typeString: String {
      // PNG chunk type names are always ASCII; render directly without
      // relying on Foundation's `String(bytes:encoding:)`.
      var out = ""
      for b in type {
        out.append(Character(UnicodeScalar(b)))
      }
      return out
    }
  }

  /// A cursor over a PNG bytestream that reads chunks one at a time.
  struct ChunkReader {
    let bytes: [UInt8]
    var pos: Int

    init(bytes: [UInt8]) {
      self.bytes = bytes
      self.pos = 0
    }

    /// Reads the 8-byte PNG signature. Throws if the stream does not start
    /// with the expected magic.
    mutating func readSignature() throws(PNG.DecodingError) {
      guard pos + 8 <= bytes.count else {
        throw .truncated(stage: "signature")
      }
      let sig = Array(bytes[pos..<pos + 8])
      if sig != PNG.signature {
        throw .invalidSignature(sig)
      }
      pos += 8
    }

    /// Reads a single chunk and validates its CRC.
    mutating func readChunk() throws(PNG.DecodingError) -> Chunk {
      guard pos + 8 <= bytes.count else {
        throw .truncated(stage: "chunk header")
      }
      let length = Int(readUInt32BE(at: pos))
      let type = Array(bytes[pos + 4..<pos + 8])
      pos += 8

      guard length >= 0, length <= bytes.count - pos - 4 else {
        throw .truncated(stage: "chunk data")
      }
      let data = Array(bytes[pos..<pos + length])
      pos += length

      let crc = readUInt32BE(at: pos)
      pos += 4

      let computed = PNG.crc32(type: type, data: data)
      guard computed == crc else {
        var typeString = ""
        for b in type { typeString.append(Character(UnicodeScalar(b))) }
        throw .invalidChunkCRC(type: typeString)
      }
      return Chunk(type: type, data: data)
    }

    /// Returns true once all bytes have been consumed.
    var atEnd: Bool { pos >= bytes.count }

    private func readUInt32BE(at p: Int) -> UInt32 {
      UInt32(bytes[p]) << 24
        | UInt32(bytes[p + 1]) << 16
        | UInt32(bytes[p + 2]) << 8
        | UInt32(bytes[p + 3])
    }
  }
}

extension PNG {

  /// CRC-32 (IEEE 802.3) over the chunk's type bytes followed by its data,
  /// as required by RFC 2083 §3.4.
  static func crc32(type: [UInt8], data: [UInt8]) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for b in type {
      crc = crc32Table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8)
    }
    for b in data {
      crc = crc32Table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8)
    }
    return crc ^ 0xFFFF_FFFF
  }

  /// Precomputed CRC-32 lookup table (IEEE 802.3, polynomial 0xEDB88320).
  static let crc32Table: [UInt32] = {
    var table = [UInt32](repeating: 0, count: 256)
    for n in 0..<256 {
      var c = UInt32(n)
      for _ in 0..<8 {
        if c & 1 != 0 {
          c = 0xEDB8_8320 ^ (c >> 1)
        } else {
          c = c >> 1
        }
      }
      table[n] = c
    }
    return table
  }()
}
