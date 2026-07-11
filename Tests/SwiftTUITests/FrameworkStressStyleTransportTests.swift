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

extension FrameworkStressStyleTransportTests {
  @Test("stress style transport 004 adjacent full chunks do not exchange bits")
  func styleTransport004AdjacentFullChunksDoNotExchangeBits() {
    // Hypothesis: index advancement can leak low bits across three-byte chunk boundaries.
    let bytes: [UInt8] = [0x00, 0x01, 0x02, 0xFD, 0xFE, 0xFF]
    #expect(StyleTransportBase64.decode(StyleTransportBase64.encode(bytes)) == bytes)
  }
}

extension FrameworkStressStyleTransportTests {
  @Test("stress style transport 005 every byte value survives one payload")
  func styleTransport005EveryByteValueSurvivesOnePayload() {
    // Hypothesis: signed or scalar conversion can corrupt bytes above ASCII.
    let bytes = (0...255).map(UInt8.init)
    let encoded = StyleTransportBase64.encode(bytes)
    #expect(StyleTransportBase64.decode(encoded) == bytes)
  }
}

extension FrameworkStressStyleTransportTests {
  @Test("stress style transport 006 malformed lengths are rejected without prefix decode")
  func styleTransport006MalformedLengthsAreRejectedWithoutPrefixDecode() {
    // Hypothesis: a valid prefix can be returned while one to three trailing scalars are ignored.
    for encoded in ["A", "AAA", "AAAAA", "AAAAAAA"] {
      #expect(StyleTransportBase64.decode(encoded) == nil)
    }
  }
}

extension FrameworkStressStyleTransportTests {
  @Test("stress style transport 007 nonalphabet scalars reject the whole payload")
  func styleTransport007NonalphabetScalarsRejectTheWholePayload() {
    // Hypothesis: invalid alphabet entries can decode as zero and yield plausible JSON.
    for encoded in ["AA A", "AA-A", "AA_A", "AA\nA", "AAéA"] {
      #expect(StyleTransportBase64.decode(encoded) == nil)
    }
  }
}

extension FrameworkStressStyleTransportTests {
  @Test("stress style transport 008 leading padding never decodes")
  func styleTransport008LeadingPaddingNeverDecodes() {
    // Hypothesis: padding in the first or second slot can underflow chunk assembly.
    #expect(StyleTransportBase64.decode("=AAA") == nil)
    #expect(StyleTransportBase64.decode("A=AA") == nil)
  }
}

extension FrameworkStressStyleTransportTests {
  @Test("stress style transport 009 third-slot padding requires fourth-slot padding")
  func styleTransport009ThirdSlotPaddingRequiresFourthSlotPadding() {
    // Hypothesis: accepting AA=A can synthesize a byte from a structurally invalid chunk.
    #expect(StyleTransportBase64.decode("AA=A") == nil)
    #expect(StyleTransportBase64.decode("AA==") == [0])
  }
}

extension FrameworkStressStyleTransportTests {
  @Test("stress style transport 010 padding is legal only in the final chunk")
  func styleTransport010PaddingIsLegalOnlyInTheFinalChunk() {
    // Hypothesis: early padding can truncate the payload while trailing chunks are ignored.
    #expect(StyleTransportBase64.decode("AA==AAAA") == nil)
    #expect(StyleTransportBase64.decode("AAA=AAAA") == nil)
  }
}

extension FrameworkStressStyleTransportTests {
  @Test("stress style transport 011 JSON whitespace is accepted at every boundary")
  func styleTransport011JSONWhitespaceIsAcceptedAtEveryBoundary() {
    // Hypothesis: whitespace after a comma or colon can advance the parser twice.
    var parser = StyleTransportJSONParser(" \n { \t \"a\" \r : \n \"b\" \t } \r ")
    let value = parser.parse()
    #expect(value?.objectValue?["a"]?.stringValue == "b")
  }
}

extension FrameworkStressStyleTransportTests {
  @Test("stress style transport 012 nested objects retain siblings around null")
  func styleTransport012NestedObjectsRetainSiblingsAroundNull() {
    // Hypothesis: returning from a nested object can consume its parent's comma.
    var parser = StyleTransportJSONParser(#"{"a":{"x":"1"},"b":null,"c":{"y":"2"}}"#)
    let object = parser.parse()?.objectValue
    #expect(object?["a"]?.objectValue?["x"]?.stringValue == "1")
    if case .null = object?["b"] { } else { Issue.record("expected null sibling") }
    #expect(object?["c"]?.objectValue?["y"]?.stringValue == "2")
  }
}

// NEXT STYLE TRANSPORT STRESS TEST
