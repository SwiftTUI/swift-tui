// Compiled out on Windows: the web host is deliberately absent from the
// first Windows release (Stage 5.3 of the Windows plan, option (i)) —
// its socket layer is POSIX-bound and the umbrella's dependency edge is
// platform-conditional.
#if !os(Windows)
  /// Minimal SHA-1 (RFC 3174), present solely to derive the RFC 6455
  /// `Sec-WebSocket-Accept` handshake value.
  ///
  /// SHA-1 is cryptographically broken for collision resistance and must not be
  /// used for anything security-sensitive. The WebSocket opening handshake
  /// requires exactly this digest, and uses it only to prove the server read the
  /// client's nonce — not to protect anything. Do not add other callers.
  enum WebHostSHA1 {
    static func digest(
      _ message: [UInt8]
    ) -> [UInt8] {
      var h0: UInt32 = 0x6745_2301
      var h1: UInt32 = 0xEFCD_AB89
      var h2: UInt32 = 0x98BA_DCFE
      var h3: UInt32 = 0x1032_5476
      var h4: UInt32 = 0xC3D2_E1F0

      var padded = message
      let messageBitCount = UInt64(message.count) &* 8
      padded.append(0x80)
      while padded.count % 64 != 56 {
        padded.append(0)
      }
      for shift in stride(from: 56, through: 0, by: -8) {
        padded.append(UInt8(truncatingIfNeeded: messageBitCount >> UInt64(shift)))
      }

      var schedule = [UInt32](repeating: 0, count: 80)
      for chunkStart in stride(from: 0, to: padded.count, by: 64) {
        for wordIndex in 0..<16 {
          let byteIndex = chunkStart + wordIndex * 4
          schedule[wordIndex] =
            (UInt32(padded[byteIndex]) << 24)
            | (UInt32(padded[byteIndex + 1]) << 16)
            | (UInt32(padded[byteIndex + 2]) << 8)
            | UInt32(padded[byteIndex + 3])
        }
        for wordIndex in 16..<80 {
          let mixed =
            schedule[wordIndex - 3] ^ schedule[wordIndex - 8]
            ^ schedule[wordIndex - 14] ^ schedule[wordIndex - 16]
          schedule[wordIndex] = (mixed << 1) | (mixed >> 31)
        }

        var a = h0
        var b = h1
        var c = h2
        var d = h3
        var e = h4

        for round in 0..<80 {
          let f: UInt32
          let k: UInt32
          switch round {
          case 0..<20:
            f = (b & c) | (~b & d)
            k = 0x5A82_7999
          case 20..<40:
            f = b ^ c ^ d
            k = 0x6ED9_EBA1
          case 40..<60:
            f = (b & c) | (b & d) | (c & d)
            k = 0x8F1B_BCDC
          default:
            f = b ^ c ^ d
            k = 0xCA62_C1D6
          }

          let temp = ((a << 5) | (a >> 27)) &+ f &+ e &+ k &+ schedule[round]
          e = d
          d = c
          c = (b << 30) | (b >> 2)
          b = a
          a = temp
        }

        h0 = h0 &+ a
        h1 = h1 &+ b
        h2 = h2 &+ c
        h3 = h3 &+ d
        h4 = h4 &+ e
      }

      var digest: [UInt8] = []
      digest.reserveCapacity(20)
      for word in [h0, h1, h2, h3, h4] {
        digest.append(UInt8(truncatingIfNeeded: word >> 24))
        digest.append(UInt8(truncatingIfNeeded: word >> 16))
        digest.append(UInt8(truncatingIfNeeded: word >> 8))
        digest.append(UInt8(truncatingIfNeeded: word))
      }
      return digest
    }
  }
#endif
