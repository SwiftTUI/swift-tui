import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// The failing tests of the review of transition stages 2, 3 and 4a at
/// swift-tui 0.23.0 (root repository,
/// docs/reports/2026-11-21-transition-stages-review.md). Each test states the
/// behaviour the design promises. Every test here fails at 0.23.0 except the
/// two named controls, which pass and show that the scenario itself is sound.
@MainActor
@Suite("Transition stages review", .serialized)
struct TransitionStagesReviewTests {
  private static let letters = "ABCDEFGHIJKLMNOPQRST"
  private static let linear = Animation.linear(duration: .milliseconds(800))

  // MARK: - Finding 1: a transition inside the content of a custom body

  @Test("control: a custom body on a container removes through its body")
  func outerBodyPlaysWithoutAnInnerTransition() throws {
    let probe = try StagesReviewProbe(named: "outer-alone") { step, _, _ in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 {
          HStack(spacing: 0) { Text(Self.letters) }
            .transition(StagesReviewReveal())
        }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.linear)
      #expect(probe.removingCount == 1)
      #expect(probe.activeAnimationCount == 2)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.line(1) == String(Self.letters.prefix(10)), "\(probe.frame)")
    }
  }

  @Test("a transition on a view inside the content does not end the body's removal")
  func innerTransitionLeavesTheOuterBodyAnimating() throws {
    // The removals of one frame are planned in the order of a `Set` of node
    // ids, which differs from one tree to the next. Twelve trees see both
    // orders.
    var animating: [Int] = []
    var shown: [String] = []
    for round in 0..<12 {
      let probe = try StagesReviewProbe(named: "inner-\(round)") { step, _, _ in
        VStack(alignment: .leading, spacing: 0) {
          Text("TITLE")
          if step == 0 {
            HStack(spacing: 0) { Text(Self.letters).transition(.opacity) }
              .transition(StagesReviewReveal())
          }
        }
      }
      defer { probe.shutdown() }
      try probe.run { start in
        try probe.set(1, animation: Self.linear)
        animating.append(probe.activeAnimationCount)
        try probe.advance(to: start.advanced(by: .milliseconds(400)))
        shown.append(probe.line(1))
      }
    }
    // The body's clip path and its opacity animate toward the didDisappear
    // phase in every tree, whichever removal was planned first.
    #expect(Set(animating).count == 1, "the result depends on the planning order: \(animating)")
    #expect(animating.allSatisfy { $0 == 2 }, "\(animating)")
    // Half way, the clip path has uncovered half of the text.
    #expect(shown.allSatisfy { $0 == String(Self.letters.prefix(10)) }, "\(shown)")
  }

  // MARK: - Finding 2: a shape field outside its animatable data

  @Test(
    "a field the data does not cover takes effect while the data animates",
    arguments: ["fill", "clipShape"])
  func shapeFieldChangesWhileItsDataAnimates(use: String) throws {
    let log = StagesReviewLog()
    let probe = try StagesReviewProbe(
      named: "shape-field-\(use)", size: .init(width: 24, height: 4), log: log
    ) { step, value, log in
      VStack(alignment: .leading, spacing: 0) {
        if use == "fill" {
          StagesReviewWedge(fraction: value, fromTrailing: step == 1, log: log)
            .fill(Color.white).frame(width: 20, height: 1)
        } else {
          Text(String(repeating: "X", count: 20))
            .clipShape(StagesReviewWedge(fraction: value, fromTrailing: step == 1, log: log))
        }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      // The wedge grows from the leading edge.
      try probe.setValue(1, animation: Self.linear)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.line(0).count == 10, "\(probe.frame)")
      #expect(log.fields.allSatisfy { $0 == "leading" })

      // A plain write moves the wedge to the trailing edge. The data, and
      // its animation, are untouched.
      let before = log.fields.count
      try probe.set(1, animation: nil)
      try probe.advance(to: start.advanced(by: .milliseconds(600)))
      #expect(probe.activeAnimationCount == 1)
      // Every sample from the write on is drawn by the shape as it is now.
      let later = Array(log.fields[before...])
      #expect(!later.isEmpty)
      #expect(later.allSatisfy { $0 == "trailing" }, "\(later)")
      // Three quarters of the row, up to its trailing edge.
      #expect(probe.line(0).count == 20, "\(probe.frame)")
      #expect(probe.line(0).hasPrefix("     "), "\(probe.frame)")
    }
  }

  // MARK: - Finding 3: content that emits several views

  @Test(
    "content that emits several views is laid out under a custom transition as it is without one",
    arguments: ["group", "forEach", "view with two roots"])
  func severalContentViewsKeepTheirLayout(shape: String) {
    @ViewBuilder func content() -> some View {
      switch shape {
      case "group":
        Group {
          Text("FIRST-FIRST")
          Text("SECOND")
        }
      case "forEach":
        ForEach(0..<3, id: \.self) { Text("row \($0)") }
      default:
        StagesReviewPair()
      }
    }
    let plain = stagesReviewRows(
      "several-plain-\(shape)",
      VStack(alignment: .leading, spacing: 0) {
        content()
        Text("BELOW")
      })
    let builtIn = stagesReviewRows(
      "several-built-in-\(shape)",
      VStack(alignment: .leading, spacing: 0) {
        content().transition(.opacity)
        Text("BELOW")
      })
    let custom = stagesReviewRows(
      "several-custom-\(shape)",
      VStack(alignment: .leading, spacing: 0) {
        content().transition(StagesReviewDim())
        Text("BELOW")
      })
    #expect(builtIn == plain)
    #expect(custom == plain, "\(custom)")
  }

  // MARK: - Finding 4: the layout role of the content

  @Test("control: a flexible frame keeps its width under a custom transition")
  func flexibleFrameKeepsItsWidth() {
    let builtIn = stagesReviewRows(
      "flexible-built-in",
      HStack(spacing: 0) {
        Text("L")
        Text("MID").frame(maxWidth: .infinity).transition(.opacity)
        Text("R")
      })
    let custom = stagesReviewRows(
      "flexible-custom",
      HStack(spacing: 0) {
        Text("L")
        Text("MID").frame(maxWidth: .infinity).transition(StagesReviewDim())
        Text("R")
      })
    #expect(custom == builtIn, "\(custom)")
  }

  @Test("a layout priority is honoured under a custom transition")
  func layoutPriorityPassesThroughACustomTransition() {
    let a = String(repeating: "a", count: 20)
    let b = String(repeating: "b", count: 20)
    let plain = stagesReviewRows(
      "priority-plain",
      HStack(spacing: 0) {
        Text(a)
        Text(b).layoutPriority(1)
      })
    let builtIn = stagesReviewRows(
      "priority-built-in",
      HStack(spacing: 0) {
        Text(a)
        Text(b).layoutPriority(1).transition(.opacity)
      })
    let custom = stagesReviewRows(
      "priority-custom",
      HStack(spacing: 0) {
        Text(a)
        Text(b).layoutPriority(1).transition(StagesReviewDim())
      })
    #expect(builtIn == plain)
    #expect(custom == plain, "\(custom)")
  }

  @Test("a spacer expands under a custom transition")
  func spacerExpandsUnderACustomTransition() {
    let plain = stagesReviewRows(
      "spacer-plain",
      HStack(spacing: 0) {
        Text("L")
        Spacer()
        Text("R")
      })
    let builtIn = stagesReviewRows(
      "spacer-built-in",
      HStack(spacing: 0) {
        Text("L")
        Spacer().transition(.opacity)
        Text("R")
      })
    let custom = stagesReviewRows(
      "spacer-custom",
      HStack(spacing: 0) {
        Text("L")
        Spacer().transition(StagesReviewDim())
        Text("R")
      })
    #expect(builtIn == plain)
    #expect(custom == plain, "\(custom)")
  }
}

// MARK: - Fixtures

/// A rectangle covering `fraction` of the width. Every fraction has the same
/// element topology, so two of them interpolate.
private struct StagesReviewRevealShape: Shape {
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

/// An interpolable body: a clip path that covers the whole view at identity
/// and nothing outside it, and an opacity.
private struct StagesReviewReveal: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .clipShape(StagesReviewRevealShape(fraction: phase.isIdentity ? 1 : 0))
      .opacity(phase.isIdentity ? 1 : 0.2)
  }
}

/// An opacity from one to zero.
private struct StagesReviewDim: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.opacity(phase.isIdentity ? 1 : 0)
  }
}

/// A view whose body has two roots.
private struct StagesReviewPair: View {
  var body: some View {
    Text("FIRST-FIRST")
    Text("SECOND")
  }
}

/// A rectangle that covers `fraction` of its width, from the leading edge or
/// from the trailing one. The fraction is its animatable data; the edge is
/// not.
private struct StagesReviewWedge: Shape, Animatable {
  var fraction: Double
  var fromTrailing = false
  let log: StagesReviewLog

  nonisolated var animatableData: Double {
    get { fraction }
    set { fraction = newValue }
  }

  func path(in rect: Rect) -> Path {
    log.values.append(fraction)
    log.fields.append(fromTrailing ? "trailing" : "leading")
    let width = rect.size.width * fraction
    let left = fromTrailing ? rect.origin.x + rect.size.width - width : rect.origin.x
    let bottom = rect.origin.y + rect.size.height
    var path = Path()
    path.move(to: Point(x: left, y: rect.origin.y))
    path.addLine(to: Point(x: left + width, y: rect.origin.y))
    path.addLine(to: Point(x: left + width, y: bottom))
    path.addLine(to: Point(x: left, y: bottom))
    path.closeSubpath()
    return path
  }
}
