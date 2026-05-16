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
        foregroundColor: try! .hex("#102030"),
        backgroundColor: try! .hex("#405060"),
        tintColor: try! .hex("#708090"),
        palette: [
          7: try! .hex("#777777"),
          0: try! .hex("#000000"),
          15: try! .hex("#FFFFFF"),
        ],
        colorSchemeContrast: .increased,
        source: .override
      ),
      theme: .init(
        foreground: try! .hex("#ABCDEF"),
        background: try! .hex("#012345"),
        tint: try! .hex("#456789"),
        separator: try! .hex("#111111"),
        selection: try! .hex("#222222"),
        placeholder: try! .hex("#333333"),
        link: try! .hex("#444444"),
        fill: try! .hex("#555555"),
        windowBackground: try! .hex("#666666"),
        success: try! .hex("#777777"),
        warning: try! .hex("#888888"),
        danger: try! .hex("#999999"),
        info: try! .hex("#AAAAAA"),
        muted: try! .hex("#BBBBBB")
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
        foregroundColor: try! .hex("#112233"),
        backgroundColor: try! .hex("#445566"),
        tintColor: try! .hex("#778899"),
        palette: [
          10: try! .hex("#0A0A0A"),
          2: try! .hex("#020202"),
          1: try! .hex("#010101"),
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
      foregroundColor: try! .hex("#eceff4"),
      backgroundColor: try! .hex("#1e222a"),
      tintColor: try! .hex("#56b6c2"),
      palette: [
        0: try! .hex("#20242c"),
        1: try! .hex("#e05757"),
        2: try! .hex("#61c67b"),
        3: try! .hex("#ebb33c"),
        4: try! .hex("#5ba3ff"),
        5: try! .hex("#b46eff"),
        6: try! .hex("#56b6c2"),
        7: try! .hex("#eceff4"),
        8: try! .hex("#8c92ac"),
        9: try! .hex("#ff7b72"),
        10: try! .hex("#7ee787"),
        11: try! .hex("#f2cc60"),
        12: try! .hex("#79c0ff"),
        13: try! .hex("#d2a8ff"),
        14: try! .hex("#7de2d1"),
        15: try! .hex("#ffffff"),
      ],
      colorSchemeContrast: .increased,
      source: .override
    ),
    theme: .init(
      foreground: try! .hex("#eceff4"),
      background: try! .hex("#1e222a"),
      tint: try! .hex("#56b6c2"),
      separator: try! .hex("#8c92ac"),
      selection: try! .hex("#2e3440"),
      placeholder: try! .hex("#8c92ac"),
      link: try! .hex("#5ba3ff"),
      fill: try! .hex("#2b303b"),
      windowBackground: try! .hex("#1e222a"),
      success: try! .hex("#61c67b"),
      warning: try! .hex("#ebb33c"),
      danger: try! .hex("#e05757"),
      info: try! .hex("#56b6c2"),
      muted: try! .hex("#8c92ac")
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
