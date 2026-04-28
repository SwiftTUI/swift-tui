extension JPEG {

  /// Color conversion helpers used after IDCT to produce 8-bit RGB.
  enum Color {

    /// Converts a YCbCr triplet (each 0...255) to RGB using the JFIF
    /// transformation. Constants are scaled by 2^16 to keep math integer:
    ///
    ///   R = Y + 1.402   * (Cr - 128)
    ///   G = Y - 0.34414 * (Cb - 128) - 0.71414 * (Cr - 128)
    ///   B = Y + 1.772   * (Cb - 128)
    @inline(__always)
    static func ycbcrToRGB(y: UInt8, cb: UInt8, cr: UInt8) -> (UInt8, UInt8, UInt8) {
      // Centered values (-128...127).
      let yi = Int32(y) &<< 16 &+ (1 &<< 15)  // +0.5 for rounding
      let cbCentered = Int32(cb) &- 128
      let crCentered = Int32(cr) &- 128

      let r = yi &+ 91881 &* crCentered
      let g = yi &- 22554 &* cbCentered &- 46802 &* crCentered
      let b = yi &+ 116130 &* cbCentered

      return (
        clamp(r &>> 16),
        clamp(g &>> 16),
        clamp(b &>> 16)
      )
    }

    /// CMYK → RGB using the (subtractive) approximation used by Photoshop:
    ///
    ///   R = (255 - C) * (255 - K) / 255
    ///   G = (255 - M) * (255 - K) / 255
    ///   B = (255 - Y) * (255 - K) / 255
    ///
    /// Adobe stores inverse CMYK in JPEGs (so 0 = full ink), so this
    /// formulation simplifies to `(C * K) / 255` etc when ink values are
    /// already inverted; the helper expects the values straight from the
    /// scan and matches Photoshop's behavior.
    @inline(__always)
    static func cmykToRGB(c: UInt8, m: UInt8, y: UInt8, k: UInt8) -> (UInt8, UInt8, UInt8) {
      let kk = Int32(k)
      let r = Int32(c) &* kk / 255
      let g = Int32(m) &* kk / 255
      let b = Int32(y) &* kk / 255
      return (clamp(r), clamp(g), clamp(b))
    }

    @inline(__always)
    static func clamp(_ value: Int32) -> UInt8 {
      if value < 0 { return 0 }
      if value > 255 { return 255 }
      return UInt8(value)
    }
  }
}
