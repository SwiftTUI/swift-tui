import Foundation
import Testing

@_spi(Runners) @testable import TerminalUI

@Suite
struct TerminalRenderStyleCodecTests {
  @Test("codec decodes the shared WebTUI default dark fixture")
  func decodesSharedDefaultDarkFixture() throws {
    let fixture = try transportFixture(named: "terminal-render-style-default-dark")
    let decoded = try #require(TerminalRenderStyleCodec.decodeBase64(fixture.base64))

    #expect(decoded == webTUIDefaultDarkRenderStyle())
    #expect(decodedJSONString(fromBase64: fixture.base64) == fixture.json)
  }

  @Test("codec decodes the shared WebTUI default light fixture")
  func decodesSharedDefaultLightFixture() throws {
    let fixture = try transportFixture(named: "terminal-render-style-default-light")
    let decoded = try #require(TerminalRenderStyleCodec.decodeBase64(fixture.base64))

    #expect(decoded == webTUIDefaultLightRenderStyle())
    #expect(decodedJSONString(fromBase64: fixture.base64) == fixture.json)
  }

  @Test("codec encodes the shared WebTUI default fixtures byte-for-byte")
  func encodesSharedFixturesByteForByte() throws {
    let darkFixture = try transportFixture(named: "terminal-render-style-default-dark")
    let lightFixture = try transportFixture(named: "terminal-render-style-default-light")

    let encodedDark = try #require(
      TerminalRenderStyleCodec.encodeBase64(webTUIDefaultDarkRenderStyle())
    )
    let encodedLight = try #require(
      TerminalRenderStyleCodec.encodeBase64(webTUIDefaultLightRenderStyle())
    )

    #expect(encodedDark == darkFixture.base64)
    #expect(encodedLight == lightFixture.base64)
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
        colorScheme: .dark,
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
        == ##"{"appearance":{"foregroundColor":"#102030","backgroundColor":"#405060","tintColor":"#708090","palette":{"0":"#000000","7":"#777777","15":"#ffffff"},"colorScheme":"dark","colorSchemeContrast":"increased","source":"override"},"theme":{"foreground":"#abcdef","background":"#012345","tint":"#456789","separator":"#111111","selection":"#222222","placeholder":"#333333","link":"#444444","fill":"#555555","windowBackground":"#666666","success":"#777777","warning":"#888888","danger":"#999999","info":"#aaaaaa","muted":"#bbbbbb"}}"##
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
        colorScheme: .dark,
        colorSchemeContrast: .standard,
        source: .override
      ),
      theme: nil
    )

    let encoded = try #require(TerminalRenderStyleCodec.encodeBase64(style))
    let json = try #require(decodedJSONString(fromBase64: encoded))

    #expect(
      json
        == ##"{"appearance":{"foregroundColor":"#112233","backgroundColor":"#445566","tintColor":"#778899","palette":{"1":"#010101","2":"#020202","10":"#0a0a0a"},"colorScheme":"dark","colorSchemeContrast":"standard","source":"override"}}"##
    )
  }

  @Test(
    "codec rejects invalid base64, malformed JSON, invalid hex, unknown enums, and non-integer palette keys"
  )
  func rejectsInvalidPayloads() throws {
    let baseFixture = try transportFixture(named: "terminal-render-style-default-dark")
    let invalidPayloads = [
      "not base64!",
      base64EncodedJSON(##"{"appearance":{"foregroundColor":"#FFFFFF""##),
      base64EncodedJSON(
        baseFixture.json.replacingOccurrences(of: "#d4d4d4", with: "not-a-hex")
      ),
      base64EncodedJSON(
        baseFixture.json.replacingOccurrences(of: "\"dark\"", with: "\"night\"")
      ),
      base64EncodedJSON(
        baseFixture.json.replacingOccurrences(
          of: "\"palette\":{\"0\":\"#000000\"",
          with: "\"palette\":{\"accent\":\"#000000\""
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

private func webTUIDefaultDarkRenderStyle() -> TerminalRenderStyle {
  .init(
    appearance: .init(
      foregroundColor: .hex("#d4d4d4"),
      backgroundColor: .hex("#1e1e1e"),
      tintColor: .hex("#11a8cd"),
      palette: [
        0: .hex("#000000"),
        1: .hex("#cd3131"),
        2: .hex("#0dbc79"),
        3: .hex("#e5e510"),
        4: .hex("#2472c8"),
        5: .hex("#bc3fbc"),
        6: .hex("#11a8cd"),
        7: .hex("#e5e5e5"),
        8: .hex("#666666"),
        9: .hex("#f14c4c"),
        10: .hex("#23d18b"),
        11: .hex("#f5f543"),
        12: .hex("#3b8eea"),
        13: .hex("#d670d6"),
        14: .hex("#29b8db"),
        15: .hex("#e5e5e5"),
      ],
      colorScheme: .dark,
      colorSchemeContrast: .increased,
      source: .override
    ),
    theme: .init(
      foreground: .hex("#d4d4d4"),
      background: .hex("#1e1e1e"),
      tint: .hex("#11a8cd"),
      separator: .hex("#666666"),
      selection: .hex("#264f78"),
      placeholder: .hex("#666666"),
      link: .hex("#2472c8"),
      fill: .hex("#2b303b"),
      windowBackground: .hex("#1e1e1e"),
      success: .hex("#0dbc79"),
      warning: .hex("#e5e510"),
      danger: .hex("#cd3131"),
      info: .hex("#11a8cd"),
      muted: .hex("#666666")
    )
  )
}

private func webTUIDefaultLightRenderStyle() -> TerminalRenderStyle {
  .init(
    appearance: .init(
      foregroundColor: .hex("#1f2328"),
      backgroundColor: .hex("#ffffff"),
      tintColor: .hex("#1b7c83"),
      palette: [
        0: .hex("#1f2328"),
        1: .hex("#cf222e"),
        2: .hex("#1a7f37"),
        3: .hex("#9a6700"),
        4: .hex("#0969da"),
        5: .hex("#8250df"),
        6: .hex("#1b7c83"),
        7: .hex("#6e7781"),
        8: .hex("#57606a"),
        9: .hex("#a40e26"),
        10: .hex("#116329"),
        11: .hex("#633c01"),
        12: .hex("#0550ae"),
        13: .hex("#8250df"),
        14: .hex("#116b74"),
        15: .hex("#24292f"),
      ],
      colorScheme: .light,
      colorSchemeContrast: .increased,
      source: .override
    ),
    theme: .init(
      foreground: .hex("#1f2328"),
      background: .hex("#ffffff"),
      tint: .hex("#1b7c83"),
      separator: .hex("#57606a"),
      selection: .hex("#c8ddff"),
      placeholder: .hex("#57606a"),
      link: .hex("#0969da"),
      fill: .hex("#f6f8fa"),
      windowBackground: .hex("#ffffff"),
      success: .hex("#1a7f37"),
      warning: .hex("#9a6700"),
      danger: .hex("#cf222e"),
      info: .hex("#1b7c83"),
      muted: .hex("#57606a")
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
