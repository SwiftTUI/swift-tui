import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

@Suite("SwiftTUI style-transport stress behavior", .serialized)
struct FrameworkStressStyleTransportTests {
  @Test("stress style transport 001 empty Base64 round trip stays empty")
  func styleTransport001EmptyBase64RoundTripStaysEmpty() {
    // Hypothesis: the zero-chunk fast path can encode or decode a phantom byte.
    #expect(StyleTransportBase64.encode([]) == "")
    #expect(StyleTransportBase64.decode("") == [])
  }
}

extension FrameworkStressStyleTransportTests {
  @Test("stress style transport 002 one-byte payload preserves double padding")
  func styleTransport002OneBytePayloadPreservesDoublePadding() {
    // Hypothesis: the final one-byte chunk can emit or consume an extra zero.
    let encoded = StyleTransportBase64.encode([0xFF])
    #expect(encoded == "/w==")
    #expect(StyleTransportBase64.decode(encoded) == [0xFF])
  }
}

extension FrameworkStressStyleTransportTests {
  @Test("stress style transport 003 two-byte payload preserves single padding")
  func styleTransport003TwoBytePayloadPreservesSinglePadding() {
    // Hypothesis: the final two-byte chunk can lose its low eight bits.
    let bytes: [UInt8] = [0x12, 0xFE]
    let encoded = StyleTransportBase64.encode(bytes)
    #expect(encoded.hasSuffix("="))
    #expect(!encoded.hasSuffix("=="))
    #expect(StyleTransportBase64.decode(encoded) == bytes)
  }
}

// NEXT STYLE TRANSPORT STRESS TEST
