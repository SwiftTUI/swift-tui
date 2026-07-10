import Testing

@testable import SwiftTUIGraph

/// Property-style lock on the two-comparator agreement contract (F114): for
/// any pair of values BOTH comparators can judge (`Equatable` values), the
/// production gate (`compareEquatable`) and the reflective diagnostic
/// comparator (`compare`) must agree — the `MemoSkipTrace` shadow oracle is
/// only meaningful if it verifies the same equality the production gate
/// trusts. Previously enforced only by the shared fast path plus
/// hand-written examples in `MemoValueComparatorTests`.
@MainActor
@Suite("Memo comparator agreement")
struct MemoComparatorAgreementTests {
  private struct Plain: Equatable {
    var count: Int
    var label: String
  }

  private struct Nested: Equatable {
    var inner: Plain
    var flag: Bool
  }

  private enum Payload: Equatable {
    case none
    case value(Int)
    case labeled(String, Int)
  }

  private struct Custom: Equatable {
    var raw: Int
    // Custom equality: only the parity matters. Both comparators must
    // respect the type's own == (the reflective path's field-wise walk is
    // gated behind the Equatable fast path).
    static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.raw % 2 == rhs.raw % 2
    }
  }

  /// (name, lhs, rhs, expectedEqual) — generated pairs spanning value
  /// shapes: per-field mutations, nesting, associated values, optionals,
  /// collections, and custom equality that diverges from field equality.
  private static var generatedPairs: [(String, Any, Any, Bool)] {
    var pairs: [(String, Any, Any, Bool)] = []
    let base = Plain(count: 1, label: "a")
    pairs.append(("plain-equal", base, Plain(count: 1, label: "a"), true))
    pairs.append(("plain-count", base, Plain(count: 2, label: "a"), false))
    pairs.append(("plain-label", base, Plain(count: 1, label: "b"), false))

    let nested = Nested(inner: base, flag: false)
    pairs.append(("nested-equal", nested, Nested(inner: base, flag: false), true))
    pairs.append(
      ("nested-inner", nested, Nested(inner: Plain(count: 9, label: "a"), flag: false), false)
    )
    pairs.append(("nested-flag", nested, Nested(inner: base, flag: true), false))

    pairs.append(("enum-equal", Payload.value(3), Payload.value(3), true))
    pairs.append(("enum-case", Payload.value(3), Payload.none, false))
    pairs.append(("enum-assoc", Payload.labeled("x", 1), Payload.labeled("x", 2), false))

    pairs.append(("optional-some-equal", Optional(base), Optional(base), true))
    pairs.append(("optional-some-nil", Optional(base), Plain?.none, false))
    pairs.append(("optional-nil-nil", Plain?.none, Plain?.none, true))

    pairs.append(("array-equal", [1, 2, 3], [1, 2, 3], true))
    pairs.append(("array-order", [1, 2, 3], [3, 2, 1], false))

    pairs.append(("custom-parity-equal", Custom(raw: 2), Custom(raw: 4), true))
    pairs.append(("custom-parity-diff", Custom(raw: 2), Custom(raw: 3), false))
    return pairs
  }

  @Test("production and diagnostic comparators agree on every generated Equatable pair")
  func comparatorsAgreeOnGeneratedPairs() {
    for (name, lhs, rhs, expectedEqual) in Self.generatedPairs {
      let production = MemoValueComparator.compareEquatable(lhs, rhs)
      let diagnostic = MemoValueComparator.compare(lhs, rhs)

      #expect(
        production == (expectedEqual ? .equal : .changed),
        "\(name): production gate disagrees with the type's own =="
      )
      #expect(
        diagnostic == (expectedEqual ? .equal : .changed),
        "\(name): diagnostic comparator disagrees with the type's own =="
      )
      #expect(
        production == diagnostic,
        "\(name): the two comparators diverged — the shadow oracle no longer verifies the gate's equality"
      )
    }
  }
}
