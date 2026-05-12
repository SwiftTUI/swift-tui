import Foundation
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

@Suite
struct TerminalRenderStyleCodecTests {
  @Test("codec decodes the shared WebHost default fixture")
  func decodesSharedDefaultFixture() throws {
    let fixture = try transportFixture(named: "terminal-render-style-default")
    let decoded = try #require(TerminalRenderStyleCodec.decodeBase64(fixture.base64))

    #expect(decoded == webTUIDefaultRenderStyle())
    #expect(decodedJSONString(fromBase64: fixture.base64) == fixture.json)
  }

  @Test("codec encodes the shared WebHost default fixture byte-for-byte")
  func encodesSharedFixtureByteForByte() throws {
    let fixture = try transportFixture(named: "terminal-render-style-default")
    let encoded = try #require(
      TerminalRenderStyleCodec.encodeBase64(webTUIDefaultRenderStyle())
    )

    #expect(encoded == fixture.base64)
  }

  @Test("codec encodes canonical JSON with theme fields in stable order")
  func encodesCanonicalJSONWithTheme() throws {
    let style = TerminalRenderStyle(
      appearance: .init(
        foregroundColor: .hex("#102030"),
        backgroundColor: .hex("#405060"),
        tintColor: .hex("#708090"),
        palette: [
          7: .hex("#777777"),
          0: .hex("#000000"),
          15: .hex("#FFFFFF"),
        ],
        colorSchemeContrast: .increased,
        source: .override
      ),
      theme: .init(
        foreground: .hex("#ABCDEF"),
        background: .hex("#012345"),
        tint: .hex("#456789"),
        separator: .hex("#111111"),
        selection: .hex("#222222"),
        placeholder: .hex("#333333"),
        link: .hex("#444444"),
        fill: .hex("#555555"),
        windowBackground: .hex("#666666"),
        success: .hex("#777777"),
        warning: .hex("#888888"),
        danger: .hex("#999999"),
        info: .hex("#AAAAAA"),
        muted: .hex("#BBBBBB")
      )
    )

    let encoded = try #require(TerminalRenderStyleCodec.encodeBase64(style))
    let json = try #require(decodedJSONString(fromBase64: encoded))

    #expect(
      json
        == ##"{"appearance":{"foregroundColor":"#102030","backgroundColor":"#405060","tintColor":"#708090","palette":{"0":"#000000","1":"#e05757","2":"#61c67b","3":"#ebb33c","4":"#5ba3ff","5":"#b46eff","6":"#56b6c2","7":"#777777","8":"#8c92ac","9":"#ff7b72","10":"#7ee787","11":"#f2cc60","12":"#79c0ff","13":"#d2a8ff","14":"#7de2d1","15":"#ffffff"},"colorSchemeContrast":"increased","source":"override"},"theme":{"foreground":"#abcdef","background":"#012345","tint":"#456789","separator":"#111111","selection":"#222222","placeholder":"#333333","link":"#444444","fill":"#555555","windowBackground":"#666666","success":"#777777","warning":"#888888","danger":"#999999","info":"#aaaaaa","muted":"#bbbbbb"}}"##
    )
  }

  @Test("codec omits theme when nil and sorts palette keys numerically")
  func omitsThemeAndSortsPaletteKeys() throws {
    let style = TerminalRenderStyle(
      appearance: .init(
        foregroundColor: .hex("#112233"),
        backgroundColor: .hex("#445566"),
        tintColor: .hex("#778899"),
        palette: [
          10: .hex("#0A0A0A"),
          2: .hex("#020202"),
          1: .hex("#010101"),
        ],
        colorSchemeContrast: .standard,
        source: .override
      ),
      theme: nil
    )

    let encoded = try #require(TerminalRenderStyleCodec.encodeBase64(style))
    let json = try #require(decodedJSONString(fromBase64: encoded))

    #expect(
      json
        == ##"{"appearance":{"foregroundColor":"#112233","backgroundColor":"#445566","tintColor":"#778899","palette":{"0":"#20242c","1":"#010101","2":"#020202","3":"#ebb33c","4":"#5ba3ff","5":"#b46eff","6":"#56b6c2","7":"#eceff4","8":"#8c92ac","9":"#ff7b72","10":"#0a0a0a","11":"#f2cc60","12":"#79c0ff","13":"#d2a8ff","14":"#7de2d1","15":"#ffffff"},"colorSchemeContrast":"standard","source":"override"}}"##
    )
  }

  @Test(
    "codec rejects invalid base64, malformed JSON, invalid hex, unknown enums, and non-integer palette keys"
  )
  func rejectsInvalidPayloads() throws {
    let baseFixture = try transportFixture(named: "terminal-render-style-default")
    let invalidPayloads = [
      "not base64!",
      base64EncodedJSON(##"{"appearance":{"foregroundColor":"#FFFFFF""##),
      base64EncodedJSON(
        baseFixture.json.replacingOccurrences(of: "#eceff4", with: "not-a-hex")
      ),
      base64EncodedJSON(
        baseFixture.json.replacingOccurrences(of: "\"override\"", with: "\"mystery\"")
      ),
      base64EncodedJSON(
        baseFixture.json.replacingOccurrences(
          of: "\"palette\":{\"0\":\"#20242c\"",
          with: "\"palette\":{\"accent\":\"#20242c\""
        )
      ),
    ]

    for payload in invalidPayloads {
      #expect(TerminalRenderStyleCodec.decodeBase64(payload) == nil)
    }
  }
}

private struct TransportFixture {
  let json: String
  let base64: String
}

private func transportFixture(
  named basename: String
) throws -> TransportFixture {
  let fixturesDirectory = fixtureDirectoryURL()
  let jsonURL = fixturesDirectory.appendingPathComponent("\(basename).json")
  let base64URL = fixturesDirectory.appendingPathComponent("\(basename).base64.txt")

  let json = try String(contentsOf: jsonURL, encoding: .utf8)
    .trimmingCharacters(in: .whitespacesAndNewlines)
  let base64 = try String(contentsOf: base64URL, encoding: .utf8)
    .trimmingCharacters(in: .whitespacesAndNewlines)

  return .init(
    json: json,
    base64: base64
  )
}

private func fixtureDirectoryURL() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures")
    .appendingPathComponent("Transport")
}

private func webTUIDefaultRenderStyle() -> TerminalRenderStyle {
  .init(
    appearance: .init(
      foregroundColor: .hex("#eceff4"),
      backgroundColor: .hex("#1e222a"),
      tintColor: .hex("#56b6c2"),
      palette: [
        0: .hex("#20242c"),
        1: .hex("#e05757"),
        2: .hex("#61c67b"),
        3: .hex("#ebb33c"),
        4: .hex("#5ba3ff"),
        5: .hex("#b46eff"),
        6: .hex("#56b6c2"),
        7: .hex("#eceff4"),
        8: .hex("#8c92ac"),
        9: .hex("#ff7b72"),
        10: .hex("#7ee787"),
        11: .hex("#f2cc60"),
        12: .hex("#79c0ff"),
        13: .hex("#d2a8ff"),
        14: .hex("#7de2d1"),
        15: .hex("#ffffff"),
      ],
      colorSchemeContrast: .increased,
      source: .override
    ),
    theme: .init(
      foreground: .hex("#eceff4"),
      background: .hex("#1e222a"),
      tint: .hex("#56b6c2"),
      separator: .hex("#8c92ac"),
      selection: .hex("#2e3440"),
      placeholder: .hex("#8c92ac"),
      link: .hex("#5ba3ff"),
      fill: .hex("#2b303b"),
      windowBackground: .hex("#1e222a"),
      success: .hex("#61c67b"),
      warning: .hex("#ebb33c"),
      danger: .hex("#e05757"),
      info: .hex("#56b6c2"),
      muted: .hex("#8c92ac")
    )
  )
}

private func decodedJSONString(
  fromBase64 encoded: String
) -> String? {
  guard let data = Data(base64Encoded: encoded) else {
    return nil
  }

  return String(decoding: data, as: UTF8.self)
}

private func base64EncodedJSON(
  _ json: String
) -> String {
  Data(json.utf8).base64EncodedString()
}
