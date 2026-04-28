extension JPEG {

  /// A canonical Huffman decoding table, built once from a `DHT` segment
  /// and consumed by ``BitReader``.
  ///
  /// Decoding follows ITU-T T.81, Annex C: codes are formed by
  /// concatenating bits and compared against `maxCode[length]`.
  struct HuffmanTable {
    // For each code length L (1...16):
    //   - minCode[L-1]: smallest code value of length L (or -1 if none)
    //   - maxCode[L-1]: largest code value of length L (or -1 if none)
    //   - valOffset[L-1]: offset into `huffVal` where length-L symbols begin
    // We size the arrays to 17 to allow a sentinel at index 16.
    var minCode: [Int32]  // length 17
    var maxCode: [Int32]  // length 17
    var valOffset: [Int]  // length 17
    var huffVal: [UInt8]  // flat list of symbols in canonical order

    // Fast 9-bit lookup table. Each entry is either:
    //   - (length, symbol) packed as (lenInHighByte, symbol) when length <= 9
    //   - (0xFF, _) sentinel meaning "fall through to slow path"
    // Index = next 9 bits (MSB-first) of the bitstream.
    var fastLength: [UInt8]  // 512
    var fastSymbol: [UInt8]  // 512

    init(empty: Void = ()) {
      self.minCode = .init(repeating: -1, count: 17)
      self.maxCode = .init(repeating: -1, count: 17)
      self.valOffset = .init(repeating: 0, count: 17)
      self.huffVal = []
      self.fastLength = .init(repeating: 0xFF, count: 512)
      self.fastSymbol = .init(repeating: 0, count: 512)
    }
  }
}

extension JPEG.HuffmanTable {

  /// The cap on each axis of the destination identifier in DHT (`Tc<<4|Th`).
  /// Class is 0=DC, 1=AC; destination is 0...3.
  static let maxClass: Int = 1
  static let maxDestination: Int = 3

  /// Parses one or more Huffman tables from a `DHT` segment payload.
  ///
  /// The caller indexes its destination tables by class (DC=0, AC=1) and
  /// destination id (0...3); this routine writes parsed tables into
  /// `tables[class][id]`.
  static func parse(
    payload: ArraySlice<UInt8>,
    into tables: inout [[JPEG.HuffmanTable?]]
  ) throws(JPEG.DecodingError) {
    var i = payload.startIndex
    let end = payload.endIndex
    while i < end {
      guard end - i >= 17 else {
        throw .invalidHuffmanTable(reason: "truncated header")
      }
      let head = payload[i]
      let cls = Int(head >> 4)
      let dst = Int(head & 0x0F)
      i += 1

      guard cls == 0 || cls == 1 else {
        throw .invalidHuffmanTable(reason: "class must be 0 (DC) or 1 (AC), got \(cls)")
      }
      guard (0...3).contains(dst) else {
        throw .invalidHuffmanTable(reason: "destination must be 0-3, got \(dst)")
      }

      // 16 length counts.
      var counts = [Int](repeating: 0, count: 16)
      for L in 0..<16 {
        counts[L] = Int(payload[i + L])
      }
      i += 16

      let total = counts.reduce(0, +)
      guard total <= 256 else {
        throw .invalidHuffmanTable(reason: "symbol count \(total) exceeds 256")
      }
      guard end - i >= total else {
        throw .invalidHuffmanTable(reason: "truncated symbol list")
      }

      var huffVal = [UInt8](repeating: 0, count: total)
      for k in 0..<total {
        huffVal[k] = payload[i + k]
      }
      i += total

      let table = try JPEG.HuffmanTable.build(counts: counts, huffVal: huffVal)
      tables[cls][dst] = table
    }
  }

  /// Constructs a canonical decoding table from `bits[1...16]` counts and
  /// the flat symbol list.
  static func build(
    counts: [Int],
    huffVal: [UInt8]
  ) throws(JPEG.DecodingError) -> JPEG.HuffmanTable {
    precondition(counts.count == 16)

    var t = JPEG.HuffmanTable()
    t.huffVal = huffVal

    // Compute canonical codes per length.
    var huffCode = [Int32](repeating: 0, count: huffVal.count)
    var k = 0
    var code: Int32 = 0
    for L in 0..<16 {
      // Each code is one bit longer than the previous, so shift left.
      for _ in 0..<counts[L] {
        if k >= huffVal.count {
          throw .invalidHuffmanTable(reason: "code count exceeds symbol list length")
        }
        huffCode[k] = code
        code &+= 1
        k += 1
      }
      // Codes of length L+1 must not collide with the next prefix.
      if code > (1 << (L + 1)) {
        throw .invalidHuffmanTable(reason: "code count overflows length \(L + 1)")
      }
      code <<= 1
    }

    // minCode/maxCode/valOffset per length L (1...16, stored at L-1).
    var p = 0
    for L in 0..<16 {
      if counts[L] == 0 {
        t.minCode[L] = -1
        t.maxCode[L] = -1
        t.valOffset[L] = 0
      } else {
        t.valOffset[L] = p - Int(huffCode[p])
        t.minCode[L] = huffCode[p]
        t.maxCode[L] = huffCode[p + counts[L] - 1]
        p += counts[L]
      }
    }
    // Sentinel at index 16: any 16-bit code > maxCode[15] fails.
    t.minCode[16] = -1
    t.maxCode[16] = -1
    t.valOffset[16] = 0

    // Build fast 9-bit lookup. For every code of length <= 9, the table
    // entry indexed by (code << (9 - length)) ... ((code+1) << (9 - length)) - 1
    // gets length+symbol.
    var sym = 0
    for L in 1...9 {
      let count = counts[L - 1]
      for _ in 0..<count {
        let c = Int(huffCode[sym])
        let pad = 9 - L
        let lo = c << pad
        let hi = lo + (1 << pad)
        for idx in lo..<hi {
          t.fastLength[idx] = UInt8(L)
          t.fastSymbol[idx] = huffVal[sym]
        }
        sym += 1
      }
    }

    return t
  }
}
