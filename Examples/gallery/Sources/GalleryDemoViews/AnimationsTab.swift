import TerminalUI

/// Showcases the animation features that landed in the 2026-04-10
/// gap-closure pass.  Each section exercises a distinct capability
/// — spring/bezier curves, repeat behaviors, opacity + move
/// transitions, frame animation, and withAnimation completion
/// callbacks — so the gallery doubles as a visual smoke test.
struct AnimationsTab: View {
  @State private var colorDemo: ColorDemoState = .init()
  @State private var transitionDemo: TransitionDemoState = .init()
  @State private var frameDemo: FrameDemoState = .init()
  @State private var completionDemo: CompletionDemoState = .init()

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
      completionSection
      Spacer(minLength: 0)
    }
    .padding(1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Animations").foregroundStyle(.foreground)
      Text("Exercise every feature from the 2026-04-10 gap-closure pass.")
        .foregroundStyle(.separator)
    }
  }

  // MARK: - Color animation with spring / bezier / bouncy curves

  private var colorSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("withAnimation color").foregroundStyle(.muted)
      HStack(spacing: 1) {
        Text("■■■■■■■■■■")
          .foregroundStyle(colorDemo.color)
        Text(colorDemo.curveLabel)
          .foregroundStyle(.separator)
      }
      HStack(spacing: 1) {
        Button("linear") {
          withAnimation(.linear(duration: .milliseconds(400))) {
            colorDemo.advance(curveLabel: "linear")
          }
        }
        Button("easeInOut") {
          withAnimation(.easeInOut(duration: .milliseconds(400))) {
            colorDemo.advance(curveLabel: "easeInOut")
          }
        }
        Button("spring") {
          withAnimation(.spring(duration: .milliseconds(500), bounce: 0.2)) {
            colorDemo.advance(curveLabel: "spring")
          }
        }
        Button("bouncy") {
          withAnimation(.bouncy) {
            colorDemo.advance(curveLabel: "bouncy")
          }
        }
      }
    }
  }

  // MARK: - Opacity + move transitions

  private var transitionSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(".transition(...) insertion & removal")
        .foregroundStyle(.muted)
      HStack(spacing: 2) {
        Button(transitionDemo.showOpacity ? "hide opacity" : "show opacity") {
          withAnimation(.easeInOut(duration: .milliseconds(350))) {
            transitionDemo.showOpacity.toggle()
          }
        }
        Button(transitionDemo.showSlide ? "hide slide" : "show slide") {
          withAnimation(.easeInOut(duration: .milliseconds(350))) {
            transitionDemo.showSlide.toggle()
          }
        }
      }
      // Opacity transition — fades in/out via pre-composited color.
      if transitionDemo.showOpacity {
        Text("fade target")
          .foregroundStyle(.tint)
          .padding(1)
          .transition(.opacity)
      }
      // Move transition — slides in from the leading edge and out
      // to the trailing edge.  This uses the new wrapping path for
      // padded roots so sibling layout does not shift.
      if transitionDemo.showSlide {
        Text("slide target")
          .foregroundStyle(.tint)
          .padding(1)
          .transition(.slide)
      }
    }
  }

  // MARK: - Frame size animation

  private var frameSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("frame animation via .flexibleFrame(maxWidth:)")
        .foregroundStyle(.muted)
      HStack(spacing: 2) {
        Button("narrow") {
          withAnimation(.smooth(duration: .milliseconds(500))) {
            frameDemo.wide = false
          }
        }
        Button("wide") {
          withAnimation(.smooth(duration: .milliseconds(500))) {
            frameDemo.wide = true
          }
        }
      }
      Text(frameDemo.wide ? "◆ wide ◆" : "narrow")
        .foregroundStyle(.foreground)
        .frame(
          maxWidth: .finite(frameDemo.wide ? 40 : 12),
          alignment: .center
        )
    }
  }

  // MARK: - withAnimation completion callback

  private var completionSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("withAnimation completion callback")
        .foregroundStyle(.muted)
      HStack(spacing: 2) {
        Button("run") {
          let target = completionDemo.current == .a ? CompletionDemoState.Tone.b : .a
          withAnimation(.easeInOut(duration: .milliseconds(400))) {
            completionDemo.current = target
          } completion: {
            // The completion closure is fired from the animation
            // controller's tick loop which is already on the main
            // actor; hop into it explicitly so Swift 6 strict
            // concurrency is happy.
            MainActor.assumeIsolated {
              completionDemo.finishedRuns += 1
            }
          }
        }
      }
      Text("finished runs: \(completionDemo.finishedRuns)")
        .foregroundStyle(.separator)
      Text("current tone")
        .foregroundStyle(completionDemo.current.color)
    }
  }
}

// MARK: - Local state types

extension AnimationsTab {
  struct ColorDemoState: Equatable {
    var color: Color = .red
    var curveLabel: String = "(tap a curve)"

    mutating func advance(curveLabel: String) {
      color = color.rotatedHue(by: 60)
      self.curveLabel = curveLabel
    }
  }

  struct TransitionDemoState: Equatable {
    var showOpacity: Bool = true
    var showSlide: Bool = false
  }

  struct FrameDemoState: Equatable {
    var wide: Bool = false
  }

  struct CompletionDemoState: Equatable {
    enum Tone: Equatable {
      case a
      case b

      var color: Color {
        switch self {
        case .a: .cyan
        case .b: .yellow
        }
      }
    }
    var current: Tone = .a
    var finishedRuns: Int = 0
  }
}
