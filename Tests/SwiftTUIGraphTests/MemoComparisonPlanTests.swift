import Testing

@testable import SwiftTUIGraph

/// Pins the per-type ``MemoComparisonPlan`` builder: which tier each fixture
/// shape gets, that plan application agrees with the reflective diagnostic
/// comparator wherever both can judge, and that the soundness direction only
/// ever errs toward recompute (never false-equal). These fixtures also pin the
/// runtime reflection bindings (`swift_reflectionMirror_*`) across toolchain
/// bumps — a behavior drift there must fail here, not in production.
@MainActor
@Suite("Memo comparison plans")
struct MemoComparisonPlanTests {
  init() {
    MemoComparisonPlanCache.resetForTesting()
  }

  // ── Fixtures ────────────────────────────────────────────────────────────

  /// Interior padding: `flag` at offset 8, `scale` at 16 — bytes 9–15 are
  /// uninitialized, so this must NOT get the whole-value byte tier.
  private struct PodFixture {
    var count: Int
    var flag: Bool
    var scale: Double
  }

  /// Fields tile the size exactly — the whole-value byte tier is sound.
  private struct PackedPodFixture {
    var count: Int
    var scale: Double
  }

  private struct EquatableFixture: Equatable {
    var label: String
  }

  private struct StringFieldFixture {
    var label: String
    var count: Int
  }

  private struct ClosureFixture {
    var label: String
    var action: () -> Void
  }

  private struct NestedFixture {
    var inner: StringFieldFixture
    var flag: Bool
  }

  private final class RefBox {
    var value = 0
  }

  private struct ClassRefFixture {
    var box: RefBox
    var label: String
  }

  private enum PodChoice {
    case one, two
  }

  private struct PodEnumFieldFixture {
    var choice: PodChoice
    var label: String
  }

  private enum NonPodChoice {
    case none
    case labeled(String)
  }

  private struct NonPodEnumFieldFixture {
    var choice: NonPodChoice
    var label: String
  }

  private struct FakeWrapper: DynamicProperty {
    var onChange: () -> Void
  }

  private struct WrapperBearingFixture {
    var _storage: FakeWrapper
    var label: String
  }

  private struct WeakRefFixture {
    weak var box: RefBox?
    var label: String
  }

  private struct EmptyFixture {}

  // ── Tier classification ─────────────────────────────────────────────────

  @Test("tier classification per fixture shape")
  func tierClassification() {
    // Padded POD: the whole-value byte tier would read uninitialized padding
    // and false-unequal every pair — it must demote to the field tier.
    #expect(MemoComparisonPlanCache.diagnosticTier(for: PodFixture.self) == .fields)
    #expect(MemoComparisonPlanCache.diagnosticTier(for: PackedPodFixture.self) == .pod)
    #expect(MemoComparisonPlanCache.diagnosticTier(for: EquatableFixture.self) == .equatable)
    #expect(MemoComparisonPlanCache.diagnosticTier(for: StringFieldFixture.self) == .fields)
    #expect(MemoComparisonPlanCache.diagnosticTier(for: ClosureFixture.self) == .unplannable)
    #expect(MemoComparisonPlanCache.diagnosticTier(for: NestedFixture.self) == .fields)
    #expect(MemoComparisonPlanCache.diagnosticTier(for: ClassRefFixture.self) == .fields)
    #expect(MemoComparisonPlanCache.diagnosticTier(for: PodEnumFieldFixture.self) == .fields)
    #expect(
      MemoComparisonPlanCache.diagnosticTier(for: NonPodEnumFieldFixture.self) == .unplannable
    )
    #expect(MemoComparisonPlanCache.diagnosticTier(for: WrapperBearingFixture.self) == .fields)
    #expect(MemoComparisonPlanCache.diagnosticTier(for: WeakRefFixture.self) == .unplannable)
    // Empty struct: POD of size zero.
    #expect(MemoComparisonPlanCache.diagnosticTier(for: EmptyFixture.self) == .pod)
  }

  // ── Plan application ────────────────────────────────────────────────────

  private func planCompare(_ lhs: Any, _ rhs: Any) -> MemoComparison? {
    _ = MemoComparisonPlanCache.hasPlan(for: type(of: lhs))
    return MemoValueComparator.compareForReuse(lhs, rhs)
  }

  @Test("POD values compare by value regardless of padding")
  func podTier() {
    // Padded shape: served by the field tier (per-field spans skip padding).
    let base = PodFixture(count: 1, flag: true, scale: 0.5)
    #expect(planCompare(base, PodFixture(count: 1, flag: true, scale: 0.5)) == .equal)
    #expect(planCompare(base, PodFixture(count: 2, flag: true, scale: 0.5)) == .changed)
    #expect(planCompare(base, PodFixture(count: 1, flag: false, scale: 0.5)) == .changed)
    // Packed shape: served by the whole-value byte tier.
    let packed = PackedPodFixture(count: 1, scale: 0.5)
    #expect(planCompare(packed, PackedPodFixture(count: 1, scale: 0.5)) == .equal)
    #expect(planCompare(packed, PackedPodFixture(count: 1, scale: 0.25)) == .changed)
  }

  @Test("field tier compares mixed POD and Equatable fields")
  func fieldTier() {
    let base = StringFieldFixture(label: "a", count: 1)
    #expect(planCompare(base, StringFieldFixture(label: "a", count: 1)) == .equal)
    #expect(planCompare(base, StringFieldFixture(label: "b", count: 1)) == .changed)
    #expect(planCompare(base, StringFieldFixture(label: "a", count: 2)) == .changed)
  }

  @Test("nested sub-plans descend by value")
  func nestedTier() {
    let base = NestedFixture(inner: .init(label: "a", count: 1), flag: true)
    #expect(
      planCompare(base, NestedFixture(inner: .init(label: "a", count: 1), flag: true))
        == .equal
    )
    #expect(
      planCompare(base, NestedFixture(inner: .init(label: "b", count: 1), flag: true))
        == .changed
    )
    #expect(
      planCompare(base, NestedFixture(inner: .init(label: "a", count: 1), flag: false))
        == .changed
    )
  }

  @Test("class fields compare by identity, not contents")
  func classIdentityTier() {
    let shared = RefBox()
    let other = RefBox()
    let base = ClassRefFixture(box: shared, label: "a")
    #expect(planCompare(base, ClassRefFixture(box: shared, label: "a")) == .equal)
    // Same contents, different instance: conservative inequality.
    #expect(planCompare(base, ClassRefFixture(box: other, label: "a")) == .changed)
    #expect(planCompare(base, ClassRefFixture(box: shared, label: "b")) == .changed)
  }

  @Test("POD enum fields compare through the byte tier")
  func podEnumFieldTier() {
    let base = PodEnumFieldFixture(choice: .one, label: "a")
    #expect(planCompare(base, PodEnumFieldFixture(choice: .one, label: "a")) == .equal)
    #expect(planCompare(base, PodEnumFieldFixture(choice: .two, label: "a")) == .changed)
  }

  @Test("dynamic-property storage is slot identity, not compared data")
  func wrapperFieldsAreSkipped() {
    var first = 0
    var second = 0
    let lhs = WrapperBearingFixture(_storage: .init(onChange: { first += 1 }), label: "a")
    let rhs = WrapperBearingFixture(_storage: .init(onChange: { second += 1 }), label: "a")
    // The two wrapper closures differ; the plan must not consult them — the
    // dependency gate owns wrapper-covered state.
    #expect(planCompare(lhs, rhs) == .equal)
    #expect(
      planCompare(lhs, WrapperBearingFixture(_storage: .init(onChange: {}), label: "b"))
        == .changed
    )
  }

  @Test("unplannable types fall back to the Equatable-only verdict")
  func unplannableFallsBack() {
    let lhs = ClosureFixture(label: "a", action: {})
    let rhs = ClosureFixture(label: "a", action: {})
    _ = MemoComparisonPlanCache.hasPlan(for: ClosureFixture.self)
    // Cached-nil plan: the gate cannot judge the pair (recompute).
    #expect(MemoValueComparator.compareForReuse(lhs, rhs) == nil)
    // Without any cache entry the historical Equatable-only path answers.
    MemoComparisonPlanCache.resetForTesting()
    #expect(MemoValueComparator.compareForReuse(lhs, rhs) == nil)
    #expect(
      MemoValueComparator.compareForReuse(
        EquatableFixture(label: "a"),
        EquatableFixture(label: "a")
      ) == .equal
    )
  }

  @Test("only value-witnessing plans may serve under uncertified empty invalidation")
  func emptyInvalidationServiceability() {
    _ = MemoComparisonPlanCache.hasPlan(for: EquatableFixture.self)
    _ = MemoComparisonPlanCache.hasPlan(for: PackedPodFixture.self)
    _ = MemoComparisonPlanCache.hasPlan(for: StringFieldFixture.self)
    _ = MemoComparisonPlanCache.hasPlan(for: ClassRefFixture.self)
    #expect(
      MemoComparisonPlanCache.mayServeUnderUncertifiedEmptyInvalidation(EquatableFixture.self)
    )
    #expect(
      MemoComparisonPlanCache.mayServeUnderUncertifiedEmptyInvalidation(PackedPodFixture.self)
    )
    #expect(
      MemoComparisonPlanCache.mayServeUnderUncertifiedEmptyInvalidation(StringFieldFixture.self)
    )
    // A class-identity comparator witnesses only the reference; the referenced
    // contents are an out-of-band channel a forced re-render must refresh.
    #expect(
      !MemoComparisonPlanCache.mayServeUnderUncertifiedEmptyInvalidation(ClassRefFixture.self)
    )
  }

  @Test("type mismatch is a structural change")
  func typeMismatch() {
    #expect(
      MemoValueComparator.compareForReuse(
        PodFixture(count: 1, flag: true, scale: 0.5),
        EquatableFixture(label: "a")
      ) == .changed
    )
  }

  // ── Agreement with the reflective diagnostic comparator ─────────────────

  @Test("plan verdicts agree with the diagnostic comparator on judged pairs")
  func agreementWithDiagnostic() {
    let pairs: [(Any, Any)] = [
      (PodFixture(count: 1, flag: true, scale: 0.5), PodFixture(count: 1, flag: true, scale: 0.5)),
      (PodFixture(count: 1, flag: true, scale: 0.5), PodFixture(count: 2, flag: true, scale: 0.5)),
      (StringFieldFixture(label: "a", count: 1), StringFieldFixture(label: "a", count: 1)),
      (StringFieldFixture(label: "a", count: 1), StringFieldFixture(label: "b", count: 1)),
      (
        NestedFixture(inner: .init(label: "a", count: 1), flag: true),
        NestedFixture(inner: .init(label: "a", count: 1), flag: true)
      ),
      (
        NestedFixture(inner: .init(label: "a", count: 1), flag: true),
        NestedFixture(inner: .init(label: "b", count: 1), flag: false)
      ),
    ]
    for (lhs, rhs) in pairs {
      let planVerdict = planCompare(lhs, rhs)
      let diagnosticVerdict = MemoValueComparator.compare(lhs, rhs)
      // The invariant is one-directional soundness: a plan `.equal` requires
      // the diagnostic to agree; a plan may be stricter (padding) but these
      // fixtures have none, so the verdicts must match exactly.
      #expect(planVerdict == diagnosticVerdict, "for \(type(of: lhs))")
    }
  }
}
