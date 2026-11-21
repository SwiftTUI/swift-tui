import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Content that emits several views under one custom transition, across
/// frames that do not evaluate the view the transition is on: a sibling that
/// changes by itself, a row that changes by itself, and a row count that
/// crosses between one and two. `TransitionContentBoundaryTests` covers the
/// frames that evaluate everything.
@MainActor
@Suite("Transition content under selective frames", .serialized)
struct TransitionContentSelectiveFrameTests {
  private static let upper = "ABCDEFGHIJKLMNOPQRST"
  private static let lower = "abcdefghijklmnopqrst"
  private static let digits = "01234567890123456789"
  private static let linear = Animation.linear(duration: .milliseconds(800))

  // MARK: - A sibling that changes by itself

  @Test("the values of the body survive a frame that evaluates only a sibling")
  func bodyValuesSurviveASiblingOnlyFrame() throws {
    let ticker = SelectiveTicker()
    let probe = try StagesReviewProbe(named: "sibling-frame-removal") { step, _, _ in
      VStack(alignment: .leading, spacing: 0) {
        SelectiveTickerView(ticker: ticker)
        if step == 0 {
          Group {
            Text(Self.upper)
            Text(Self.lower)
          }
          .transition(SelectiveReveal())
        }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try ticker.bump()
      _ = try probe.harness.render()
      #expect(probe.line(0) == "tick 1", "\(probe.frame)")
      #expect(probe.line(1) == Self.upper, "\(probe.frame)")
      #expect(probe.line(2) == Self.lower, "\(probe.frame)")

      try probe.set(1, animation: Self.linear)
      #expect(probe.activeAnimationCount > 0)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.line(1) == String(Self.upper.prefix(10)), "\(probe.frame)")
      #expect(probe.line(2) == String(Self.lower.prefix(10)), "\(probe.frame)")
      try probe.advance(to: start.advanced(by: .milliseconds(900)))
      #expect(probe.removingCount == 0)
      #expect(probe.line(1) == "", "\(probe.frame)")
    }
  }

  @Test("a clip of the body stays on each view after a frame that evaluates only a sibling")
  func bodyClipSurvivesASiblingOnlyFrame() throws {
    let ticker = SelectiveTicker()
    let probe = try StagesReviewProbe(named: "sibling-frame-rest") { _, _, _ in
      VStack(alignment: .leading, spacing: 0) {
        SelectiveTickerView(ticker: ticker)
        Group {
          Text(Self.upper)
          Text(Self.lower)
        }
        .transition(SelectiveHalf())
      }
    }
    defer { probe.shutdown() }
    #expect(probe.line(1) == String(Self.upper.prefix(10)), "\(probe.frame)")
    #expect(probe.line(2) == String(Self.lower.prefix(10)), "\(probe.frame)")
    try ticker.bump()
    _ = try probe.harness.render()
    #expect(probe.line(0) == "tick 1", "\(probe.frame)")
    #expect(probe.line(1) == String(Self.upper.prefix(10)), "\(probe.frame)")
    #expect(probe.line(2) == String(Self.lower.prefix(10)), "\(probe.frame)")
  }

  // MARK: - A row count that crosses between one and two

  @Test("two rows to one removes only the row that left")
  func twoRowsToOne() throws {
    let probe = try Self.rowsProbe(named: "rows-two-to-one") { step in
      step == 0 ? [Self.upper, Self.lower] : [Self.upper]
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.linear)
      #expect(probe.removingCount == 1)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.line(1) == Self.upper, "\(probe.frame)")
      #expect(probe.line(2) == String(Self.lower.prefix(10)), "\(probe.frame)")
      try probe.advance(to: start.advanced(by: .milliseconds(900)))
      #expect(probe.removingCount == 0)
      #expect(probe.activeAnimationCount == 0)
      #expect(probe.line(1) == Self.upper, "\(probe.frame)")
      #expect(probe.line(2) == "", "\(probe.frame)")
    }
  }

  @Test("one row to two to three inserts only the row that joined")
  func oneRowToThree() throws {
    let probe = try Self.rowsProbe(named: "rows-one-to-three") { step in
      Array([Self.upper, Self.lower, Self.digits].prefix(step + 1))
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.linear)
      try probe.advance(to: start.advanced(by: .milliseconds(900)))
      #expect(probe.activeAnimationCount == 0)
      #expect(probe.line(2) == Self.lower, "\(probe.frame)")

      try probe.set(2, animation: Self.linear, completion: "second")
      #expect(probe.removingCount == 0)
      try probe.advance(to: start.advanced(by: .milliseconds(1300)))
      #expect(probe.removingCount == 0)
      #expect(probe.line(1) == Self.upper, "\(probe.frame)")
      #expect(probe.line(2) == Self.lower, "\(probe.frame)")
      #expect(probe.line(3) == String(Self.digits.prefix(10)), "\(probe.frame)")
      try probe.advance(to: start.advanced(by: .milliseconds(1800)))
      #expect(probe.line(3) == Self.digits, "\(probe.frame)")
    }
  }

  @Test("control: with a built-in transition, two rows to one removes only the row that left")
  func builtInTwoRowsToOne() throws {
    let probe = try StagesReviewProbe(named: "built-in-two-to-one") { step, _, _ in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        ForEach(step == 0 ? [Self.upper, Self.lower] : [Self.upper], id: \.self) { Text($0) }
          .transition(.opacity)
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.linear)
      #expect(probe.removingCount == 1)
      try probe.advance(to: start.advanced(by: .milliseconds(900)))
      #expect(probe.removingCount == 0)
      #expect(probe.line(1) == Self.upper, "\(probe.frame)")
      #expect(probe.line(2) == "", "\(probe.frame)")
    }
  }

  @Test("control: with a built-in transition, a third row joins without a removal")
  func builtInOneRowToThree() throws {
    let probe = try StagesReviewProbe(named: "built-in-one-to-three") { step, _, _ in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        ForEach(Array([Self.upper, Self.lower, Self.digits].prefix(step + 1)), id: \.self) {
          Text($0)
        }
        .transition(.opacity)
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.linear)
      #expect(probe.removingCount == 0)
      try probe.advance(to: start.advanced(by: .milliseconds(900)))
      try probe.set(2, animation: Self.linear, completion: "second")
      #expect(probe.removingCount == 0)
      try probe.advance(to: start.advanced(by: .milliseconds(1800)))
      #expect(probe.line(3) == Self.digits, "\(probe.frame)")
    }
  }

  @Test("after one row became two, a frame that evaluates only a sibling keeps both rows")
  func grownRowsSurviveASiblingOnlyFrame() throws {
    let ticker = SelectiveTicker()
    let probe = try StagesReviewProbe(named: "rows-grown-sibling") { step, _, _ in
      VStack(alignment: .leading, spacing: 0) {
        SelectiveTickerView(ticker: ticker)
        ForEach(step == 0 ? [Self.upper] : [Self.upper, Self.lower], id: \.self) { Text($0) }
          .transition(SelectiveReveal())
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.linear)
      try probe.advance(to: start.advanced(by: .milliseconds(900)))
      #expect(probe.line(1) == Self.upper, "\(probe.frame)")
      #expect(probe.line(2) == Self.lower, "\(probe.frame)")
      try ticker.bump()
      _ = try probe.harness.render()
      #expect(probe.line(0) == "tick 1", "\(probe.frame)")
      #expect(probe.line(1) == Self.upper, "\(probe.frame)")
      #expect(probe.line(2) == Self.lower, "\(probe.frame)")
      #expect(probe.line(3) == "", "\(probe.frame)")
    }
  }

  // MARK: - A row that changes by itself

  @Test("a row that swaps its own view stays, and its sibling still updates")
  func rowThatSwapsItsOwnViewStays() throws {
    let flip = SelectiveTicker()
    let count = SelectiveTicker()
    let probe = try StagesReviewProbe(named: "row-own-swap") { _, _, _ in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        Group {
          SelectiveFlipRow(ticker: flip)
          SelectiveTickerView(ticker: count)
        }
        .transition(SelectiveStill())
      }
    }
    defer { probe.shutdown() }
    #expect(probe.line(1) == "off", "\(probe.frame)")
    #expect(probe.line(2) == "tick 0", "\(probe.frame)")
    try flip.bump()
    _ = try probe.harness.render()
    #expect(probe.line(1) == "ON", "\(probe.frame)")
    #expect(probe.line(2) == "tick 0", "\(probe.frame)")
    try count.bump()
    _ = try probe.harness.render()
    #expect(probe.line(1) == "ON", "\(probe.frame)")
    #expect(probe.line(2) == "tick 1", "\(probe.frame)")
    try flip.bump()
    _ = try probe.harness.render()
    #expect(probe.line(1) == "off", "\(probe.frame)")
    #expect(probe.line(2) == "tick 1", "\(probe.frame)")
  }

  // MARK: - The body, evaluated for each view

  @Test("a body with a stack of its own around a clip animates each view")
  func bodyWithAWrapperAroundAClipAnimatesEachView() throws {
    let probe = try StagesReviewProbe(named: "wrapped-clip-removal") { step, _, _ in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 {
          Group {
            Text(Self.upper)
            Text(Self.lower)
          }
          .transition(SelectiveWrappedReveal())
        }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      #expect(probe.line(1) == Self.upper, "\(probe.frame)")
      #expect(probe.line(2) == Self.lower, "\(probe.frame)")
      try probe.set(1, animation: Self.linear)
      #expect(probe.removingCount == 2)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.line(1) == String(Self.upper.prefix(10)), "\(probe.frame)")
      #expect(probe.line(2) == String(Self.lower.prefix(10)), "\(probe.frame)")
    }
  }

  @Test("a handler the body declares runs for each view")
  func bodyHandlersRunForEachView() throws {
    let probe = try StagesReviewProbe(named: "body-handlers") { _, _, log in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        Group {
          Text(Self.upper)
          Text(Self.lower)
        }
        .transition(SelectiveAppearing(log: log))
      }
    }
    defer { probe.shutdown() }
    #expect(probe.log.completions == ["appear", "appear"], "\(probe.log.completions)")
  }

  @Test("a change to the transition's value reaches each view")
  func changedTransitionValueReachesEachView() throws {
    let probe = try StagesReviewProbe(named: "changed-transition-value") { step, _, _ in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        Group {
          Text(Self.upper)
          Text(Self.lower)
        }
        .transition(SelectiveFraction(fraction: step == 0 ? 0.5 : 0.25))
      }
    }
    defer { probe.shutdown() }
    #expect(probe.line(1) == String(Self.upper.prefix(10)), "\(probe.frame)")
    #expect(probe.line(2) == String(Self.lower.prefix(10)), "\(probe.frame)")
    try probe.set(1, animation: nil)
    #expect(probe.line(1) == String(Self.upper.prefix(5)), "\(probe.frame)")
    #expect(probe.line(2) == String(Self.lower.prefix(5)), "\(probe.frame)")
  }

  @Test("an absent branch among several views takes no transition and no place")
  func absentBranchTakesNoPlace() throws {
    func rows(custom: Bool, shown: Bool) -> [String] {
      stagesReviewRows(
        "absent-branch-\(custom)-\(shown)",
        VStack(alignment: .leading, spacing: 1) {
          Text("TITLE")
          if custom {
            Group {
              if shown { Text(Self.upper) }
              Text(Self.lower)
            }
            .transition(SelectiveBadged())
          } else {
            Group {
              if shown { Text(Self.upper + "!") }
              Text(Self.lower + "!")
            }
          }
          Text("BELOW")
        })
    }
    // The body adds a view beside each view of the content. A branch that is
    // absent has no body around it: nothing is drawn for it and the stack
    // puts no spacing around it.
    #expect(rows(custom: true, shown: true) == rows(custom: false, shown: true))
    #expect(rows(custom: true, shown: false) == rows(custom: false, shown: false))
  }

  @Test("the rows of a list under one transition are the rows it has without one")
  func listRowsKeepTheirPlaces() {
    let plain = stagesReviewRows(
      "list-rows-plain",
      List {
        ForEach([Self.upper, Self.lower, Self.digits], id: \.self) { Text($0) }
      })
    let custom = stagesReviewRows(
      "list-rows-custom",
      List {
        ForEach([Self.upper, Self.lower, Self.digits], id: \.self) { Text($0) }
          .transition(SelectiveStill())
      })
    #expect(custom == plain, "\(custom)")
  }

  // MARK: - Content read from its type

  @Test(
    "a view of a group stays when the view beside it leaves",
    arguments: ["on the group", "on each view"])
  func groupViewStaysWhenItsNeighbourLeaves(placement: String) throws {
    // Two views to one, outside a `ForEach`. Written on the group or on
    // each view, the transition is on each view either way.
    let probe = try StagesReviewProbe(named: "group-two-to-one-\(placement)") { step, _, _ in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if placement == "on the group" {
          Group {
            Text(Self.upper)
            if step == 0 { Text(Self.lower) }
          }
          .transition(SelectiveReveal())
        } else {
          Group {
            Text(Self.upper).transition(SelectiveReveal())
            if step == 0 { Text(Self.lower).transition(SelectiveReveal()) }
          }
        }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.linear)
      #expect(probe.removingCount == 1)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.line(1) == Self.upper, "\(probe.frame)")
      #expect(probe.line(2) == String(Self.lower.prefix(10)), "\(probe.frame)")
      try probe.advance(to: start.advanced(by: .milliseconds(900)))
      #expect(probe.removingCount == 0)
      #expect(probe.line(1) == Self.upper, "\(probe.frame)")
      #expect(probe.line(2) == "", "\(probe.frame)")

      // The view that stayed still has its transition.
      try probe.set(2, animation: Self.linear, completion: "second")
      #expect(probe.line(1) == Self.upper, "\(probe.frame)")
    }
  }

  @Test("a changed transition reaches a view inside a view that could be reused")
  func changedTransitionReachesAReusableView() throws {
    // The first child has two roots and plain values for fields, so a
    // resolve that sees the same value may serve what it resolved before.
    let probe = try StagesReviewProbe(named: "changed-transition-reuse") { step, _, _ in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        Group {
          SelectiveTwoRows(first: Self.upper, second: Self.lower)
          Text(Self.digits)
        }
        .transition(SelectiveFraction(fraction: step == 0 ? 0.5 : 0.25))
      }
    }
    defer { probe.shutdown() }
    #expect(probe.line(1) == String(Self.upper.prefix(10)), "\(probe.frame)")
    try probe.set(1, animation: nil)
    #expect(probe.line(1) == String(Self.upper.prefix(5)), "\(probe.frame)")
    #expect(probe.line(2) == String(Self.lower.prefix(5)), "\(probe.frame)")
    #expect(probe.line(3) == String(Self.digits.prefix(5)), "\(probe.frame)")
  }

  @Test("the views of a loop in a builder each take the transition")
  func loopViewsEachTakeTheTransition() {
    let plain = stagesReviewRows(
      "loop-plain",
      VStack(alignment: .leading, spacing: 0) {
        Group {
          for row in [Self.upper, Self.lower] {
            Text(row)
          }
        }
        Text("BELOW")
      })
    let custom = stagesReviewRows(
      "loop-custom",
      VStack(alignment: .leading, spacing: 0) {
        Group {
          for row in [Self.upper, Self.lower] {
            Text(row)
          }
        }
        .transition(SelectiveStill())
        Text("BELOW")
      })
    #expect(custom == plain, "\(custom)")
  }

  @Test("a view whose body contains its own type resolves under a custom transition")
  func recursiveViewTypeResolves() {
    let rows = stagesReviewRows(
      "recursive-type",
      VStack(alignment: .leading, spacing: 0) {
        SelectiveCountdown(count: 3).transition(SelectiveStill())
        Group {
          SelectiveCountdown(count: 2)
          Text("BELOW")
        }
        .transition(SelectiveStill())
      })
    #expect(Array(rows.prefix(3)) == ["done", "done", "BELOW"], "\(rows)")
  }

  // MARK: - Helpers

  private static func rowsProbe(
    named name: String,
    rows: @escaping (Int) -> [String]
  ) throws -> StagesReviewProbe<AnyView> {
    try StagesReviewProbe(named: name) { step, _, _ in
      AnyView(
        VStack(alignment: .leading, spacing: 0) {
          Text("TITLE")
          ForEach(rows(step), id: \.self) { Text($0) }
            .transition(SelectiveReveal())
        })
    }
  }
}

// MARK: - Fixtures

/// The state of a view that changes by itself, reachable from a test.
@MainActor
private final class SelectiveTicker {
  var binding: Binding<Int>?

  func bump() throws {
    let binding = try #require(binding)
    binding.wrappedValue += 1
  }
}

/// A row that owns a counter and shows it.
private struct SelectiveTickerView: View {
  let ticker: SelectiveTicker
  @State private var count = 0

  var body: some View {
    let _ = capture()
    Text("tick \(count)")
  }

  private func capture() {
    ticker.binding = $count
  }
}

/// A row that owns a flag and shows one of two views for it.
private struct SelectiveFlipRow: View {
  let ticker: SelectiveTicker
  @State private var count = 0

  var body: some View {
    let _ = capture()
    if count % 2 == 1 {
      Text("ON")
    } else {
      Text("off")
    }
  }

  private func capture() {
    ticker.binding = $count
  }
}

private struct SelectiveRevealShape: Shape {
  var fraction: Double

  func path(in rect: Rect) -> Path {
    var path = Path()
    let right = rect.origin.x + rect.size.width * fraction
    let bottom = rect.origin.y + rect.size.height
    path.move(to: Point(x: rect.origin.x, y: rect.origin.y))
    path.addLine(to: Point(x: right, y: rect.origin.y))
    path.addLine(to: Point(x: right, y: bottom))
    path.addLine(to: Point(x: rect.origin.x, y: bottom))
    path.closeSubpath()
    return path
  }
}

/// A clip path that covers the whole view at identity and nothing outside
/// it.
private struct SelectiveReveal: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.clipShape(SelectiveRevealShape(fraction: phase.isIdentity ? 1 : 0))
  }
}

/// A clip path that covers the leading half of the view in every phase.
private struct SelectiveHalf: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.clipShape(SelectiveRevealShape(fraction: 0.5))
  }
}

/// The reveal, inside a stack the body adds.
private struct SelectiveWrappedReveal: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      content.clipShape(SelectiveRevealShape(fraction: phase.isIdentity ? 1 : 0))
    }
  }
}

/// A body that records when its content appears.
private struct SelectiveAppearing: Transition {
  let log: StagesReviewLog

  func body(content: Content, phase: TransitionPhase) -> some View {
    let log = log
    return content.onAppear { log.completions.append("appear") }.opacity(1)
  }
}

/// A clip path that covers a fixed fraction of the view in every phase.
private struct SelectiveFraction: Transition {
  var fraction: Double

  func body(content: Content, phase: TransitionPhase) -> some View {
    content.clipShape(SelectiveRevealShape(fraction: fraction))
  }
}

/// A body that adds a mark after its content.
private struct SelectiveBadged: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    HStack(spacing: 0) {
      content
      Text("!")
    }
  }
}

/// A view whose body has two roots and whose fields are plain values.
private struct SelectiveTwoRows: View {
  let first: String
  let second: String

  var body: some View {
    Text(first)
    Text(second)
  }
}

/// A view whose body is its own type until the count runs out.
private struct SelectiveCountdown: View {
  let count: Int

  var body: some View {
    if count == 0 {
      Text("done")
    } else {
      SelectiveCountdown(count: count - 1)
    }
  }
}

/// A body that changes nothing.
private struct SelectiveStill: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.opacity(1)
  }
}
