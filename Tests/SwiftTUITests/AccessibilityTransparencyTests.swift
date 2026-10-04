import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct AccessibilityTransparencyTests {
  private func render<V: View>(_ view: V, reduced: Bool, enabled: Bool = true) -> RasterSurface {
    var environment = EnvironmentValues()
    environment.accessibilityPreferences.reduceTransparency = reduced
    environment.isEnabled = enabled
    return DefaultRenderer().render(
      view, context: .init(identity: testIdentity("Transparency"), environmentValues: environment),
      proposal: .init(width: 12, height: 4)
    ).rasterSurface
  }

  @Test("reduce transparency removes text alpha, decorations and ancestor fades")
  func textPaint() throws {
    let view = VStack {
      Text("X").foregroundStyle(Color.red.opacity(0.3))
        .cellBackground(Color.blue.opacity(0.4))
        .underline(color: Color.green.opacity(0.2)).opacity(0.5)
    }.opacity(0.5)
    let normal = render(view, reduced: false).cells.flatMap { $0 }.first { $0.character == "X" }
    let reduced = render(view, reduced: true).cells.flatMap { $0 }.first { $0.character == "X" }
    let style = try #require(reduced?.style)
    #expect(style.foregroundColor == .red)
    #expect(style.backgroundColor == .blue)
    #expect(style.underlineStyle?.color == .green)
    #expect(style.opacity == 1)
    #expect(normal?.style != style)
  }

  @Test("hidden and disabled paints preserve the authored result")
  func preserveBoundaries() {
    let hidden = Text("X").foregroundStyle(Color.red).opacity(0)
    #expect(render(hidden, reduced: true).cells == render(hidden, reduced: false).cells)
    let disabled = Text("X").foregroundStyle(Color.red.opacity(0.3)).opacity(0.5)
    #expect(
      render(disabled, reduced: true, enabled: false).cells
        == render(disabled, reduced: false, enabled: false).cells)
    let scoped = VStack {
      Text("X").foregroundStyle(Color.red.opacity(0.3))
        .environment(\.accessibilityPreferences, .init(reduceTransparency: false))
    }.opacity(0.4)
    #expect(render(scoped, reduced: true).cells == render(scoped, reduced: false).cells)
  }

  private struct DirectPaint: CanvasDrawing, Equatable {
    func draw(into context: inout CanvasContext) {
      context.setCell(
        at: .zero, character: "X", foreground: .red.opacity(0.3), background: .blue.opacity(0.4))
    }
  }

  @Test("sampled paints, tile patterns and direct Canvas cells become opaque")
  func graphicPaint() throws {
    let gradient = LinearGradient(
      colors: [.red.opacity(0.3), .blue.opacity(0.6)], startPoint: .leading, endPoint: .trailing)
    func verify<V: View>(_ view: V, tile: Bool = false) throws {
      let cells = render(view, reduced: true).cells.flatMap { $0 }
      let colors = cells.flatMap {
        [$0.style?.foregroundColor, $0.style?.backgroundColor].compactMap { $0 }
      }
      #expect(!colors.isEmpty)
      #expect(colors.allSatisfy { $0.alpha == 1 || $0.alpha == 0 })
      if tile { #expect(cells.contains { $0.character == "·" }) }
    }
    try verify(Rectangle().fill(gradient).frame(width: 12, height: 4).opacity(0.5))
    try verify(
      Rectangle().fill(TileStyle(.dots, foreground: gradient, background: Color.green.opacity(0.2)))
        .frame(width: 12, height: 4), tile: true)
    try verify(Canvas(DirectPaint()).frame(width: 1, height: 1))
    let clear = Rectangle().fill(Color.clear).frame(width: 12, height: 4)
    #expect(render(clear, reduced: true).cells == render(clear, reduced: false).cells)
  }
}
