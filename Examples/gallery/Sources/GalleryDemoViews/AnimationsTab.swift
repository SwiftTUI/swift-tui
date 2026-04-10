import TerminalUI

/// Showcases the animation features that landed in the 2026-04-10
/// gap-closure pass.  Each section exercises a distinct capability
/// — spring/bezier curves, transitions with different edges, frame
/// animation, and withAnimation completion callbacks — so the
/// gallery doubles as a visual smoke test.
///
/// All durations are long (1000–2000 ms) so the interpolation is
/// unmistakable on a 30fps terminal.  Elements are intentionally
/// large (full-block text, big ASCII figures) so the visual change
/// cannot be missed.
struct AnimationsTab: View {
  // Color demo: high-contrast red↔blue toggle.  Direct field
  // mutation inside the withAnimation closure — no mutating method
  // indirection.
  @State private var colorBlue: Bool = false
  @State private var curveLabel: String = "(tap a curve)"

  // Transition demo: two independent toggles.
  @State private var showOpacityFigure: Bool = true
  @State private var showSlideFigure: Bool = false

  // Frame demo: narrow↔wide width.
  @State private var wide: Bool = false

  // Offset demo: target offset the text slides to.
  @State private var offsetX: Int = 0

  // Position demo: absolute target position the marker jumps to.
  @State private var positionX: Int = 10
  @State private var positionY: Int = 2

  // Matched geometry demo: which column the "hero" lives in.
  @State private var heroOnRight: Bool = false
  // Namespace scoping the matched geometry key so the same "hero"
  // string ID wouldn't collide with any other section's usage.
  @Namespace private var heroNamespace

  // Completion demo: a counter ticked by the callback closure.
  @State private var completionRuns: Int = 0
  @State private var completionAccent: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      header
      Divider()
      colorSection
      Divider()
      transitionSection
      Divider()
      frameSection
      Divider()
      offsetSection
      Divider()
      positionSection
      Divider()
      matchedGeometrySection
      Divider()
      phaseAnimatorSection
      Divider()
      completionSection
      Spacer(minLength: 0)
    }
    .padding(1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Animations").foregroundStyle(.foreground)
      Text("Every button triggers a multi-second animation via withAnimation.")
        .foregroundStyle(.separator)
    }
  }

  // MARK: - Color animation with spring / bezier / bouncy curves

  private var colorSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("1. withAnimation foreground color — curve: \(curveLabel)")
        .foregroundStyle(.muted)
      // Full-block row so the colour change is unmistakable.
      Text("████████████████████████████")
        .foregroundStyle(colorBlue ? Color.blue : Color.red)
      HStack(spacing: 1) {
        Button("linear") {
          withAnimation(.linear(duration: .milliseconds(1500))) {
            colorBlue.toggle()
            curveLabel = "linear"
          }
        }
        Button("easeInOut") {
          withAnimation(.easeInOut(duration: .milliseconds(1500))) {
            colorBlue.toggle()
            curveLabel = "easeInOut"
          }
        }
        Button("spring") {
          withAnimation(.spring(duration: .milliseconds(1500), bounce: 0.3)) {
            colorBlue.toggle()
            curveLabel = "spring"
          }
        }
        Button("bouncy") {
          withAnimation(.bouncy) {
            colorBlue.toggle()
            curveLabel = "bouncy"
          }
        }
      }
    }
  }

  // MARK: - Opacity + move transitions

  private var transitionSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("2. .transition(...) insertion & removal")
        .foregroundStyle(.muted)
      HStack(spacing: 2) {
        Button(showOpacityFigure ? "fade out" : "fade in") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            showOpacityFigure.toggle()
          }
        }
        Button(showSlideFigure ? "slide out" : "slide in") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            showSlideFigure.toggle()
          }
        }
      }
      // Opacity transition — a large TextFigure fades in/out via the
      // pre-composited cell-background blend.
      if showOpacityFigure {
        TextFigure("FADE", font: .smMono9)
          .foregroundStyle(Color.cyan)
          .transition(.opacity)
      }
      // Slide transition — uses .transition(.slide), which is an
      // asymmetric move(edge: .leading) → move(edge: .trailing) that
      // exercises the placed-level overlay injection path.
      if showSlideFigure {
        TextFigure("SLIDE", font: .smMono9)
          .foregroundStyle(Color.yellow)
          .transition(.slide)
      }
    }
  }

  // MARK: - Frame size animation

  private var frameSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("3. frame animation via .frame(maxWidth:) under .smooth")
        .foregroundStyle(.muted)
      HStack(spacing: 2) {
        Button("narrow") {
          withAnimation(.smooth(duration: .milliseconds(1500))) {
            wide = false
          }
        }
        Button("wide") {
          withAnimation(.smooth(duration: .milliseconds(1500))) {
            wide = true
          }
        }
      }
      Text(wide ? "◆ wide ◆" : "narrow")
        .foregroundStyle(.foreground)
        .frame(
          maxWidth: .finite(wide ? 40 : 12),
          alignment: .center
        )
    }
  }

  // MARK: - .offset animation via direct state mutation

  private var offsetSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("4. .offset(x:y:) animation via withAnimation state change")
        .foregroundStyle(.muted)
      HStack(spacing: 2) {
        Button("left") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            offsetX = 0
          }
        }
        Button("center") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            offsetX = 15
          }
        }
        Button("right") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            offsetX = 30
          }
        }
        Button("spring") {
          withAnimation(.spring(duration: .milliseconds(1500), bounce: 0.4)) {
            offsetX = offsetX == 0 ? 30 : 0
          }
        }
      }
      Text("▶ slide me")
        .foregroundStyle(Color.magenta)
        .offset(x: offsetX, y: 0)
    }
  }

  // MARK: - .position animation via absolute placement

  private var positionSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("5. .position(x:y:) absolute placement animated via withAnimation")
        .foregroundStyle(.muted)
      HStack(spacing: 2) {
        Button("NW") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            positionX = 10
            positionY = 1
          }
        }
        Button("NE") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            positionX = 50
            positionY = 1
          }
        }
        Button("SW") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            positionX = 10
            positionY = 5
          }
        }
        Button("SE") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            positionX = 50
            positionY = 5
          }
        }
      }
      // The marker gets absolutely positioned inside a fixed-height
      // slot.  Without .frame(height:), .position would expand to
      // fill the full proposed space of the outer VStack, shoving
      // subsequent sections off the screen.
      Text("◎")
        .foregroundStyle(Color.cyan)
        .position(x: positionX, y: positionY)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(height: 7)
  }

  // MARK: - matchedGeometryEffect

  private var matchedGeometrySection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("6. matchedGeometryEffect — hero slides between two slots")
        .foregroundStyle(.muted)
      HStack(spacing: 2) {
        Button(heroOnRight ? "move left" : "move right") {
          withAnimation(.easeInOut(duration: .milliseconds(1500))) {
            heroOnRight.toggle()
          }
        }
      }
      // Two HStack orderings swapped based on state.  The
      // Text("★ hero") is tagged with matchedGeometryEffect(id:in:)
      // scoped to the heroNamespace, so the controller recognizes
      // it as the same view across the swap and animates the
      // translation between the two slots.
      HStack(spacing: 3) {
        if !heroOnRight {
          Text("★ hero")
            .foregroundStyle(Color.yellow)
            .matchedGeometryEffect(id: "hero", in: heroNamespace)
          Text("(empty)")
            .foregroundStyle(.muted)
        } else {
          Text("(empty)")
            .foregroundStyle(.muted)
          Text("★ hero")
            .foregroundStyle(Color.yellow)
            .matchedGeometryEffect(id: "hero", in: heroNamespace)
        }
      }
    }
  }

  // MARK: - PhaseAnimator auto-cycling demo

  private var phaseAnimatorSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("7. PhaseAnimator — auto-cycles through phases on its own")
        .foregroundStyle(.muted)
      PhaseAnimator([PhaseDemoPhase.red, .yellow, .green, .cyan]) { phase in
        Text("●●●●●●●●●●●●●●●●")
          .foregroundStyle(phase.color)
          .offset(x: phase.offsetX, y: 0)
      } animation: { phase in
        switch phase {
        case .red: .linear(duration: .milliseconds(600))
        case .yellow: .easeInOut(duration: .milliseconds(600))
        case .green: .spring(duration: .milliseconds(800), bounce: 0.3)
        case .cyan: .easeInOut(duration: .milliseconds(600))
        }
      }
    }
  }

  // MARK: - withAnimation completion callback

  private var completionSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("8. withAnimation completion callback — fires once per batch drain")
        .foregroundStyle(.muted)
      HStack(spacing: 2) {
        Button("run") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            completionAccent.toggle()
          } completion: {
            // The controller fires this from its tick loop on the
            // main actor; Swift 6 strict concurrency requires an
            // explicit hop since the closure signature is @Sendable.
            MainActor.assumeIsolated {
              completionRuns += 1
            }
          }
        }
      }
      Text("completed runs: \(completionRuns)")
        .foregroundStyle(.separator)
      Text("accent bar:")
        .foregroundStyle(.muted)
      Text("██████████████████████")
        .foregroundStyle(completionAccent ? Color.magenta : Color.green)
    }
  }
}

/// Phase values used by the PhaseAnimator demo section.  Each
/// phase pairs a color with an x-offset so the marker visibly
/// cycles color and position together.
enum PhaseDemoPhase: Equatable, Sendable {
  case red
  case yellow
  case green
  case cyan

  var color: Color {
    switch self {
    case .red: .red
    case .yellow: .yellow
    case .green: .green
    case .cyan: .cyan
    }
  }

  var offsetX: Int {
    switch self {
    case .red: 0
    case .yellow: 10
    case .green: 20
    case .cyan: 10
    }
  }
}
