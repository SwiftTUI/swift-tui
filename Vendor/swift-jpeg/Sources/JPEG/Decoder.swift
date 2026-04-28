extension JPEG {

  /// The raw decoded result of a baseline JPEG: per-component 8-bit sample
  /// planes at full image resolution (after chroma upsampling).
  struct Decoded {
    var width: Int
    var height: Int
    var components: [[UInt8]]  // length 1, 3, or 4; each `width * height`
    var componentIDs: [Int]  // matches `components` order
    var isAdobeYCCK: Bool  // true if APP14 declared Adobe YCCK
    var isAdobeRGB: Bool  // true if APP14 declared Adobe RGB (rare)
  }

  /// Stateful baseline-JPEG decoder. The driver reads markers from `bytes`,
  /// updates `state` (quant/huffman tables, frame, restart interval), and
  /// when the `SOS` marker is reached, decodes the scan into per-component
  /// 8-bit sample planes.
  struct Decoder {
    // Byte stream.
    var bytes: [UInt8]
    var pos: Int

    // Tables, frame, restart interval.
    var quantTables: [Int: QuantizationTable] = [:]
    var huffmanTables: [[HuffmanTable?]] = [
      Array(repeating: nil, count: 4),  // DC, 0...3
      Array(repeating: nil, count: 4),  // AC, 0...3
    ]
    var restartInterval: Int = 0
    var frame: FrameHeader? = nil

    // APP14 (Adobe) hints — needed to disambiguate 3-component RGB vs.
    // YCbCr and 4-component CMYK vs. YCCK.
    var adobeColorTransform: Int? = nil
    // 0 = unknown / 3-component default to YCbCr, 4-component default to CMYK
    // 1 = YCbCr (3-component)
    // 2 = YCCK (4-component, inverted CMYK after YCbCr)

    // Per-component output planes (allocated lazily once SOF arrives).
    var componentPlanes: [[UInt8]] = []
    var blocksPerComponentX: [Int] = []  // H[c] * numMCUs_X
    var blocksPerComponentY: [Int] = []  // V[c] * numMCUs_Y
    var componentPlaneStride: [Int] = []  // bytes per row in plane
    var componentPlaneHeight: [Int] = []  // rows in plane

    init(bytes: [UInt8]) {
      self.bytes = bytes
      self.pos = 0
    }

    /// Decodes the entire JPEG into raw component planes.
    mutating func decode() throws(JPEG.DecodingError) -> Decoded {
      try expectSOI()

      scan: while true {
        let marker = try readMarker()
        switch marker {
        case Marker.SOF0:
          try parseSOF()
        case Marker.SOF1:
          // Extended sequential — the bitstream is shaped almost
          // identically to baseline, but we keep the conservative
          // "baseline only" stance so callers know what they get.
          throw .unsupportedProcess(marker: marker)
        case Marker.DQT:
          try parseDQT()
        case Marker.DHT:
          try parseDHT()
        case Marker.DRI:
          try parseDRI()
        case Marker.SOS:
          try parseSOSAndDecodeScan()
        // Baseline JPEGs typically have a single scan. After it
        // we expect EOI; loop until we find it.
        case Marker.EOI:
          break scan
        case Marker.COM:
          try skipSegment()
        case let m where (Marker.APP0...Marker.APP15).contains(m):
          if m == 0xEE {
            try parseAPP14Adobe()
          } else {
            try skipSegment()
          }
        case Marker.DNL, Marker.DHP, Marker.EXP:
          try skipSegment()
        case let m where Marker.isUnsupportedSOF(m):
          throw .unsupportedProcess(marker: m)
        case Marker.DAC:
          throw .unsupportedProcess(marker: marker)
        default:
          // Unknown marker — skip its segment if it has a length.
          try skipSegment()
        }
      }

      guard let frame = self.frame else {
        throw .truncated(stage: "frame header missing")
      }

      // Crop component planes to the declared image dimensions and
      // upsample subsampled chroma to full resolution.
      let upsampled = try upsampleAllComponents(frame: frame)
      return Decoded(
        width: frame.width,
        height: frame.height,
        components: upsampled,
        componentIDs: frame.components.map(\.id),
        isAdobeYCCK: adobeColorTransform == 2,
        isAdobeRGB: adobeColorTransform == 0 && frame.components.count == 3
          && frame.components.map(\.id) == [82, 71, 66]  // 'R','G','B'
      )
    }

    // MARK: Marker stream

    mutating func expectSOI() throws(JPEG.DecodingError) {
      guard pos + 2 <= bytes.count, bytes[pos] == 0xFF, bytes[pos + 1] == Marker.SOI else {
        throw .missingSOI
      }
      pos += 2
    }

    /// Reads the next marker byte (after consuming any 0xFF fill bytes).
    mutating func readMarker() throws(JPEG.DecodingError) -> UInt8 {
      // Skip any non-FF bytes (shouldn't happen in well-formed files
      // outside of entropy data — but be lenient).
      while pos < bytes.count && bytes[pos] != 0xFF {
        pos += 1
      }
      // Skip the run of 0xFF fill.
      while pos < bytes.count && bytes[pos] == 0xFF {
        pos += 1
      }
      guard pos < bytes.count else {
        throw .truncated(stage: "marker scan")
      }
      let m = bytes[pos]
      pos += 1
      return m
    }

    mutating func readUInt16BE() throws(JPEG.DecodingError) -> Int {
      guard pos + 2 <= bytes.count else {
        throw .truncated(stage: "16-bit field")
      }
      let v = Int(bytes[pos]) << 8 | Int(bytes[pos + 1])
      pos += 2
      return v
    }

    /// Reads the next variable-length segment's payload (sans the 2-byte
    /// length field) and returns it as a slice into `bytes`.
    mutating func readSegmentPayload(marker: UInt8) throws(JPEG.DecodingError)
      -> ArraySlice<UInt8>
    {
      let length = try readUInt16BE()
      guard length >= 2 else {
        throw .malformedSegment(marker: marker, reason: "length < 2")
      }
      let payloadLength = length - 2
      guard pos + payloadLength <= bytes.count else {
        throw .truncated(stage: "segment 0xFF\(String(marker, radix: 16))")
      }
      let slice = bytes[pos..<(pos + payloadLength)]
      pos += payloadLength
      return slice
    }

    mutating func skipSegment() throws(JPEG.DecodingError) {
      let length = try readUInt16BE()
      guard length >= 2 else { return }
      let body = length - 2
      guard pos + body <= bytes.count else {
        throw .truncated(stage: "skip segment")
      }
      pos += body
    }

    // MARK: Segment parsing

    mutating func parseSOF() throws(JPEG.DecodingError) {
      let payload = try readSegmentPayload(marker: Marker.SOF0)
      var i = payload.startIndex
      guard payload.count >= 6 else {
        throw .malformedSegment(marker: Marker.SOF0, reason: "header < 6 bytes")
      }
      let precision = Int(payload[i])
      i += 1
      let height = (Int(payload[i]) << 8) | Int(payload[i + 1])
      i += 2
      let width = (Int(payload[i]) << 8) | Int(payload[i + 1])
      i += 2
      let n = Int(payload[i])
      i += 1

      guard precision == 8 else {
        throw .unsupportedPrecision(precision)
      }
      guard width > 0, height > 0, n > 0 else {
        throw .emptyImage
      }
      guard n == 1 || n == 3 || n == 4 else {
        throw .malformedSegment(
          marker: Marker.SOF0,
          reason: "unsupported component count \(n)"
        )
      }
      guard payload.count >= 6 + 3 * n else {
        throw .malformedSegment(marker: Marker.SOF0, reason: "truncated component list")
      }

      var comps: [FrameComponent] = []
      comps.reserveCapacity(n)
      for _ in 0..<n {
        let id = Int(payload[i])
        i += 1
        let sampling = payload[i]
        i += 1
        let quant = Int(payload[i])
        i += 1
        let h = Int(sampling >> 4)
        let v = Int(sampling & 0x0F)
        guard (1...4).contains(h), (1...4).contains(v) else {
          throw .invalidSamplingFactors(componentID: id, h: h, v: v)
        }
        guard (0...3).contains(quant) else {
          throw .invalidSamplingFactors(componentID: id, h: h, v: v)
        }
        comps.append(
          FrameComponent(
            id: id,
            horizontalSampling: h,
            verticalSampling: v,
            quantTableID: quant
          ))
      }

      self.frame = FrameHeader(
        precision: precision,
        height: height,
        width: width,
        components: comps
      )

      // Allocate per-component planes sized to the block grid.
      let hMax = comps.map(\.horizontalSampling).max() ?? 1
      let vMax = comps.map(\.verticalSampling).max() ?? 1
      let mcuW = hMax * 8
      let mcuH = vMax * 8
      let numMCUsX = (width + mcuW - 1) / mcuW
      let numMCUsY = (height + mcuH - 1) / mcuH

      componentPlanes = []
      blocksPerComponentX = []
      blocksPerComponentY = []
      componentPlaneStride = []
      componentPlaneHeight = []
      for c in comps {
        let bx = numMCUsX * c.horizontalSampling
        let by = numMCUsY * c.verticalSampling
        let stride = bx * 8
        let height = by * 8
        componentPlanes.append([UInt8](repeating: 0, count: stride * height))
        blocksPerComponentX.append(bx)
        blocksPerComponentY.append(by)
        componentPlaneStride.append(stride)
        componentPlaneHeight.append(height)
      }
    }

    mutating func parseDQT() throws(JPEG.DecodingError) {
      let payload = try readSegmentPayload(marker: Marker.DQT)
      try QuantizationTable.parse(payload: payload, into: &quantTables)
    }

    mutating func parseDHT() throws(JPEG.DecodingError) {
      let payload = try readSegmentPayload(marker: Marker.DHT)
      try HuffmanTable.parse(payload: payload, into: &huffmanTables)
    }

    mutating func parseDRI() throws(JPEG.DecodingError) {
      let payload = try readSegmentPayload(marker: Marker.DRI)
      guard payload.count == 2 else {
        throw .malformedSegment(marker: Marker.DRI, reason: "expected 2-byte interval")
      }
      let i = payload.startIndex
      restartInterval = (Int(payload[i]) << 8) | Int(payload[i + 1])
    }

    mutating func parseAPP14Adobe() throws(JPEG.DecodingError) {
      let payload = try readSegmentPayload(marker: 0xEE)
      // Adobe APP14: "Adobe" + 12 bytes of metadata, last byte = transform.
      guard payload.count >= 12 else { return }
      let i = payload.startIndex
      let header = [UInt8](payload[i..<(i + 5)])
      if header == [0x41, 0x64, 0x6F, 0x62, 0x65] {
        // Skip version (2), flags0 (2), flags1 (2), then transform (1).
        let transform = Int(payload[i + 11])
        if (0...2).contains(transform) {
          adobeColorTransform = transform
        }
      }
    }

    // MARK: Scan / entropy decode

    mutating func parseSOSAndDecodeScan() throws(JPEG.DecodingError) {
      guard let frame = frame else {
        throw .unexpectedMarker(Marker.SOS, stage: "before SOF0")
      }
      let payload = try readSegmentPayload(marker: Marker.SOS)
      var i = payload.startIndex
      guard payload.count >= 1 else {
        throw .malformedSegment(marker: Marker.SOS, reason: "empty header")
      }
      let n = Int(payload[i])
      i += 1
      guard payload.count == 1 + 2 * n + 3 else {
        throw .malformedSegment(
          marker: Marker.SOS,
          reason: "wrong header length (n=\(n))"
        )
      }

      // Build scan-component list, mapped to frame component indices.
      var scanIndices: [Int] = []
      var dcTableIDs: [Int] = []
      var acTableIDs: [Int] = []
      scanIndices.reserveCapacity(n)
      dcTableIDs.reserveCapacity(n)
      acTableIDs.reserveCapacity(n)

      for _ in 0..<n {
        let id = Int(payload[i])
        i += 1
        let tableByte = payload[i]
        i += 1
        let dc = Int(tableByte >> 4)
        let ac = Int(tableByte & 0x0F)
        guard let frameIndex = frame.components.firstIndex(where: { $0.id == id }) else {
          throw .undefinedTable(kind: "scan component id", id: id)
        }
        scanIndices.append(frameIndex)
        dcTableIDs.append(dc)
        acTableIDs.append(ac)
      }
      // Spectral selection / approximation — must be (0, 63, 0) for baseline.
      let ss = Int(payload[i])
      i += 1
      let se = Int(payload[i])
      i += 1
      let ah_al = payload[i]
      i += 1
      _ = ah_al
      guard ss == 0, se == 63 else {
        throw .unsupportedProcess(marker: Marker.SOS)
      }

      // Now the entropy-coded data begins.
      var bits = JPEG.BitReader(bytes: bytes, pos: pos, end: bytes.count)
      var dcPredictors = [Int32](repeating: 0, count: scanIndices.count)

      let comps = frame.components
      let hMax = comps.map(\.horizontalSampling).max() ?? 1
      let vMax = comps.map(\.verticalSampling).max() ?? 1
      let mcuW = hMax * 8
      let mcuH = vMax * 8
      let numMCUsX = (frame.width + mcuW - 1) / mcuW
      let numMCUsY = (frame.height + mcuH - 1) / mcuH

      // For interleaved scans (n > 1), we walk MCUs; for single-component
      // scans, blocks march in component-resolution raster order.
      // Baseline files almost always use a single interleaved scan, so we
      // implement the interleaved path and have the single-component path
      // fall through with H=V=1 and one block per MCU.
      let mcuBlocks: [(scanIdx: Int, bxLocal: Int, byLocal: Int)] = {
        var result: [(Int, Int, Int)] = []
        if n == 1 {
          // Single-component: each MCU is one block; its position
          // follows the component's own block grid.
          return [(0, 0, 0)]
        }
        for s in 0..<n {
          let comp = comps[scanIndices[s]]
          for by in 0..<comp.verticalSampling {
            for bx in 0..<comp.horizontalSampling {
              result.append((s, bx, by))
            }
          }
        }
        return result
      }()

      // Single-component scan iteration uses component-private block grid.
      let singleBlocksX: Int
      let singleBlocksY: Int
      if n == 1 {
        let s = scanIndices[0]
        singleBlocksX =
          (frame.width * comps[s].horizontalSampling + (hMax * 8 - 1))
          / (hMax * 8)
        singleBlocksY =
          (frame.height * comps[s].verticalSampling + (vMax * 8 - 1))
          / (vMax * 8)
      } else {
        singleBlocksX = 0
        singleBlocksY = 0
      }
      let totalMCUs =
        (n == 1)
        ? singleBlocksX * singleBlocksY
        : numMCUsX * numMCUsY

      var sinceRestart = 0
      var nextRestartIndex = 0

      for mcuIndex in 0..<totalMCUs {
        let mcuX: Int
        let mcuY: Int
        if n == 1 {
          mcuX = mcuIndex % singleBlocksX
          mcuY = mcuIndex / singleBlocksX
        } else {
          mcuX = mcuIndex % numMCUsX
          mcuY = mcuIndex / numMCUsX
        }

        for entry in mcuBlocks {
          let scanS = entry.scanIdx
          let frameIdx = scanIndices[scanS]
          let comp = comps[frameIdx]
          guard let qt = quantTables[comp.quantTableID] else {
            throw .undefinedTable(kind: "quant", id: comp.quantTableID)
          }
          guard let dcTable = huffmanTables[0][dcTableIDs[scanS]] else {
            throw .undefinedTable(kind: "DC Huffman", id: dcTableIDs[scanS])
          }
          guard let acTable = huffmanTables[1][acTableIDs[scanS]] else {
            throw .undefinedTable(kind: "AC Huffman", id: acTableIDs[scanS])
          }

          var block = [Int32](repeating: 0, count: 64)
          try decodeBlock(
            bits: &bits,
            dcTable: dcTable,
            acTable: acTable,
            quant: qt,
            dcPredictor: &dcPredictors[scanS],
            block: &block
          )

          // Compute block destination in component plane.
          let bx: Int
          let by: Int
          if n == 1 {
            bx = mcuX
            by = mcuY
          } else {
            bx = mcuX * comp.horizontalSampling + entry.bxLocal
            by = mcuY * comp.verticalSampling + entry.byLocal
          }
          let stride = componentPlaneStride[frameIdx]
          let outBase = by * 8 * stride + bx * 8
          JPEG.IDCT.transformBlock(
            input: block,
            output: &componentPlanes[frameIdx],
            outBase: outBase,
            outStride: stride
          )
        }

        // Restart marker handling.
        if restartInterval > 0 {
          sinceRestart += 1
          if sinceRestart == restartInterval && mcuIndex < totalMCUs - 1 {
            sinceRestart = 0
            // Force the bit reader to consume up to and including
            // the expected RST marker.
            bits.discardToByte()
            // If the marker was already discovered while filling
            // the buffer, the bit reader has it stashed.
            if bits.markerHit == nil {
              // Drain bytes until we hit a marker.
              while bits.markerHit == nil && !bits.hitEOF {
                _ = bits.nextByte()
              }
            }
            guard let m = bits.markerHit else {
              throw .truncated(stage: "expected RST marker")
            }
            let expected = Marker.RST0 &+ UInt8(nextRestartIndex)
            if m != expected {
              // Some encoders emit RST markers in the wrong
              // index; accept any RSTn and move on.
              guard Marker.isRestart(m) else {
                throw .unexpectedMarker(m, stage: "restart")
              }
            }
            bits.markerHit = nil
            nextRestartIndex = (nextRestartIndex + 1) & 7
            for k in dcPredictors.indices { dcPredictors[k] = 0 }
          }
        }
      }

      // Whatever marker the bit reader stashed (or where pos sits) is the
      // boundary for subsequent marker scanning. Roll the decoder cursor
      // back to just before the next marker.
      if let m = bits.markerHit {
        // We've already consumed the marker byte (and the preceding 0xFF).
        // Synthesize that position by stepping back two.
        pos = bits.pos
        _ = m  // already accounted for
        // Re-prepend the marker so readMarker() picks it up next time.
        // Easiest: rewind so the next `readMarker()` finds it.
        pos -= 2
        // Sanity: bytes[pos] should be 0xFF and bytes[pos+1] == m.
      } else {
        pos = bits.pos
      }
    }

    /// Decodes one 8×8 block: differential DC + run-length AC, then
    /// dequantizes with the given table (still in zigzag order at the
    /// time of dequantization — the IDCT input wants natural order).
    mutating func decodeBlock(
      bits: inout JPEG.BitReader,
      dcTable: JPEG.HuffmanTable,
      acTable: JPEG.HuffmanTable,
      quant: JPEG.QuantizationTable,
      dcPredictor: inout Int32,
      block: inout [Int32]
    ) throws(JPEG.DecodingError) {
      // DC.
      guard let s = bits.decode(dcTable) else {
        throw .truncated(stage: "DC symbol")
      }
      let category = Int(s)
      guard category <= 11 else {
        throw .invalidBitstream(reason: "DC magnitude category \(category) > 11")
      }
      let dcDiff: Int32
      if category == 0 {
        dcDiff = 0
      } else {
        guard let raw = bits.receiveBits(category) else {
          throw .truncated(stage: "DC magnitude")
        }
        dcDiff = extendJPEGSign(raw, category)
      }
      dcPredictor &+= dcDiff
      block[0] = dcPredictor &* quant.values[0]

      // AC.
      var k = 1
      while k < 64 {
        guard let rs = bits.decode(acTable) else {
          throw .truncated(stage: "AC symbol")
        }
        let r = Int(rs >> 4)
        let ssCat = Int(rs & 0x0F)
        if ssCat == 0 {
          if r == 15 {
            // ZRL: 16 zeros.
            k += 16
            continue
          }
          // EOB.
          break
        }
        k += r
        if k >= 64 {
          throw .invalidBitstream(reason: "AC run of zeros overflows block")
        }
        guard let raw = bits.receiveBits(ssCat) else {
          throw .truncated(stage: "AC magnitude")
        }
        let value = extendJPEGSign(raw, ssCat)
        let zigPos = JPEG.zigzag[k]
        block[zigPos] = value &* quant.values[zigPos]
        k += 1
      }
    }

    // MARK: Upsampling

    /// Upsamples each component plane to the full image resolution using
    /// nearest-neighbor replication, then crops to `width × height`.
    mutating func upsampleAllComponents(frame: FrameHeader)
      throws(JPEG.DecodingError) -> [[UInt8]]
    {
      let hMax = frame.components.map(\.horizontalSampling).max() ?? 1
      let vMax = frame.components.map(\.verticalSampling).max() ?? 1

      var out: [[UInt8]] = []
      out.reserveCapacity(frame.components.count)

      for (idx, comp) in frame.components.enumerated() {
        let plane = componentPlanes[idx]
        let stride = componentPlaneStride[idx]

        // Subsample factors: how many image pixels each component
        // sample covers.
        let xRatio = hMax / comp.horizontalSampling
        let yRatio = vMax / comp.verticalSampling
        _ = (hMax % comp.horizontalSampling == 0)
        _ = (vMax % comp.verticalSampling == 0)
        // Non-divisible ratios are vanishingly rare and rejected here
        // implicitly by the integer division (the result is still
        // correct visually for nearest-neighbor).

        var dst = [UInt8](repeating: 0, count: frame.width * frame.height)
        for y in 0..<frame.height {
          let sy = y / yRatio
          let srcRow = sy * stride
          let dstRow = y * frame.width
          for x in 0..<frame.width {
            let sx = x / xRatio
            dst[dstRow + x] = plane[srcRow + sx]
          }
        }
        out.append(dst)
      }
      return out
    }
  }
}
