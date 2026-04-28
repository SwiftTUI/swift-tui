extension PNG {

  /// PNG color types (IHDR field).
  enum ColorType: UInt8, Sendable, Equatable {
    case grayscale = 0
    case rgb = 2
    case palette = 3
    case grayscaleAlpha = 4
    case rgba = 6

    /// The number of *samples* per pixel (one for grayscale and palette,
    /// two for grayscale + alpha, three for RGB, four for RGBA).
    var samples: Int {
      switch self {
      case .grayscale, .palette: return 1
      case .grayscaleAlpha: return 2
      case .rgb: return 3
      case .rgba: return 4
      }
    }

    /// The set of legal `bitDepth` values per RFC 2083 §11.2.2.
    var allowedBitDepths: Set<UInt8> {
      switch self {
      case .grayscale: return [1, 2, 4, 8, 16]
      case .rgb: return [8, 16]
      case .palette: return [1, 2, 4, 8]
      case .grayscaleAlpha: return [8, 16]
      case .rgba: return [8, 16]
      }
    }
  }

  /// All metadata plus raw sample bytes produced by the decoder. The
  /// outer `Image` value wraps this and exposes only what callers need.
  struct DecodedPNG {
    let width: Int
    let height: Int
    let colorType: ColorType
    let bitDepth: Int
    let palette: [(r: UInt8, g: UInt8, b: UInt8)]?
    /// Optional per-palette-entry alpha (color type 3), or a single
    /// "transparent sample" value for color types 0 (grayscale) and 2
    /// (RGB). For grayscale the value is the gray sample; for RGB it's
    /// `(r, g, b)` packed into the low 48 bits, big-endian.
    let transparency: Transparency?
    /// Row-major raw samples. For sub-byte depths, samples are still
    /// packed within bytes the same way the PNG file stores them — the
    /// `unpack` step handles that.
    let samples: [UInt8]
    /// Bytes per scanline at full resolution (matches `samples.count /
    /// height`).
    let rowBytes: Int
  }

  /// Transparency information from an optional `tRNS` chunk.
  enum Transparency {
    /// Per-palette-entry alpha (color type 3). Indices beyond this
    /// array's length are fully opaque.
    case paletteAlpha([UInt8])
    /// A single transparent gray sample (color type 0). Compared at the
    /// declared bit depth.
    case grayscale(UInt16)
    /// A single transparent RGB triple (color type 2). Each component is
    /// compared at the declared bit depth.
    case rgb(r: UInt16, g: UInt16, b: UInt16)
  }
}

extension PNG {

  /// Top-level PNG decoder. Buffers every IDAT chunk, runs zlib inflate,
  /// then unfilters and (if interlaced) reassembles Adam7 sub-images
  /// into a flat row-major byte plane.
  struct Decoder {
    var bytes: [UInt8]

    init(bytes: [UInt8]) {
      self.bytes = bytes
    }

    mutating func decode() throws(PNG.DecodingError) -> DecodedPNG {
      var reader = ChunkReader(bytes: bytes)
      try reader.readSignature()

      // ---- IHDR ----
      let ihdr = try reader.readChunk()
      guard ihdr.type == [0x49, 0x48, 0x44, 0x52] else {
        throw .missingChunk(type: "IHDR")
      }
      guard ihdr.data.count == 13 else {
        throw .invalidColorTypeBitDepth(colorType: 0xFF, bitDepth: 0)
      }
      let width = Int(
        UInt32(ihdr.data[0]) << 24 | UInt32(ihdr.data[1]) << 16
          | UInt32(ihdr.data[2]) << 8 | UInt32(ihdr.data[3]))
      let height = Int(
        UInt32(ihdr.data[4]) << 24 | UInt32(ihdr.data[5]) << 16
          | UInt32(ihdr.data[6]) << 8 | UInt32(ihdr.data[7]))
      guard width > 0, height > 0 else {
        throw .emptyImage
      }
      let bitDepth = ihdr.data[8]
      let colorTypeRaw = ihdr.data[9]
      let compression = ihdr.data[10]
      let filterMethod = ihdr.data[11]
      let interlace = ihdr.data[12]

      guard let colorType = ColorType(rawValue: colorTypeRaw),
        colorType.allowedBitDepths.contains(bitDepth)
      else {
        throw .invalidColorTypeBitDepth(colorType: colorTypeRaw, bitDepth: bitDepth)
      }
      guard compression == 0 else {
        throw .unsupportedMethod(field: "compression", value: compression)
      }
      guard filterMethod == 0 else {
        throw .unsupportedMethod(field: "filter", value: filterMethod)
      }
      guard interlace == 0 || interlace == 1 else {
        throw .unsupportedMethod(field: "interlace", value: interlace)
      }

      // ---- subsequent chunks ----
      var palette: [(UInt8, UInt8, UInt8)]? = nil
      var transparency: PNG.Transparency? = nil
      var idatBuffer: [UInt8] = []
      var sawIEND = false

      chunks: while !reader.atEnd {
        let chunk = try reader.readChunk()
        switch chunk.type {
        case [0x50, 0x4C, 0x54, 0x45]:  // PLTE
          guard chunk.data.count % 3 == 0 else {
            throw .invalidPalette(reason: "length \(chunk.data.count) is not a multiple of 3")
          }
          let entries = chunk.data.count / 3
          if colorType == .palette, entries > 1 << Int(bitDepth) {
            throw .invalidPalette(
              reason: "\(entries) entries exceeds 2^\(bitDepth) limit"
            )
          }
          var p: [(UInt8, UInt8, UInt8)] = []
          p.reserveCapacity(entries)
          for i in 0..<entries {
            p.append((chunk.data[i * 3], chunk.data[i * 3 + 1], chunk.data[i * 3 + 2]))
          }
          palette = p

        case [0x49, 0x44, 0x41, 0x54]:  // IDAT
          idatBuffer.append(contentsOf: chunk.data)

        case [0x74, 0x52, 0x4E, 0x53]:  // tRNS
          transparency = try parseTransparency(
            data: chunk.data,
            colorType: colorType,
            bitDepth: Int(bitDepth)
          )

        case [0x49, 0x45, 0x4E, 0x44]:  // IEND
          sawIEND = true
          break chunks

        default:
          // Ancillary / unknown chunks are skipped. The CRC has already
          // been validated by `ChunkReader.readChunk`.
          continue chunks
        }
      }

      guard sawIEND else { throw .missingChunk(type: "IEND") }
      if colorType == .palette, palette == nil {
        throw .missingChunk(type: "PLTE")
      }
      guard !idatBuffer.isEmpty else { throw .missingChunk(type: "IDAT") }

      // ---- inflate IDAT ----
      let inflated = try PNG.zlibInflate(idatBuffer)

      // ---- unfilter (and de-interlace if needed) ----
      let bitsPerPixel = Int(bitDepth) * colorType.samples
      let bpp = max(1, (bitsPerPixel + 7) / 8)
      let rowBytes = (width * bitsPerPixel + 7) / 8

      var samples = [UInt8](repeating: 0, count: rowBytes * height)

      if interlace == 0 {
        var inOffset = 0
        var outOffset = 0
        try unfilter(
          input: inflated,
          offset: &inOffset,
          output: &samples,
          outputOffset: &outOffset,
          rows: height,
          rowBytes: rowBytes,
          bpp: bpp
        )
      } else {
        try deinterlaceAdam7(
          inflated: inflated,
          width: width,
          height: height,
          bitsPerPixel: bitsPerPixel,
          bpp: bpp,
          rowBytes: rowBytes,
          output: &samples
        )
      }

      return DecodedPNG(
        width: width,
        height: height,
        colorType: colorType,
        bitDepth: Int(bitDepth),
        palette: palette,
        transparency: transparency,
        samples: samples,
        rowBytes: rowBytes
      )
    }

    private func parseTransparency(
      data: [UInt8],
      colorType: ColorType,
      bitDepth: Int
    ) throws(PNG.DecodingError) -> PNG.Transparency {
      switch colorType {
      case .palette:
        return .paletteAlpha(data)
      case .grayscale:
        guard data.count == 2 else {
          throw .invalidTransparency(
            reason: "grayscale tRNS must be 2 bytes, got \(data.count)"
          )
        }
        let v = (UInt16(data[0]) << 8) | UInt16(data[1])
        return .grayscale(v)
      case .rgb:
        guard data.count == 6 else {
          throw .invalidTransparency(
            reason: "RGB tRNS must be 6 bytes, got \(data.count)"
          )
        }
        let r = (UInt16(data[0]) << 8) | UInt16(data[1])
        let g = (UInt16(data[2]) << 8) | UInt16(data[3])
        let b = (UInt16(data[4]) << 8) | UInt16(data[5])
        return .rgb(r: r, g: g, b: b)
      default:
        throw .invalidTransparency(
          reason: "tRNS chunk is not allowed for color type \(colorType.rawValue)"
        )
      }
    }

    /// Decodes the seven Adam7 passes, unfiltering each one separately,
    /// then writes the reconstructed sub-image pixels into the
    /// full-resolution `output` buffer at the correct (x, y) positions.
    private func deinterlaceAdam7(
      inflated: [UInt8],
      width: Int,
      height: Int,
      bitsPerPixel: Int,
      bpp: Int,
      rowBytes: Int,
      output: inout [UInt8]
    ) throws(PNG.DecodingError) {
      var inOffset = 0

      for pass in PNG.adam7Passes {
        let pw = PNG.passWidth(pass, imageWidth: width)
        let ph = PNG.passHeight(pass, imageHeight: height)
        if pw == 0 || ph == 0 { continue }

        let passRowBytes = (pw * bitsPerPixel + 7) / 8
        var passSamples = [UInt8](repeating: 0, count: passRowBytes * ph)
        var outOffset = 0
        try PNG.unfilter(
          input: inflated,
          offset: &inOffset,
          output: &passSamples,
          outputOffset: &outOffset,
          rows: ph,
          rowBytes: passRowBytes,
          bpp: bpp
        )

        // Place this pass's pixels into the full-image grid.
        for py in 0..<ph {
          let srcRowStart = py * passRowBytes
          let dstY = pass.yStart + py * pass.yStep
          for px in 0..<pw {
            let dstX = pass.xStart + px * pass.xStep
            copyPixel(
              from: passSamples,
              srcRowStart: srcRowStart,
              srcPixelIndex: px,
              into: &output,
              dstY: dstY,
              dstX: dstX,
              imageWidth: width,
              fullRowBytes: rowBytes,
              bitsPerPixel: bitsPerPixel
            )
          }
        }
      }
    }

    /// Copies a single pixel from a packed pass scanline into the
    /// full-resolution output buffer. Handles sub-byte depths by reading
    /// the relevant bits from the source and writing them at the
    /// destination's bit offset.
    private func copyPixel(
      from src: [UInt8],
      srcRowStart: Int,
      srcPixelIndex: Int,
      into dst: inout [UInt8],
      dstY: Int,
      dstX: Int,
      imageWidth: Int,
      fullRowBytes: Int,
      bitsPerPixel: Int
    ) {
      if bitsPerPixel >= 8 {
        let bytesPerPixel = bitsPerPixel / 8
        let srcOffset = srcRowStart + srcPixelIndex * bytesPerPixel
        let dstOffset = dstY * fullRowBytes + dstX * bytesPerPixel
        for k in 0..<bytesPerPixel {
          dst[dstOffset + k] = src[srcOffset + k]
        }
      } else {
        // bitsPerPixel ∈ {1, 2, 4}. Each byte holds `8 / bpp` pixels,
        // packed MSB-first per RFC 2083 §7.2.
        let bpp = bitsPerPixel
        let srcByte = srcRowStart + (srcPixelIndex * bpp) / 8
        let srcBit = (srcPixelIndex * bpp) % 8
        let mask: UInt8 = UInt8((1 << bpp) - 1)
        let shiftSrc = 8 - bpp - srcBit
        let value = (src[srcByte] >> UInt8(shiftSrc)) & mask

        let dstByte = dstY * fullRowBytes + (dstX * bpp) / 8
        let dstBit = (dstX * bpp) % 8
        let shiftDst = 8 - bpp - dstBit
        // Clear destination bits and OR in the new value.
        dst[dstByte] &= ~(mask << UInt8(shiftDst))
        dst[dstByte] |= (value & mask) << UInt8(shiftDst)
      }
    }
  }
}
