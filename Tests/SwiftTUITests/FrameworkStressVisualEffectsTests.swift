import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI visual-effects stress behavior", .serialized)
struct FrameworkStressVisualEffectsTests {}

@MainActor
private func visualEffectsRetainedFrame<Content: View>(
  _ view: Content,
  renderer: DefaultRenderer,
  identity: Identity,
  generation: Int
) -> RenderSnapshot {
  renderer.render(
    view,
    context: .init(
      identity: identity,
      invalidatedIdentities: generation == 0 ? [] : [identity]
    )
  )
}

@MainActor
private func visualEffectsFreshFrame<Content: View>(
  _ view: Content,
  identity: Identity
) -> RenderSnapshot {
  DefaultRenderer(layoutEngine: .init(cache: MeasurementCache())).render(
    view,
    context: .init(identity: identity)
  )
}

private func visualEffectsBrailleDotCount(_ cell: RasterCell) -> Int {
  guard let scalar = cell.character.unicodeScalars.first?.value,
    scalar >= 0x2800,
    scalar <= 0x28FF
  else {
    return 0
  }
  return Int(scalar - 0x2800).nonzeroBitCount
}

// MARK: - Attempt 001: analytic shape-family churn

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 001 analytic shape geometry follows every replacement")
  func visualEffects001AnalyticShapeGeometryFollowsEveryReplacement() {
    // Hypothesis: retained shape extraction can reuse the first analytic geometry when a stable
    // erased slot cycles among geometries whose payloads share the same fill operation and frame.
    struct Root: View {
      let generation: Int

      var body: some View {
        Group {
          switch generation % 5 {
          case 0:
            AnyView(Rectangle().fill(Color.red))
          case 1:
            AnyView(RoundedRectangle(cornerRadius: 3).fill(Color.red))
          case 2:
            AnyView(Circle().fill(Color.red))
          case 3:
            AnyView(Ellipse().fill(Color.red))
          default:
            AnyView(Capsule().fill(Color.red))
          }
        }
        .frame(width: 18, height: 8)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("VisualEffects001")

    for generation in 0..<25 {
      let root = Root(generation: generation)
      let retained = visualEffectsRetainedFrame(
        root,
        renderer: renderer,
        identity: identity,
        generation: generation
      )
      let fresh = visualEffectsFreshFrame(root, identity: identity)

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(
        retained.rasterSurface.cells.joined().contains {
          visualEffectsBrailleDotCount($0) > 0 || $0.style?.backgroundColor != nil
        }
      )
    }
  }
}
