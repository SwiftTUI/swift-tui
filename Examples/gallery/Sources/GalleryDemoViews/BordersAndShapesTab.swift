import TerminalUI

/// Showcases the "Borders & Shapes" revamp landed across Milestones
/// 1–7A of the 2026-04-11 pass.  Each panel exercises a distinct slice
/// of the new API surface so the tab doubles as a visual smoke test
/// for:
///
///   1. A chasing-light perimeter gradient driven by an animated
///      ``BorderBlend`` phase via `withAnimation(.repeatForever)`.
///   2. The built-in ``BorderSet`` catalog — a grid of small bordered
///      cards, one per built-in set, so every glyph family is visible.
///   3. Per-side ``BorderEdgeStyle`` foregrounds — a traffic-light card
///      and a CSS-shorthand two-color card.
///   4. Curved shapes — ``Circle``, ``Ellipse``, and ``Capsule`` across
///      fill / strokeBorder / ``TileStyle`` variants, including a
///      ``PhaseAnimator``-driven gradient that smoothly rotates
///      through the four corner orientations (the payoff for the
///      Animatable-protocol migration in
///      ``docs/proposals/ANIMATABLE_PROTOCOL_MIGRATION.md``).
///   5. A hand-drawn ``Canvas`` sparkline, the arbitrary-drawing
///      escape hatch alongside the shape fill/stroke algebra.
///   6. A direct ``withAnimation`` gradient rotation demo: tap a
///      button and the linear gradient interpolates its start and
///      end points to a new orientation, exercising
///      ``LinearGradient`` 's `Animatable` conformance through a real
///      run loop.
struct BordersAndShapesTab: View {
  @State private var gradientPhase: Double = 0

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 1) {
        BordersAndShapesHeader()
        Divider()
        chasingLightSection
        Divider()
        BordersAndShapesCatalogSection()
        Divider()
        BordersAndShapesEdgeStyleSection()
        Divider()
        BordersAndShapesCurvedShapesSection()
        Divider()
        BordersAndShapesCanvasSection()
        Divider()
        BordersAndShapesAnimatedGradientsSection()
        Spacer(minLength: 0)
      }
      .padding(1)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var chasingLightSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("1. BorderBlend + animated phase — chasing-light perimeter")
        .foregroundStyle(.muted)
      Text("chasing light")
        .padding(1)
        .frame(width: 30, height: 3)
        .border(
          blend: BorderBlend([.red, .yellow, .green, .cyan, .blue, .magenta, .red]),
          set: .rounded,
          phase: gradientPhase
        )
        .onAppear {
          withAnimation(
            .linear(duration: .milliseconds(3000))
              .repeatForever(autoreverses: false)
          ) {
            gradientPhase = 1.0
          }
        }
    }
  }
}

private struct BordersAndShapesHeader: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Borders & Shapes").foregroundStyle(.foreground)
      Text("BorderSet catalog, per-side colors, animated gradient, curved shapes, Canvas.")
        .foregroundStyle(.separator)
    }
  }
}

private struct BordersAndShapesCatalogSection: View {
  private func borderCard(_ label: String, set: BorderSet) -> some View {
    Text(label)
      .padding(.horizontal, 1)
      .border(set: set)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("2. Built-in BorderSet catalog").foregroundStyle(.muted)
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 2) {
          borderCard("single", set: .single)
          borderCard("rounded", set: .rounded)
          borderCard("double", set: .double)
          borderCard("heavy", set: .heavy)
        }
        HStack(spacing: 2) {
          borderCard("block", set: .block)
          borderCard("outerHalf", set: .outerHalfBlock)
          borderCard("innerHalf", set: .innerHalfBlock)
          borderCard("ascii", set: .ascii)
        }
        HStack(spacing: 2) {
          borderCard("singleDbl", set: .singleDouble)
          borderCard("doubleSgl", set: .doubleSingle)
          borderCard("dashed", set: .dashed)
          borderCard("dashedHvy", set: .dashedHeavy)
        }
      }
    }
  }
}

private struct BordersAndShapesEdgeStyleSection: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("3. Per-side colors via BorderEdgeStyle").foregroundStyle(.muted)
      HStack(spacing: 3) {
        Text("traffic light")
          .padding(1)
          .border(
            BorderEdgeStyle(top: .red, right: .yellow, bottom: .green, left: .blue),
            set: .heavy
          )
        Text("top/btm vs left/right")
          .padding(1)
          .border(
            BorderEdgeStyle(topBottom: .cyan, leftRight: .magenta),
            set: .rounded
          )
      }
    }
  }
}

private struct BordersAndShapesCurvedShapesSection: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("4. Curved shapes — Circle, Ellipse, Capsule")
        .foregroundStyle(.muted)
      Text("fill").foregroundStyle(.separator)
      HStack(spacing: 2) {
        Circle()
          .fill(Color.red)
          .frame(width: 10, height: 5)
        Ellipse()
          .fill(Color.green)
          .frame(width: 14, height: 5)
        Capsule()
          .fill(Color.blue)
          .frame(width: 16, height: 3)
      }
      Text("strokeBorder").foregroundStyle(.separator)
      HStack(spacing: 2) {
        Circle()
          .strokeBorder(Color.red)
          .frame(width: 10, height: 5)
        Ellipse()
          .strokeBorder(Color.green)
          .frame(width: 14, height: 5)
        Capsule()
          .strokeBorder(Color.blue)
          .frame(width: 16, height: 3)
      }
      Text("TileStyle — light / medium / heavy shade").foregroundStyle(.separator)
      HStack(spacing: 2) {
        Circle()
          .fill(TileStyle(.lightShade, foreground: .white))
          .frame(width: 10, height: 5)
        Ellipse()
          .fill(TileStyle(.mediumShade, foreground: .white))
          .frame(width: 14, height: 5)
        Capsule()
          .fill(TileStyle(.heavyShade, foreground: .white))
          .frame(width: 16, height: 3)
      }
      // PhaseAnimator-driven TileStyle with a linear-gradient
      // foreground.  Pre-Animatable-protocol migration this row froze
      // on phase 0 (gradients had no diff signal) or, post-stranded-
      // completion fix, snapped between corners every 500 ms.  After
      // the migration, the start and end points interpolate
      // continuously across the 500 ms window so the diagonal sweep
      // visibly rotates through topLeading → topTrailing →
      // bottomTrailing → bottomLeading and back.
      Text("Animated gradient tile style — rotates smoothly via PhaseAnimator")
        .foregroundStyle(.separator)
      HStack(spacing: 2) {
        Rectangle()
          .fill(TileStyle(.init(glyph: "/"), foreground: .yellow))
          .frame(width: 5, height: 5)
        PhaseAnimator(GradientRotationPhase.allCases) { phase in
          Rectangle()
            .fill(
              TileStyle(
                .init(glyph: "/"),
                foreground: LinearGradient(
                  colors: [.white, .red],
                  startPoint: phase.startPoint,
                  endPoint: phase.endPoint
                )
              )
            )
            .frame(width: 5, height: 5)
        } animation: { _ in
          .linear(duration: .milliseconds(500))
        }
        Rectangle()
          .fill(TileStyle(.dots, foreground: .white))
          .frame(width: 5, height: 5)
      }
    }
  }
}

private struct BordersAndShapesCanvasSection: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("5. Canvas sparkline — 20 data points in a 30×4 frame")
        .foregroundStyle(.muted)
      Canvas(
        Sparkline(
          values: [
            0.2, 0.5, 0.8, 0.6, 0.9, 1.0, 0.7, 0.5, 0.3, 0.6,
            0.4, 0.8, 0.9, 0.7, 0.5, 0.4, 0.6, 0.8, 0.5, 0.3,
          ]
        )
      )
      .foregroundStyle(Color.cyan)
      .frame(width: 30, height: 4)
    }
  }
}

/// Direct ``withAnimation`` gradient-rotation demo.  Tapping the
/// button advances the gradient direction one step around the
/// `GradientDirection` ring under an `easeInOut` 800 ms animation,
/// so the bar's color sweep rotates smoothly between orientations.
/// Exercises ``LinearGradient``'s `Animatable` conformance through a
/// real run loop end-to-end (resolve → snapshot diff → controller
/// interpolation → raster).
private struct BordersAndShapesAnimatedGradientsSection: View {
  @State private var gradientDirection: GradientDirection = .horizontal

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("6. Direct withAnimation — tap to rotate gradient")
        .foregroundStyle(.muted)
      Button("rotate") {
        withAnimation(.easeInOut(duration: .milliseconds(800))) {
          gradientDirection = gradientDirection.next
        }
      }
      Rectangle()
        .fill(
          LinearGradient(
            colors: [.red, .yellow, .green, .blue],
            startPoint: gradientDirection.startPoint,
            endPoint: gradientDirection.endPoint
          )
        )
        .frame(width: 30, height: 5)
    }
  }
}

/// Phase values for the PhaseAnimator-driven gradient rotation in
/// ``BordersAndShapesCurvedShapesSection``.  Each case names a
/// corner; the gradient's `startPoint` sits at the named corner and
/// the `endPoint` sits at the diagonally opposite corner so every
/// transition is a 90° rotation and the animation interpolates the
/// endpoints continuously through the midpoint of the square.
private enum GradientRotationPhase: Hashable, CaseIterable {
  case topLeading
  case topTrailing
  case bottomTrailing
  case bottomLeading

  var startPoint: UnitPoint {
    switch self {
    case .topLeading: return .topLeading
    case .topTrailing: return .topTrailing
    case .bottomTrailing: return .bottomTrailing
    case .bottomLeading: return .bottomLeading
    }
  }

  var endPoint: UnitPoint {
    switch self {
    case .topLeading: return .bottomTrailing
    case .topTrailing: return .bottomLeading
    case .bottomTrailing: return .topLeading
    case .bottomLeading: return .topTrailing
    }
  }
}

/// Direction states for ``BordersAndShapesAnimatedGradientsSection``.
/// Cycling through `.horizontal → .diagonal → .vertical →
/// .antidiagonal → .horizontal` walks the gradient through every 45°
/// orientation, and `withAnimation` interpolates `startPoint` and
/// `endPoint` independently so the sweep visibly rotates instead of
/// snapping.
private enum GradientDirection: Hashable, CaseIterable {
  case horizontal
  case diagonal
  case vertical
  case antidiagonal

  var next: GradientDirection {
    switch self {
    case .horizontal: return .diagonal
    case .diagonal: return .vertical
    case .vertical: return .antidiagonal
    case .antidiagonal: return .horizontal
    }
  }

  var startPoint: UnitPoint {
    switch self {
    case .horizontal: return .leading
    case .diagonal: return .topLeading
    case .vertical: return .top
    case .antidiagonal: return .topTrailing
    }
  }

  var endPoint: UnitPoint {
    switch self {
    case .horizontal: return .trailing
    case .diagonal: return .bottomTrailing
    case .vertical: return .bottom
    case .antidiagonal: return .bottomLeading
    }
  }
}

/// Minimal ``CanvasDrawing`` that plots an array of values as a polyline in
/// continuous cell space. Scales both axes to fit the canvas context, leaving
/// enough in-cell margin for the final sample to land inside the active grid.
struct Sparkline: CanvasDrawing, Equatable {
  let values: [Double]

  func draw(into context: inout CanvasContext) {
    guard values.count >= 2 else { return }
    let maxV = values.max() ?? 1
    let minV = values.min() ?? 0
    let range = max(0.001, maxV - minV)
    let maxX = max(0, Double(context.size.width) - 0.5 / Double(context.grid.subdivisionsX))
    let maxY = max(0, Double(context.size.height) - 0.5 / Double(context.grid.subdivisionsY))
    let xStep = maxX / Double(values.count - 1)
    for i in 0..<(values.count - 1) {
      let x0 = Double(i) * xStep
      let x1 = Double(i + 1) * xStep
      let y0 = maxY - ((values[i] - minV) / range) * maxY
      let y1 = maxY - ((values[i + 1] - minV) / range) * maxY
      context.line(from: Point(x: x0, y: y0), to: Point(x: x1, y: y1))
    }
  }
}
