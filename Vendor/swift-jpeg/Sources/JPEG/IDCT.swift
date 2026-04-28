extension JPEG {

  /// 8×8 inverse DCT used by the baseline decoder.
  ///
  /// This is a Swift port of the integer IDCT used by `stb_image.h` (in
  /// turn derived from the IJG `jidctint` algorithm). Constants are
  /// pre-multiplied by 2^12 so the inner loop uses pure integer math; the
  /// final shifts undo that scaling and clamp to `0...255`.
  enum IDCT {

    // f2f(x) = round(x * 4096)
    @inline(__always) static func f2f(_ x: Double) -> Int32 {
      Int32((x * 4096.0 + 0.5).rounded(.down))
    }
    // fsh(x) = x << 12
    @inline(__always) static func fsh(_ x: Int32) -> Int32 { x &<< 12 }

    // Pre-scaled constants. Computed once at compile time.
    static let K_0_5411961: Int32 = 2217
    static let K_n1_8477591: Int32 = -7568
    static let K_0_7653669: Int32 = 3135
    static let K_0_2986313: Int32 = 1223
    static let K_2_0531199: Int32 = 8410
    static let K_3_0727110: Int32 = 12586
    static let K_1_5013211: Int32 = 6149
    static let K_1_1758756: Int32 = 4816
    static let K_n0_8999762: Int32 = -3686
    static let K_n2_5629154: Int32 = -10498
    static let K_n1_9615705: Int32 = -8034
    static let K_n0_3901806: Int32 = -1598

    /// Performs 1D IDCT on 8 inputs. Returns `(x0, x1, x2, x3, t0, t1, t2, t3)`
    /// such that the spatial samples are:
    ///   `[x0+t3, x1+t2, x2+t1, x3+t0, x3-t0, x2-t1, x1-t2, x0-t3]`
    @inline(__always)
    static func idct1D(
      _ s0: Int32, _ s1: Int32, _ s2: Int32, _ s3: Int32,
      _ s4: Int32, _ s5: Int32, _ s6: Int32, _ s7: Int32
    ) -> (Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32) {
      // Even part.
      let p1 = (s2 &+ s6) &* K_0_5411961
      let t2 = p1 &+ s6 &* K_n1_8477591
      let t3 = p1 &+ s2 &* K_0_7653669
      let s04Add = fsh(s0 &+ s4)
      let s04Sub = fsh(s0 &- s4)
      let x0 = s04Add &+ t3
      let x3 = s04Add &- t3
      let x1 = s04Sub &+ t2
      let x2 = s04Sub &- t2

      // Odd part.
      var u0 = s7
      var u1 = s5
      var u2 = s3
      var u3 = s1
      let q3 = u0 &+ u2
      let q4 = u1 &+ u3
      let q1 = u0 &+ u3
      let q2 = u1 &+ u2
      let q5 = (q3 &+ q4) &* K_1_1758756
      u0 = u0 &* K_0_2986313
      u1 = u1 &* K_2_0531199
      u2 = u2 &* K_3_0727110
      u3 = u3 &* K_1_5013211
      let r1 = q5 &+ q1 &* K_n0_8999762
      let r2 = q5 &+ q2 &* K_n2_5629154
      let r3 = q3 &* K_n1_9615705
      let r4 = q4 &* K_n0_3901806
      u3 = u3 &+ r1 &+ r4
      u2 = u2 &+ r2 &+ r3
      u1 = u1 &+ r2 &+ r4
      u0 = u0 &+ r1 &+ r3

      return (x0, x1, x2, x3, u0, u1, u2, u3)
    }

    /// Runs the full 2D IDCT on a 64-coefficient block (in natural
    /// order, already dequantized) and writes 8-bit samples (centered
    /// to 0...255 with the +128 level shift) to `output[outBase + r*outStride + c]`.
    static func transformBlock(
      input block: [Int32],
      output: inout [UInt8],
      outBase: Int,
      outStride: Int
    ) {
      // Pass 1: columns. Store intermediate with extra 2 bits of
      // precision, so we shift by 10 here.
      var v = [Int32](repeating: 0, count: 64)
      for i in 0..<8 {
        // Fast path: AC all zero — output is 4 * DC.
        if block[i + 8] == 0 && block[i + 16] == 0
          && block[i + 24] == 0 && block[i + 32] == 0
          && block[i + 40] == 0 && block[i + 48] == 0
          && block[i + 56] == 0
        {
          let dc = block[i] &* 4
          for k in 0..<8 {
            v[i + k * 8] = dc
          }
          continue
        }

        let r = idct1D(
          block[i + 0],
          block[i + 8],
          block[i + 16],
          block[i + 24],
          block[i + 32],
          block[i + 40],
          block[i + 48],
          block[i + 56]
        )
        let bias: Int32 = 512
        let x0 = r.0 &+ bias
        let x1 = r.1 &+ bias
        let x2 = r.2 &+ bias
        let x3 = r.3 &+ bias
        v[i + 0] = (x0 &+ r.7) &>> 10
        v[i + 56] = (x0 &- r.7) &>> 10
        v[i + 8] = (x1 &+ r.6) &>> 10
        v[i + 48] = (x1 &- r.6) &>> 10
        v[i + 16] = (x2 &+ r.5) &>> 10
        v[i + 40] = (x2 &- r.5) &>> 10
        v[i + 24] = (x3 &+ r.4) &>> 10
        v[i + 32] = (x3 &- r.4) &>> 10
      }

      // Pass 2: rows. Final shift adds +128 level shift and clamps.
      for j in 0..<8 {
        let row = j * 8
        let r = idct1D(
          v[row + 0], v[row + 1], v[row + 2], v[row + 3],
          v[row + 4], v[row + 5], v[row + 6], v[row + 7]
        )
        // Pre-shift bias: (128 << 17) for level shift, +65536 for rounding.
        let bias: Int32 = 65536 &+ (128 &<< 17)
        let x0 = r.0 &+ bias
        let x1 = r.1 &+ bias
        let x2 = r.2 &+ bias
        let x3 = r.3 &+ bias

        let o = outBase + j * outStride
        output[o + 0] = clamp((x0 &+ r.7) &>> 17)
        output[o + 7] = clamp((x0 &- r.7) &>> 17)
        output[o + 1] = clamp((x1 &+ r.6) &>> 17)
        output[o + 6] = clamp((x1 &- r.6) &>> 17)
        output[o + 2] = clamp((x2 &+ r.5) &>> 17)
        output[o + 5] = clamp((x2 &- r.5) &>> 17)
        output[o + 3] = clamp((x3 &+ r.4) &>> 17)
        output[o + 4] = clamp((x3 &- r.4) &>> 17)
      }
    }

    @inline(__always)
    static func clamp(_ value: Int32) -> UInt8 {
      if value < 0 { return 0 }
      if value > 255 { return 255 }
      return UInt8(value)
    }
  }
}
