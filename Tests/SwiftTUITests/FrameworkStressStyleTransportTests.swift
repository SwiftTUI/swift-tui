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

// NEXT STYLE TRANSPORT STRESS TEST
