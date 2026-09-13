import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct PathAnimationIntegrationTests {
  @Test("STUI-355: compatible authored paths render start, midpoint and final animation samples")
  func renderedSamples() throws {
    let from = Path(Rect(origin: .zero, size: .init(width: 0.2, height: 1)))
    let to = Path(Rect(origin: .zero, size: .init(width: 1, height: 1)))
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    _ = controller.register(animation)
    let time = MonotonicInstant.now()
    func node(_ path: Path) -> ResolvedNode {
      ResolvedNode(
        identity: Identity(components: ["morph"]), kind: .view("Path"),
        drawPayload: .shape(
          .init(geometry: .path(BoxedPath(path), .nonZero), operation: .fill(style: .color(.white)))
        ))
    }
    controller.processResolvedTree(node(from), transaction: .init(), timestamp: time)
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(node(to), transaction: transaction, timestamp: time)
    var surfaces: [RasterSurface] = []
    for milliseconds in [0, 100, 200] {
      var sample = node(to)
      _ = controller.applyInterpolations(
        to: &sample, at: time.advanced(by: .milliseconds(milliseconds)))
      guard case .shape(let payload) = sample.drawPayload,
        case .path(let boxed, _) = payload.geometry
      else {
        Issue.record("missing path sample")
        return
      }
      let expected = Path(
        Rect(origin: .zero, size: .init(width: 0.2 + 0.8 * Double(milliseconds) / 200, height: 1)))
      let actualSurface = render(boxed.path)
      #expect(actualSurface == render(expected))
      surfaces.append(actualSurface)
    }
    #expect(surfaces[0] != surfaces[1])
    #expect(surfaces[1] != surfaces[2])
    #expect(from.interpolated(to: to, progress: 0) == from)
    #expect(from.interpolated(to: to, progress: 1) == to)
  }

  @Test("morph topology mismatch snaps, including equal point counts with different element kinds")
  func topologyAndDegenerates() throws {
    let move = Path([.move(to: .zero)])
    let line = Path([.line(to: .init(x: 1, y: 1))])
    #expect(!move.isInterpolable(to: line))
    for progress in [0, 0.5, 1, .nan] {
      #expect(move.interpolated(to: line, progress: progress) == line)
      let sample = try #require(
        AnyAnimatable(move).interpolated(to: AnyAnimatable(line), progress: progress))
      #expect(sample.unwrap(as: Path.self) == line)
    }
    #expect(Path().isInterpolable(to: Path()))
    #expect(Path().interpolated(to: Path(), progress: 0.5) == Path())
    let collapsed = Path([.move(to: .zero), .line(to: .zero), .close])
    #expect(collapsed.isInterpolable(to: collapsed))
    #expect(collapsed.interpolated(to: collapsed, progress: 0.5) == collapsed)
    let curves = Path([
      .move(to: .zero), .quadCurve(to: .init(x: 1, y: 1), control: .init(x: 0, y: 1)),
      .curve(to: .zero, control1: .init(x: 1, y: 0), control2: .init(x: 0, y: 1)), .close,
    ])
    let translated = curves.translatedBy(dx: 2, dy: 4)
    #expect(curves.interpolated(to: translated, progress: 0.5) == curves.translatedBy(dx: 1, dy: 2))
    var copy = curves
    copy.animatableData = .init([])
    #expect(copy == curves)
  }

  private func render(_ path: Path) -> RasterSurface {
    DefaultRenderer().render(AuthoredPath(path: path).fill(Color.white).frame(width: 20, height: 8))
      .rasterSurface
  }
}

private struct AuthoredPath: Shape {
  var path: Path
  func path(in rect: Rect) -> Path {
    path.scaledBy(sx: rect.size.width, sy: rect.size.height).translatedBy(
      dx: rect.origin.x, dy: rect.origin.y)
  }
}
