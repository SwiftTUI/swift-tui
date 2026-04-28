extension PNG {

  /// A bit reader over a PNG/zlib bitstream.
  ///
  /// DEFLATE bytes are read LSB-first: the *first* bit of a multi-bit
  /// element is the least-significant bit of its byte (RFC 1951 §3.1.1).
  /// Huffman codes are packed starting with the *most-significant* bit of
  /// the code, but the bits arrive in the stream LSB-first; the decoder
  /// rebuilds the code by left-shifting each new bit into a running value.
  struct BitReader {
    let bytes: [UInt8]
    var pos: Int = 0
    /// Number of bits already consumed from `bytes[pos]`. `0` means the
    /// next bit is the LSB of the current byte; `8` means the byte is
    /// exhausted and `pos` should advance.
    var bitsConsumed: Int = 0

    @inline(__always)
    mutating func readBit() throws(PNG.DecodingError) -> UInt32 {
      if bitsConsumed == 8 {
        pos += 1
        bitsConsumed = 0
      }
      guard pos < bytes.count else {
        throw .truncated(stage: "DEFLATE bit stream")
      }
      let bit = UInt32((bytes[pos] >> bitsConsumed) & 1)
      bitsConsumed += 1
      return bit
    }

    /// Reads `n` bits, LSB-first (first bit = LSB of result). Used for
    /// raw values like block headers, lengths, and extra bits — not for
    /// Huffman codes.
    @inline(__always)
    mutating func readBits(_ n: Int) throws(PNG.DecodingError) -> UInt32 {
      var value: UInt32 = 0
      for i in 0..<n {
        let b = try readBit()
        value |= b << i
      }
      return value
    }

    /// Aligns the read cursor to the next byte boundary (used before
    /// stored / uncompressed blocks).
    mutating func alignToByte() {
      if bitsConsumed > 0 {
        pos += 1
        bitsConsumed = 0
      }
    }

    /// Reads `count` whole bytes after a byte alignment. Used inside
    /// stored blocks.
    mutating func readBytes(_ count: Int) throws(PNG.DecodingError) -> [UInt8] {
      guard pos + count <= bytes.count else {
        throw .truncated(stage: "stored block")
      }
      let slice = Array(bytes[pos..<pos + count])
      pos += count
      return slice
    }
  }
}

extension PNG {

  /// A canonical Huffman tree, suitable for decoding either the
  /// literal/length alphabet (max 286 symbols) or the distance alphabet
  /// (max 30 symbols) of a DEFLATE block.
  struct HuffmanTree {
    /// `firstCode[L]` = the canonical code value of the first symbol of
    /// length `L`. Indexed by code length 0...15.
    var firstCode: [UInt32]
    /// `firstSymbolIndex[L]` = where in `symbols` the run of length-`L`
    /// symbols begins.
    var firstSymbolIndex: [Int]
    /// `count[L]` = how many symbols have length `L`.
    var count: [Int]
    /// Symbols sorted by (length, symbol). Length-0 symbols are excluded.
    var symbols: [Int]
    /// Maximum code length actually used (1...15). 0 means the tree is
    /// empty (no symbols).
    var maxLength: Int

    /// Builds a canonical tree from per-symbol code lengths. A length of
    /// `0` means the symbol is unused.
    static func build(lengths: [Int]) throws(PNG.DecodingError) -> HuffmanTree {
      var blCount = [Int](repeating: 0, count: 16)
      for l in lengths {
        guard l >= 0, l <= 15 else {
          throw .invalidDeflateStream(reason: "huffman code length out of range: \(l)")
        }
        blCount[l] += 1
      }
      // The length-0 bucket counts unused symbols; ignore for canonical math.
      blCount[0] = 0

      var firstCode = [UInt32](repeating: 0, count: 16)
      var code: UInt32 = 0
      for length in 1...15 {
        code = (code + UInt32(blCount[length - 1])) << 1
        firstCode[length] = code
      }

      var firstSymbolIndex = [Int](repeating: 0, count: 16)
      var running = 0
      for length in 1...15 {
        firstSymbolIndex[length] = running
        running += blCount[length]
      }

      var symbols = [Int](repeating: 0, count: running)
      // Use a per-length cursor while filling, so the symbol table is
      // sorted by (length asc, symbol asc).
      var cursor = firstSymbolIndex
      for symbol in 0..<lengths.count {
        let l = lengths[symbol]
        if l == 0 { continue }
        symbols[cursor[l]] = symbol
        cursor[l] += 1
      }

      // Validate: a canonical tree must use exactly 2^maxLength codes.
      // We accept under-full trees only in two trivial cases (empty tree
      // and a single one-bit code, both of which DEFLATE permits).
      var maxLength = 0
      for l in 1...15 where blCount[l] > 0 { maxLength = l }
      if maxLength == 0 {
        return HuffmanTree(
          firstCode: firstCode,
          firstSymbolIndex: firstSymbolIndex,
          count: blCount,
          symbols: symbols,
          maxLength: 0
        )
      }
      // Single-symbol tree: DEFLATE allows a distance tree with a single
      // code of length 1; treat its code as `0`.
      if symbols.count == 1 {
        return HuffmanTree(
          firstCode: firstCode,
          firstSymbolIndex: firstSymbolIndex,
          count: blCount,
          symbols: symbols,
          maxLength: max(maxLength, 1)
        )
      }
      // Kraft check: sum of 2^(maxLength - l) over used symbols must
      // equal 2^maxLength.
      var kraft: UInt64 = 0
      for l in 1...maxLength {
        kraft &+= UInt64(blCount[l]) &* (UInt64(1) << UInt64(maxLength - l))
      }
      let target: UInt64 = UInt64(1) << UInt64(maxLength)
      if kraft != target {
        throw .invalidDeflateStream(
          reason: "huffman code lengths are over- or under-subscribed"
        )
      }

      return HuffmanTree(
        firstCode: firstCode,
        firstSymbolIndex: firstSymbolIndex,
        count: blCount,
        symbols: symbols,
        maxLength: maxLength
      )
    }

    /// Decodes a single symbol from the bit reader.
    @inline(__always)
    func decode(_ reader: inout BitReader) throws(PNG.DecodingError) -> Int {
      var code: UInt32 = 0
      for length in 1...15 {
        let bit = try reader.readBit()
        code = (code << 1) | bit
        let countAtL = count[length]
        if countAtL > 0 {
          let first = firstCode[length]
          if code >= first && code < first + UInt32(countAtL) {
            let offset = Int(code - first)
            return symbols[firstSymbolIndex[length] + offset]
          }
        }
      }
      throw .invalidDeflateStream(reason: "huffman code not found within 15 bits")
    }
  }
}

extension PNG {

  /// Length-code base values, indexed by symbol `length_code - 257`.
  /// (RFC 1951 §3.2.5)
  static let lengthBase: [Int] = [
    3, 4, 5, 6, 7, 8, 9, 10,
    11, 13, 15, 17, 19, 23, 27, 31,
    35, 43, 51, 59, 67, 83, 99, 115,
    131, 163, 195, 227, 258,
  ]

  /// Number of extra bits to read for each length code.
  static let lengthExtra: [Int] = [
    0, 0, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1, 2, 2, 2, 2,
    3, 3, 3, 3, 4, 4, 4, 4,
    5, 5, 5, 5, 0,
  ]

  /// Distance-code base values, indexed by distance code `0...29`.
  static let distanceBase: [Int] = [
    1, 2, 3, 4, 5, 7, 9, 13,
    17, 25, 33, 49, 65, 97, 129, 193,
    257, 385, 513, 769, 1025, 1537, 2049, 3073,
    4097, 6145, 8193, 12289, 16385, 24577,
  ]

  /// Number of extra bits to read for each distance code.
  static let distanceExtra: [Int] = [
    0, 0, 0, 0, 1, 1, 2, 2,
    3, 3, 4, 4, 5, 5, 6, 6,
    7, 7, 8, 8, 9, 9, 10, 10,
    11, 11, 12, 12, 13, 13,
  ]

  /// The fixed-Huffman code lengths for the literal/length alphabet
  /// (RFC 1951 §3.2.6). Symbols `0...143` are 8 bits, `144...255` are 9
  /// bits, `256...279` are 7 bits, `280...287` are 8 bits.
  static let fixedLitLengths: [Int] = {
    var arr = [Int](repeating: 0, count: 288)
    for i in 0...143 { arr[i] = 8 }
    for i in 144...255 { arr[i] = 9 }
    for i in 256...279 { arr[i] = 7 }
    for i in 280...287 { arr[i] = 8 }
    return arr
  }()

  /// The fixed-Huffman code lengths for the distance alphabet. RFC 1951
  /// §3.2.6 specifies all 32 symbols at length 5, even though only
  /// 0...29 are ever emitted; the two unused symbols are required for
  /// the canonical Kraft sum to balance.
  static let fixedDistLengths: [Int] = [Int](repeating: 5, count: 32)

  /// Order in which the 19 code-length-alphabet code lengths appear
  /// inside a dynamic-Huffman block header (RFC 1951 §3.2.7).
  static let codeLengthOrder: [Int] = [
    16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
  ]
}

extension PNG {

  /// Decompresses a zlib-wrapped DEFLATE stream into a flat byte array.
  ///
  /// The two-byte zlib header is parsed for sanity (CM must be `8` =
  /// DEFLATE; FCHECK must validate; FDICT must be unset for PNG); the
  /// trailing four-byte big-endian Adler-32 is verified against the
  /// inflated bytes.
  static func zlibInflate(
    _ bytes: [UInt8]
  ) throws(PNG.DecodingError) -> [UInt8] {
    guard bytes.count >= 6 else {
      throw .invalidDeflateStream(reason: "stream too short for zlib wrapper")
    }
    let cmf = bytes[0]
    let flg = bytes[1]
    let cm = cmf & 0x0F
    guard cm == 8 else {
      throw .invalidDeflateStream(reason: "compression method \(cm) is not DEFLATE")
    }
    // FCHECK: (cmf*256 + flg) must be a multiple of 31.
    let combined = (UInt32(cmf) &* 256) &+ UInt32(flg)
    guard combined % 31 == 0 else {
      throw .invalidDeflateStream(reason: "FCHECK validation failed")
    }
    // FDICT bit (bit 5 of FLG): PNG forbids preset dictionaries.
    if (flg & 0x20) != 0 {
      throw .invalidDeflateStream(reason: "preset dictionary (FDICT) not allowed in PNG")
    }

    // Inflate the raw DEFLATE payload, leaving the last 4 bytes for the
    // Adler-32 trailer.
    let deflateEnd = bytes.count - 4
    let inflated = try rawInflate(
      bytes: Array(bytes[2..<deflateEnd])
    )

    // Verify Adler-32. Stored big-endian per zlib (RFC 1950 §2.2).
    let expected =
      UInt32(bytes[bytes.count - 4]) << 24
      | UInt32(bytes[bytes.count - 3]) << 16
      | UInt32(bytes[bytes.count - 2]) << 8
      | UInt32(bytes[bytes.count - 1])
    let actual = adler32(inflated)
    guard expected == actual else {
      throw .invalidAdler32
    }

    return inflated
  }

  /// Inflates a raw DEFLATE stream (no zlib wrapper). Public-but-internal
  /// so the test target can exercise it directly without round-tripping
  /// the zlib envelope.
  static func rawInflate(
    bytes: [UInt8]
  ) throws(PNG.DecodingError) -> [UInt8] {
    var reader = BitReader(bytes: bytes)
    var output: [UInt8] = []
    output.reserveCapacity(bytes.count * 4)

    blocks: while true {
      let bfinal = try reader.readBit()
      let btype = try reader.readBits(2)
      switch btype {
      case 0:
        try inflateStoredBlock(reader: &reader, output: &output)
      case 1:
        try inflateHuffmanBlock(
          reader: &reader,
          litTree: fixedLitTree,
          distTree: fixedDistTree,
          output: &output
        )
      case 2:
        let (lit, dist) = try readDynamicTrees(reader: &reader)
        try inflateHuffmanBlock(
          reader: &reader,
          litTree: lit,
          distTree: dist,
          output: &output
        )
      default:
        throw .invalidDeflateStream(reason: "reserved block type 3")
      }
      if bfinal == 1 { break blocks }
    }

    return output
  }

  private static func inflateStoredBlock(
    reader: inout BitReader,
    output: inout [UInt8]
  ) throws(PNG.DecodingError) {
    reader.alignToByte()
    let lenBytes = try reader.readBytes(4)
    let len = Int(lenBytes[0]) | (Int(lenBytes[1]) << 8)
    let nlen = Int(lenBytes[2]) | (Int(lenBytes[3]) << 8)
    guard (len ^ 0xFFFF) == nlen else {
      throw .invalidDeflateStream(reason: "stored block LEN/NLEN mismatch")
    }
    let payload = try reader.readBytes(len)
    output.append(contentsOf: payload)
  }

  private static func inflateHuffmanBlock(
    reader: inout BitReader,
    litTree: HuffmanTree,
    distTree: HuffmanTree,
    output: inout [UInt8]
  ) throws(PNG.DecodingError) {
    while true {
      let symbol = try litTree.decode(&reader)
      if symbol < 256 {
        output.append(UInt8(symbol))
        continue
      }
      if symbol == 256 { return }
      // Length symbol.
      let lenIndex = symbol - 257
      guard lenIndex >= 0, lenIndex < lengthBase.count else {
        throw .invalidDeflateStream(reason: "length symbol \(symbol) out of range")
      }
      var length = lengthBase[lenIndex]
      let lExtra = lengthExtra[lenIndex]
      if lExtra > 0 {
        length += Int(try reader.readBits(lExtra))
      }
      // Distance symbol.
      let distSymbol = try distTree.decode(&reader)
      guard distSymbol >= 0, distSymbol < distanceBase.count else {
        throw .invalidDeflateStream(reason: "distance symbol \(distSymbol) out of range")
      }
      var distance = distanceBase[distSymbol]
      let dExtra = distanceExtra[distSymbol]
      if dExtra > 0 {
        distance += Int(try reader.readBits(dExtra))
      }
      // Copy `length` bytes from `distance` bytes back, byte-by-byte
      // (the back-reference may overlap, e.g. for runs of repeating
      // bytes — the byte-by-byte copy is required for correctness).
      guard distance >= 1, distance <= output.count else {
        throw .invalidDeflateStream(
          reason: "distance \(distance) exceeds output buffer (size \(output.count))"
        )
      }
      let start = output.count - distance
      for k in 0..<length {
        output.append(output[start + k])
      }
    }
  }

  private static func readDynamicTrees(
    reader: inout BitReader
  ) throws(PNG.DecodingError) -> (lit: HuffmanTree, dist: HuffmanTree) {
    let hlit = Int(try reader.readBits(5)) + 257
    let hdist = Int(try reader.readBits(5)) + 1
    let hclen = Int(try reader.readBits(4)) + 4

    var clLengths = [Int](repeating: 0, count: 19)
    for i in 0..<hclen {
      clLengths[codeLengthOrder[i]] = Int(try reader.readBits(3))
    }
    let clTree = try HuffmanTree.build(lengths: clLengths)

    let total = hlit + hdist
    var lengths = [Int](repeating: 0, count: total)
    var i = 0
    while i < total {
      let symbol = try clTree.decode(&reader)
      switch symbol {
      case 0...15:
        lengths[i] = symbol
        i += 1
      case 16:
        guard i > 0 else {
          throw .invalidDeflateStream(reason: "code-length 16 with no previous length")
        }
        let repeatCount = Int(try reader.readBits(2)) + 3
        let v = lengths[i - 1]
        guard i + repeatCount <= total else {
          throw .invalidDeflateStream(reason: "code-length 16 overflow")
        }
        for _ in 0..<repeatCount { lengths[i] = v; i += 1 }
      case 17:
        let repeatCount = Int(try reader.readBits(3)) + 3
        guard i + repeatCount <= total else {
          throw .invalidDeflateStream(reason: "code-length 17 overflow")
        }
        for _ in 0..<repeatCount { lengths[i] = 0; i += 1 }
      case 18:
        let repeatCount = Int(try reader.readBits(7)) + 11
        guard i + repeatCount <= total else {
          throw .invalidDeflateStream(reason: "code-length 18 overflow")
        }
        for _ in 0..<repeatCount { lengths[i] = 0; i += 1 }
      default:
        throw .invalidDeflateStream(reason: "invalid code-length symbol \(symbol)")
      }
    }

    let lit = try HuffmanTree.build(lengths: Array(lengths[0..<hlit]))
    let dist = try HuffmanTree.build(lengths: Array(lengths[hlit..<total]))
    return (lit, dist)
  }

  /// Lazily-built fixed literal/length tree (always the same).
  static let fixedLitTree: HuffmanTree = {
    // `try!` is justified: the fixed code lengths are spec-defined and
    // cannot fail Kraft validation.
    do {
      return try HuffmanTree.build(lengths: fixedLitLengths)
    } catch {
      fatalError("PNG: fixed literal tree failed to build: \(error)")
    }
  }()

  /// Lazily-built fixed distance tree (always the same).
  static let fixedDistTree: HuffmanTree = {
    do {
      return try HuffmanTree.build(lengths: fixedDistLengths)
    } catch {
      fatalError("PNG: fixed distance tree failed to build: \(error)")
    }
  }()

  /// Adler-32 checksum (RFC 1950 §9). Used to validate the inflated
  /// IDAT payload against the trailer in the zlib wrapper.
  static func adler32(_ data: [UInt8]) -> UInt32 {
    let modulus: UInt32 = 65521
    var s1: UInt32 = 1
    var s2: UInt32 = 0
    // Naïve implementation — fast enough for image-sized payloads, and
    // a tight loop with `&+` keeps overflow defined.
    for b in data {
      s1 = (s1 &+ UInt32(b)) % modulus
      s2 = (s2 &+ s1) % modulus
    }
    return (s2 << 16) | s1
  }
}
