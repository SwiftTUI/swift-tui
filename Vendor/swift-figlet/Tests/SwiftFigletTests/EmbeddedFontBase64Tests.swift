import Testing

@testable import SwiftTUIVendorFigletEmbeddedFonts

@Suite("EmbeddedFonts base64 decoding")
struct EmbeddedFontBase64Tests {
  @Test("decodes RFC 4648 vectors to bytes")
  func decodesKnownVectors() {
    #expect(EmbeddedFontStorage.base64Decode("") == [])
    #expect(EmbeddedFontStorage.base64Decode("TWFu") == Array("Man".utf8))
    #expect(EmbeddedFontStorage.base64Decode("TWE=") == Array("Ma".utf8))
    #expect(EmbeddedFontStorage.base64Decode("TQ==") == Array("M".utf8))
    #expect(EmbeddedFontStorage.base64Decode("Zm9vYmFy") == Array("foobar".utf8))
  }

  @Test("decodes the full alphabet plus + and /")
  func decodesFullAlphabet() {
    // 0xFB 0xFF 0xBF encodes to "+/+/"-style bytes exercising index 62 and 63.
    #expect(EmbeddedFontStorage.base64Decode("++//") == [0xFB, 0xEF, 0xFF])
  }

  @Test("rejects malformed input")
  func rejectsMalformedInput() {
    #expect(EmbeddedFontStorage.base64Decode("abc") == nil)  // not a multiple of 4
    #expect(EmbeddedFontStorage.base64Decode("ab@d") == nil)  // illegal character
    #expect(EmbeddedFontStorage.base64Decode("=AAA") == nil)  // leading padding
  }
}
