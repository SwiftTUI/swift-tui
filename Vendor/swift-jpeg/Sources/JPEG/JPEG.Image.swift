extension JPEG {

  /// A rectangular image decoded from a baseline JPEG bytestream.
  ///
  /// The public surface mirrors `PNG.Image`: ``size`` is a `(x, y)` tuple
  /// of pixel dimensions, ``decompress(stream:)`` is the primary
  /// constructor, and ``unpack(as:)`` produces a row-major flat array of
  /// `RGBA` pixels.
  public struct Image: Sendable {
    /// The pixel dimensions of this image.
    public let size: (x: Int, y: Int)

    /// The number of components in the source JPEG (1 = grayscale,
    /// 3 = YCbCr / RGB, 4 = CMYK / YCCK).
    public let components: Int

    // Internal: row-major full-resolution sample planes.
    let planes: [[UInt8]]

    // Internal: original colorspace hints.
    let isAdobeYCCK: Bool
    let isAdobeRGB: Bool

    init(
      size: (Int, Int), components: Int, planes: [[UInt8]],
      isAdobeYCCK: Bool, isAdobeRGB: Bool
    ) {
      self.size = size
      self.components = components
      self.planes = planes
      self.isAdobeYCCK = isAdobeYCCK
      self.isAdobeRGB = isAdobeRGB
    }

    /// Decodes the JPEG bytestream produced by `stream`.
    public static func decompress<Source>(
      stream: inout Source
    ) throws -> JPEG.Image where Source: JPEG.BytestreamSource {
      let bytes = JPEG.Image.loadAllBytes(from: &stream)
      var decoder = JPEG.Decoder(bytes: bytes)
      let decoded = try decoder.decode()
      return JPEG.Image(
        size: (decoded.width, decoded.height),
        components: decoded.components.count,
        planes: decoded.components,
        isAdobeYCCK: decoded.isAdobeYCCK,
        isAdobeRGB: decoded.isAdobeRGB
      )
    }

    /// Unpacks the decoded image into a flat row-major array of `RGBA<T>`.
    ///
    /// Component count is mapped as follows:
    /// * 1 → grayscale, replicated to R/G/B, alpha = `T.max`
    /// * 3 → YCbCr (or Adobe RGB if the APP14 marker says so)
    /// * 4 → Adobe CMYK / YCCK
    public func unpack<T>(as type: JPEG.RGBA<T>.Type) -> [JPEG.RGBA<T>] {
      let total = size.x * size.y
      var out = [JPEG.RGBA<T>](
        repeating: JPEG.RGBA<T>(0, 0, 0, JPEG.RGBA<T>.opaqueAlpha),
        count: total
      )
      switch components {
      case 1:
        let g = planes[0]
        for i in 0..<total {
          let v = scale(UInt8: g[i], to: T.self)
          out[i] = JPEG.RGBA<T>(v, v, v, JPEG.RGBA<T>.opaqueAlpha)
        }

      case 3:
        let p0 = planes[0]
        let p1 = planes[1]
        let p2 = planes[2]
        if isAdobeRGB {
          for i in 0..<total {
            out[i] = JPEG.RGBA<T>(
              scale(UInt8: p0[i], to: T.self),
              scale(UInt8: p1[i], to: T.self),
              scale(UInt8: p2[i], to: T.self),
              JPEG.RGBA<T>.opaqueAlpha
            )
          }
        } else {
          for i in 0..<total {
            let (r, g, b) = JPEG.Color.ycbcrToRGB(y: p0[i], cb: p1[i], cr: p2[i])
            out[i] = JPEG.RGBA<T>(
              scale(UInt8: r, to: T.self),
              scale(UInt8: g, to: T.self),
              scale(UInt8: b, to: T.self),
              JPEG.RGBA<T>.opaqueAlpha
            )
          }
        }

      case 4:
        let p0 = planes[0]
        let p1 = planes[1]
        let p2 = planes[2]
        let p3 = planes[3]
        if isAdobeYCCK {
          // Convert YCbCr → RGB first, then apply K mask.
          for i in 0..<total {
            let (r, g, b) = JPEG.Color.ycbcrToRGB(y: p0[i], cb: p1[i], cr: p2[i])
            let k = Int32(p3[i])
            let r2 = (Int32(r) &* k) / 255
            let g2 = (Int32(g) &* k) / 255
            let b2 = (Int32(b) &* k) / 255
            out[i] = JPEG.RGBA<T>(
              scale(UInt8: clampU8(r2), to: T.self),
              scale(UInt8: clampU8(g2), to: T.self),
              scale(UInt8: clampU8(b2), to: T.self),
              JPEG.RGBA<T>.opaqueAlpha
            )
          }
        } else {
          // Adobe inverted CMYK: 255 = no ink → RGB = (C*K/255, M*K/255, Y*K/255).
          for i in 0..<total {
            let (r, g, b) = JPEG.Color.cmykToRGB(c: p0[i], m: p1[i], y: p2[i], k: p3[i])
            out[i] = JPEG.RGBA<T>(
              scale(UInt8: r, to: T.self),
              scale(UInt8: g, to: T.self),
              scale(UInt8: b, to: T.self),
              JPEG.RGBA<T>.opaqueAlpha
            )
          }
        }

      default:
        // Already validated at parse time; reaching here is impossible.
        break
      }
      return out
    }

    /// Reads as many bytes as the source will provide, with adaptive
    /// chunk sizing. Some `BytestreamSource` implementations (notably
    /// `InMemoryPNGSource` in this project) treat partial reads as
    /// failures, so we fall back to a 1-byte read at the tail.
    static func loadAllBytes<S: JPEG.BytestreamSource>(from source: inout S) -> [UInt8] {
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

// MARK: - Internal helpers

@inline(__always)
private func scale<T>(UInt8 value: UInt8, to: T.Type) -> T
where T: FixedWidthInteger & UnsignedInteger {
  if T.bitWidth == 8 {
    return T(value)
  }
  if T.bitWidth == 16 {
    // Replicate the byte: 0xAB → 0xABAB. Matches PNG's bit-depth scaling.
    let v = UInt16(value)
    return T(truncatingIfNeeded: (v << 8) | v)
  }
  // Generic fallback.
  let denom = T.max / T(255)
  return T(value) &* denom
}

@inline(__always)
private func clampU8(_ value: Int32) -> UInt8 {
  if value < 0 { return 0 }
  if value > 255 { return 255 }
  return UInt8(value)
}
