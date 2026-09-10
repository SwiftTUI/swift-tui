import SwiftTUICore

/// An animated activity indicator.
///
/// The spinner's glyph frames, cadence, and paint come from the nearest
/// `spinnerStyle(_:)` environment value; the primitive owns the animation
/// task, iteration state, cancellation identity, stage semantics, and
/// reduced-motion behavior. Custom frame sequences use `GlyphSpinnerStyle`.
///
/// An invalid presentation (empty active frames, a non-positive cadence,
/// frames of mixed cell width) renders the automatic presentation instead and
/// reports one `style.invalidPresentation` issue per spinner and issue text:
/// the fallback keeps animating, and each tick re-validates the same style,
/// so the report repeats only when the style value changes.
public struct Spinner: View {
  public init(stage: Stage = .active) {
    self.stage = stage
  }

  let stage: Stage
  @State var iteration: Int = 0

  public var body: some View {
    // The spinner's own node, captured here: a tick invalidation re-runs
    // only the innermost environment closure, whose current node is a
    // descendant, and the reported-issue record must live on one node.
    let owner = ViewNodeContext.current
    return EnvironmentReader(\.spinnerStyle) { spinnerStyle in
      EnvironmentReader(\.renderingReduceMotion) { accessibilityReduceMotion in
        EnvironmentReader(\.styleEnvironmentSnapshot) { styleEnvironment in
          spinnerBody(
            presentation: resolvedPresentation(
              style: spinnerStyle,
              accessibilityReduceMotion: accessibilityReduceMotion,
              styleEnvironment: styleEnvironment,
              owner: owner
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
    styleEnvironment: StyleEnvironmentSnapshot,
    owner: SwiftTUICore.ViewNode?
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
    if problems.isEmpty {
      // A valid style clears the record, so a later regression to the same
      // invalid style is a style change and reports again.
      Self.setReportedInvalidPresentation(nil, on: owner)
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
        // frame head — the `forEach.staleElementBindingWrite` route. That
        // queue dedupes only until the frame drains, while the automatic
        // fallback keeps ticking and every tick re-validates this style, so
        // the node remembers the issue it last reported and reports once
        // per spinner and issue text until the style value changes.
        guard Self.reportedInvalidPresentation(on: owner) != issue.message else {
          return
        }
        Self.setReportedInvalidPresentation(issue.message, on: owner)
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

  /// Framework-reserved slot ordinal on the spinner's node, in the negative
  /// range `StateSlotOrdinals` hands out (`menuExpansion` is -12_000_000):
  /// the issue text last reported for an invalid presentation, or `nil`.
  private static let reportedInvalidPresentationOrdinal = -13_000_000

  /// The slot is materialized only once a report happens, so a spinner with
  /// a valid style hosts no extra state.
  @MainActor
  private static func reportedInvalidPresentation(
    on owner: SwiftTUICore.ViewNode?
  ) -> String? {
    guard let owner, owner.hasStateSlot(ordinal: reportedInvalidPresentationOrdinal) else {
      return nil
    }
    return owner.primedStateSlot(ordinal: reportedInvalidPresentationOrdinal, seed: nil as String?)
  }

  /// Silent by design: the record is resolve-time bookkeeping, and an
  /// invalidating write from inside the body would schedule a needless frame.
  @MainActor
  private static func setReportedInvalidPresentation(
    _ message: String?,
    on owner: SwiftTUICore.ViewNode?
  ) {
    guard let owner, reportedInvalidPresentation(on: owner) != message else {
      return
    }
    owner.setStateSlotSilently(ordinal: reportedInvalidPresentationOrdinal, value: message)
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
              try? await SpinnerTaskClock.sleep(presentation.interval)
              guard !Task.isCancelled else { return }
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

/// Task-scoped cadence dependency; production uses the continuous clock.
package enum SpinnerTaskClock {
  /// The cadence dependency as a nominal type. A task-local whose value type
  /// is an `async` function type crashed release builds inside
  /// `swift_task_localValuePush` with null value-type metadata (Swift 6.3.3,
  /// macOS and Linux); a struct's metadata is static, so the binding is sound.
  package struct Sleep: Sendable {
    private let sleep: @Sendable (Duration) async throws -> Void

    package init(_ sleep: @escaping @Sendable (Duration) async throws -> Void) {
      self.sleep = sleep
    }

    package func callAsFunction(_ duration: Duration) async throws {
      try await sleep(duration)
    }
  }

  @TaskLocal package static var sleep = Sleep { duration in
    try await Task.sleep(for: duration)
  }

  /// Binds `sleep` around the synchronous `operation`, so a task started
  /// inside it inherits the binding. Tests bind through here.
  package static func withSleep(_ sleep: Sleep, perform operation: () throws -> Void) rethrows {
    try $sleep.withValue(sleep, operation: operation)
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
