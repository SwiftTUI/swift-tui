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

private struct VisualEffectsPathShape: InsettableShape {
  let pathValue: Path
  var rule: FillRule = .nonZero

  var geometry: ShapeGeometry {
    .path(BoxedPath(pathValue), rule)
  }
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

// MARK: - Attempt 002: custom-path control-point churn

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 002 custom path uses its current control points")
  func visualEffects002CustomPathUsesCurrentControlPoints() {
    // Hypothesis: BoxedPath's storage-identity equality shortcut can let retained draw extraction
    // pair a newly boxed custom path with an older path after repeated same-shape reconstruction.
    struct Root: View {
      let generation: Int

      var body: some View {
        var path = Path()
        let shoulder = Double((generation % 7) + 1) / 8
        path.move(to: Point(x: 0.05, y: 0.05))
        path.addLine(to: Point(x: 0.95, y: shoulder))
        path.addLine(to: Point(x: 0.7 - shoulder / 3, y: 0.95))
        path.addLine(to: Point(x: 0.1 + shoulder / 4, y: 0.7))
        path.close()
        return VisualEffectsPathShape(pathValue: path)
          .fill(Color.cyan)
          .frame(width: 20, height: 9)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("VisualEffects002")

    for generation in 0..<28 {
      let root = Root(generation: generation)
      let retained = visualEffectsRetainedFrame(
        root,
        renderer: renderer,
        identity: identity,
        generation: generation
      )
      let fresh = visualEffectsFreshFrame(root, identity: identity)

      #expect(retained.rasterSurface == fresh.rasterSurface)
    }
  }
}

// MARK: - Attempt 003: custom-path fill-rule churn

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 003 custom path follows current winding rule")
  func visualEffects003CustomPathFollowsCurrentWindingRule() {
    // Hypothesis: retained shape equivalence can overlook the FillRule associated with an equal
    // boxed path, leaving the pentagram center filled after switching to even-odd (or vice versa).
    func pentagram() -> Path {
      let points = [
        Point(x: 0.5, y: 0.04), Point(x: 0.94, y: 0.36),
        Point(x: 0.77, y: 0.88), Point(x: 0.23, y: 0.88),
        Point(x: 0.06, y: 0.36),
      ]
      var path = Path()
      path.move(to: points[0])
      path.addLine(to: points[2])
      path.addLine(to: points[4])
      path.addLine(to: points[1])
      path.addLine(to: points[3])
      path.close()
      return path
    }

    struct Root: View {
      let path: Path
      let generation: Int

      var body: some View {
        VisualEffectsPathShape(
          pathValue: path,
          rule: generation.isMultiple(of: 2) ? .nonZero : .evenOdd
        )
        .fill(Color.yellow)
        .frame(width: 20, height: 10)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("VisualEffects003")
    var previous: RasterSurface?

    for generation in 0..<20 {
      let root = Root(path: pentagram(), generation: generation)
      let retained = visualEffectsRetainedFrame(
        root,
        renderer: renderer,
        identity: identity,
        generation: generation
      )
      let fresh = visualEffectsFreshFrame(root, identity: identity)

      #expect(retained.rasterSurface == fresh.rasterSurface)
      if let previous {
        #expect(retained.rasterSurface != previous)
      }
      previous = retained.rasterSurface
    }
  }
}

// MARK: - Attempt 004: open and closed path topology churn

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 004 path stroke follows open and closed topology")
  func visualEffects004PathStrokeFollowsOpenAndClosedTopology() {
    // Hypothesis: retained path-stroke commands can preserve a departed closing segment because
    // only the point sequence, rather than the close element, participates in payload refresh.
    struct Root: View {
      let generation: Int

      var body: some View {
        var path = Path()
        path.move(to: Point(x: 0.08, y: 0.1))
        path.addLine(to: Point(x: 0.9, y: 0.18))
        path.addLine(to: Point(x: 0.55, y: 0.9))
        if generation.isMultiple(of: 2) {
          path.close()
        }
        return VisualEffectsPathShape(pathValue: path)
          .stroke(Color.magenta, style: .single)
          .frame(width: 22, height: 10)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("VisualEffects004")
    var previous: RasterSurface?

    for generation in 0..<20 {
      let root = Root(generation: generation)
      let retained = visualEffectsRetainedFrame(
        root,
        renderer: renderer,
        identity: identity,
        generation: generation
      )
      let fresh = visualEffectsFreshFrame(root, identity: identity)

      #expect(retained.rasterSurface == fresh.rasterSurface)
      if let previous {
        #expect(retained.rasterSurface != previous)
      }
      previous = retained.rasterSurface
    }
  }
}

// MARK: - Attempt 005: nested custom-shape inset churn

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 005 nested inset depth reaches the current path fill")
  func visualEffects005NestedInsetDepthReachesCurrentPathFill() {
    // Hypothesis: nested InsetShape wrappers can retain an earlier accumulated insetAmount even
    // while both wrapper values change, making a current path render at a prior generation's size.
    var diamond = Path()
    diamond.move(to: Point(x: 0.5, y: 0))
    diamond.addLine(to: Point(x: 1, y: 0.5))
    diamond.addLine(to: Point(x: 0.5, y: 1))
    diamond.addLine(to: Point(x: 0, y: 0.5))
    diamond.close()

    struct Root: View {
      let path: Path
      let generation: Int

      var body: some View {
        VisualEffectsPathShape(pathValue: path)
          .inset(by: generation % 5)
          .inset(by: (generation + 1) % 4)
          .fill(Color.green)
          .frame(width: 24, height: 12)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("VisualEffects005")

    for generation in 0..<24 {
      let root = Root(path: diamond, generation: generation)
      let retained = visualEffectsRetainedFrame(
        root,
        renderer: renderer,
        identity: identity,
        generation: generation
      )
      let fresh = visualEffectsFreshFrame(root, identity: identity)

      #expect(retained.rasterSurface == fresh.rasterSurface)
    }
  }
}

// MARK: - Attempt 006: fill and stroke operation replacement

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 006 stable shape replaces fill and stroke operations")
  func visualEffects006StableShapeReplacesFillAndStrokeOperations() {
    // Hypothesis: retained draw reuse can treat an unchanged rounded-rectangle geometry as proof
    // that its ShapeOperation is unchanged, replaying a solid fill after the node becomes a stroke.
    struct Root: View {
      let generation: Int

      var body: some View {
        Group {
          if generation.isMultiple(of: 2) {
            AnyView(RoundedRectangle(cornerRadius: 4).fill(Color.blue))
          } else {
            AnyView(
              RoundedRectangle(cornerRadius: 4)
                .stroke(Color.blue, style: .double)
            )
          }
        }
        .frame(width: 22, height: 10)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("VisualEffects006")
    var previous: RasterSurface?

    for generation in 0..<20 {
      let root = Root(generation: generation)
      let retained = visualEffectsRetainedFrame(
        root,
        renderer: renderer,
        identity: identity,
        generation: generation
      )
      let fresh = visualEffectsFreshFrame(root, identity: identity)

      #expect(retained.rasterSurface == fresh.rasterSurface)
      if let previous {
        #expect(retained.rasterSurface != previous)
      }
      previous = retained.rasterSurface
    }
  }
}

// MARK: - Attempt 007: stroke and strokeBorder replacement

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 007 stable shape replaces stroke and strokeBorder masks")
  func visualEffects007StableShapeReplacesStrokeAndStrokeBorderMasks() {
    // Hypothesis: the strokeBorder bit can be lost when a retained shape keeps the same geometry,
    // style, and StrokeStyle, leaving an outside stroke where an interior-masking border is current.
    struct Root: View {
      let generation: Int

      var body: some View {
        Group {
          if generation.isMultiple(of: 2) {
            AnyView(Capsule().stroke(Color.white, style: .heavy))
          } else {
            AnyView(Capsule().strokeBorder(Color.white, style: .heavy))
          }
        }
        .frame(width: 24, height: 9)
        .background(Color.red.opacity(0.35))
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("VisualEffects007")

    func strokeBorderValue(in node: ResolvedNode) -> Bool? {
      if case .shape(let payload) = node.drawPayload,
        case .stroke(_, _, let strokeBorder, _) = payload.operation
      {
        return strokeBorder
      }
      for child in node.children {
        if let value = strokeBorderValue(in: child) {
          return value
        }
      }
      return nil
    }

    for generation in 0..<20 {
      let root = Root(generation: generation)
      let retained = visualEffectsRetainedFrame(
        root,
        renderer: renderer,
        identity: identity,
        generation: generation
      )
      let fresh = visualEffectsFreshFrame(root, identity: identity)

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(strokeBorderValue(in: retained.resolvedTree) == !generation.isMultiple(of: 2))
    }
  }
}

// MARK: - Attempt 008: shape-stroke glyph-set churn

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 008 shape stroke uses its current border glyph set")
  func visualEffects008ShapeStrokeUsesCurrentBorderGlyphSet() {
    // Hypothesis: ShapeOperation equality can refresh the stroke color while retaining the first
    // StrokeStyle.borderSet, causing a rectangle to keep old edge and corner glyphs after churn.
    struct Root: View {
      let generation: Int

      var style: StrokeStyle {
        switch generation % 5 {
        case 0: .single
        case 1: .double
        case 2: .heavy
        case 3: .ascii
        default: .rounded
        }
      }

      var body: some View {
        Rectangle()
          .stroke(Color.cyan, style: style)
          .frame(width: 18, height: 7)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("VisualEffects008")

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
    }
  }
}
