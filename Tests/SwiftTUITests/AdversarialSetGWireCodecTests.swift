import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIPrimitives
@_spi(Runners) @testable import SwiftTUIRuntime

private let setGJSONAlphabet =
  hostileGraphemeAlphabet + [
    "\"", "\\", "/", "\u{1}", "\u{1F}", "\u{7F}", "\u{9F}", "\u{80}", "\u{2028}", "\u{FFFF}",
    "\u{10FFFF}", "😀", "\u{D7FF}", "\u{E000}",
  ]

/// Foundation's reading of a JSON string literal, or nil when it rejects it.
private func setGFoundationString(_ literal: String) -> String? {
  guard
    let value = try? JSONSerialization.jsonObject(
      with: Data(literal.utf8), options: [.fragmentsAllowed])
  else { return nil }
  return value as? String
}

private func setGStyleString(_ literal: String) -> String? {
  var parser = StyleTransportJSONParser(literal)
  guard case .string(let value)? = parser.parse() else { return nil }
  return value
}

private func setGHex(_ value: Int) -> String {
  let digits = String(value & 0xFF_FFFF, radix: 16)
  return "#" + String(repeating: "0", count: 6 - digits.count) + digits
}

private let setGAlphas: [Double] = [1, 1, 1, 0, 0.5, 0.25, 1.0 / 3, 0.123_456_789, 0.999_999]

private func setGColor(_ raw: Int) -> Color {
  // A byte-hex sRGB colour, with an alpha other than 1 now and then.
  let color = try! Color(hex: setGHex(raw))
  let alpha = setGAlphas[(raw >> 24) % setGAlphas.count]
  return alpha == 1 ? color : color.withAlpha(alpha)
}

private let setGBigRecordChunk = String(repeating: "a", count: HostWireBudget.recordBytes + 2)

@MainActor
@Suite("Campaign F5 pass 2 wire codec properties", .serialized)
struct AdversarialSetGWireCodecTests {
  @Test(arguments: Array(143...150))
  func wireCodec(id: Int) {
    switch id {
    case 143: base64RoundTrip(id)
    case 144: base64Rejections(id)
    case 145: jsonLiteralRoundTrip(id)
    case 146: jsonGrammarAgreement(id)
    case 147: styleRoundTrip(id)
    case 148: styleFixedPoint(id)
    case 149: jsonBudgets(id)
    default: recordBudget(id)
    }
  }

  private func base64RoundTrip(_ id: Int) {
    setGProperty(id, Gen<[Int]>.array(of: .int(in: 0...255), count: 0...40)) { values in
      let bytes = values.map { UInt8($0) }
      let encoded = StyleTransportBase64.encode(bytes)
      guard encoded == Data(bytes).base64EncodedString() else {
        return "encoding \(encoded) differs from Foundation \(Data(bytes).base64EncodedString())"
      }
      guard StyleTransportBase64.decode(encoded) == bytes else { return "round trip lost bytes" }
      let vectors = [
        ("", ""), ("f", "Zg=="), ("fo", "Zm8="), ("foo", "Zm9v"), ("foob", "Zm9vYg=="),
        ("fooba", "Zm9vYmE="), ("foobar", "Zm9vYmFy"),
      ]
      for (plain, expected) in vectors
      where StyleTransportBase64.encode(Array(plain.utf8)) != expected
        || StyleTransportBase64.decode(expected) != Array(plain.utf8)
      {
        return "RFC 4648 vector \(plain) failed"
      }
      return nil
    }
  }

  private func base64Rejections(_ id: Int) {
    let generator = Gen<([Int], [Int])>.zip(
      Gen<[Int]>.array(of: .int(in: 0...255), count: 1...24), setGDraws(3))
    setGProperty(id, generator) { draw in
      let (values, n) = draw
      var scalars = Array(StyleTransportBase64.encode(values.map { UInt8($0) }).unicodeScalars)
      let position = n[1] % scalars.count
      switch n[0] % 5 {
      case 0:
        scalars.removeLast()
      case 1:
        guard scalars.count > 4 else { return nil }
        scalars[n[1] % (scalars.count - 4)] = "="
      case 2:
        let foreign: [Unicode.Scalar] = ["-", "_", "é", " ", "*", "\u{0}"]
        scalars[position] = foreign[n[2] % foreign.count]
      case 3:
        scalars[scalars.count - 4 + n[2] % 2] = "="
      default:
        scalars[scalars.count - 2] = "="
        scalars[scalars.count - 1] = "A"
      }
      let text = String(String.UnicodeScalarView(scalars))
      // RFC 4648 fixes the grammar; Foundation's decoder is more lenient than
      // the RFC for interior padding, so it is not an oracle here (correction C2).
      let decoded = StyleTransportBase64.decode(text)
      return decoded == nil ? nil : "accepted malformed \(text) as \(decoded!)"
    }
  }

  private func jsonLiteralRoundTrip(_ id: Int) {
    setGProperty(id, Gen<String>.string(from: setGJSONAlphabet, count: 0...12)) { text in
      guard let parsed = setGStyleString(JSONStringEncoding.quoted(text)) else {
        return "rejected the encoding of \(text.debugDescription)"
      }
      return Array(parsed.unicodeScalars) == Array(text.unicodeScalars)
        ? nil : "parsed \(parsed.debugDescription) from \(text.debugDescription)"
    }
  }

  private func jsonGrammarAgreement(_ id: Int) {
    let pieces: [String] = [
      "a", "Z", "é", "😀", "\u{7F}", "\u{9F}", "\u{2028}", "\u{1}", "\u{1F}", "\t", " ", "\\\"",
      "\\\\", "\\/", "\\b", "\\f", "\\n", "\\r", "\\t", "\\u0041", "\\u00e9", "\\u00E9",
      "\\uD83D\\uDE00", "\\ud83d\\ude00", "\\u2028", "\\u0000", "\\uFFFF", "\\x", "\\U0041",
      "\\u12", "\\uZZZZ",
    ]
    // Every piece is a whole token, so no surrogate escape is ever left
    // unpaired: RFC 8259 §8.2 leaves lone surrogates unspecified.
    let generator = Gen<([String], Int)>.zip(
      Gen<[String]>.array(of: .element(of: pieces), count: 0...6), .int(in: 0...3))
    setGProperty(id, generator) { draw in
      let (body, framing) = draw
      let literal = "\"" + body.joined() + (framing == 0 ? "" : "\"")
      let ours = setGStyleString(literal)
      let theirs = setGFoundationString(literal)
      switch (ours, theirs) {
      case (nil, nil):
        return nil
      case (let ours?, let theirs?):
        return Array(ours.unicodeScalars) == Array(theirs.unicodeScalars)
          ? nil
          : "\(literal.debugDescription): style \(ours.debugDescription), Foundation \(theirs.debugDescription)"
      default:
        return
          "\(literal.debugDescription): style \(String(describing: ours)), Foundation \(String(describing: theirs))"
      }
    }
  }

  private func styleRoundTrip(_ id: Int) {
    setGProperty(id, setGDraws(30, 0...Int(UInt32.max))) { n in
      var palette = TerminalPalette.default
      for index in 0..<(n[0] % 5) { palette[n[1 + index] % 16] = setGColor(n[6 + index]) }
      let appearance = TerminalAppearance(
        foregroundColor: setGColor(n[11]), backgroundColor: setGColor(n[12]),
        tintColor: setGColor(n[13]), palette: palette,
        colorSchemeContrast: n[14] % 2 == 0 ? .standard : .increased,
        source: [.activeQuery, .environmentHeuristics, .fallback, .override][n[14] / 2 % 4])
      let theme: Theme? =
        n[15] % 2 == 0
        ? nil
        : Theme(
          foreground: setGColor(n[16]), background: setGColor(n[17]), tint: setGColor(n[18]),
          separator: setGColor(n[19]), selection: setGColor(n[20]),
          placeholder: setGColor(n[21]), link: setGColor(n[22]), fill: setGColor(n[23]),
          windowBackground: setGColor(n[24]), success: setGColor(n[25]),
          warning: setGColor(n[26]), danger: setGColor(n[27]), info: setGColor(n[28]),
          muted: setGColor(n[29]))
      func flag(_ raw: Int) -> Bool? { [nil, true, false][raw % 3] }
      let profiles = AccessibilityColorProfile.allCases
      let style = TerminalRenderStyle(
        appearance: appearance, theme: theme,
        accessibilityPreferences: AccessibilityPreferences(
          reduceMotion: flag(n[15] / 2),
          contrast: [nil, .standard, .increased][n[15] / 6 % 3],
          differentiateWithoutColor: flag(n[15] / 18),
          reduceTransparency: flag(n[15] / 54),
          colorProfile: n[15] / 162 % 2 == 0 ? nil : profiles[n[15] / 324 % profiles.count]))
      guard let encoded = TerminalRenderStyleCodec.encodeBase64(style) else {
        return "style did not encode"
      }
      guard let decoded = TerminalRenderStyleCodec.decodeBase64(encoded) else {
        return "encoded style did not decode"
      }
      return decoded == style ? nil : "decoded \(decoded) != \(style)"
    }
  }

  private func styleFixedPoint(_ id: Int) {
    setGProperty(id, setGDraws(12, 0...Int(UInt32.max))) { n in
      let colors = [
        "\"#102030\"", "\"#abc\"", "\"#11223344\"", "\"red\"", "1", "null", "\"#GG0000\"",
      ]
      let alphas = ["\"0.5\"", "\"1e-1\"", "\"nan\"", "\"2\"", "\"0x1p-1\"", "5"]
      func color(_ raw: Int) -> String { colors[raw % colors.count] }
      var appearance = [
        "\"foregroundColor\":\(color(n[0]))", "\"backgroundColor\":\(color(n[1]))",
        "\"tintColor\":\(color(n[2]))",
        "\"colorSchemeContrast\":\(["\"standard\"", "\"increased\"", "\"loud\""][n[3] % 3])",
        "\"source\":\(["\"fallback\"", "\"override\"", "\"other\""][n[3] / 3 % 3])",
      ]
      if n[4] % 3 != 0 {
        appearance.append(
          "\"palette\":{\"\(n[4] % 20 - 2)\":\(color(n[5])),\"0\(n[4] % 3)\":\(color(n[6]))}")
      }
      if n[7] % 2 == 0 {
        appearance.append(
          "\"alpha\":{\"foregroundColor\":\(alphas[n[7] / 2 % alphas.count])}")
      }
      if n[8] % 3 == 0 { appearance.remove(at: n[8] / 3 % appearance.count) }
      var fields = ["\"appearance\":{\(appearance.joined(separator: ","))}"]
      if n[9] % 3 == 1 { fields.append("\"theme\":null") }
      if n[9] % 3 == 2 { fields.append("\"theme\":\"none\"") }
      fields.append("\"reduceMotion\":\(["\"true\"", "\"false\"", "\"maybe\"", "null"][n[10] % 4])")
      fields.append("\"colorProfile\":\(["\"monochrome\"", "\"sepia\"", "null"][n[11] % 3])")
      let json = "{\(fields.joined(separator: ","))}"
      let encoded = StyleTransportBase64.encode(Array(json.utf8))
      guard let decoded = TerminalRenderStyleCodec.decodeBase64(encoded) else { return nil }
      guard let again = TerminalRenderStyleCodec.encodeBase64(decoded),
        let redecoded = TerminalRenderStyleCodec.decodeBase64(again)
      else { return "decoded \(json) does not re-encode" }
      return redecoded == decoded ? nil : "\(json) decodes to \(decoded), then \(redecoded)"
    }
  }

  private func jsonBudgets(_ id: Int) {
    setGProperty(id, Gen<String>.string(from: setGJSONAlphabet, count: 0...12)) { text in
      let quoted = JSONStringEncoding.quoted(text)
      let budget = try HostWireBudget.jsonStringBytes(text)
      guard budget == quoted.utf8.count else {
        return "budget \(budget) for \(quoted.utf8.count) encoded bytes"
      }
      guard let decoded = setGFoundationString(quoted) else {
        return "Foundation rejects \(quoted.debugDescription)"
      }
      return Array(decoded.unicodeScalars) == Array(text.unicodeScalars)
        ? nil : "Foundation reads \(decoded.debugDescription) from \(quoted.debugDescription)"
    }
  }

  private func recordBudget(_ id: Int) {
    setGProperty(id, setGDraws(3)) { n in
      let prefix = "\u{1E}surface:"
      let total = HostWireBudget.recordBytes + n[0] % 5 - 2
      let terminated = n[1] % 2 == 0
      let content = total - prefix.utf8.count - (terminated ? 1 : 0)
      let split = n[2] % (content + 1)
      var record = HostWireRecord(prefix)
      record += String(setGBigRecordChunk.prefix(split))
      record += String(setGBigRecordChunk.prefix(content - split))
      if terminated { record += "\n" }
      let admitted = (try? record.finish()) != nil
      let expected = total - (terminated ? 1 : 0) <= HostWireBudget.recordBytes
      return admitted == expected
        ? nil : "\(total)-byte record (LF \(terminated)) admitted \(admitted)"
    }
  }
}
