import Foundation

/// LZW compressor for GIF image data.
///
/// GIF's LZW variant starts with a dictionary preloaded with every
/// possible literal byte (`0..<2^minCodeSize`) plus two reserved codes:
/// `clearCode = 1 << minCodeSize` and `eoiCode = clearCode + 1`. Codes
/// are emitted with a variable bit width starting at `minCodeSize + 1`,
/// and grow toward 12 bits as the dictionary fills. When the dictionary
/// reaches its 4096-entry ceiling we emit a clear code and start over.
/// Bits within each output byte are packed LSB-first — the opposite of
/// JPEG's MSB-first packing.
///
/// We use an `OrderedDictionary`-equivalent keyed by `(prefixCode,
/// nextByte)`. For the small alphabets GIFs typically use this is more
/// than fast enough.
package enum LZWEncoder {

  package static func encode(indices: [UInt8], minCodeSize: Int) -> [UInt8] {
    precondition((2...8).contains(minCodeSize), "minCodeSize must be 2...8")

    let clearCode = 1 << minCodeSize
    let eoiCode = clearCode + 1
    let maxDictSize = 1 << 12

    var writer = BitWriter()
    var codeSize = minCodeSize + 1

    // Dictionary: `(prefixCode, suffixByte) -> code`.
    var dictionary: [DictKey: Int] = [:]
    dictionary.reserveCapacity(4096)

    func resetDictionary() {
      dictionary.removeAll(keepingCapacity: true)
      codeSize = minCodeSize + 1
    }

    // Always lead with a clear code.
    writer.writeCode(clearCode, bits: codeSize)
    resetDictionary()

    var nextCode = eoiCode + 1
    var currentCode: Int? = nil  // accumulated longest-match code

    for byte in indices {
      if currentCode == nil {
        currentCode = Int(byte)
        continue
      }
      let key = DictKey(prefix: currentCode!, suffix: byte)
      if let existing = dictionary[key] {
        currentCode = existing
      } else {
        writer.writeCode(currentCode!, bits: codeSize)
        if nextCode < maxDictSize {
          dictionary[key] = nextCode
          nextCode += 1
          // The decoder skips its add on the first non-clear code (it
          // has no `prevCode` yet), so its `dictSize` lags the encoder's
          // `nextCode` by exactly one entry. Bumping `codeSize` when
          // `nextCode == (1 << codeSize)` would therefore put the
          // encoder one emit ahead of the decoder; we delay the bump
          // by one so both sides change width on the same wire byte.
          // (Equivalently: bump after the entry whose code value is
          // `(1 << codeSize)` is *also* on the wire, matching giflib's
          // canonical encoder.)
          if nextCode == (1 << codeSize) + 1 && codeSize < 12 {
            codeSize += 1
          }
        } else {
          // Dictionary is full — flush a clear code and start over.
          writer.writeCode(clearCode, bits: codeSize)
          resetDictionary()
          nextCode = eoiCode + 1
        }
        currentCode = Int(byte)
      }
    }

    if let last = currentCode {
      writer.writeCode(last, bits: codeSize)
    }
    writer.writeCode(eoiCode, bits: codeSize)

    return writer.flushed()
  }

  private struct DictKey: Hashable {
    var prefix: Int
    var suffix: UInt8
  }

  /// Bit accumulator that packs LSB-first into a flat byte buffer, the
  /// way GIF's LZW expects.
  private struct BitWriter {
    var output: [UInt8] = []
    var buffer: UInt32 = 0
    var bitCount: Int = 0

    mutating func writeCode(_ code: Int, bits: Int) {
      buffer |= UInt32(code & ((1 << bits) - 1)) << bitCount
      bitCount += bits
      while bitCount >= 8 {
        output.append(UInt8(buffer & 0xFF))
        buffer >>= 8
        bitCount -= 8
      }
    }

    consuming func flushed() -> [UInt8] {
      if bitCount > 0 {
        output.append(UInt8(buffer & 0xFF))
        buffer = 0
        bitCount = 0
      }
      return output
    }
  }
}
