import SwiftTUICore

/// An animated activity indicator.
///
/// The spinner's glyph frames, cadence, and paint come from the nearest
/// `spinnerStyle(_:)` environment value; the primitive owns the animation
/// task, iteration state, cancellation identity, stage semantics, and
/// reduced-motion behavior. Custom frame sequences use `GlyphSpinnerStyle`.
public struct Spinner: View {
  public init(stage: Stage = .active) {
    self.stage = stage
  }

  let stage: Stage
  @State var iteration: Int = 0

  public var body: some View {
    EnvironmentReader(\.spinnerStyle) { spinnerStyle in
      EnvironmentReader(\.accessibilityReduceMotion) { accessibilityReduceMotion in
        EnvironmentReader(\.styleEnvironmentSnapshot) { styleEnvironment in
          spinnerBody(
            presentation: resolvedPresentation(
              style: spinnerStyle,
              accessibilityReduceMotion: accessibilityReduceMotion,
              styleEnvironment: styleEnvironment
            ),
            accessibilityReduceMotion: accessibilityReduceMotion
          )
        }
      }
    }
  }

  @MainActor
  private func resolvedPresentation(
    style: AnySpinnerStyle,
    accessibilityReduceMotion: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) -> SpinnerStylePresentation {
    let presentation = style.presentation(
      for: SpinnerStyleConfiguration(
        stage: stage,
        accessibilityReduceMotion: accessibilityReduceMotion,
        styleEnvironment: styleEnvironment
      )
    )
    var problems: [String] = []
    if presentation.activeFrames.isEmpty {
      problems.append("active frames are empty")
    }
    if presentation.interval <= .zero {
      problems.append("interval is not positive")
    }
    let frameWidths = Set(presentation.activeFrames.map(Self.frameCellWidth(of:)))
    if frameWidths.count > 1 {
      problems.append("active frames mix terminal-cell widths \(frameWidths.sorted())")
    }
    return StyleMisuse.validatedPresentation(
      presentation,
      problems: problems,
      family: "SpinnerStyle",
      styleLabel: style.description,
      identity: nil,
      report: { issue in
        // The spinner body resolves in composed (non-primitive) context, so
        // the issue rides the imperative queue and surfaces at the next
        // frame head — the `forEach.staleElementBindingWrite` route.
        ImperativeRuntimeIssueQueue.record(issue)
      },
      fallback: {
        AnySpinnerStyle.automatic.presentation(
          for: SpinnerStyleConfiguration(
            stage: stage,
            accessibilityReduceMotion: accessibilityReduceMotion,
            styleEnvironment: styleEnvironment
          )
        )
      }
    )
  }

  private static func frameCellWidth(of frame: String) -> Int {
    frame.reduce(0) { width, character in
      width + cellWidth(of: character)
    }
  }

  @ViewBuilder
  private func spinnerBody(
    presentation: SpinnerStylePresentation,
    accessibilityReduceMotion: Bool
  ) -> some View {
    if accessibilityReduceMotion {
      spinnerText(presentation: presentation, accessibilityReduceMotion: true)
    } else {
      spinnerText(presentation: presentation, accessibilityReduceMotion: false)
        .task(
          id: SpinnerTaskKey(
            activeFrames: presentation.activeFrames,
            stage: stage,
            interval: presentation.interval
          )
        ) {
          switch stage {
          case .active:
            while !Task.isCancelled {
              try? await Task.sleep(for: presentation.interval)
              let max = presentation.activeFrames.count
              var newIteration = iteration + 1
              newIteration %= max
              iteration = newIteration
            }
          case .finished, .inactive:
            break
          }
        }
    }
  }

  @ViewBuilder
  private func spinnerText(
    presentation: SpinnerStylePresentation,
    accessibilityReduceMotion: Bool
  ) -> some View {
    Group {
      switch stage {
      case .active:
        if accessibilityReduceMotion {
          Text(presentation.activeFrames.first ?? presentation.inactiveFrame)
        } else {
          Text(
            presentation.activeFrames[safe: iteration]
              ?? presentation.activeFrames.first
              ?? presentation.inactiveFrame
          )
        }
      case .finished:
        Text(presentation.finishedFrame)
      case .inactive:
        Text(presentation.inactiveFrame)
      }
    }
    .modifier(SpinnerForegroundModifier(foregroundStyle: presentation.foregroundStyle))
  }

  public enum Stage: Hashable, Sendable, CustomStringConvertible {
    case inactive
    case active
    case finished
    public var description: String {
      switch self {
      case .inactive: "inactive"
      case .active: "active"
      case .finished: "finished"
      }
    }
  }
}

/// Applies the presentation's paint only when one was resolved, so the
/// default (`nil`) path inherits the ambient foreground without adding a
/// styling node.
private struct SpinnerForegroundModifier: ViewModifier, Sendable {
  let foregroundStyle: AnyShapeStyle?

  func body(content: Content) -> some View {
    if let foregroundStyle {
      content.foregroundStyle(foregroundStyle)
    } else {
      content
    }
  }
}

/// Composite key used to drive the spinner's `.task(id:)` cancellation.
///
/// The resolved active frame sequence, the stage, and the cadence
/// participate, so changing any of them cancels the old tick loop cleanly.
/// Presentation paint deliberately does not participate — a theme or
/// contrast change restyles the glyph without resetting the spinner's
/// phase — and replacing the style with one that resolves to the same
/// frames, cadence, and stage does not restart the loop.
private struct SpinnerTaskKey: Hashable, Sendable {
  let activeFrames: [String]
  let stage: Spinner.Stage
  let interval: Duration
}

extension Array {
  subscript(safe safe: Int) -> Element? {
    if safe < self.count {
      self[safe]
    } else {
      nil
    }
  }
}
