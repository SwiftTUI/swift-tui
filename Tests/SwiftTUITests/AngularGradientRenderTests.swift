import SwiftTUIViews
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime

@MainActor
@Suite
struct AngularGradientRenderTests {
  /// Red over the first quarter of the turn, blue over the rest.
  private var quarter: AngularGradient {
    AngularGradient(
      stops: [
        .init(color: Color.red, location: 0),
        .init(color: Color.red, location: 0.25),
        .init(color: Color.blue, location: 0.25),
        .init(color: Color.blue, location: 1),
      ])
  }

  private func cells<V: View>(_ view: V, width: Int, height: Int) -> [[RasterCell]] {
    DefaultRenderer().render(
      view.frame(width: width, height: height, alignment: .topLeading),
      context: .init(identity: testIdentity("AngularGradientRender")),
      proposal: .init(width: width, height: height)
    ).rasterSurface.cells
  }

  private enum Hue: Equatable {
    case red
    case blue
    case other
  }

  /// The renderer maps named colors through the terminal theme, so a painted
  /// cell is compared by hue and not against `Color.red` itself.
  private func hue(_ color: Color?) -> Hue {
    guard let color else {
      return .other
    }
    if color.red > color.blue + 0.2 {
      return .red
    }
    return color.blue > color.red + 0.2 ? .blue : .other
  }

  private func paint(_ cell: RasterCell) -> Hue {
    hue(cell.style?.backgroundColor ?? cell.style?.foregroundColor)
  }

  private func ink(_ cell: RasterCell) -> Hue {
    hue(cell.style?.foregroundColor)
  }

  @Test("the first quarter of a conic fill is the lower trailing quadrant")
  func fillSweepsClockwiseFromThreeOClock() {
    let rows = cells(Rectangle().fill(quarter), width: 20, height: 10)
    #expect(paint(rows[8][17]) == .red)
    #expect(paint(rows[1][17]) == .blue)
    #expect(paint(rows[8][2]) == .blue)
    #expect(paint(rows[1][2]) == .blue)
  }

  @Test("the angle is geometric, not stretched to the shape's cells")
  func angleIsGeometric() {
    // Red over the first eighth of the turn: a 45 degree wedge on screen.
    let eighth = AngularGradient(
      stops: [
        .init(color: Color.red, location: 0),
        .init(color: Color.red, location: 0.125),
        .init(color: Color.blue, location: 0.125),
        .init(color: Color.blue, location: 1),
      ])
    let rows = cells(Rectangle().fill(eighth), width: 40, height: 10)
    // (26, 9) is 6.5 cells right of center and 4.5 down. A cell is twice as tall
    // as it is wide, so that is 54 degrees on screen: outside the wedge. Measured
    // in raw cells it would be 35 degrees and inside it.
    #expect(paint(rows[9][26]) == .blue)
    // (30, 7) is 10.5 right and 2.5 down: 25 degrees on screen, inside.
    #expect(paint(rows[7][30]) == .red)
  }

  @Test("on a border, the first quarter runs from the trailing edge to the bottom edge")
  func borderPaint() {
    // As SwiftUI measured on a stroked rectangle: from the middle of the
    // trailing edge, through the bottom-trailing corner, to the middle of the
    // bottom edge.
    let rows = cells(EmptyView().frame(width: 9, height: 5).border(quarter), width: 9, height: 5)
    #expect(ink(rows[3][8]) == .red)
    #expect(ink(rows[4][6]) == .red)
    #expect(ink(rows[1][8]) == .blue)
    #expect(ink(rows[4][2]) == .blue)
    #expect(ink(rows[0][4]) == .blue)
  }

  @Test("the dot shorthands build the same gradients")
  func shorthands() {
    let colors = [Color.red, Color.blue, Color.red]
    #expect(
      AnyShapeStyle(.conicGradient(colors: colors, angle: .degrees(30)))
        == AnyShapeStyle(AngularGradient(colors: colors, angle: .degrees(30))))
    #expect(
      AnyShapeStyle(
        .angularGradient(colors: colors, startAngle: .degrees(0), endAngle: .degrees(90)))
        == AnyShapeStyle(
          AngularGradient(colors: colors, startAngle: .degrees(0), endAngle: .degrees(90))))
  }

  // MARK: - Animation

  private func interpolatedAngle(_ build: (AngularGradient) -> ResolvedNode) -> (
    start: Double?, pending: Bool
  ) {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(1000))
    controller.register(animation)
    let colors = [Color.red, Color.blue, Color.red]
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(
      build(AngularGradient(colors: colors, angle: .radians(0))),
      transaction: .init(), timestamp: t0)
    var frame = build(AngularGradient(colors: colors, angle: .radians(2)))
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame, transaction: transaction, timestamp: t0)
    let result = controller.applyInterpolations(
      to: &frame, at: t0.advanced(by: .milliseconds(500)))

    var style: AnyShapeStyle?
    if case .border(_, _, let foreground, _, _, _, _) = frame.layoutBehavior {
      style = foreground?.top
    } else if case .shape(let payload) = frame.drawPayload,
      case .stroke(let paint, _, _, _) = payload.operation
    {
      style = paint
    }
    guard case .angularGradient(let gradient)? = style else {
      return (nil, result.hasPendingWork)
    }
    return (gradient.startAngle.radians, result.hasPendingWork)
  }

  @Test("withAnimation interpolates a conic gradient's angle on a border")
  func borderAngleAnimates() throws {
    let identity = Identity(components: [.named("conic-border")])
    let result = interpolatedAngle { gradient in
      ResolvedNode(
        identity: identity,
        kind: .view("Border"),
        layoutBehavior: .border(
          .single, placement: .outset,
          foreground: BorderEdgeStyle(AnyShapeStyle(gradient)),
          background: nil, blend: nil, blendPhase: 0, sides: .all))
    }
    #expect(result.pending)
    let start = try #require(result.start)
    #expect(abs(start - 1) < 0.05, "got \(start)")
  }

  @Test("withAnimation interpolates a conic gradient's angle on a shape stroke")
  func strokeAngleAnimates() throws {
    let identity = Identity(components: [.named("conic-stroke")])
    let result = interpolatedAngle { gradient in
      ResolvedNode(
        identity: identity,
        kind: .view("Shape"),
        drawPayload: .shape(
          ShapePayload(
            geometry: .rectangle,
            operation: .stroke(
              style: AnyShapeStyle(gradient), strokeStyle: .single, strokeBorder: false))))
    }
    #expect(result.pending)
    let start = try #require(result.start)
    #expect(abs(start - 1) < 0.05, "got \(start)")
  }

  @Test("the deprecated blend border still draws, for the deprecation window")
  @available(*, deprecated)
  func deprecatedBlendBorder() {
    let blend = BorderBlend([Color.red, Color.blue, Color.red])
    let rows = cells(
      EmptyView().frame(width: 6, height: 3).border(blend: blend, set: .single),
      width: 6, height: 3)
    #expect(String(rows[0].map(\.character)) == "┌────┐")
    #expect(ink(rows[0][0]) == .red)
  }
}
