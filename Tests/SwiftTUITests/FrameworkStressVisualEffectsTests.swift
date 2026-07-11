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

// MARK: - Attempt 009: shape-stroke placement churn

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 009 shape stroke follows inset and outset placement")
  func visualEffects009ShapeStrokeFollowsInsetAndOutsetPlacement() {
    // Hypothesis: retained shape payloads can preserve StrokeStyle.Placement independently from
    // their current border glyph set, shifting a live stroke by one cell after placement churn.
    struct Root: View {
      let generation: Int

      var body: some View {
        RoundedRectangle(cornerRadius: 3)
          .stroke(
            Color.yellow,
            style: StrokeStyle(
              lineWidth: 1,
              borderSet: .single,
              placement: generation.isMultiple(of: 2) ? .outset : .inset
            )
          )
          .frame(width: 20, height: 8)
      }
    }

    func placement(in node: ResolvedNode) -> StrokeStyle.Placement? {
      if case .shape(let payload) = node.drawPayload,
        case .stroke(_, let style, _, _) = payload.operation
      {
        return style.placement
      }
      for child in node.children {
        if let value = placement(in: child) {
          return value
        }
      }
      return nil
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("VisualEffects009")

    for generation in 0..<24 {
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
        placement(in: retained.resolvedTree)
          == (generation.isMultiple(of: 2) ? .outset : .inset)
      )
    }
  }
}

// MARK: - Attempt 010: stroke background-style churn

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 010 shape stroke carries its current background style")
  func visualEffects010ShapeStrokeCarriesCurrentBackgroundStyle() {
    // Hypothesis: the optional BorderBackgroundStyle can lag behind the foreground stroke payload,
    // pairing current outline glyphs with a background color captured by an earlier generation.
    struct Root: View {
      let generation: Int

      var background: Color {
        switch generation % 4 {
        case 0: .red.opacity(0.25)
        case 1: .blue.opacity(0.5)
        case 2: .green.opacity(0.75)
        default: .magenta.opacity(0.4)
        }
      }

      var body: some View {
        Capsule()
          .stroke(Color.white, style: .double, background: background)
          .frame(width: 24, height: 9)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("VisualEffects010")

    for generation in 0..<24 {
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

// MARK: - Attempt 011: linear-gradient direction churn

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 011 linear gradient follows current endpoints")
  func visualEffects011LinearGradientFollowsCurrentEndpoints() {
    // Hypothesis: retained shape-style extraction can update gradient stops without replacing the
    // endpoint pair, leaving the fill oriented along an earlier generation's direction vector.
    struct Root: View {
      let generation: Int

      var endpoints: (UnitPoint, UnitPoint) {
        switch generation % 4 {
        case 0: (.topLeading, .bottomTrailing)
        case 1: (.topTrailing, .bottomLeading)
        case 2: (.leading, .trailing)
        default: (.bottom, .top)
        }
      }

      var body: some View {
        Rectangle()
          .fill(
            LinearGradient(
              colors: [.red, .yellow, .blue],
              startPoint: endpoints.0,
              endPoint: endpoints.1
            )
          )
          .frame(width: 25, height: 9)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("VisualEffects011")

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

// MARK: - Attempt 012: gradient stop-cardinality churn

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 012 linear gradient follows current stop topology")
  func visualEffects012LinearGradientFollowsCurrentStopTopology() {
    // Hypothesis: retained style snapshots can reuse an equal endpoint pair while overlooking a
    // changed Gradient stop count or location, replaying a stale interpolation topology.
    struct Root: View {
      let generation: Int

      var gradient: Gradient {
        switch generation % 4 {
        case 0:
          Gradient(colors: [.red, .blue])
        case 1:
          Gradient(colors: [.red, .green, .blue])
        case 2:
          Gradient(stops: [
            .init(color: .yellow, location: 0),
            .init(color: .magenta, location: 0.18),
            .init(color: .cyan, location: 1),
          ])
        default:
          Gradient(colors: [.white])
        }
      }

      var body: some View {
        RoundedRectangle(cornerRadius: 2)
          .fill(
            LinearGradient(
              gradient: gradient,
              startPoint: .leading,
              endPoint: .trailing
            )
          )
          .frame(width: 27, height: 8)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("VisualEffects012")

    for generation in 0..<24 {
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

// MARK: - Attempt 013: radial-gradient geometry churn

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 013 radial gradient follows current center and radii")
  func visualEffects013RadialGradientFollowsCurrentCenterAndRadii() {
    // Hypothesis: radial-gradient retained equivalence can refresh colors but reuse an old center
    // or radius pair, especially when a later generation returns to a prior endpoint radius.
    struct Root: View {
      let generation: Int

      var center: UnitPoint {
        switch generation % 5 {
        case 0: .center
        case 1: .topLeading
        case 2: .bottomTrailing
        case 3: UnitPoint(x: 0.25, y: 0.7)
        default: UnitPoint(x: 0.8, y: 0.3)
        }
      }

      var body: some View {
        Ellipse()
          .fill(
            RadialGradient(
              colors: [.white, .cyan, .blue],
              center: center,
              startRadius: Double(generation % 3),
              endRadius: Double(5 + generation % 7)
            )
          )
          .frame(width: 25, height: 11)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("VisualEffects013")

    for generation in 0..<35 {
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

// MARK: - Attempt 014: shape-style family replacement

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 014 fill replaces color gradient and tile style families")
  func visualEffects014FillReplacesColorGradientAndTileStyleFamilies() {
    // Hypothesis: retained ShapeOperation storage can preserve the first AnyShapeStyle case while
    // later generations replace it with a structurally different paint family at the same slot.
    struct Root: View {
      let generation: Int

      var style: AnyShapeStyle {
        switch generation % 4 {
        case 0:
          AnyShapeStyle(Color.red)
        case 1:
          AnyShapeStyle(
            LinearGradient(colors: [.yellow, .blue], startPoint: .top, endPoint: .bottom)
          )
        case 2:
          AnyShapeStyle(
            RadialGradient(colors: [.white, .magenta], center: .center, endRadius: 8)
          )
        default:
          AnyShapeStyle(
            TileStyle(.checkerShade, foreground: Color.cyan, background: Color.black)
          )
        }
      }

      var body: some View {
        RoundedRectangle(cornerRadius: 3)
          .fill(style)
          .frame(width: 24, height: 10)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("VisualEffects014")

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

// MARK: - Attempt 015: tile glyph and paint churn

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 015 tile fill follows current pattern and paints")
  func visualEffects015TileFillFollowsCurrentPatternAndPaints() {
    // Hypothesis: TileStyle's empty generic animatable data and nested erased paints can make a
    // retained fill reuse old pattern glyphs or a departed optional background paint.
    struct Root: View {
      let generation: Int

      var style: TileStyle {
        switch generation % 4 {
        case 0:
          TileStyle(.lightShade, foreground: Color.red)
        case 1:
          TileStyle(.dots, foreground: Color.blue, background: Color.black)
        case 2:
          TileStyle(
            .init(rows: ["/\\", "\\/"]),
            foreground: LinearGradient(
              colors: [.yellow, .magenta],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
        default:
          TileStyle(.checkerShade, foreground: Color.cyan, background: Color.green.opacity(0.4))
        }
      }

      var body: some View {
        Capsule()
          .fill(style)
          .frame(width: 26, height: 9)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("VisualEffects015")

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

// MARK: - Attempt 016: unequal-stop gradient animation churn

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 016 unequal gradient stop counts snap to current target")
  func visualEffects016UnequalGradientStopCountsSnapToCurrentTarget() {
    // Hypothesis: AnimatableArray returns empty arithmetic for unequal counts, but repeated shape-
    // fill animations may still enqueue that invalid interpolation and preserve an older gradient.
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(1000))
    controller.register(animation)
    let identity = testIdentity("VisualEffects016", "Shape")

    func gradient(for generation: Int) -> LinearGradient {
      if generation.isMultiple(of: 2) {
        return LinearGradient(
          gradient: Gradient(colors: [.red, .blue]),
          startPoint: .leading,
          endPoint: .trailing
        )
      }
      return LinearGradient(
        gradient: Gradient(stops: [
          .init(color: .yellow, location: 0),
          .init(color: .green, location: 0.35),
          .init(color: .magenta, location: 1),
        ]),
        startPoint: .top,
        endPoint: .bottom
      )
    }

    func node(for generation: Int) -> ResolvedNode {
      ResolvedNode(
        identity: identity,
        kind: .view("Rectangle"),
        drawPayload: .shape(
          ShapePayload(
            geometry: .rectangle,
            operation: .fill(style: AnyShapeStyle(gradient(for: generation)))
          )
        )
      )
    }

    func fillGradient(in node: ResolvedNode) -> LinearGradient? {
      guard case .shape(let payload) = node.drawPayload,
        case .fill(let style, _) = payload.operation,
        case .linearGradient(let gradient) = style
      else {
        return nil
      }
      return gradient
    }

    let start = MonotonicInstant.now()
    controller.processResolvedTree(node(for: 0), transaction: .init(), timestamp: start)

    for generation in 1...16 {
      let targetGradient = gradient(for: generation)
      var targetNode = node(for: generation)
      var transaction = TransactionSnapshot()
      transaction.animationRequest = .animate(animation.animationBox)
      let frameStart = start.advanced(by: .milliseconds(generation * 1200))

      controller.processResolvedTree(
        targetNode,
        transaction: transaction,
        timestamp: frameStart
      )
      _ = controller.applyInterpolations(
        to: &targetNode,
        at: frameStart.advanced(by: .milliseconds(500))
      )

      withKnownIssue(
        "Unequal-count gradient animation retains prior stops while interpolating current endpoints"
      ) {
        #expect(fillGradient(in: targetNode) == targetGradient)
      }
    }
  }
}

// MARK: - Attempt 017: animated style-family replacement

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 017 cross-family fill animation snaps to current style")
  func visualEffects017CrossFamilyFillAnimationSnapsToCurrentStyle() {
    // Hypothesis: a shape-fill animation can keep the previous slot's concrete AnyAnimatable box
    // when the style family changes, applying a stale color or gradient instead of snapping.
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(800))
    controller.register(animation)
    let identity = testIdentity("VisualEffects017", "Shape")

    func style(for generation: Int) -> AnyShapeStyle {
      switch generation % 4 {
      case 0:
        AnyShapeStyle(Color.red)
      case 1:
        AnyShapeStyle(
          LinearGradient(colors: [.yellow, .blue], startPoint: .leading, endPoint: .trailing)
        )
      case 2:
        AnyShapeStyle(
          RadialGradient(colors: [.white, .magenta], center: .center, endRadius: 6)
        )
      default:
        AnyShapeStyle(TileStyle(.dots, foreground: Color.cyan, background: Color.black))
      }
    }

    func node(for generation: Int) -> ResolvedNode {
      ResolvedNode(
        identity: identity,
        kind: .view("Ellipse"),
        drawPayload: .shape(
          ShapePayload(
            geometry: .ellipse,
            operation: .fill(style: style(for: generation))
          )
        )
      )
    }

    func fillStyle(in node: ResolvedNode) -> AnyShapeStyle? {
      guard case .shape(let payload) = node.drawPayload,
        case .fill(let style, _) = payload.operation
      else {
        return nil
      }
      return style
    }

    let start = MonotonicInstant.now()
    controller.processResolvedTree(node(for: 0), transaction: .init(), timestamp: start)

    for generation in 1...16 {
      let targetStyle = style(for: generation)
      var targetNode = node(for: generation)
      var transaction = TransactionSnapshot()
      transaction.animationRequest = .animate(animation.animationBox)
      let frameStart = start.advanced(by: .milliseconds(generation * 1000))

      controller.processResolvedTree(
        targetNode,
        transaction: transaction,
        timestamp: frameStart
      )
      _ = controller.applyInterpolations(
        to: &targetNode,
        at: frameStart.advanced(by: .milliseconds(400))
      )

      #expect(fillStyle(in: targetNode) == targetStyle)
    }
  }
}

// MARK: - Attempt 018: translucent blend-mode churn

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 018 overlapping translucent fill uses current blend mode")
  func visualEffects018OverlappingTranslucentFillUsesCurrentBlendMode() {
    // Hypothesis: retained DrawEffects can preserve a previous BlendMode even while the overlaid
    // translucent shape and its destination backdrop both re-rasterize at stable identities.
    struct Root: View {
      let generation: Int

      var mode: BlendMode {
        switch generation % 6 {
        case 0: .normal
        case 1: .multiply
        case 2: .screen
        case 3: .overlay
        case 4: .darken
        default: .lighten
        }
      }

      var body: some View {
        Rectangle()
          .fill(Color.blue.opacity(0.8))
          .frame(width: 24, height: 9)
          .overlay {
            RoundedRectangle(cornerRadius: 2)
              .fill(Color.red.opacity(0.65))
              .frame(width: 16, height: 7)
              .blendMode(mode)
          }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("VisualEffects018")

    for generation in 0..<30 {
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
        retained.rasterSurface.presentationLayers.contains {
          $0.effects.contains(.blendMode(root.mode))
        }
      )
    }
  }
}

// MARK: - Attempt 019: compositing-group topology churn

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 019 compositing group topology leaves and returns")
  func visualEffects019CompositingGroupTopologyLeavesAndReturns() {
    // Hypothesis: retained surface-composition metadata can outlive a removed compositingGroup,
    // continuing to isolate a stable erased subtree after the group modifier has departed.
    struct Root: View {
      let generation: Int

      var layeredContent: some View {
        Rectangle()
          .fill(Color.blue.opacity(0.7))
          .frame(width: 22, height: 8)
          .overlay {
            Circle()
              .fill(Color.yellow.opacity(0.6))
              .frame(width: 14, height: 7)
          }
      }

      var body: some View {
        Group {
          if generation.isMultiple(of: 2) {
            AnyView(layeredContent.compositingGroup())
          } else {
            AnyView(layeredContent)
          }
        }
      }
    }

    func containsCompositingGroup(_ node: PlacedNode) -> Bool {
      if node.surfaceComposition.role == .isolatedCompositingGroup {
        return true
      }
      return node.children.contains(where: containsCompositingGroup)
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("VisualEffects019")

    for generation in 0..<24 {
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
        containsCompositingGroup(retained.placedTree) == generation.isMultiple(of: 2)
      )
    }
  }
}

// MARK: - Attempt 020: blend and group effect-order churn

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 020 blend and compositing group preserve authored order")
  func visualEffects020BlendAndCompositingGroupPreserveAuthoredOrder() {
    // Hypothesis: retained DrawEffects may compare as a set or stop at the group marker, making
    // blend-before-group and blend-after-group collapse to one stale compositing interpretation.
    struct Root: View {
      let generation: Int

      var layeredContent: some View {
        Rectangle()
          .fill(Color.green.opacity(0.75))
          .frame(width: 22, height: 8)
          .overlay {
            RoundedRectangle(cornerRadius: 2)
              .fill(Color.magenta.opacity(0.55))
              .frame(width: 15, height: 6)
          }
      }

      var body: some View {
        Group {
          if generation.isMultiple(of: 2) {
            AnyView(layeredContent.blendMode(.multiply).compositingGroup())
          } else {
            AnyView(layeredContent.compositingGroup().blendMode(.multiply))
          }
        }
        .background(Color.blue.opacity(0.7))
      }
    }

    func authoredEffects(in node: PlacedNode) -> [DrawEffect]? {
      if node.drawEffects.ordered.count == 2 {
        return node.drawEffects.ordered
      }
      for child in node.children {
        if let effects = authoredEffects(in: child) {
          return effects
        }
      }
      return nil
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("VisualEffects020")

    for generation in 0..<24 {
      let root = Root(generation: generation)
      let retained = visualEffectsRetainedFrame(
        root,
        renderer: renderer,
        identity: identity,
        generation: generation
      )
      let fresh = visualEffectsFreshFrame(root, identity: identity)
      let expected: [DrawEffect] = generation.isMultiple(of: 2)
        ? [.blendMode(.multiply), .compositingGroup]
        : [.compositingGroup, .blendMode(.multiply)]

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(authoredEffects(in: retained.placedTree) == expected)
    }
  }
}

// MARK: - Attempt 021: border-blend stop and phase churn

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 021 border blend follows current stops and phase")
  func visualEffects021BorderBlendFollowsCurrentStopsAndPhase() {
    // Hypothesis: retained border layout behavior can update blendPhase while preserving the first
    // BorderBlend stop topology, producing plausible motion along the wrong color loop.
    struct Root: View {
      let generation: Int

      var blend: BorderBlend {
        switch generation % 3 {
        case 0:
          BorderBlend([.red, .blue, .red])
        case 1:
          BorderBlend([.yellow, .green, .magenta, .yellow])
        default:
          BorderBlend(stops: [
            .init(color: .white, location: 0),
            .init(color: .cyan, location: 0.2),
            .init(color: .blue, location: 0.85),
            .init(color: .white, location: 1),
          ])
        }
      }

      var body: some View {
        Text("retained border blend")
          .frame(width: 28, height: 7)
          .border(
            blend: blend,
            set: .single,
            phase: Double(generation % 11) / 11
          )
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("VisualEffects021")

    for generation in 0..<33 {
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

// MARK: - Attempt 022: per-edge border-style reorder churn

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 022 per-edge border colors follow current rotation")
  func visualEffects022PerEdgeBorderColorsFollowCurrentRotation() {
    // Hypothesis: retained border commands can keep the first top/right/bottom/left association
    // after the same four styles rotate among edges, a case set-like equality would miss.
    struct Root: View {
      let generation: Int

      var style: BorderEdgeStyle {
        switch generation % 4 {
        case 0:
          BorderEdgeStyle(top: Color.red, right: Color.green, bottom: Color.blue, left: Color.yellow)
        case 1:
          BorderEdgeStyle(top: Color.yellow, right: Color.red, bottom: Color.green, left: Color.blue)
        case 2:
          BorderEdgeStyle(top: Color.blue, right: Color.yellow, bottom: Color.red, left: Color.green)
        default:
          BorderEdgeStyle(top: Color.green, right: Color.blue, bottom: Color.yellow, left: Color.red)
        }
      }

      var body: some View {
        Text("edge rotation")
          .frame(width: 24, height: 7)
          .border(style, set: .double)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("VisualEffects022")

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

// MARK: - Attempt 023: analytic overlay-mask geometry churn

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 023 strokeBorder overlay remasks background geometry")
  func visualEffects023StrokeBorderOverlayRemasksBackgroundGeometry() {
    // Hypothesis: DrawExtractor can retain the first overlay BorderMask when a strokeBorder shape
    // changes analytic geometry, clipping the current background with a departed silhouette.
    struct Root: View {
      let generation: Int

      var body: some View {
        EmptyView()
          .frame(width: 24, height: 10, alignment: .topLeading)
          .background(Color.blue.opacity(0.65))
          .overlay {
            switch generation % 4 {
            case 0:
              AnyView(Circle().strokeBorder(Color.white, style: .single))
            case 1:
              AnyView(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white, style: .single))
            case 2:
              AnyView(Capsule().strokeBorder(Color.white, style: .single))
            default:
              AnyView(Rectangle().strokeBorder(Color.white, style: .single))
            }
          }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("VisualEffects023")

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

// MARK: - Attempt 024: custom-path overlay-mask topology churn

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 024 custom strokeBorder remasks current path background")
  func visualEffects024CustomStrokeBorderRemasksCurrentPathBackground() {
    // Hypothesis: overlay background masking can key a custom border mask by shape kind and bounds,
    // missing changed BoxedPath topology and continuing to expose the old path interior.
    struct Root: View {
      let generation: Int

      var path: Path {
        var value = Path()
        if generation.isMultiple(of: 2) {
          value.move(to: Point(x: 0.5, y: 0.02))
          value.addLine(to: Point(x: 0.98, y: 0.5))
          value.addLine(to: Point(x: 0.5, y: 0.98))
          value.addLine(to: Point(x: 0.02, y: 0.5))
        } else {
          value.move(to: Point(x: 0.05, y: 0.08))
          value.addLine(to: Point(x: 0.95, y: 0.2))
          value.addLine(to: Point(x: 0.72, y: 0.92))
          value.addLine(to: Point(x: 0.2, y: 0.72))
        }
        value.close()
        return value
      }

      var body: some View {
        EmptyView()
          .frame(width: 26, height: 11, alignment: .topLeading)
          .background(Color.green.opacity(0.55))
          .overlay {
            VisualEffectsPathShape(pathValue: path)
              .inset(by: generation % 3)
              .strokeBorder(Color.white, style: .single)
          }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("VisualEffects024")

    for generation in 0..<30 {
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

// MARK: - Attempt 025: moving oversized shape under a stable clip

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 025 stable clip follows oversized shape translation")
  func visualEffects025StableClipFollowsOversizedShapeTranslation() {
    // Hypothesis: retained clip commands can combine the current clip bounds with a previous child
    // translation, leaving stale gradient fragments as an oversized shape moves behind the viewport.
    struct Root: View {
      let generation: Int

      var body: some View {
        RoundedRectangle(cornerRadius: 3)
          .fill(
            LinearGradient(
              colors: [.red, .yellow, .blue],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .frame(width: 30, height: 13)
          .offset(x: (generation % 11) - 5, y: (generation % 7) - 3)
          .frame(width: 14, height: 6, alignment: .topLeading)
          .clipped()
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("VisualEffects025")

    for generation in 0..<35 {
      let root = Root(generation: generation)
      let retained = visualEffectsRetainedFrame(
        root,
        renderer: renderer,
        identity: identity,
        generation: generation
      )
      let fresh = visualEffectsFreshFrame(root, identity: identity)

      #expect(retained.rasterSurface.size == CellSize(width: 14, height: 6))
      #expect(retained.rasterSurface == fresh.rasterSurface)
    }
  }
}

// MARK: - Attempt 026: clipped image visible-bounds churn

extension FrameworkStressVisualEffectsTests {
  @Test("stress visual effects 026 clipped image publishes current visible bounds")
  func visualEffects026ClippedImagePublishesCurrentVisibleBounds() throws {
    // Hypothesis: a retained image attachment can update its logical bounds while preserving an
    // earlier visibleBounds intersection after the image translates behind a stable clip.
    let pngBytes = try makePNGBytes(
      width: 32,
      height: 32,
      pixels: Array(repeating: rgbaPixel(red: 255, green: 80, blue: 40), count: 32 * 32)
    )

    struct Root: View {
      let pngBytes: [UInt8]
      let generation: Int

      var body: some View {
        Image(data: pngBytes)
          .resizable()
          .frame(width: 12, height: 6)
          .offset(x: (generation % 9) - 4, y: (generation % 5) - 2)
          .frame(width: 7, height: 4, alignment: .topLeading)
          .clipped()
      }
    }

    func clippedToViewport(_ bounds: CellRect) -> CellRect {
      let minX = max(0, bounds.origin.x)
      let minY = max(0, bounds.origin.y)
      let maxX = min(7, bounds.origin.x + bounds.size.width)
      let maxY = min(4, bounds.origin.y + bounds.size.height)
      return CellRect(
        origin: CellPoint(x: minX, y: minY),
        size: CellSize(width: max(0, maxX - minX), height: max(0, maxY - minY))
      )
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("VisualEffects026")

    for generation in 0..<27 {
      let root = Root(pngBytes: pngBytes, generation: generation)
      let retained = visualEffectsRetainedFrame(
        root,
        renderer: renderer,
        identity: identity,
        generation: generation
      )
      let fresh = visualEffectsFreshFrame(root, identity: identity)
      let attachment = try #require(retained.rasterSurface.imageAttachments.first)

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(attachment.visibleBounds == clippedToViewport(attachment.bounds))
    }
  }
}
