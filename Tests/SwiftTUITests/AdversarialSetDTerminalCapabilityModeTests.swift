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
    setDKnown(
      "NEW-7: a Display P3 colour is written at true colour as its raw P3 components (204;102;51) instead of the sRGB values the host wire exports (219;94;31); true-colour SGR emission skips the sRGB conversion the 256-colour path applies (TerminalCellTextRenderer.swift:303-308); contract: HostWireStyleTable.swift:76-81, TerminalCellTextRenderer+ColorCodes.swift:96"
    ) {
      #expect(
        zip(components, expected).allSatisfy { abs($0 - $1) <= 1 },
        "terminal \(components) against the host-wire sRGB export \(expected)")
    }
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
}
