extension GIF {

  /// LZW decompressor for GIF image data blocks.
  ///
  /// GIF uses a variable-length-code variant of LZW. Codes start at
  /// `minCodeSize + 1` bits and grow toward 12 bits as the dictionary
  /// fills. The codes `clear = 1 << minCodeSize` and `eoi = clear + 1`
  /// are reserved; clear resets the dictionary and eoi terminates the
  /// stream. The compressed payload is split into "sub-blocks" — each
  /// preceded by a 1-byte length, terminated by a zero-length sub-block.
  enum LZW {

    /// Decompresses a flat byte stream of LZW-coded data into the
    /// indexed-color samples it represents.
    ///
    /// `bytes` is the concatenated payload of all sub-blocks in the
    /// image data (sub-block headers already stripped).
    ///
    /// Returns the decoded sequence of palette indices.
    static func decode(
      bytes: [UInt8],
      minCodeSize: Int,
      expectedCount: Int
    ) throws(GIF.DecodingError) -> [UInt8] {
      guard (2...8).contains(minCodeSize) else {
        throw .invalidMinCodeSize(minCodeSize)
      }

      let clearCode = 1 << minCodeSize
      let eoiCode = clearCode + 1
      let initialDictSize = eoiCode + 1
      let maxDictSize = 1 << 12

      // The dictionary stores entries as (prefixCode, suffixByte). The
      // expansion is reconstructed on demand via a small backing array
      // we walk back through.
      var prefix = [Int32](repeating: -1, count: maxDictSize)
      var suffix = [UInt8](repeating: 0, count: maxDictSize)
      // Singletons for codes 0..<clearCode.
      for i in 0..<clearCode {
        suffix[i] = UInt8(i)
      }

      var dictSize = initialDictSize
      var codeSize = minCodeSize + 1
      var prevCode: Int32 = -1
      var firstByte: UInt8 = 0
      var output = [UInt8]()
      output.reserveCapacity(expectedCount)

      // Bit-stream state. Bits within each byte are read LSB-first
      // (this is the GIF/LZW convention, opposite to JPEG).
      var bitBuffer: UInt32 = 0
      var bitsInBuffer: Int = 0
      var bytePos: Int = 0

      // Scratch buffer for reconstructing dictionary entries (max 4096).
      var stack = [UInt8](repeating: 0, count: maxDictSize)

      while true {
        // Refill the bit buffer until we have enough bits.
        while bitsInBuffer < codeSize {
          guard bytePos < bytes.count else {
            // End of compressed stream without an EOI: tolerate
            // by treating it as EOI (some encoders elide it).
            return output
          }
          bitBuffer |= UInt32(bytes[bytePos]) << bitsInBuffer
          bitsInBuffer += 8
          bytePos += 1
        }

        let mask: UInt32 = (1 << codeSize) - 1
        let code = Int(bitBuffer & mask)
        bitBuffer >>= codeSize
        bitsInBuffer -= codeSize

        if code == eoiCode {
          return output
        }

        if code == clearCode {
          dictSize = initialDictSize
          codeSize = minCodeSize + 1
          prevCode = -1
          continue
        }

        if prevCode == -1 {
          // First non-clear code must be a singleton; output it.
          guard code < clearCode else {
            throw .malformedLZWStream(
              reason: "first code after clear is a non-literal"
            )
          }
          output.append(UInt8(code))
          firstByte = UInt8(code)
          prevCode = Int32(code)
          continue
        }

        // Decode the entry referenced by `code` by walking the chain
        // back to a singleton, pushing suffix bytes onto a stack so
        // we can emit them in the correct (forward) order.
        var top = 0
        var c: Int
        if code < dictSize {
          c = code
        } else if code == dictSize {
          // KwKwK case: the new entry is being referenced before
          // being added. The expansion is `prev + firstByte(prev)`.
          stack[top] = firstByte
          top += 1
          c = Int(prevCode)
        } else {
          throw .invalidLZWCode(code)
        }

        while c >= clearCode {
          if top >= stack.count {
            throw .malformedLZWStream(reason: "dictionary chain too long")
          }
          stack[top] = suffix[c]
          top += 1
          c = Int(prefix[c])
          if c < 0 {
            throw .malformedLZWStream(reason: "broken dictionary chain")
          }
        }
        // c is now a literal.
        stack[top] = UInt8(c)
        top += 1

        // Emit in forward (decoded) order.
        let firstOut = UInt8(c)
        while top > 0 {
          top -= 1
          output.append(stack[top])
        }

        // Add a new dictionary entry (prev + firstOut) — but only if
        // the dictionary still has room.
        if dictSize < maxDictSize {
          prefix[dictSize] = prevCode
          suffix[dictSize] = firstOut
          dictSize += 1
          if dictSize == (1 << codeSize) && codeSize < 12 {
            codeSize += 1
          }
        }

        firstByte = firstOut
        prevCode = Int32(code)
      }
    }
  }
}
