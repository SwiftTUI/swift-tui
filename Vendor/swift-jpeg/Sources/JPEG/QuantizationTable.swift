extension JPEG {

  /// An 8×8 quantization table, stored in **natural** (post-zigzag) order.
  struct QuantizationTable {
    /// 64 entries, indexed by row-major position (0...63).
    var values: [Int32]

    init() {
      self.values = .init(repeating: 1, count: 64)
    }
  }

  /// The standard JPEG zigzag ordering. `zigzag[k]` is the natural-order
  /// position of the `k`-th coefficient in the bitstream.
  static let zigzag: [Int] = [
    0, 1, 8, 16, 9, 2, 3, 10,
    17, 24, 32, 25, 18, 11, 4, 5,
    12, 19, 26, 33, 40, 48, 41, 34,
    27, 20, 13, 6, 7, 14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36,
    29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46,
    53, 60, 61, 54, 47, 55, 62, 63,
  ]
}

extension JPEG.QuantizationTable {
  /// Parses one or more quantization tables from a `DQT` segment payload
  /// (the bytes between the segment length and the next marker, exclusive
  /// of the length itself).
  ///
  /// The caller writes each parsed table into `tables[id]`.
  static func parse(
    payload: ArraySlice<UInt8>,
    into tables: inout [Int: JPEG.QuantizationTable]
  ) throws(JPEG.DecodingError) {
    var i = payload.startIndex
    let end = payload.endIndex
    while i < end {
      let head = payload[i]
      let precision = Int(head >> 4)  // 0 = 8-bit, 1 = 16-bit
      let id = Int(head & 0x0F)  // destination 0...3
      i += 1

      guard precision == 0 || precision == 1 else {
        throw .invalidQuantizationTable(reason: "precision must be 0 or 1, got \(precision)")
      }
      guard (0...3).contains(id) else {
        throw .invalidQuantizationTable(reason: "destination must be 0-3, got \(id)")
      }

      let bytesPerEntry = precision == 0 ? 1 : 2
      let need = 64 * bytesPerEntry
      guard end - i >= need else {
        throw .invalidQuantizationTable(reason: "truncated table \(id)")
      }

      var table = JPEG.QuantizationTable()
      for k in 0..<64 {
        let value: Int32
        if precision == 0 {
          value = Int32(payload[i])
          i += 1
        } else {
          value = (Int32(payload[i]) << 8) | Int32(payload[i + 1])
          i += 2
        }
        table.values[JPEG.zigzag[k]] = value
      }
      tables[id] = table
    }
  }
}
