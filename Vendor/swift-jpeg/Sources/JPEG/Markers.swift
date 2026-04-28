extension JPEG {

  /// JPEG marker bytes (the byte that follows `0xFF`).
  enum Marker {
    // Frame types we accept.
    static let SOF0: UInt8 = 0xC0  // baseline DCT
    // Frame types we explicitly reject (so callers see a clean error
    // rather than a malformed-data crash deep in the decoder).
    static let SOF1: UInt8 = 0xC1  // extended sequential DCT
    static let SOF2: UInt8 = 0xC2  // progressive DCT
    static let SOF3: UInt8 = 0xC3  // lossless
    static let SOF5: UInt8 = 0xC5
    static let SOF6: UInt8 = 0xC6
    static let SOF7: UInt8 = 0xC7
    static let SOF9: UInt8 = 0xC9
    static let SOF10: UInt8 = 0xCA
    static let SOF11: UInt8 = 0xCB
    static let SOF13: UInt8 = 0xCD
    static let SOF14: UInt8 = 0xCE
    static let SOF15: UInt8 = 0xCF

    static let DHT: UInt8 = 0xC4  // Define Huffman Table
    static let DAC: UInt8 = 0xCC  // Define Arithmetic Conditioning (unsupported)

    static let RST0: UInt8 = 0xD0
    static let RST7: UInt8 = 0xD7

    static let SOI: UInt8 = 0xD8  // Start Of Image
    static let EOI: UInt8 = 0xD9  // End Of Image
    static let SOS: UInt8 = 0xDA  // Start Of Scan
    static let DQT: UInt8 = 0xDB  // Define Quantization Table
    static let DNL: UInt8 = 0xDC
    static let DRI: UInt8 = 0xDD  // Define Restart Interval
    static let DHP: UInt8 = 0xDE
    static let EXP: UInt8 = 0xDF

    static let APP0: UInt8 = 0xE0
    static let APP15: UInt8 = 0xEF

    static let JPG0: UInt8 = 0xF0
    static let JPG13: UInt8 = 0xFD

    static let COM: UInt8 = 0xFE  // Comment

    static let TEM: UInt8 = 0x01

    /// `true` if `m` is one of the `RST0..=RST7` restart markers.
    @inlinable
    static func isRestart(_ m: UInt8) -> Bool {
      (RST0...RST7).contains(m)
    }

    /// `true` if `m` is a Start-Of-Frame marker for a process this
    /// decoder cannot handle (anything besides `SOF0`).
    @inlinable
    static func isUnsupportedSOF(_ m: UInt8) -> Bool {
      switch m {
      case SOF1, SOF2, SOF3, SOF5, SOF6, SOF7,
        SOF9, SOF10, SOF11, SOF13, SOF14, SOF15:
        return true
      default:
        return false
      }
    }
  }

  /// One frame component (parsed from the SOF segment).
  struct FrameComponent {
    var id: Int  // component identifier (1=Y, 2=Cb, 3=Cr in JFIF)
    var horizontalSampling: Int  // H_i, 1...4
    var verticalSampling: Int  // V_i, 1...4
    var quantTableID: Int  // 0...3
  }

  /// One scan component (parsed from the SOS segment).
  struct ScanComponent {
    var id: Int  // matching FrameComponent.id
    var dcTableID: Int  // 0...3
    var acTableID: Int  // 0...3
  }

  /// The frame header. `numComponents == 1` is grayscale; `3` is YCbCr (or
  /// rare RGB); `4` is CMYK / YCCK.
  struct FrameHeader {
    var precision: Int
    var height: Int
    var width: Int
    var components: [FrameComponent]
  }
}
