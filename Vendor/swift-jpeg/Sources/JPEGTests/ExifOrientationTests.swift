import Testing

@testable import SwiftTUIVendorJPEG

@Suite struct ExifOrientationTests {
  @Test func everyOrientationMapsRowsAndColumns() {
    let original = JPEG.Decoded(
      width: 2, height: 3,
      components: [[1, 2, 3, 4, 5, 6]], componentIDs: [1],
      isAdobeYCCK: false, isAdobeRGB: false)
    let expected: [[UInt8]] = [
      [1, 2, 3, 4, 5, 6], [2, 1, 4, 3, 6, 5],
      [6, 5, 4, 3, 2, 1], [5, 6, 3, 4, 1, 2],
      [1, 3, 5, 2, 4, 6], [5, 3, 1, 6, 4, 2],
      [6, 4, 2, 5, 3, 1], [2, 4, 6, 1, 3, 5],
    ]
    for orientation in 1...8 {
      let result = original.oriented(orientation)
      #expect(result.width == (orientation >= 5 ? 3 : 2))
      #expect(result.height == (orientation >= 5 ? 2 : 3))
      #expect(result.components == [expected[orientation - 1]])
    }
  }

  @Test func tiffByteOrdersOffsetsAndTruncationsAreBounded() {
    let little: [UInt8] = [
      0x49, 0x49, 42, 0, 8, 0, 0, 0, 1, 0,
      0x12, 1, 3, 0, 1, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0,
    ]
    let big: [UInt8] = [
      0x4D, 0x4D, 0, 42, 0, 0, 0, 8, 0, 1,
      1, 0x12, 0, 3, 0, 0, 0, 1, 0, 6, 0, 0, 0, 0, 0, 0,
    ]
    for tiff in [little, big] {
      #expect(JPEG.exifOrientation(in: tiff) == 6)
      for end in 0..<22 {
        #expect(JPEG.exifOrientation(in: Array(tiff.prefix(end))) == nil)
      }
      for byte in [4, 5, 6, 7] {
        var malformed = tiff
        malformed[byte] = 0xFF
        #expect(JPEG.exifOrientation(in: malformed) == nil)
      }
    }
    for value in [UInt8(0), 9, 255] {
      var malformed = little
      malformed[18] = value
      #expect(JPEG.exifOrientation(in: malformed) == nil)
    }
  }
}
