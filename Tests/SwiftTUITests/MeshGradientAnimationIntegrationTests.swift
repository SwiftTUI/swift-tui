import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("MeshGradient animation end-to-end", .serialized)
struct MeshGradientAnimationIntegrationTests {
  @Test("matching mesh topology interpolates and renders the midpoint")
  func matchingTopologyRendersMidpoint() throws {
    let from = animationMesh(
      center: .init(0.5, 0.5),
      centerColor: .red,
      background: .black
    )
    let to = animationMesh(
      center: .init(0.7, 0.3),
      centerColor: .blue,
      background: .white
    )
    let (interpolated, tick) = try interpolate(from: from, to: to)

    #expect(tick.hasPendingWork)
    #expect(abs(interpolated.points[4].x - 0.6) < 0.001)
    #expect(abs(interpolated.points[4].y - 0.4) < 0.001)
    expectColor(
      interpolated.colors[4],
      equals: Color.red.interpolated(to: .blue, progress: 0.5, method: .perceptual),
      tolerance: 0.001
    )
    expectColor(
      interpolated.background,
      equals: Color.black.interpolated(to: .white, progress: 0.5, method: .perceptual),
      tolerance: 0.001
    )

    let midpointSurface = rasterize(interpolated)
    #expect(midpointSurface != rasterize(from))
    #expect(midpointSurface != rasterize(to))
    #expect(
      Set(
        midpointSurface.cells
          .flatMap { $0 }
          .compactMap { $0.style?.backgroundColor }
      ).count > 2
    )
  }

  @Test("mesh structure changes snap to the target")
  func structuralChangesSnapToTarget() throws {
    let from = animationMesh(
      center: .init(0.5, 0.5),
      centerColor: .red,
      background: .black
    )
    let smoothingTarget = MeshGradient(
      width: from.width,
      height: from.height,
      points: from.points,
      colors: from.colors,
      background: from.background,
      smoothsColors: false,
      colorSpace: from.colorSpace
    )
    let colorSpaceTarget = MeshGradient(
      width: from.width,
      height: from.height,
      points: from.points,
      colors: from.colors,
      background: from.background,
      smoothsColors: from.smoothsColors,
      colorSpace: .perceptual
    )
    let topologyTarget = MeshGradient(
      width: 2,
      height: 2,
      points: [.init(0, 0), .init(1, 0), .init(0, 1), .init(1, 1)],
      colors: [.red, .blue, .green, .white]
    )

    for target in [smoothingTarget, colorSpaceTarget, topologyTarget] {
      let (interpolated, _) = try interpolate(from: from, to: target)
      #expect(interpolated == target)
    }
  }

  @Test("full-surface mesh animation damages every row across its width")
  func fullSurfaceAnimationDamage() throws {
    let from = animationMesh(
      center: .init(0.4, 0.6),
      centerColor: .red,
      background: .black
    )
    let to = MeshGradient(
      width: from.width,
      height: from.height,
      points: from.points,
      colors: from.colors.map { color in
        Color(
          red: 1 - color.red,
          green: 1 - color.green,
          blue: 1 - color.blue,
          alpha: color.alpha,
          profile: color.profile
        )
      },
      background: .white,
      smoothsColors: from.smoothsColors,
      colorSpace: from.colorSpace
    )
    let (interpolated, _) = try interpolate(from: from, to: to)
    let previous = rasterize(from)
    let current = rasterize(interpolated)
    let damage = try #require(
      RasterSurfaceDamageDiff.diff(previous: previous, current: current)
    )

    #expect(damage.dirtyRows == Set(0..<current.size.height))
    for row in 0..<current.size.height {
      #expect(damage.columnRanges(for: row) == [0..<current.size.width])
    }
  }

  @Test("unchanged mesh reuses the retained frame without text damage")
  func unchangedMeshRetainsWithoutDamage() {
    let renderer = DefaultRenderer()
    let identity = Identity(components: [.named("retained-mesh")])
    let mesh = animationMesh(
      center: .init(0.5, 0.5),
      centerColor: .red,
      background: .black
    )
    let view = Rectangle()
      .fill(mesh)
      .frame(width: 12, height: 6)

    let first = renderer.render(
      view,
      context: .init(identity: identity),
      proposal: .init(width: 12, height: 6)
    )
    let second = renderer.render(
      view,
      context: .init(identity: identity),
      proposal: .init(width: 12, height: 6)
    )

    #expect(second.rasterSurface == first.rasterSurface)
    #expect(second.presentationDamage?.textRows.isEmpty != false)
  }

  @Test("changed retained mesh matches a fresh raster")
  func changedRetainedMeshMatchesFresh() {
    let retainedRenderer = DefaultRenderer()
    let identity = Identity(components: [.named("changed-retained-mesh")])
    let initial = animationMesh(
      center: .init(0.5, 0.5),
      centerColor: .red,
      background: .black
    )
    let changed = animationMesh(
      center: .init(0.65, 0.35),
      centerColor: .blue,
      background: .white
    )
    let proposal = ProposedSize(width: 12, height: 6)

    _ = retainedRenderer.render(
      Rectangle().fill(initial).frame(width: 12, height: 6),
      context: .init(identity: identity),
      proposal: proposal
    )
    let retained = retainedRenderer.render(
      Rectangle().fill(changed).frame(width: 12, height: 6),
      context: .init(identity: identity, invalidatedIdentities: [identity]),
      proposal: proposal
    )
    let fresh = DefaultRenderer().render(
      Rectangle().fill(changed).frame(width: 12, height: 6),
      context: .init(identity: identity),
      proposal: proposal
    )

    #expect(retained.rasterSurface == fresh.rasterSurface)
    #expect(retained.presentationDamage?.textRows.isEmpty == false)
  }

  private func interpolate(
    from: MeshGradient,
    to: MeshGradient
  ) throws -> (MeshGradient, AnimationTickResult) {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    _ = controller.register(animation)
    let identity = Identity(components: [.named("mesh-gradient-leaf")])
    let t0 = MonotonicInstant.now()
    let seedNode = meshNode(identity: identity, gradient: from)

    controller.processResolvedTree(
      seedNode,
      transaction: .init(),
      timestamp: t0
    )
    var target = meshNode(identity: identity, gradient: to)
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(target, transaction: transaction, timestamp: t0)
    let tick = controller.applyInterpolations(
      to: &target,
      at: t0.advanced(by: .milliseconds(100))
    )

    guard
      case .shape(let payload) = target.drawPayload,
      case .fill(let style?, _) = payload.operation,
      case .meshGradient(let gradient) = style
    else {
      throw MeshGradientAnimationTestError.missingInterpolatedStyle
    }
    return (gradient, tick)
  }

  private func meshNode(identity: Identity, gradient: MeshGradient) -> ResolvedNode {
    ResolvedNode(
      identity: identity,
      kind: .view("MeshGradient"),
      drawPayload: .shape(
        ShapePayload(
          geometry: .rectangle,
          insetAmount: 0,
          operation: .fill(style: .meshGradient(gradient), mode: .full)
        )
      )
    )
  }

  private func rasterize(_ gradient: MeshGradient) -> RasterSurface {
    let bounds = CellRect(origin: .zero, size: .init(width: 12, height: 6))
    return Rasterizer().rasterize(
      DrawNode(
        identity: Identity(components: [.named("mesh-gradient-raster")]),
        bounds: bounds,
        commands: [
          .fill(
            bounds: bounds,
            geometry: .rectangle,
            insetAmount: 0,
            style: .meshGradient(gradient),
            mode: .full
          )
        ]
      )
    )
  }
}

private enum MeshGradientAnimationTestError: Error {
  case missingInterpolatedStyle
}

private func animationMesh(
  center: SIMD2<Float>,
  centerColor: Color,
  background: Color
) -> MeshGradient {
  MeshGradient(
    width: 3,
    height: 3,
    points: [
      .init(0, 0), .init(0.5, 0), .init(1, 0),
      .init(0, 0.5), center, .init(1, 0.5),
      .init(0, 1), .init(0.5, 1), .init(1, 1),
    ],
    colors: [
      .black, .red, .blue,
      .green, centerColor, .yellow,
      .cyan, .magenta, .white,
    ],
    background: background,
    smoothsColors: true,
    colorSpace: .device
  )
}

private func expectColor(
  _ actual: Color,
  equals expected: Color,
  tolerance: Double
) {
  #expect(abs(actual.red - expected.red) < tolerance)
  #expect(abs(actual.green - expected.green) < tolerance)
  #expect(abs(actual.blue - expected.blue) < tolerance)
  #expect(abs(actual.alpha - expected.alpha) < tolerance)
}
