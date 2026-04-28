extension PNG {

  /// A rectangular image decoded from a PNG bytestream.
  ///
  /// The public surface mirrors `JPEG.Image` and `GIF.Image`: ``size`` is
  /// a `(x, y)` tuple of pixel dimensions, ``decompress(stream:)`` is the
  /// primary constructor, and ``unpack(as:)`` produces a row-major flat
  /// array of `RGBA` pixels.
  public struct Image: Sendable {
    /// The pixel dimensions of this image.
    public let size: (x: Int, y: Int)

    /// The PNG color type (0 grayscale, 2 RGB, 3 palette, 4 grayscale+α,
    /// 6 RGBA). Provided for callers that want to vary their behaviour
    /// per source format; typical code can ignore this and call
    /// ``unpack(as:)``.
    public let colorType: UInt8

    /// The PNG bit depth (1, 2, 4, 8, or 16).
    public let bitDepth: Int

    // ----- internal storage -----
    let samples: [UInt8]
    let rowBytes: Int
    let palette: [(r: UInt8, g: UInt8, b: UInt8)]?
    let transparency: PNG.Transparency?
    let pngColorType: PNG.ColorType

    init(
      size: (Int, Int),
      colorType: PNG.ColorType,
      bitDepth: Int,
      samples: [UInt8],
      rowBytes: Int,
      palette: [(r: UInt8, g: UInt8, b: UInt8)]?,
      transparency: PNG.Transparency?
    ) {
      self.size = size
      self.colorType = colorType.rawValue
      self.bitDepth = bitDepth
      self.samples = samples
      self.rowBytes = rowBytes
      self.palette = palette
      self.transparency = transparency
      self.pngColorType = colorType
    }

    /// Decodes the PNG bytestream produced by `stream`.
    public static func decompress<Source>(
      stream: inout Source
    ) throws -> PNG.Image where Source: PNG.BytestreamSource {
      let bytes = PNG.Image.loadAllBytes(from: &stream)
      var decoder = PNG.Decoder(bytes: bytes)
      let decoded = try decoder.decode()
      return PNG.Image(
        size: (decoded.width, decoded.height),
        colorType: decoded.colorType,
        bitDepth: decoded.bitDepth,
        samples: decoded.samples,
        rowBytes: decoded.rowBytes,
        palette: decoded.palette,
        transparency: decoded.transparency
      )
    }

    /// Unpacks the decoded image into a flat row-major array of `RGBA<T>`.
    ///
    /// Bit depths are scaled to the target type by the same convention
    /// PNG itself uses (RFC 2083 §13.13): bit replication, so a sample
    /// of `0xAB` at 8 bits becomes `0xABAB` at 16 bits, a sample of
    /// `0b1010` at 4 bits becomes `0xAA` at 8 bits, and so on.
    ///
    /// Color types are mapped as follows:
    /// * 0 → grayscale, replicated to R/G/B; alpha = `T.max` unless the
    ///       sample equals the `tRNS` gray sample, in which case α = 0
    /// * 2 → RGB; alpha = `T.max` unless `(r, g, b)` equals the `tRNS`
    ///       triple, in which case α = 0
    /// * 3 → palette lookup; alpha from the `tRNS` table (or `T.max`)
    /// * 4 → grayscale + α
    /// * 6 → RGBA passthrough
    public func unpack<T>(as type: PNG.RGBA<T>.Type) -> [PNG.RGBA<T>]
    where T: FixedWidthInteger & UnsignedInteger {
      let total = size.x * size.y
      var out = [PNG.RGBA<T>](
        repeating: PNG.RGBA<T>(0, 0, 0, PNG.RGBA<T>.opaqueAlpha),
        count: total
      )

      switch pngColorType {
      case .grayscale:
        unpackGrayscale(into: &out, as: type)
      case .rgb:
        unpackRGB(into: &out, as: type)
      case .palette:
        unpackPalette(into: &out, as: type)
      case .grayscaleAlpha:
        unpackGrayscaleAlpha(into: &out, as: type)
      case .rgba:
        unpackRGBA(into: &out, as: type)
      }
      return out
    }

    // MARK: grayscale

    private func unpackGrayscale<T>(
      into out: inout [PNG.RGBA<T>],
      as: PNG.RGBA<T>.Type
    ) where T: FixedWidthInteger & UnsignedInteger {
      let opaque = PNG.RGBA<T>.opaqueAlpha
      let clear = PNG.RGBA<T>.clearAlpha
      var transparentSample: UInt16? = nil
      if case .grayscale(let v) = transparency { transparentSample = v }

      for y in 0..<size.y {
        for x in 0..<size.x {
          let raw = readSample(x: x, y: y, sample: 0)
          let isTransparent = (raw == transparentSample)
          let scaled: T = scaleSample(raw, sourceBits: bitDepth)
          out[y * size.x + x] = PNG.RGBA<T>(
            scaled, scaled, scaled,
            isTransparent ? clear : opaque
          )
        }
      }
    }

    // MARK: RGB

    private func unpackRGB<T>(
      into out: inout [PNG.RGBA<T>],
      as: PNG.RGBA<T>.Type
    ) where T: FixedWidthInteger & UnsignedInteger {
      let opaque = PNG.RGBA<T>.opaqueAlpha
      let clear = PNG.RGBA<T>.clearAlpha
      var triple: (UInt16, UInt16, UInt16)? = nil
      if case .rgb(let r, let g, let b) = transparency { triple = (r, g, b) }

      for y in 0..<size.y {
        for x in 0..<size.x {
          let r = readSample(x: x, y: y, sample: 0)
          let g = readSample(x: x, y: y, sample: 1)
          let b = readSample(x: x, y: y, sample: 2)
          let isTransparent: Bool
          if let t = triple {
            isTransparent = (r == t.0 && g == t.1 && b == t.2)
          } else {
            isTransparent = false
          }
          out[y * size.x + x] = PNG.RGBA<T>(
            scaleSample(r, sourceBits: bitDepth),
            scaleSample(g, sourceBits: bitDepth),
            scaleSample(b, sourceBits: bitDepth),
            isTransparent ? clear : opaque
          )
        }
      }
    }

    // MARK: palette

    private func unpackPalette<T>(
      into out: inout [PNG.RGBA<T>],
      as: PNG.RGBA<T>.Type
    ) where T: FixedWidthInteger & UnsignedInteger {
      // Palette lookup. tRNS for color type 3 is a list of per-entry
      // alphas; missing entries are fully opaque.
      let opaque = PNG.RGBA<T>.opaqueAlpha
      var alphaTable: [UInt8] = []
      if case .paletteAlpha(let table) = transparency { alphaTable = table }
      let palette = self.palette ?? []

      for y in 0..<size.y {
        for x in 0..<size.x {
          let idx = Int(readSample(x: x, y: y, sample: 0))
          let entry: (UInt8, UInt8, UInt8)
          if idx < palette.count {
            entry = palette[idx]
          } else {
            entry = (0, 0, 0)
          }
          let alpha: T
          if idx < alphaTable.count {
            alpha = scaleSample(UInt16(alphaTable[idx]), sourceBits: 8)
          } else {
            alpha = opaque
          }
          out[y * size.x + x] = PNG.RGBA<T>(
            scaleSample(UInt16(entry.0), sourceBits: 8),
            scaleSample(UInt16(entry.1), sourceBits: 8),
            scaleSample(UInt16(entry.2), sourceBits: 8),
            alpha
          )
        }
      }
    }

    // MARK: grayscale + alpha

    private func unpackGrayscaleAlpha<T>(
      into out: inout [PNG.RGBA<T>],
      as: PNG.RGBA<T>.Type
    ) where T: FixedWidthInteger & UnsignedInteger {
      for y in 0..<size.y {
        for x in 0..<size.x {
          let g = readSample(x: x, y: y, sample: 0)
          let a = readSample(x: x, y: y, sample: 1)
          let v: T = scaleSample(g, sourceBits: bitDepth)
          out[y * size.x + x] = PNG.RGBA<T>(
            v, v, v,
            scaleSample(a, sourceBits: bitDepth)
          )
        }
      }
    }

    // MARK: RGBA

    private func unpackRGBA<T>(
      into out: inout [PNG.RGBA<T>],
      as: PNG.RGBA<T>.Type
    ) where T: FixedWidthInteger & UnsignedInteger {
      for y in 0..<size.y {
        for x in 0..<size.x {
          let r = readSample(x: x, y: y, sample: 0)
          let g = readSample(x: x, y: y, sample: 1)
          let b = readSample(x: x, y: y, sample: 2)
          let a = readSample(x: x, y: y, sample: 3)
          out[y * size.x + x] = PNG.RGBA<T>(
            scaleSample(r, sourceBits: bitDepth),
            scaleSample(g, sourceBits: bitDepth),
            scaleSample(b, sourceBits: bitDepth),
            scaleSample(a, sourceBits: bitDepth)
          )
        }
      }
    }

    // MARK: sample reading

    /// Reads one sample at pixel `(x, y)`. `sample` is the channel index
    /// inside the pixel (0 for grayscale or palette index, 0/1 for
    /// gray+α, 0/1/2 for RGB, 0/1/2/3 for RGBA).
    ///
    /// For 8-bit samples, the result is the byte value. For 16-bit
    /// samples, the result is the big-endian `UInt16`. For sub-byte
    /// depths (1, 2, 4 — only used with grayscale and palette), the
    /// result is the unscaled small integer.
    private func readSample(x: Int, y: Int, sample: Int) -> UInt16 {
      let samplesPerPixel = pngColorType.samples
      let rowStart = y * rowBytes
      switch bitDepth {
      case 8:
        let off = rowStart + x * samplesPerPixel + sample
        return UInt16(samples[off])
      case 16:
        let off = rowStart + (x * samplesPerPixel + sample) * 2
        return UInt16(samples[off]) << 8 | UInt16(samples[off + 1])
      case 1, 2, 4:
        // Sub-byte depths are only legal for color types 0 and 3, both
        // of which have a single sample per pixel — `sample` is always
        // 0 here. Pixels are packed MSB-first.
        let bpp = bitDepth
        let bitIndex = x * bpp
        let byte = rowStart + bitIndex / 8
        let shift = 8 - bpp - (bitIndex % 8)
        let mask: UInt8 = UInt8((1 << bpp) - 1)
        return UInt16((samples[byte] >> UInt8(shift)) & mask)
      default:
        // Unreachable — IHDR validation rejects other depths.
        return 0
      }
    }

    /// Reads as many bytes as the source will provide. Mirrors the GIF
    /// and JPEG decoders' `loadAllBytes` so the same `BytestreamSource`
    /// adapter works across all three.
    static func loadAllBytes<S: PNG.BytestreamSource>(
      from source: inout S
    ) -> [UInt8] {
      var data: [UInt8] = []
      let chunkSize = 4096
      while let chunk = source.read(count: chunkSize) {
        data.append(contentsOf: chunk)
      }
      while let byte = source.read(count: 1) {
        data.append(byte[0])
      }
      return data
    }
  }
}

// MARK: - Sub-byte to T scaling

/// Scales a non-negative source sample of `sourceBits` bits up (or down)
/// to the target unsigned integer type using bit replication, matching
/// the convention from RFC 2083 §13.13. For example, the 4-bit sample
/// `0b1011` becomes `0b1011_1011` at 8 bits and `0b1011_1011_1011_1011`
/// at 16 bits.
@inline(__always)
private func scaleSample<T>(
  _ value: UInt16,
  sourceBits: Int
) -> T where T: FixedWidthInteger & UnsignedInteger {
  let targetBits = T.bitWidth
  if sourceBits == targetBits {
    return T(truncatingIfNeeded: value)
  }
  if sourceBits > targetBits {
    // Down-scale: keep the high `targetBits` of the source (e.g. 16 → 8
    // truncates to the high byte).
    let shift = sourceBits - targetBits
    return T(truncatingIfNeeded: value >> UInt16(shift))
  }
  // Up-scale: bit-replicate. We fill the target by repeating the source
  // pattern. This ensures `0` stays `0` and `(1 << sourceBits) - 1`
  // becomes `T.max`, which is what PNG callers expect.
  var bitsRemaining = targetBits
  var result: UInt64 = 0
  while bitsRemaining >= sourceBits {
    result = (result << UInt64(sourceBits)) | UInt64(value)
    bitsRemaining -= sourceBits
  }
  if bitsRemaining > 0 {
    let shift = sourceBits - bitsRemaining
    result = (result << UInt64(bitsRemaining)) | UInt64(value >> UInt16(shift))
  }
  return T(truncatingIfNeeded: result)
}
