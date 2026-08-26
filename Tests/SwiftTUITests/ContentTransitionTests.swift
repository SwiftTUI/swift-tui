import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// N0 pins for `ContentTransition` (plan 2026-08-25-004 §4), driven through a
/// real `RunLoop` so the button's `withAnimation` write, the controller's
/// `.textRoll` slot, draw extraction, and the raster all take part.
///
/// The fixture lays out a reference `Text` on row 0 (its foreground is the
/// undimmed colour), the transitioning `Text` on row 1, and the button that
/// flips the string on row 2. A cell is "dimmed" when its resolved
/// foreground differs from the reference cell's: the raster bakes fractional
/// opacity into the foreground colour.
@MainActor
@Suite(.serialized)
struct ContentTransitionTests {
  private static let bumpLabel = "bump"
  private static let duration: Duration = .milliseconds(600)
  private static let settle: Duration = .milliseconds(900)

  // MARK: - numericText

  @Test("numericText rolls only the changed column and lands on the new string")
  func numericTextRollsTheChangedColumn() async throws {
    let harness = try AnimatorRuntimeHarness {
      RollFixture(from: "41", to: "42", transition: .numericText())
    }
    defer { harness.shutdown() }

    let rows = try await Self.rowsAfterBump(harness)
    #expect(rows.last?.text == "42", "rows: \(rows.map(\.text))")
    #expect(Set(rows.map(\.text)).isSubset(of: ["41", "42"]), "rows: \(rows.map(\.text))")
    #expect(rows.contains { $0.text == "41" }, "the roll must start from the old string")
    #expect(
      rows.contains { $0.text == "42" && $0.dimmed[1] },
      "the changed column dims mid-roll: \(rows)"
    )
    #expect(rows.allSatisfy { !$0.dimmed[0] }, "the unchanged column is untouched: \(rows)")
    #expect(rows.last.map { !$0.dimmed[1] } == true, "the roll ends undimmed: \(rows)")
  }

  @Test("numericText counts up through the intermediate digits")
  func numericTextCountsUp() async throws {
    let harness = try AnimatorRuntimeHarness {
      RollFixture(from: "7", to: "0", transition: .numericText())
    }
    defer { harness.shutdown() }

    let digits = try await Self.rowsAfterBump(harness).map(\.text)
    Self.expectRun(digits, along: ["7", "8", "9", "0"])
    #expect(digits.contains("8") || digits.contains("9"), "no intermediate digit: \(digits)")
  }

  @Test("numericText(countsDown:) counts down through the intermediate digits")
  func numericTextCountsDown() async throws {
    let harness = try AnimatorRuntimeHarness {
      RollFixture(from: "7", to: "0", transition: .numericText(countsDown: true))
    }
    defer { harness.shutdown() }

    let digits = try await Self.rowsAfterBump(harness).map(\.text)
    Self.expectRun(digits, along: ["7", "6", "5", "4", "3", "2", "1", "0"])
    #expect(digits.contains("6") || digits.contains("5"), "no intermediate digit: \(digits)")
  }

  @Test("numericText(value:) takes its direction from the sign of the change")
  func numericTextValuePicksDirectionFromTheDelta() async throws {
    let down = try AnimatorRuntimeHarness {
      RollFixture(from: "7", to: "0", fromValue: 7, toValue: 0)
    }
    let downDigits = try await Self.rowsAfterBump(down).map(\.text)
    down.shutdown()
    Self.expectRun(downDigits, along: ["7", "6", "5", "4", "3", "2", "1", "0"])
    #expect(downDigits.contains("6") || downDigits.contains("5"), "digits: \(downDigits)")

    let up = try AnimatorRuntimeHarness {
      RollFixture(from: "7", to: "0", fromValue: 7, toValue: 10)
    }
    defer { up.shutdown() }
    let upDigits = try await Self.rowsAfterBump(up).map(\.text)
    Self.expectRun(upDigits, along: ["7", "8", "9", "0"])
    #expect(upDigits.contains("8") || upDigits.contains("9"), "digits: \(upDigits)")
  }

  @Test("a length change lays out at the new width from the first tick")
  func lengthChangeLaysOutAtTheNewWidth() async throws {
    let harness = try AnimatorRuntimeHarness {
      RollFixture(from: "99", to: "100", transition: .numericText())
    }
    defer { harness.shutdown() }

    let rows = try await Self.rowsAfterBump(harness).drop { $0.text == "99" }
    #expect(rows.last?.text == "100", "rows: \(rows.map(\.text))")
    #expect(
      rows.allSatisfy { $0.text.count == 3 && $0.text.first == "1" },
      "every post-write frame is three columns wide with the added column present: \(rows.map(\.text))"
    )
    #expect(
      rows.contains { $0.text == "199" || $0.text == "100" && $0.dimmed[1] },
      "the shared columns roll: \(rows)"
    )
  }

  @Test("non-digit columns cross-fade while digit columns roll")
  func nonDigitColumnsCrossFade() async throws {
    let harness = try AnimatorRuntimeHarness {
      RollFixture(from: "1,5", to: "2.5", transition: .numericText())
    }
    defer { harness.shutdown() }

    let rows = try await Self.rowsAfterBump(harness)
    #expect(rows.last?.text == "2.5", "rows: \(rows.map(\.text))")
    let separators = rows.map { String($0.text.dropFirst().prefix(1)) }
    Self.expectRun(separators, along: [",", "."])
    #expect(rows.allSatisfy { $0.text.last == "5" && !$0.dimmed[2] }, "the suffix is untouched: \(rows)")
    #expect(rows.allSatisfy { ["1", "2"].contains($0.text.first.map(String.init)) }, "rows: \(rows)")
    #expect(rows.contains { $0.dimmed[1] }, "the separator column dims through the cross-fade: \(rows)")
  }

  // MARK: - opacity, identity, and the cut cases

  @Test("opacity dims the old string out and the new string in, never a mix")
  func opacityCrossFadesTheWholeString() async throws {
    let harness = try AnimatorRuntimeHarness {
      RollFixture(from: "41", to: "42", transition: .opacity)
    }
    defer { harness.shutdown() }

    let rows = try await Self.rowsAfterBump(harness)
    #expect(rows.last?.text == "42", "rows: \(rows.map(\.text))")
    Self.expectRun(rows.map(\.text), along: ["41", "42"])
    #expect(rows.contains { $0.text == "41" && $0.dimmed[0] && $0.dimmed[1] }, "old string dims: \(rows)")
    #expect(rows.contains { $0.text == "42" && $0.dimmed[0] && $0.dimmed[1] }, "new string dims in: \(rows)")
    #expect(rows.last.map { !$0.dimmed[0] && !$0.dimmed[1] } == true, "ends undimmed: \(rows)")
  }

  @Test("identity cuts inside an animated transaction")
  func identityCuts() async throws {
    let harness = try AnimatorRuntimeHarness {
      RollFixture(from: "41", to: "42", transition: .identity)
    }
    defer { harness.shutdown() }

    let rows = try await Self.rowsAfterBump(harness)
    Self.expectRun(rows.map(\.text), along: ["41", "42"])
    #expect(rows.last?.text == "42", "rows: \(rows)")
    #expect(rows.allSatisfy { !$0.dimmed.contains(true) }, "a cut never dims: \(rows)")
  }

  @Test("an unanimated write cuts")
  func unanimatedWriteCuts() async throws {
    let harness = try AnimatorRuntimeHarness {
      RollFixture(from: "41", to: "42", transition: .numericText(), animation: nil)
    }
    defer { harness.shutdown() }

    let rows = try await Self.rowsAfterBump(harness)
    Self.expectRun(rows.map(\.text), along: ["41", "42"])
    #expect(rows.last?.text == "42", "rows: \(rows)")
    #expect(rows.allSatisfy { !$0.dimmed.contains(true) }, "a cut never dims: \(rows)")
  }

  @Test("reduce motion snaps to the new string")
  func reduceMotionSnaps() async throws {
    let harness = try AnimatorRuntimeHarness(motion: .reduced) {
      RollFixture(from: "41", to: "42", transition: .numericText())
    }
    defer { harness.shutdown() }

    let rows = try await Self.rowsAfterBump(harness)
    Self.expectRun(rows.map(\.text), along: ["41", "42"])
    #expect(rows.last?.text == "42", "rows: \(rows)")
    #expect(rows.allSatisfy { !$0.dimmed.contains(true) }, "a cut never dims: \(rows)")
  }

  // MARK: - Support

  /// Row 1 of every surface presented after the button write, as text plus a
  /// per-column "dimmed" flag against the reference row.
  private static func rowsAfterBump(
    _ harness: AnimatorRuntimeHarness<RollFixture>
  ) async throws -> [ObservedRow] {
    let before = harness.surfaces.count
    try harness.clickText(bumpLabel)
    try await harness.hold(for: settle)
    let observed = harness.surfaces.dropFirst(before).map(ObservedRow.init)
    try #require(!observed.isEmpty, "no frame was presented after the write")
    return Array(observed)
  }

  /// `values` must walk `path` forward without ever stepping back.
  private static func expectRun(
    _ values: [String], along path: [String],
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    var cursor = 0
    for value in values {
      guard let index = path.firstIndex(of: value) else {
        Issue.record("\(value) is not on the path \(path): \(values)", sourceLocation: sourceLocation)
        return
      }
      if index < cursor {
        Issue.record("\(values) steps back along \(path)", sourceLocation: sourceLocation)
        return
      }
      cursor = index
    }
  }
}

private struct ObservedRow: CustomStringConvertible {
  var text: String
  var dimmed: [Bool]

  init(_ surface: RasterSurface) {
    let reference = surface.cells[0][0].style?.foregroundColor
    let cells = surface.cells[1].prefix { $0.character != " " }
    text = String(cells.map(\.character))
    dimmed = cells.map { $0.style?.foregroundColor != reference }
  }

  var description: String {
    "\(text)\(dimmed.map { $0 ? "*" : "." }.joined())"
  }
}

/// Row 0: the undimmed reference. Row 1: the transitioning text. Row 2: the
/// button whose action flips the string (inside `withAnimation` unless
/// `animation` is nil).
private struct RollFixture: View {
  var from: String
  var to: String
  var transition: ContentTransition
  var animation: Animation?
  var fromValue: Double?
  var toValue: Double?
  @State private var showsTarget = false

  init(
    from: String,
    to: String,
    transition: ContentTransition,
    animation: Animation? = .linear(duration: .milliseconds(600))
  ) {
    self.from = from
    self.to = to
    self.transition = transition
    self.animation = animation
  }

  /// The `numericText(value:)` form: the value flips with the string.
  init(from: String, to: String, fromValue: Double, toValue: Double) {
    self.from = from
    self.to = to
    self.transition = .numericText(value: fromValue)
    self.animation = .linear(duration: .milliseconds(600))
    self.fromValue = fromValue
    self.toValue = toValue
  }

  private var effectiveTransition: ContentTransition {
    if let fromValue, let toValue {
      return .numericText(value: showsTarget ? toValue : fromValue)
    }
    return transition
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("ref")
      Text(showsTarget ? to : from)
        .contentTransition(effectiveTransition)
      Button("bump") {
        if let animation {
          withAnimation(animation) { showsTarget = true }
        } else {
          showsTarget = true
        }
      }
    }
  }
}
