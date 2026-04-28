extension PNG {

  /// Reconstructs the original sample bytes from a filtered scanline
  /// stream. PNG prefixes each scanline with a one-byte filter type
  /// (0–4), then the filtered sample bytes; this routine performs the
  /// inverse of the filter so the caller is left with raw sample data.
  ///
  /// `bpp` is the per-pixel byte stride used for "left" and "upper-left"
  /// neighbour lookups (RFC 2083 §6.3): the number of bytes that one
  /// pixel occupies, rounded up to 1 for sub-byte depths. The standard
  /// values are:
  ///
  /// * grayscale         (CT 0): `ceil(bitDepth / 8)`
  /// * RGB               (CT 2): `3 * (bitDepth / 8)`
  /// * palette           (CT 3): `1`
  /// * grayscale + alpha (CT 4): `2 * (bitDepth / 8)`
  /// * RGBA              (CT 6): `4 * (bitDepth / 8)`
  ///
  /// The function consumes `rows * (1 + rowBytes)` filtered bytes from
  /// `input` starting at `offset`, advances `offset`, and writes
  /// `rows * rowBytes` reconstructed bytes into `output` starting at
  /// `outputOffset`, advancing it.
  static func unfilter(
    input: [UInt8],
    offset: inout Int,
    output: inout [UInt8],
    outputOffset: inout Int,
    rows: Int,
    rowBytes: Int,
    bpp: Int
  ) throws(PNG.DecodingError) {
    // We need access to the previous reconstructed row when filter type
    // is Up/Average/Paeth. For the first row, the "above" row is treated
    // as zero, so we can keep a scratch row of zeros and swap it in.
    var prev = [UInt8](repeating: 0, count: rowBytes)
    var current = [UInt8](repeating: 0, count: rowBytes)

    for _ in 0..<rows {
      guard offset < input.count else {
        throw .truncated(stage: "filter type byte")
      }
      let filterType = input[offset]
      offset += 1
      guard offset + rowBytes <= input.count else {
        throw .truncated(stage: "filtered scanline")
      }
      switch filterType {
      case 0:  // None
        for i in 0..<rowBytes {
          current[i] = input[offset + i]
        }
      case 1:  // Sub
        for i in 0..<rowBytes {
          let left: UInt8 = i >= bpp ? current[i - bpp] : 0
          current[i] = input[offset + i] &+ left
        }
      case 2:  // Up
        for i in 0..<rowBytes {
          current[i] = input[offset + i] &+ prev[i]
        }
      case 3:  // Average
        for i in 0..<rowBytes {
          let left: UInt32 = i >= bpp ? UInt32(current[i - bpp]) : 0
          let above: UInt32 = UInt32(prev[i])
          let avg = UInt8((left + above) / 2)
          current[i] = input[offset + i] &+ avg
        }
      case 4:  // Paeth
        for i in 0..<rowBytes {
          let a: Int = i >= bpp ? Int(current[i - bpp]) : 0
          let b: Int = Int(prev[i])
          let c: Int = i >= bpp ? Int(prev[i - bpp]) : 0
          let predicted = paeth(a: a, b: b, c: c)
          current[i] = input[offset + i] &+ UInt8(predicted)
        }
      default:
        throw .invalidFilterType(filterType)
      }
      offset += rowBytes

      // Copy reconstructed row into the output.
      for i in 0..<rowBytes {
        output[outputOffset + i] = current[i]
      }
      outputOffset += rowBytes

      // Swap buffers so `prev` is the row we just produced.
      swap(&prev, &current)
    }
  }

  /// Paeth predictor (RFC 2083 §6.6). Picks whichever of the three
  /// neighbours `a` (left), `b` (above), or `c` (upper-left) is closest
  /// to `a + b − c`. All three inputs are non-negative bytes treated as
  /// signed `Int` for the subtraction.
  @inline(__always)
  static func paeth(a: Int, b: Int, c: Int) -> Int {
    let p = a + b - c
    let pa = abs(p - a)
    let pb = abs(p - b)
    let pc = abs(p - c)
    if pa <= pb && pa <= pc { return a }
    if pb <= pc { return b }
    return c
  }
}
