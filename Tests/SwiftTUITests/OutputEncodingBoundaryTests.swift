import Foundation
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime

@Suite struct OutputEncodingBoundaryTests {
  @Test func sharedJSONStringEscapingMatchesAdmissionForEveryControlScalar() throws {
    for value: UInt32 in Array(0...0x1F) + Array(0x7F...0x9F) {
      let text = "before" + String(UnicodeScalar(value)!) + "after"
      let encoded = WebSurfaceFrameEncoder.jsonString(text)
      #expect(encoded == styleTransportJSONStringLiteral(text))
      #expect(try HostWireBudget.jsonStringBytes(text) == encoded.utf8.count)
      #expect(try JSONDecoder().decode(String.self, from: Data(encoded.utf8)) == text)
      #expect(!encoded.unicodeScalars.contains { $0.value == value })
    }
  }

  @Test func clippedCellAndHyperlinkHaveTheSameAdmittedSpan() throws {
    let surface = RasterSurface(
      size: .init(width: 1, height: 1),
      cells: [
        [
          .init(character: "漢", spanWidth: 2, hyperlink: "https://example.test")
        ]
      ])
    let encoded = WebSurfaceFrameEncoder.encode(surface)
    #expect(encoded.contains("[0,\"漢\",1,"))
    #expect(encoded.contains("\"links\":[[0,[[0,1,0]]]]"))
    #expect(encoded != HostWireBudget.rejectionRecord)
  }

  @Test func missingDeltaRowExplicitlyClearsThePreviousRow() {
    var state = HostWireCapabilities(acceptsDeltaFrames: true).negotiatedEncodingState(epochID: 1)
    let full = RasterSurface(size: .init(width: 1, height: 2), lines: ["a", "b"])
    _ = WebSurfaceFrameEncoder.encode(full, damage: nil, state: &state)
    let short = RasterSurface(size: full.size, cells: [full.cells[0]])
    let encoded = WebSurfaceFrameEncoder.encode(short, damage: .init(dirtyRows: [1]), state: &state)
    #expect(encoded.contains("\"encoding\":\"delta\""))
    #expect(encoded.contains("[1,[]]"))
  }

  @Test func alphaMetadataPreservesEveryStyleColorCategory() throws {
    var appearance = TerminalAppearance.fallback
    appearance.foregroundColor = Color(hexRGB: 0x123456).withAlpha(0.123456789)
    appearance.backgroundColor = Color(hexRGB: 0x112233).withAlpha(0)
    appearance.tintColor = Color(hexRGB: 0xABCDEF).withAlpha(0.5)
    appearance.palette.red = Color(hexRGB: 0xFF0000).withAlpha(0.75)
    var theme = Theme()
    theme.selection = Color(hexRGB: 0x334455).withAlpha(0.3333333333333)
    theme.link = Color(hexRGB: 0x0000FF).withAlpha(0.23456789)
    let style = TerminalRenderStyle(appearance: appearance, theme: theme)
    let encoded = try #require(TerminalRenderStyleCodec.encodeBase64(style))
    #expect(TerminalRenderStyleCodec.decodeBase64(encoded) == style)
    let json = try #require(String(data: Data(base64Encoded: encoded)!, encoding: .utf8))
    let invalid = json.replacingOccurrences(of: "0.3333333333333", with: "nan")
    #expect(TerminalRenderStyleCodec.decodeBase64(Data(invalid.utf8).base64EncodedString()) == nil)
  }
}
