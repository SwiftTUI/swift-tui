import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Campaign two, F2 pass 2 (STUI-1283), setD181–setD190: terminal capability
// detection and emission paired with tables, wide glyphs, delta repaints and
// colour profiles. Brief 09.

@MainActor
private enum SetDTerminal {
  static let destination = "https://example.com/a"

  static func open(_ destination: String) -> String { "\u{1B}]8;;\(destination)\u{1B}\\" }
  static let close = "\u{1B}]8;;\u{1B}\\"

  static func raster<V: View>(_ view: V, _ name: String, width: Int, height: Int) -> RasterSurface {
    DefaultRenderer().render(
      view, context: .init(identity: testIdentity("setD", name)),
      proposal: .init(width: width, height: height)
    ).rasterSurface
  }

  static func bytes(_ surface: RasterSurface, _ profile: TerminalCapabilityProfile = .trueColor)
    -> String
  {
    TerminalSurfaceRenderer(capabilityProfile: profile).render(surface)
  }

  static func occurrences(of needle: String, in haystack: String) -> Int {
    haystack.components(separatedBy: needle).count - 1
  }

  /// The `38;2;R;G;B` components of the first direct-colour foreground SGR.
  static func directForeground(in bytes: String) -> [Int]? {
    guard let range = bytes.range(of: "38;2;") else { return nil }
    let tail = bytes[range.upperBound...]
    let digits = tail.prefix { $0.isNumber || $0 == ";" }
    let parts = digits.split(separator: ";").prefix(3).compactMap { Int($0) }
    return parts.count == 3 ? parts : nil
  }

  /// The `R;G;B` components that follow the first `selector` (`38;2;`,
  /// `48;2;` or `58;2;`).
  static func direct(_ selector: String, in bytes: String) -> [Int]? {
    guard let range = bytes.range(of: selector) else { return nil }
    let digits = bytes[range.upperBound...].prefix { $0.isNumber || $0 == ";" }
    let parts = digits.split(separator: ";").prefix(3).compactMap { Int($0) }
    return parts.count == 3 ? parts : nil
  }

  /// The host wire's sRGB export of `color` as byte components.
  static func exported(_ color: Color) -> [Int] {
    let hex = color.hexString(format: .rrggbb, prefix: false)
    return stride(from: 0, to: 6, by: 2).map { offset -> Int in
      let start = hex.index(hex.startIndex, offsetBy: offset)
      return Int(hex[start..<hex.index(start, offsetBy: 2)], radix: 16) ?? -1
    }
  }

  /// A one-cell surface styled with the given colours.
  static func styled(foreground: Color?, background: Color?, underline: Color?) -> RasterSurface {
    RasterSurface(
      size: .init(width: 1, height: 1),
      cells: [
        [
          RasterCell(
            character: "X",
            style: ResolvedTextStyle(
              foregroundColor: foreground, backgroundColor: background,
              underlineStyle: underline.map { TextLineStyle(color: $0) }))
        ]
      ])
  }

  static func posix(_ environment: [String: String]) -> TerminalCapabilityProfile {
    TerminalCapabilityProfile.detectPOSIXTerminal(environment: environment, isTTY: true)
  }
}

@MainActor
@Suite("Campaign F2 pass 2: terminal capabilities under rendering features", .serialized)
struct AdversarialSetDTerminalCapabilityModeTests {
  @Test("setD181: a link in a data table cell is wrapped in one OSC 8 run")
  func setD181LinkInTableCell() throws {
    let rows = setDRows(3)
    let surface = SetDTerminal.raster(
      Table(rows, columns: [TableColumn("Link")]) { row in
        Link(row.id, destination: LinkDestination(SetDTerminal.destination + row.id))
      }.tableHeaders(.hidden), "181", width: 30, height: 8)
    let bytes = SetDTerminal.bytes(surface)
    let open = SetDTerminal.open(SetDTerminal.destination + "r001")
    let start = try #require(bytes.range(of: open), "\(bytes.debugDescription)")
    let label = try #require(bytes.range(of: "r001", range: start.upperBound..<bytes.endIndex))
    let close = try #require(
      bytes.range(of: SetDTerminal.close, range: label.upperBound..<bytes.endIndex))
    #expect(!bytes[start.upperBound..<close.lowerBound].contains("\u{1B}]8;;h"), "no nested open")
  }

  @Test("setD182: a wide-glyph link label is written once inside one OSC 8 run")
  func setD182WideGlyphLinkRun() throws {
    let surface = SetDTerminal.raster(
      Link("日本", destination: LinkDestination(SetDTerminal.destination)), "182", width: 10,
      height: 1)
    let bytes = SetDTerminal.bytes(surface)
    #expect(
      SetDTerminal.occurrences(of: SetDTerminal.open(SetDTerminal.destination), in: bytes) == 1)
    #expect(SetDTerminal.occurrences(of: "日", in: bytes) == 1)
    #expect(SetDTerminal.occurrences(of: "本", in: bytes) == 1)
    let open = try #require(bytes.range(of: SetDTerminal.open(SetDTerminal.destination)))
    let close = try #require(
      bytes.range(of: SetDTerminal.close, range: open.upperBound..<bytes.endIndex))
    #expect(bytes[open.upperBound..<close.lowerBound].contains("日"))
    #expect(bytes[open.upperBound..<close.lowerBound].contains("本"))
  }

  @Test("setD183: a delta changing a linked wide glyph re-opens the link")
  func setD183DeltaReopensLinkForChangedWideGlyph() throws {
    let previous = SetDTerminal.raster(
      Link("日本", destination: LinkDestination(SetDTerminal.destination)), "183a", width: 10,
      height: 1)
    let current = SetDTerminal.raster(
      Link("月本", destination: LinkDestination(SetDTerminal.destination)), "183b", width: 10,
      height: 1)
    let plan = TerminalPresentationPlanner(capabilityProfile: .trueColor)
      .plan(previousSurface: previous, currentSurface: current)
    let batch = try #require(plan.rowBatches.first, "\(plan)")
    let open = try #require(
      batch.renderedBatch.range(of: SetDTerminal.open(SetDTerminal.destination)))
    let glyph = try #require(batch.renderedBatch.range(of: "月"))
    #expect(open.upperBound <= glyph.lowerBound, "\(batch.renderedBatch.debugDescription)")
  }

  @Test("setD184: a direct TERM under NO_COLOR in VS Code keeps hyperlinks without style")
  func setD184DirectNoColorVSCode() {
    let profile = SetDTerminal.posix([
      "TERM": "xterm-direct", "NO_COLOR": "1", "TERM_PROGRAM": "vscode", "LANG": "en_US.UTF-8",
    ])
    #expect(profile.colorLevel == .none)
    #expect(!profile.emitsStyleEscapeSequences)
    #expect(profile.supportsHyperlinks)
  }

  @Test("setD185: TERM=tmux-direct keeps true colour, hyperlinks and mouse")
  func setD185TmuxDirect() {
    let profile = SetDTerminal.posix(["TERM": "tmux-direct", "LANG": "en_US.UTF-8"])
    #expect(profile.colorLevel == .trueColor)
    #expect(profile.supportsHyperlinks)
    #expect(profile.supportsMouseReporting)
  }

  @Test("setD186: a dotted screen direct entry keeps its own capabilities")
  func setD186DottedScreenDirect() {
    let profile = SetDTerminal.posix([
      "TERM": "screen.xterm-direct", "TERM_PROGRAM": "WezTerm", "LANG": "en_US.UTF-8",
    ])
    #expect(profile.colorLevel == .trueColor)
    #expect(profile.supportsMouseReporting)
    #expect(!profile.supportsHyperlinks)
  }

  @Test("setD187: a Display P3 colour is written as sRGB direct-colour components")
  func setD187DisplayP3AtTrueColour() throws {
    let color = Color(red: 0.8, green: 0.4, blue: 0.2, profile: .displayP3)
    let surface = SetDTerminal.raster(Text("p3").foregroundStyle(color), "187", width: 4, height: 1)
    let components = try #require(
      SetDTerminal.directForeground(in: SetDTerminal.bytes(surface)), "no 38;2 foreground")
    let hex = color.hexString(format: .rrggbb, prefix: false)
    let expected = stride(from: 0, to: 6, by: 2).map { offset -> Int in
      let start = hex.index(hex.startIndex, offsetBy: offset)
      return Int(hex[start..<hex.index(start, offsetBy: 2)], radix: 16) ?? -1
    }
    try #require(expected != [204, 102, 51], "the sRGB export differs from the raw components")
    // STUI-1320: true colour converts to sRGB before writing components.
    #expect(
      zip(components, expected).allSatisfy { abs($0 - $1) <= 1 },
      "terminal \(components) against the host-wire sRGB export \(expected)")
  }

  @Test("setD188: an ASCII locale with kitty degrades a link label but encodes its destination")
  func setD188AsciiKittyLink() throws {
    let profile = SetDTerminal.posix(["TERM": "xterm-kitty", "LANG": "C"])
    try #require(profile.glyphLevel == .ascii && profile.supportsHyperlinks)
    let destination = "https://example.com/日本"
    let surface = SetDTerminal.raster(
      Link("日本", destination: LinkDestination(destination)), "188", width: 10, height: 1)
    let bytes = SetDTerminal.bytes(surface, profile)
    #expect(bytes.contains("????"), "\(bytes.debugDescription)")
    #expect(!bytes.contains("日"))
    #expect(bytes.contains(SetDTerminal.open("https://example.com/%E6%97%A5%E6%9C%AC")))
  }

  @Test("setD189: adjacent links with different destinations close before reopening")
  func setD189AdjacentLinks() throws {
    let surface = SetDTerminal.raster(
      HStack(spacing: 0) {
        Link("a", destination: LinkDestination("https://example.com/1"))
        Link("b", destination: LinkDestination("https://example.com/2"))
      }, "189", width: 10, height: 1)
    let bytes = SetDTerminal.bytes(surface)
    let first = try #require(bytes.range(of: SetDTerminal.open("https://example.com/1")))
    let second = try #require(bytes.range(of: SetDTerminal.open("https://example.com/2")))
    let between = bytes[first.upperBound..<second.lowerBound]
    #expect(between.contains(SetDTerminal.close), "\(bytes.debugDescription)")
  }

  @Test("setD190: an empty TERM_PROGRAM does not outrank a VTE marker")
  func setD190EmptyTermProgramAndVTE() {
    let profile = SetDTerminal.posix([
      "TERM": "xterm-256color", "TERM_PROGRAM": "", "VTE_VERSION": "7600",
      "LANG": "en_US.UTF-8",
    ])
    #expect(profile.supportsHyperlinks)
  }

  // Wave 4 (STUI-1320): true colour converts every colour to sRGB before
  // writing its components.

  @Test("w4fk09: Display P3 background and underline colours are written as sRGB components")
  func w4fk09DisplayP3BackgroundAndUnderline() throws {
    let color = Color(red: 0.8, green: 0.4, blue: 0.2, profile: .displayP3)
    let bytes = SetDTerminal.bytes(
      SetDTerminal.styled(foreground: color, background: color, underline: color))
    let expected = SetDTerminal.exported(color)
    try #require(expected == [219, 94, 31], "the host-wire export \(expected)")
    for selector in ["38;2;", "48;2;", "58;2;"] {
      let components = try #require(
        SetDTerminal.direct(selector, in: bytes), "\(selector) in \(bytes.debugDescription)")
      #expect(components == expected, "\(selector) \(components) against \(expected)")
    }
  }

  @Test("w4fk10: greys stay neutral and whites stay white in every profile")
  func w4fk10GreysAndWhitesAcrossProfiles() throws {
    func foreground(_ color: Color) throws -> [Int] {
      let bytes = SetDTerminal.bytes(
        SetDTerminal.styled(foreground: color, background: nil, underline: nil))
      return try #require(SetDTerminal.direct("38;2;", in: bytes), "\(bytes.debugDescription)")
    }
    let sRGBGrey = try foreground(Color(white: 0.5))
    #expect(sRGBGrey == [127, 127, 127])
    #expect(try foreground(Color(white: 0.5, profile: .displayP3)) == sRGBGrey)
    let linear = Color(white: 0.5, profile: .linearSRGB)
    let linearGrey = try foreground(linear)
    #expect(Set(linearGrey).count == 1, "a linear grey stays neutral: \(linearGrey)")
    #expect(
      zip(linearGrey, SetDTerminal.exported(linear)).allSatisfy { abs($0 - $1) <= 1 },
      "linear grey \(linearGrey) against \(SetDTerminal.exported(linear))")
    for white in [Color(white: 1, profile: .displayP3), Color(white: 1, profile: .linearSRGB)] {
      let components = try foreground(white)
      #expect(components.allSatisfy { $0 >= 254 }, "\(white.profile.name) white: \(components)")
    }
  }

  @Test("w4fk11: sRGB colours keep their bytes and extended components still clamp")
  func w4fk11SRGBBytesUnchanged() {
    let bytes = SetDTerminal.bytes(
      SetDTerminal.styled(
        foreground: Color(red: 1.05, green: 0.5, blue: -0.2),
        background: Color(hexRGB: 0x56B6C2),
        underline: Color(red: 2, green: -1, blue: 0.5)))
    #expect(bytes.contains("38;2;255;127;0"), "\(bytes.debugDescription)")
    #expect(bytes.contains("48;2;86;182;194"), "\(bytes.debugDescription)")
    #expect(bytes.contains("58;2;255;0;127"), "\(bytes.debugDescription)")
  }
}
