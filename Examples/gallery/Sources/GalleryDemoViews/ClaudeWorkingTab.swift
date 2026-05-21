import Foundation
import SwiftTUIRuntime

// MARK: - Public state model
//
// `ClaudeWorkingPanel` is pure render — given a `ClaudeWorkingState` it
// draws one frame.  The Tab below owns a scripted state machine that
// mutates the model over time so the panel animates.  This split keeps
// the panel itself deterministic and snapshot-testable.

/// One subtask shown under the agent's current working header.
public enum ClaudeWorkingItemState: Sendable, Hashable {
  case pending
  case inProgress
  case completed
}

public struct ClaudeWorkingItem: Identifiable, Sendable, Hashable {
  public let id: UUID
  public var title: String
  public var state: ClaudeWorkingItemState

  public init(
    id: UUID = UUID(),
    title: String,
    state: ClaudeWorkingItemState
  ) {
    self.id = id
    self.title = title
    self.state = state
  }
}

/// Direction of token usage shown in the header metadata.
public enum ClaudeTokenDirection: Sendable, Hashable {
  case up
  case down
}

/// Optional trailing phrase printed in yellow after the metadata
/// (e.g. "almost done thinking…" or "thought for 2s").
public enum ClaudeStatusTail: Sendable, Hashable {
  case thinking(remaining: String)
  case thoughtFor(seconds: Int)
}

public struct ClaudeWorkingState: Sendable, Hashable {
  public var title: String
  public var elapsedSeconds: Int
  /// Token count in thousands; `15.4` renders as `15.4k`.
  public var tokensThousands: Double
  public var tokenDirection: ClaudeTokenDirection
  public var statusTail: ClaudeStatusTail?
  /// Subtasks the agent has chosen to surface.  Order matches the
  /// rendered order; the first row gets the `└` tree connector.
  public var items: [ClaudeWorkingItem]
  /// Hidden-item counters used by the summary line.  When both are
  /// zero the summary line is omitted.
  public var hiddenPendingCount: Int
  public var hiddenCompletedCount: Int

  public init(
    title: String,
    elapsedSeconds: Int,
    tokensThousands: Double,
    tokenDirection: ClaudeTokenDirection,
    statusTail: ClaudeStatusTail? = nil,
    items: [ClaudeWorkingItem],
    hiddenPendingCount: Int = 0,
    hiddenCompletedCount: Int = 0
  ) {
    self.title = title
    self.elapsedSeconds = elapsedSeconds
    self.tokensThousands = tokensThousands
    self.tokenDirection = tokenDirection
    self.statusTail = statusTail
    self.items = items
    self.hiddenPendingCount = hiddenPendingCount
    self.hiddenCompletedCount = hiddenCompletedCount
  }
}

// MARK: - Panel — reusable display

/// A faithful TUI reproduction of Claude Code's "working" pane:
/// rotating spinner glyph, shimmering header title, subtask list with
/// per-state markers and strikethrough, and an `… +N` summary line.
///
/// The panel takes a frozen `ClaudeWorkingState`.  The two animations —
/// the spinner glyph rotation and the title shimmer — are driven by
/// platform primitives:
///
/// - `Spinner(.asteriskCycle, interval: …)` owns the glyph cycle and
///   automatically pauses under reduce-motion.
/// - `TimelineView(.animation)` re-evaluates the title's
///   `foregroundStyle(LinearGradient(…))` at the platform's animation
///   cadence, producing a moving highlight across the text without
///   per-character composition.
///
/// Color interpolation between the base coral, mid, and peak shine
/// tones uses `Color.interpolated(to:progress:method:)` from
/// `SwiftTUICore`.
public struct ClaudeWorkingPanel: View {
  public let state: ClaudeWorkingState

  public init(state: ClaudeWorkingState) {
    self.state = state
  }

  // MARK: - Layout

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      headerLine
      ForEach(Array(state.items.enumerated()), id: \.offset) { entry in
        itemRow(item: entry.element, isFirst: entry.offset == 0)
      }
      summaryLine
    }
  }

  // MARK: - Header

  private var headerLine: some View {
    HStack(spacing: 1) {
      Spinner(
        .asteriskCycle,
        stage: .active,
        interval: Self.spinnerInterval
      )
      .foregroundStyle(Self.spinnerColor)
      shimmeringTitle
      metadataText
      if let tail = state.statusTail {
        statusTailText(tail)
      }
      Spacer(minLength: 0)
    }
  }

  // The shimmer is a `LinearGradient` whose stops slide horizontally
  // across the text bounds over time.  Because SwiftTUI's rasterizer
  // samples a `LinearGradient` foregroundStyle at each occupied cell
  // position (see `Rasterizer+ColorResolution.swift` → `.sampled`)
  // there is no per-character composition — the whole title is one
  // `Text` and its bold attribute persists through the gradient fill.
  // Tracks the panel's own "epoch" so the shimmer phase is computed
  // against a stable origin rather than the monotonic clock's absolute
  // value (which is arbitrary across processes).
  @State private var shimmerOrigin: MonotonicInstant = .now()

  private var shimmeringTitle: some View {
    TimelineView(.animation) { context in
      shimmerContent(at: context.instant)
    }
  }

  // Extracted so the closure handed to `TimelineView` is a single
  // expression — Swift's inference for `@ViewBuilder` closures
  // currently struggles when the closure has multiple `let`
  // bindings that produce intermediate non-View values.
  private func shimmerContent(at instant: MonotonicInstant) -> some View {
    let elapsed = shimmerOrigin.duration(to: instant).totalSeconds
    let head = Self.shineHead(for: elapsed)
    let gradient = Self.shineGradient(head: head)
    return HStack(spacing: 0) {
      Text(state.title)
        .bold()
        .foregroundStyle(gradient)
      Text(Self.titleEllipsis)
        .foregroundStyle(Self.titleBase)
    }
  }

  private var metadataText: some View {
    let mins = state.elapsedSeconds / 60
    let secs = state.elapsedSeconds % 60
    let arrow = state.tokenDirection == .down ? "↓" : "↑"
    let tokens = Self.tokenString(thousands: state.tokensThousands)
    let label = "(\(mins)m \(secs)s · \(arrow) \(tokens) tokens)"
    return Text(label).foregroundStyle(.muted)
  }

  private func statusTailText(_ tail: ClaudeStatusTail) -> some View {
    let phrase: String =
      switch tail {
      case .thinking(let remaining):
        "· \(remaining)"
      case .thoughtFor(let seconds):
        "· thought for \(seconds)s"
      }
    return Text(phrase).foregroundStyle(.yellow)
  }

  // MARK: - Items

  private func itemRow(item: ClaudeWorkingItem, isFirst: Bool) -> some View {
    HStack(spacing: 1) {
      // Two-space indent under the spinner.  The first row also
      // shows the `└` tree connector hooking the list under the
      // header; subsequent rows leave that column blank.
      Text("  ")
      Text(isFirst ? "└" : " ").foregroundStyle(.separator)
      itemMarker(for: item.state)
      itemTitle(item)
      Spacer(minLength: 0)
    }
  }

  private func itemMarker(for state: ClaudeWorkingItemState) -> some View {
    switch state {
    case .pending:
      Text("□").foregroundStyle(.foreground)
    case .inProgress:
      Text("■").foregroundStyle(Self.inProgressOrange)
    case .completed:
      Text("✓").foregroundStyle(.green)
    }
  }

  @ViewBuilder
  private func itemTitle(_ item: ClaudeWorkingItem) -> some View {
    switch item.state {
    case .pending:
      Text(item.title).foregroundStyle(.foreground)
    case .inProgress:
      Text(item.title).bold().foregroundStyle(.foreground)
    case .completed:
      Text(item.title)
        .faint()
        .strikethrough()
        .foregroundStyle(.muted)
    }
  }

  // MARK: - Summary

  @ViewBuilder
  private var summaryLine: some View {
    if state.hiddenPendingCount > 0 || state.hiddenCompletedCount > 0 {
      HStack(spacing: 1) {
        Text("    …").foregroundStyle(.separator)
        Text(
          Self.summaryText(
            pending: state.hiddenPendingCount,
            completed: state.hiddenCompletedCount
          )
        )
        .foregroundStyle(.muted)
        Spacer(minLength: 0)
      }
    }
  }

  // MARK: - Animation tuning

  // 240 ms per glyph mirrors the cadence in the spec frames — slow
  // enough that each glyph is legible, fast enough to feel alive.
  private static let spinnerInterval: Duration = .milliseconds(240)

  // One full shimmer pass (off-screen → across → off-screen) per
  // 2.5 s.  Combined with the `TimelineView(.animation)` cadence
  // (~50 ms / 20 fps) this gives roughly 50 frames per traversal.
  private static let shimmerCycleSeconds: Double = 2.5

  /// Returns the normalized horizontal position of the shine center
  /// at time `t`, in the extended range `-0.15 … 1.15`.  Values
  /// outside `0…1` correspond to the shine being off-screen, which
  /// lets the visible cycle start and end smoothly.
  private static func shineHead(for t: Double) -> Double {
    let phase =
      t.truncatingRemainder(dividingBy: shimmerCycleSeconds)
      / shimmerCycleSeconds
    return phase * 1.30 - 0.15
  }

  /// Constructs a 7-stop linear gradient with a moving peak shine.
  /// `Gradient.Stop`'s init clamps each location into `0…1`, so
  /// extended `head` values cleanly fold the shine off-screen
  /// without the caller needing to special-case them.
  private static func shineGradient(head: Double) -> LinearGradient {
    let halfWidth = 0.12
    let stops: [Gradient.Stop] = [
      .init(color: titleBase, location: 0),
      .init(color: titleBase, location: head - halfWidth),
      .init(color: titleMidShine, location: head - halfWidth * 0.5),
      .init(color: titlePeakShine, location: head),
      .init(color: titleMidShine, location: head + halfWidth * 0.5),
      .init(color: titleBase, location: head + halfWidth),
      .init(color: titleBase, location: 1),
    ]
    return LinearGradient(
      gradient: Gradient(stops: stops),
      startPoint: .leading,
      endPoint: .trailing
    )
  }

  // MARK: - Palette
  //
  // Mid and peak shine tones are computed via `Color.interpolated` —
  // a single coral hue in three luminance steps.  This keeps the
  // shimmer palette consistent if the base color is tweaked later.

  private static let titleBase = Color(red: 0.85, green: 0.46, blue: 0.34)
  private static let titleMidShine = titleBase.interpolated(
    to: Color(red: 1.0, green: 1.0, blue: 1.0),
    progress: 0.40
  )
  private static let titlePeakShine = titleBase.interpolated(
    to: Color(red: 1.0, green: 1.0, blue: 1.0),
    progress: 0.85
  )

  // Header spinner glyph color: same base orange as the title.
  private static let spinnerColor = Color(red: 0.93, green: 0.55, blue: 0.40)

  // The in-progress marker uses a slightly stronger orange so the
  // filled square stands out against the white-bold title.
  private static let inProgressOrange = Color(red: 0.90, green: 0.42, blue: 0.30)

  // Trailing dim ellipsis after the title and before the metadata.
  private static let titleEllipsis = "…"

  // MARK: - Static formatters

  private static func tokenString(thousands: Double) -> String {
    // Match the spec's `15.4k` formatting — one decimal place,
    // truncated when the value rounds to a whole number.
    if thousands >= 100 {
      return "\(Int(thousands.rounded()))k"
    }
    let rounded = (thousands * 10).rounded() / 10
    if rounded == rounded.rounded() {
      return "\(Int(rounded))k"
    }
    return String(format: "%.1fk", rounded)
  }

  private static func summaryText(pending: Int, completed: Int) -> String {
    if pending > 0 && completed > 0 {
      return "+\(pending) pending, \(completed) completed"
    }
    if pending > 0 {
      return "+\(pending) pending"
    }
    return "+\(completed) completed"
  }
}

// MARK: - Gallery tab — scripts the demo

struct ClaudeWorkingTab: View {
  // Scenario the tab is currently playing.  Each scenario carries a
  // baked sequence of states; on tick the tab advances to the next
  // frame.
  @State private var stepIndex: Int = 0
  // A running counter so the elapsed display continues to advance
  // even when the script itself sits on the same step.
  @State private var tickCounter: Int = 0

  // The scripted timeline.  Each `Step` is rendered for `holdTicks`
  // before the tab moves on to the next step.
  private struct Step: Sendable {
    let holdTicks: Int
    let state: ClaudeWorkingState
  }

  private static let script: [Step] = ClaudeWorkingTab.makeScript()

  var body: some View {
    let current = currentState

    VStack(alignment: .leading, spacing: 0) {
      // Soft title bar so the tab itself is discoverable.  The
      // panel does not draw its own header outside of the working
      // line, so this keeps the gallery context visible.
      HStack(spacing: 1) {
        Text("Claude working pane")
          .foregroundStyle(.muted)
        Spacer(minLength: 0)
        Text(restartHint).foregroundStyle(.separator)
      }
      .padding(.bottom, 1)

      ClaudeWorkingPanel(state: current)

      Spacer(minLength: 0)
    }
    .padding(2)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task(id: TabTickKey()) {
      // Step the script forward on a 1 s cadence.  The panel itself
      // delegates spinner+shimmer animation to platform primitives.
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard !Task.isCancelled else { return }
        tickCounter &+= 1
        advanceStepIfNeeded()
      }
    }
    .toolbarItem(
      .init(
        title: "Restart demo",
        action: {
          stepIndex = 0
          tickCounter = 0
        }
      )
    )
  }

  private var restartHint: String {
    "Restart demo via toolbar"
  }

  // Stable-ish ID for `.task(id:)`.  We do not actually want the
  // task to restart, so the key is constant.  Using a struct here
  // (rather than `Bool`) makes the intent explicit.
  private struct TabTickKey: Hashable, Sendable {}

  private var currentState: ClaudeWorkingState {
    let bounded = min(stepIndex, Self.script.count - 1)
    var state = Self.script[bounded].state
    // Replace the script's nominal elapsed value with one that
    // ticks live, so the seconds display keeps moving even while
    // the script holds on a single step.
    state.elapsedSeconds = state.elapsedSeconds + tickCounter
    return state
  }

  private func advanceStepIfNeeded() {
    // Each step has a `holdTicks` budget.  The script index is the
    // index of the step currently being displayed; we accumulate
    // tickCounter against a running threshold computed from the
    // prior steps.  This re-computation is intentionally cheap —
    // the script is short.
    var threshold = 0
    for (idx, step) in Self.script.enumerated() {
      threshold += step.holdTicks
      if tickCounter < threshold {
        stepIndex = idx
        return
      }
    }
    stepIndex = Self.script.count - 1
  }

  private static func makeScript() -> [Step] {
    let specSelfReview = UUID()
    let writeDesignDoc = UUID()
    let transitionToImpl = UUID()
    let implChunk1 = UUID()
    let implChunk2 = UUID()
    let implChunk3 = UUID()
    let exploreContext = UUID()
    let askClarifying = UUID()

    func item(
      _ id: UUID,
      _ title: String,
      _ state: ClaudeWorkingItemState
    ) -> ClaudeWorkingItem {
      ClaudeWorkingItem(id: id, title: title, state: state)
    }

    // Step 1: write design doc is the active subtask, three hidden
    // completed items behind it.  Mirrors frame_0014.
    let step1 = ClaudeWorkingState(
      title: "Write design doc",
      elapsedSeconds: 225,  // 3m 45s
      tokensThousands: 15.4,
      tokenDirection: .down,
      statusTail: nil,
      items: [
        item(specSelfReview, "Spec self-review and user review", .completed),
        item(writeDesignDoc, "Write design doc", .inProgress),
        item(transitionToImpl, "Transition to implementation", .pending),
        item(exploreContext, "Explore project context", .completed),
        item(askClarifying, "Ask clarifying questions", .completed),
      ],
      hiddenPendingCount: 0,
      hiddenCompletedCount: 2
    )

    // Step 2: implementation chunk 1 has started.  Mirrors
    // frame_0148.
    let step2 = ClaudeWorkingState(
      title: "Write design doc",
      elapsedSeconds: 228,
      tokensThousands: 15.5,
      tokenDirection: .down,
      statusTail: nil,
      items: [
        item(specSelfReview, "Spec self-review and user review", .completed),
        item(writeDesignDoc, "Write design doc", .inProgress),
        item(implChunk1, "Implement chunk 1: engine surface", .inProgress),
        item(exploreContext, "Explore project context", .completed),
        item(askClarifying, "Ask clarifying questions", .completed),
      ],
      hiddenPendingCount: 0,
      hiddenCompletedCount: 2
    )

    // Step 3: chunk 2 enqueued.  Mirrors frame_0174.
    let step3 = ClaudeWorkingState(
      title: "Write design doc",
      elapsedSeconds: 228,
      tokensThousands: 15.5,
      tokenDirection: .down,
      statusTail: nil,
      items: [
        item(specSelfReview, "Spec self-review and user review", .completed),
        item(writeDesignDoc, "Write design doc", .inProgress),
        item(implChunk1, "Implement chunk 1: engine surface", .inProgress),
        item(implChunk2, "Implement chunk 2: macOS adapter", .pending),
        item(exploreContext, "Explore project context", .completed),
      ],
      hiddenPendingCount: 0,
      hiddenCompletedCount: 3
    )

    // Step 4: chunk 3 enqueued.  Mirrors frame_0229.
    let step4 = ClaudeWorkingState(
      title: "Write design doc",
      elapsedSeconds: 230,
      tokensThousands: 15.6,
      tokenDirection: .down,
      statusTail: nil,
      items: [
        item(specSelfReview, "Spec self-review and user review", .completed),
        item(writeDesignDoc, "Write design doc", .inProgress),
        item(implChunk1, "Implement chunk 1: engine surface", .inProgress),
        item(implChunk2, "Implement chunk 2: macOS adapter", .pending),
        item(implChunk3, "Implement chunk 3: iOS adapter + motion", .pending),
      ],
      hiddenPendingCount: 0,
      hiddenCompletedCount: 4
    )

    // Step 5: hidden counts split between pending and completed.
    // Mirrors frame_0376.
    var step5 = step4
    step5.elapsedSeconds = 232
    step5.tokensThousands = 15.9
    step5.tokenDirection = .up
    step5.hiddenPendingCount = 2

    // Step 6: yellow status tail appears.  Mirrors frame_0449.
    var step6 = step5
    step6.elapsedSeconds = 234
    step6.tokensThousands = 16.2
    step6.tokenDirection = .down
    step6.statusTail = .thinking(remaining: "almost done thinking…")

    // Step 7: thought-for confirmation.  Mirrors frame_0558.
    var step7 = step6
    step7.elapsedSeconds = 236
    step7.tokensThousands = 16.4
    step7.statusTail = .thoughtFor(seconds: 2)

    return [
      Step(holdTicks: 3, state: step1),
      Step(holdTicks: 3, state: step2),
      Step(holdTicks: 3, state: step3),
      Step(holdTicks: 3, state: step4),
      Step(holdTicks: 4, state: step5),
      Step(holdTicks: 4, state: step6),
      Step(holdTicks: 6, state: step7),
    ]
  }
}
