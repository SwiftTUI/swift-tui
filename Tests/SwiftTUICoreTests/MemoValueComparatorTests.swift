import Testing

@testable import SwiftTUICore

@MainActor
@Suite
struct MemoValueComparatorTests {
  private struct EquatableStruct: Equatable {
    var x: Int
    var label: String
  }

  private struct PlainStruct {
    var a: Int
    var b: String
  }

  private struct ClosureStruct {
    var label: String
    var action: () -> Void
  }

  private struct NestedStruct {
    var inner: PlainStruct
    var tag: Int
  }

  private final class RefBox {
    let id: Int
    init(_ id: Int) { self.id = id }
  }

  // A non-Equatable enum: cannot be compared SOUNDLY by the structural path, so
  // the comparator must deny reuse for it (never serve stale UI).
  private enum NonEquatableState {
    case collapsed
    case expanded
    case loading
    case loaded(Int)
    case failed(Int)
  }

  // The recommended escape hatch: make the enum Equatable and it takes the fast
  // path, regaining precise (and reuse-enabling) comparison.
  private enum EquatableState: Equatable {
    case collapsed
    case expanded
    case loaded(Int)
  }

  private struct StateHolder {
    var state: NonEquatableState
    var tag: Int
  }

  private struct EmptyStruct {}

  @Test("Equatable values compare by ==")
  func equatableFastPath() {
    #expect(MemoValueComparator.compare(1, 1) == .equal)
    #expect(MemoValueComparator.compare(1, 2) == .changed)
    #expect(
      MemoValueComparator.compare(
        EquatableStruct(x: 5, label: "a"),
        EquatableStruct(x: 5, label: "a")
      ) == .equal)
    #expect(
      MemoValueComparator.compare(
        EquatableStruct(x: 5, label: "a"),
        EquatableStruct(x: 6, label: "a")
      ) == .changed)
  }

  @Test("Non-Equatable structs compare field-wise via Mirror")
  func fieldWiseStructural() {
    #expect(
      MemoValueComparator.compare(
        PlainStruct(a: 1, b: "x"),
        PlainStruct(a: 1, b: "x")
      ) == .equal)
    #expect(
      MemoValueComparator.compare(
        PlainStruct(a: 1, b: "x"),
        PlainStruct(a: 2, b: "x")
      ) == .changed)
    #expect(
      MemoValueComparator.compare(
        NestedStruct(inner: PlainStruct(a: 1, b: "x"), tag: 7),
        NestedStruct(inner: PlainStruct(a: 1, b: "x"), tag: 7)
      ) == .equal)
    #expect(
      MemoValueComparator.compare(
        NestedStruct(inner: PlainStruct(a: 1, b: "x"), tag: 7),
        NestedStruct(inner: PlainStruct(a: 9, b: "x"), tag: 7)
      ) == .changed)
  }

  @Test("Closure-bearing views are blocked (the interactive-leaf ceiling)")
  func closureFieldsBlock() {
    let a = ClosureStruct(label: "x", action: {})
    let b = ClosureStruct(label: "x", action: {})
    #expect(MemoValueComparator.compare(a, b) == .blocked(.closure))
  }

  @Test("Reference types compare by identity")
  func referenceIdentity() {
    let box = RefBox(1)
    #expect(MemoValueComparator.compare(box, box) == .equal)
    #expect(MemoValueComparator.compare(RefBox(1), RefBox(1)) == .changed)
  }

  /// A non-`Equatable` enum is compared CASE-AWARE: `Mirror` exposes a payload
  /// case's name as the single child's `label` and the associated value as its
  /// `value`, so the comparator can distinguish cases and recurse on payloads.
  /// The generic field-wise descent ignores labels and would false-equal
  /// `.loaded(x)` / `.failed(x)`; the case-aware path must not. Regression guard
  /// for the Stage-2 adversarial-review finding.
  @Test("Non-Equatable enum payload cases compare case-aware")
  func nonEquatableEnumPayloadCasesCompareCaseAware() {
    // Same case + same payload ⇒ equal (the common stable-leaf case, e.g.
    // `Text.Storage.plain("x")` unchanged across frames).
    #expect(
      MemoValueComparator.compare(NonEquatableState.loaded(1), NonEquatableState.loaded(1))
        == .equal)
    // Same case, changed payload ⇒ changed.
    #expect(
      MemoValueComparator.compare(NonEquatableState.loaded(1), NonEquatableState.loaded(2))
        == .changed)
    // Same arity + same payload value, DIFFERENT case (label distinguishes
    // `.loaded` from `.failed` — the field-wise descent alone would false-equal).
    #expect(
      MemoValueComparator.compare(NonEquatableState.loaded(1), NonEquatableState.failed(1))
        == .changed)
    // Different arity: no-payload → payload.
    #expect(
      MemoValueComparator.compare(NonEquatableState.loading, NonEquatableState.loaded(1))
        == .changed)
  }

  /// A no-payload non-`Equatable` enum case has no `Mirror`-recoverable
  /// discriminator, so the comparator denies reuse conservatively (sound, never
  /// stale) — including for a genuinely-unchanged case. Make the enum
  /// `Equatable` to regain precision.
  @Test("No-payload non-Equatable enum cases are conservatively denied")
  func noPayloadNonEquatableEnumsDeny() {
    // Two distinct no-payload cases: the headline false-equal hazard.
    #expect(
      MemoValueComparator.compare(NonEquatableState.collapsed, NonEquatableState.expanded)
        == .changed)
    // Genuinely-unchanged no-payload case: denied too — conservative.
    #expect(
      MemoValueComparator.compare(NonEquatableState.collapsed, NonEquatableState.collapsed)
        == .changed)
  }

  @Test("A struct field holding a non-Equatable enum is compared case-aware")
  func structWithNonEquatableEnumFieldComparesCaseAware() {
    // Different payload-case state ⇒ the holder differs.
    #expect(
      MemoValueComparator.compare(
        StateHolder(state: .loaded(1), tag: 1),
        StateHolder(state: .loaded(2), tag: 1)
      ) == .changed)
    // Different no-payload case ⇒ denied conservatively (still changed).
    #expect(
      MemoValueComparator.compare(
        StateHolder(state: .collapsed, tag: 1),
        StateHolder(state: .expanded, tag: 1)
      ) == .changed)
    // Same payload case + same payload + same sibling field ⇒ equal.
    #expect(
      MemoValueComparator.compare(
        StateHolder(state: .loaded(7), tag: 1),
        StateHolder(state: .loaded(7), tag: 1)
      ) == .equal)
  }

  @Test("Equatable enums take the fast path and compare precisely")
  func equatableEnumsCompareByCase() {
    #expect(
      MemoValueComparator.compare(EquatableState.collapsed, EquatableState.collapsed) == .equal)
    #expect(
      MemoValueComparator.compare(EquatableState.collapsed, EquatableState.expanded) == .changed)
    #expect(
      MemoValueComparator.compare(EquatableState.loaded(1), EquatableState.loaded(1)) == .equal)
    #expect(
      MemoValueComparator.compare(EquatableState.loaded(1), EquatableState.loaded(2)) == .changed)
  }

  @Test("Empty value types (no stored fields) are equal — a single inhabitant")
  func emptyValueTypesAreEqual() {
    #expect(MemoValueComparator.compare(EmptyStruct(), EmptyStruct()) == .equal)
    // Void / empty tuple.
    #expect(MemoValueComparator.compare((), ()) == .equal)
  }
}
