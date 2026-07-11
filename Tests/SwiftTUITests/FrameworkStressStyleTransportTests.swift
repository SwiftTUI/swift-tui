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

extension FrameworkStressStyleTransportTests {
  @Test("stress style transport 013 every simple string escape decodes in order")
  func styleTransport013EverySimpleStringEscapeDecodesInOrder() {
    // Hypothesis: adjacent escape sequences can skip or duplicate one decoded scalar.
    var parser = StyleTransportJSONParser(
      #"{"v":"quote:\" slash:\/ backslash:\\ b:\b f:\f n:\n r:\r t:\t"}"#
    )
    let expected = "quote:\" slash:/ backslash:\\ b:\u{8} f:\u{c} n:\n r:\r t:\t"
    #expect(parser.parse()?.objectValue?["v"]?.stringValue == expected)
  }
}

extension FrameworkStressStyleTransportTests {
  @Test("stress style transport 014 BMP Unicode escapes preserve hex case")
  func styleTransport014BMPUnicodeEscapesPreserveHexCase() {
    // Hypothesis: mixed-case hex digits can decode through different arithmetic paths.
    var parser = StyleTransportJSONParser(#"{"v":"\u00e9-\u03A9-\u4e16"}"#)
    #expect(parser.parse()?.objectValue?["v"]?.stringValue == "é-Ω-世")
  }
}

extension FrameworkStressStyleTransportTests {
  @Test("stress style transport 015 surrogate pairs combine into one scalar")
  func styleTransport015SurrogatePairsCombineIntoOneScalar() {
    // Hypothesis: the low surrogate can remain in the stream after pair combination.
    var parser = StyleTransportJSONParser(#"{"v":"\uD83D\uDE80x"}"#)
    #expect(parser.parse()?.objectValue?["v"]?.stringValue == "🚀x")
  }
}

extension FrameworkStressStyleTransportTests {
  @Test("stress style transport 016 lone high surrogates reject the document")
  func styleTransport016LoneHighSurrogatesRejectTheDocument() {
    // Hypothesis: a high surrogate can be emitted as a replacement scalar.
    for json in [#"{"v":"\uD83D"}"#, #"{"v":"\uD83Dx"}"#, #"{"v":"\uD83D\u0041"}"#] {
      var parser = StyleTransportJSONParser(json)
      #expect(parser.parse() == nil)
    }
  }
}

extension FrameworkStressStyleTransportTests {
  @Test("stress style transport 017 lone low surrogates reject the document")
  func styleTransport017LoneLowSurrogatesRejectTheDocument() {
    // Hypothesis: a low surrogate without a high half can slip through Unicode.Scalar creation.
    var parser = StyleTransportJSONParser(#"{"v":"\uDE80"}"#)
    #expect(parser.parse() == nil)
  }
}

extension FrameworkStressStyleTransportTests {
  @Test("stress style transport 018 unescaped controls reject strings")
  func styleTransport018UnescapedControlsRejectStrings() {
    // Hypothesis: raw terminal control bytes can survive JSON decoding into style fields.
    for control in ["\u{0}", "\u{1b}", "\n", "\t"] {
      var parser = StyleTransportJSONParser("{\"v\":\"before\(control)after\"}")
      #expect(parser.parse() == nil)
    }
  }
}

extension FrameworkStressStyleTransportTests {
  @Test("stress style transport 019 trailing values reject the whole document")
  func styleTransport019TrailingValuesRejectTheWholeDocument() {
    // Hypothesis: parse can return the first valid object and ignore a second payload.
    for json in [#"{}{}"#, #"{}null"#, #"{"a":"b"} garbage"#] {
      var parser = StyleTransportJSONParser(json)
      #expect(parser.parse() == nil)
    }
  }
}

extension FrameworkStressStyleTransportTests {
  @Test("stress style transport 020 duplicate keys deterministically use the last value")
  func styleTransport020DuplicateKeysDeterministicallyUseTheLastValue() {
    // Hypothesis: dictionary growth or nesting can make duplicate-key precedence unstable.
    var parser = StyleTransportJSONParser(#"{"v":"first","x":"middle","v":"last"}"#)
    let object = parser.parse()?.objectValue
    #expect(object?["v"]?.stringValue == "last")
    #expect(object?["x"]?.stringValue == "middle")
  }
}

extension FrameworkStressStyleTransportTests {
  @Test("stress style transport 021 minimal appearance decodes with default palette")
  func styleTransport021MinimalAppearanceDecodesWithDefaultPalette() throws {
    // Hypothesis: omitting both optional transport fields can leave palette storage uninitialized.
    let json =
      ##"{"appearance":{"foregroundColor":"#112233","backgroundColor":"#445566","tintColor":"#778899","colorSchemeContrast":"standard","source":"override"}}"##
    let encoded = StyleTransportBase64.encode(Array(json.utf8))
    let style = try #require(TerminalRenderStyleCodec.decodeBase64(encoded))
    #expect(style.theme == nil)
    #expect(style.appearance.foregroundColor.hexString() == "#112233")
    #expect(style.appearance.palette[0] == TerminalPalette.default[0])
    #expect(style.appearance.palette[15] == TerminalPalette.default[15])
  }
}

// NEXT STYLE TRANSPORT STRESS TEST
