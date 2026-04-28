extension JPEG {

  /// Bit-level reader for entropy-coded segments, with JPEG byte-stuffing
  /// handling.
  ///
  /// JPEG entropy data uses `0xFF 0x00` as an escape for a literal `0xFF`
  /// byte; any other `0xFF xx` sequence is a marker that terminates the
  /// segment. When such a marker is encountered, ``markerHit`` is set and
  /// further reads return EOF.
  struct BitReader {
    let bytes: [UInt8]
    var pos: Int
    let end: Int

    var bitBuffer: UInt64 = 0
    var bitsInBuffer: Int = 0

    var markerHit: UInt8? = nil
    var hitEOF: Bool = false

    init(bytes: [UInt8], pos: Int, end: Int) {
      self.bytes = bytes
      self.pos = pos
      self.end = end
    }

    /// Reads the next compressed-data byte, transparently handling
    /// `FF 00` byte-stuffing and stashing markers into ``markerHit``.
    mutating func nextByte() -> UInt8? {
      if hitEOF || markerHit != nil { return nil }
      guard pos < end else {
        hitEOF = true
        return nil
      }
      let b = bytes[pos]
      pos += 1
      if b != 0xFF {
        return b
      }
      // 0xFF — peek next byte.
      // Per JPEG spec: a string of 0xFF bytes is allowed as fill; the
      // marker is whichever non-FF byte ends the run.
      while pos < end && bytes[pos] == 0xFF {
        pos += 1
      }
      guard pos < end else {
        hitEOF = true
        return nil
      }
      let next = bytes[pos]
      pos += 1
      if next == 0x00 {
        return 0xFF
      }
      // It is a marker. Stash it and signal EOF for the bit stream.
      markerHit = next
      return nil
    }

    /// Refills the bit buffer until at least 25 bits are available
    /// (or EOF / marker is hit).
    @inline(__always)
    mutating func fill() {
      while bitsInBuffer <= 56 {
        guard let b = nextByte() else { return }
        bitBuffer |= UInt64(b) << (56 - bitsInBuffer)
        bitsInBuffer += 8
      }
    }

    /// Returns the next `n` bits MSB-first, or `nil` on EOF.
    @inline(__always)
    mutating func receiveBits(_ n: Int) -> UInt32? {
      if bitsInBuffer < n { fill() }
      guard bitsInBuffer >= n else { return nil }
      let value = UInt32(bitBuffer >> (64 - n))
      bitBuffer <<= n
      bitsInBuffer -= n
      return value
    }

    /// Decodes one Huffman symbol from the table, or returns `nil` on EOF.
    ///
    /// Tries the 9-bit fast lookup first; falls back to the canonical
    /// length-by-length search for codes longer than 9 bits.
    @inline(__always)
    mutating func decode(_ table: JPEG.HuffmanTable) -> UInt8? {
      if bitsInBuffer < 16 { fill() }
      // Fast path: peek 9 bits.
      if bitsInBuffer >= 9 {
        let idx = Int(bitBuffer >> (64 - 9))
        let len = table.fastLength[idx]
        if len <= 9 {
          bitBuffer <<= Int(len)
          bitsInBuffer -= Int(len)
          return table.fastSymbol[idx]
        }
      }
      // Slow path: lengths 10...16. Build code one bit at a time using
      // the maxCode table.
      var code: Int32 = 0
      for L in 0..<16 {
        guard let bit = receiveBits(1) else { return nil }
        code = (code << 1) | Int32(bit)
        if code <= table.maxCode[L] {
          let idx = table.valOffset[L] + Int(code)
          if idx < 0 || idx >= table.huffVal.count {
            // Corrupt bitstream — treat as EOF.
            return nil
          }
          return table.huffVal[idx]
        }
      }
      // 16-bit code didn't match any table entry.
      return nil
    }

    /// Aligns to a byte boundary by discarding 0...7 padding bits.
    /// Used after a restart-marker terminates an entropy segment.
    mutating func discardToByte() {
      let drop = bitsInBuffer % 8
      if drop > 0 {
        bitBuffer <<= drop
        bitsInBuffer -= drop
      }
      // Drop any whole bytes still buffered — restart resets state.
      bitBuffer = 0
      bitsInBuffer = 0
    }
  }
}

/// Sign-extends an `n`-bit magnitude as the JPEG spec describes (Annex F.1.2).
///
/// If the high bit is `1`, the value is positive and equals `bits`; if `0`,
/// it is negative and equals `bits - (2^n - 1)`.
@inlinable
func extendJPEGSign(_ bits: UInt32, _ n: Int) -> Int32 {
  if n == 0 { return 0 }
  let v = Int32(bits)
  let threshold = Int32(1) << (n - 1)
  if v < threshold {
    return v + (Int32(-1) << n) + 1
  }
  return v
}
