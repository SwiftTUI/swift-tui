import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// A field of an `Animatable` shape that its `animatableData` does not cover
/// takes effect while the data animates (STUI-1577), under every modifier
/// that draws a shape and for the wrappers a shape can carry.
/// `TransitionStagesReviewTests` holds the `fill` and `clipShape` cases of
/// the review; these are the ones it named and did not run.
@MainActor
@Suite("Animatable shape field change", .serialized)
struct AnimatableShapeFieldChangeTests {
  private static let linear = Animation.linear(duration: .milliseconds(800))
  private static let size = CellSize(width: 24, height: 5)

  /// The wedge drawn in the way `use` names. `changed` flips the field the
  /// data does not cover: the edge the wedge grows from, or for the two
  /// wrappers the trim and the inset.
  @ViewBuilder
  private static func drawing(
    _ use: String,
    fraction: Double,
    changed: Bool,
    log: StagesReviewLog
  ) -> some View {
    switch use {
    case "stroke":
      FieldWedge(fraction: fraction, fromTrailing: changed, log: log)
        .stroke(Color.white).frame(width: 20, height: 3)
    case "strokeBorder":
      FieldWedge(fraction: fraction, fromTrailing: changed, log: log)
        .strokeBorder(Color.white).frame(width: 20, height: 3)
    case "trim":
      FieldWedge(fraction: fraction, log: log)
        .trim(from: 0, to: changed ? 0.5 : 1)
        .stroke(Color.white).frame(width: 20, height: 3)
    default:
      FieldWedge(fraction: fraction, log: log)
        .inset(by: changed ? 1 : 0)
        .fill(Color.white).frame(width: 20, height: 3)
    }
  }

  @Test(
    "a field the data does not cover takes effect while the data animates",
    arguments: ["stroke", "strokeBorder", "trim", "inset"])
  func fieldTakesEffectWhileTheDataAnimates(use: String) throws {
    let log = StagesReviewLog()
    let animated = try StagesReviewProbe(
      named: "shape-field-change-\(use)", size: Self.size, log: log
    ) { step, value, log in
      VStack(alignment: .leading, spacing: 0) {
        Self.drawing(use, fraction: value, changed: step == 1, log: log)
      }
    }
    defer { animated.shutdown() }
    // The same shape at rest, with the changed field and the data the
    // animation shows three quarters of the way.
    let atRest = try StagesReviewProbe(
      named: "shape-field-rest-\(use)", size: Self.size
    ) { _, _, log in
      VStack(alignment: .leading, spacing: 0) {
        Self.drawing(use, fraction: 0.75, changed: true, log: log)
      }
    }
    defer { atRest.shutdown() }
    let unchanged = try StagesReviewProbe(
      named: "shape-field-unchanged-\(use)", size: Self.size
    ) { _, _, log in
      VStack(alignment: .leading, spacing: 0) {
        Self.drawing(use, fraction: 0.75, changed: false, log: log)
      }
    }
    defer { unchanged.shutdown() }
    // The field shows: the two at-rest frames differ.
    #expect(atRest.frame != unchanged.frame, "\(atRest.frame)")

    try animated.run { start in
      try animated.setValue(1, animation: Self.linear)
      try animated.advance(to: start.advanced(by: .milliseconds(400)))
      let before = log.fields.count

      // A plain write changes the field. The data, and its animation, are
      // untouched.
      try animated.set(1, animation: nil)
      try animated.advance(to: start.advanced(by: .milliseconds(600)))
      #expect(animated.activeAnimationCount == 1)
      if use == "stroke" || use == "strokeBorder" {
        // Every sample from the write on is drawn by the shape as it is now.
        let later = Array(log.fields[before...])
        #expect(!later.isEmpty)
        #expect(later.allSatisfy { $0 == "trailing" }, "\(later)")
      }
      #expect(animated.frame == atRest.frame, "\(animated.frame)")
    }
  }
}

/// A rectangle that covers `fraction` of its width, from the leading edge or
/// from the trailing one. The fraction is its animatable data; the edge is
/// not.
private struct FieldWedge: InsettableShape, Animatable {
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
