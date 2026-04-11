import TerminalUI

/// Showcases the "Borders & Shapes" revamp landed across Milestones
/// 1–7A of the 2026-04-11 pass.  Each panel exercises a distinct slice
/// of the new API surface so the tab doubles as a visual smoke test
/// for:
///
///   1. The built-in ``BorderSet`` catalog — a grid of small bordered
///      cards, one per built-in set, so every glyph family is visible.
///   2. Per-side ``BorderEdgeStyle`` foregrounds — a traffic-light card
///      and a CSS-shorthand two-color card.
///   3. A chasing-light perimeter gradient driven by an animated
///      ``BorderBlend`` phase via `withAnimation(.repeatForever)`.
///   4. Curved shapes — ``Circle``, ``Ellipse``, and ``Capsule`` across
///      fill / strokeBorder / ``PatternFill`` variants.
///   5. A hand-drawn ``Canvas`` sparkline, the arbitrary-drawing
///      escape hatch alongside the shape fill/stroke algebra.
struct BordersAndShapesTab: View {
  // Phase value driving the BorderBlend chasing-light animation.
  // Bumped once inside `withAnimation(.linear(duration:).repeatForever)`
  // on .onAppear, so the animation controller continuously interpolates
  // the phase and the pipeline re-samples the perimeter every frame.
  @State private var gradientPhase: Double = 0

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 1) {
        header
        Divider()
        borderCatalogSection
        Divider()
        edgeStyleSection
        Divider()
        chasingLightSection
        Divider()
        curvedShapesSection
        Divider()
        canvasSparklineSection
        Spacer(minLength: 0)
      }
      .padding(1)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  // MARK: - Header

  private var header: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Borders & Shapes").foregroundStyle(.foreground)
      Text("BorderSet catalog, per-side colors, animated gradient, curved shapes, Canvas.")
        .foregroundStyle(.separator)
    }
  }

  // MARK: - 1. Built-in BorderSet catalog

  // Four cards per row so the grid fits inside the gallery's ~80-col
  // terminal envelope without clipping. Each row is a VStack rendered
  // side-by-side inside an HStack. Horizontal padding adds breathing
  // room so short labels like "single" aren't cramped against the
  // border glyphs.
  private var borderCatalogSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("1. Built-in BorderSet catalog").foregroundStyle(.muted)
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

  private func borderCard(_ label: String, set: BorderSet) -> some View {
    Text(label)
      .padding(.horizontal, 1)
      .border(set: set)
  }

  // MARK: - 2. Per-side BorderEdgeStyle colors

  private var edgeStyleSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("2. Per-side colors via BorderEdgeStyle").foregroundStyle(.muted)
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

  func shitAnimation(to: Double) {
    withAnimation(.linear(duration: .seconds(0.3))) {
      gradientPhase = to
    } completion: {
      Task { @MainActor in
        try await Task.sleep(for: .seconds(0.3))
        shitAnimation(to: to + 0.3)
      }
    }
  }

  // MARK: - 3. Chasing-light perimeter gradient

  // A closed palette (red at both endpoints) so the phase wrap is
  // visually seamless. `withAnimation(.linear(...).repeatForever)` on
  // `.onAppear` drives the animation controller forever; the pipeline
  // re-samples `BorderBlend.color(at:)` at every animated phase step.
  private var chasingLightSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("3. BorderBlend + animated phase — chasing-light perimeter")
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
          shitAnimation(to: 0.3)
        }
    }
  }

  // MARK: - 4. Curved shapes — Circle / Ellipse / Capsule

  private var curvedShapesSection: some View {
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
      Text("PatternFill — light / medium / heavy shade").foregroundStyle(.separator)
      HStack(spacing: 2) {
        Circle()
          .fill(PatternFill.lightShade)
          .frame(width: 10, height: 5)
        Ellipse()
          .fill(PatternFill.mediumShade)
          .frame(width: 14, height: 5)
        Capsule()
          .fill(PatternFill.heavyShade)
          .frame(width: 16, height: 3)
      }
    }
  }

  // MARK: - 5. Canvas sparkline

  private var canvasSparklineSection: some View {
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

/// Minimal ``CanvasDrawing`` that plots an array of values as a
/// Bresenham polyline in the Braille subpixel grid. Scales both axes
/// to fit the canvas context, leaving one subpixel of margin on the
/// right so the final sample is reachable without clipping.
struct Sparkline: CanvasDrawing, Equatable {
  let values: [Double]

  func draw(into context: inout CanvasContext) {
    guard values.count >= 2 else { return }
    let maxV = values.max() ?? 1
    let minV = values.min() ?? 0
    let range = max(0.001, maxV - minV)
    let xStep = Double(context.width - 1) / Double(values.count - 1)
    for i in 0..<(values.count - 1) {
      let x0 = Int(Double(i) * xStep)
      let x1 = Int(Double(i + 1) * xStep)
      let y0 =
        context.height - 1
        - Int(((values[i] - minV) / range) * Double(context.height - 1))
      let y1 =
        context.height - 1
        - Int(((values[i + 1] - minV) / range) * Double(context.height - 1))
      context.line(from: (x0, y0), to: (x1, y1))
    }
  }
}
