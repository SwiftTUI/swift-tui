import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIPrimitives
@testable import SwiftTUIRuntime

@Suite struct ColorBoundaryContractsTests {
  @Test func exactTerminalPaletteColorsKeepTheirSlotsRegardlessOfAlpha() {
    let renderer = TerminalCellTextRenderer(capabilityProfile: .ansi256)
    let levels = [0, 95, 135, 175, 215, 255]
    for r in 0..<6 {
      for g in 0..<6 {
        for b in 0..<6 {
          let color = Color(
            red: Double(levels[r]) / 255, green: Double(levels[g]) / 255,
            blue: Double(levels[b]) / 255)
          let code = 16 + 36 * r + 6 * g + b
          #expect(renderer.ansi256Code(for: color) == code)
          #expect(renderer.ansi256Code(for: color.opacity(0.3)) == code)
        }
      }
    }
    for index in 0..<24 {
      let level = Double(8 + index * 10) / 255
      #expect(renderer.ansi256Code(for: Color(white: level, alpha: 1)) == 232 + index)
    }
  }

  @Test func decodedReferenceWhiteRejectsEveryInvalidConstructorBoundary() {
    for json in [
      #"{"name":" ","x":0.3,"y":0.3}"#,
      #"{"name":"bad","x":0,"y":0.3}"#,
      #"{"name":"bad","x":0.3,"y":0}"#,
      #"{"name":"bad","x":-0.1,"y":0.3}"#,
      #"{"name":"bad","x":0.8,"y":0.8}"#,
    ] {
      #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(ReferenceWhite.self, from: Data(json.utf8))
      }
    }
  }

  @Test func rawOpacityWrappersComposeWithoutUsingTheAliasBudget() throws {
    var style = AnyShapeStyle.semantic(.tint)
    for _ in 0..<40 { style = .opacity(style, 0.5) }
    var environment = StyleEnvironmentSnapshot()
    environment.tintStyle = .color(.red)
    let bounds = CellRect(origin: .zero, size: .init(width: 1, height: 1))
    let color = try #require(
      Rasterizer().resolveColor(
        from: style, environment: environment,
        bounds: bounds, sampleX: 0, sampleY: 0))
    #expect(color.alpha == 1.0 / 1_099_511_627_776)
    let themed = try #require(resolveStyleColor(style: style, theme: .default))
    #expect(themed.alpha == color.alpha)
  }
}
