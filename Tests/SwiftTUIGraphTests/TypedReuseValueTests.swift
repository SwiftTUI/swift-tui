import Testing

@testable import SwiftTUIGraph

// `TypedReuseValue` boxes a value by its static type when it is written, so a
// snapshot comparison does not cast the value. These tests pin that the boxed
// comparison answers exactly what `typedValuesAreEqualForReuse` answers for the
// same two values, across every proof the function knows: `Equatable`, the
// framework's own reuse equality, reference identity, and none.
@Suite("Typed reuse value equality")
struct TypedReuseValueTests {
  private struct Plain: Equatable, Sendable {
    var value: Int
  }

  /// Equal under reuse when the tags match; deliberately not `Equatable`.
  private struct Provided: TypedReuseEqualityProviding {
    var tag: Int
    var noise: Int

    func isEqualForReuse(to other: any Sendable) -> Bool {
      (other as? Self)?.tag == tag
    }
  }

  private struct Opaque: Sendable {
    var value: Int
  }

  private final class Reference: Sendable {}

  private final class EquatableReference: Equatable, Sendable {
    let value: Int

    init(_ value: Int) {
      self.value = value
    }

    static func == (lhs: EquatableReference, rhs: EquatableReference) -> Bool {
      lhs.value == rhs.value
    }
  }

  private protocol Shape: Sendable {}

  private struct Circle: Shape, Equatable {
    var radius: Int
  }

  private struct Blob: Shape {
    var size: Int
  }

  private func boxedEquality<Value: Sendable>(_ lhs: Value, _ rhs: Value) -> Bool {
    TypedReuseValue(lhs).isEqual(to: TypedReuseValue(rhs))
  }

  /// The boxed answer and the dynamic function's answer for one pair.
  private func bothAnswers<Value: Sendable>(_ lhs: Value, _ rhs: Value) -> (Bool, Bool) {
    (boxedEquality(lhs, rhs), typedValuesAreEqualForReuse(lhs, rhs))
  }

  @Test("an Equatable value type compares with its own ==")
  func equatableValueTypes() {
    #expect(bothAnswers(Plain(value: 1), Plain(value: 1)) == (true, true))
    #expect(bothAnswers(Plain(value: 1), Plain(value: 2)) == (false, false))
    #expect(bothAnswers("row", "row") == (true, true))
    #expect(bothAnswers([1, 2, 3], [1, 2, 3]) == (true, true))
    #expect(bothAnswers([1, 2, 3], [1, 2]) == (false, false))
    #expect(bothAnswers(Optional(Plain(value: 4)), Optional(Plain(value: 4))) == (true, true))
    #expect(bothAnswers(Optional(Plain(value: 4)), nil) == (false, false))
    #expect(bothAnswers(Plain?.none, nil) == (true, true))
  }

  @Test("a value type with framework reuse equality compares through it")
  func providedValueTypes() {
    #expect(bothAnswers(Provided(tag: 1, noise: 1), Provided(tag: 1, noise: 2)) == (true, true))
    #expect(bothAnswers(Provided(tag: 1, noise: 1), Provided(tag: 2, noise: 1)) == (false, false))
    #expect(
      bothAnswers([Provided(tag: 1, noise: 1)], [Provided(tag: 1, noise: 9)]) == (true, true))
  }

  @Test("a value with no typed proof never compares equal")
  func opaqueValueTypes() {
    #expect(bothAnswers(Opaque(value: 1), Opaque(value: 1)) == (false, false))
    let closure: @Sendable () -> Int = { 1 }
    #expect(bothAnswers(closure, closure) == (false, false))
  }

  @Test("a class instance compares by its dynamic type, then by identity")
  func classInstances() {
    let reference = Reference()
    #expect(bothAnswers(reference, reference) == (true, true))
    #expect(bothAnswers(reference, Reference()) == (false, false))
    #expect(bothAnswers(EquatableReference(1), EquatableReference(1)) == (true, true))
    #expect(bothAnswers(EquatableReference(1), EquatableReference(2)) == (false, false))
  }

  @Test("an existential compares by the dynamic type it holds")
  func existentials() {
    let circle: any Shape = Circle(radius: 2)
    let sameCircle: any Shape = Circle(radius: 2)
    let otherCircle: any Shape = Circle(radius: 3)
    let blob: any Shape = Blob(size: 2)
    #expect(bothAnswers(circle, sameCircle) == (true, true))
    #expect(bothAnswers(circle, otherCircle) == (false, false))
    #expect(bothAnswers(circle, blob) == (false, false))
    #expect(bothAnswers(blob, blob) == (false, false))
  }

  @Test("values written under different static types are never equal")
  func differentStaticTypes() {
    #expect(!TypedReuseValue(1).isEqual(to: TypedReuseValue(Int8(1))))
    #expect(!TypedReuseValue(Plain(value: 1)).isEqual(to: TypedReuseValue(Opaque(value: 1))))
    #expect(!TypedReuseValue(Optional(1)).isEqual(to: TypedReuseValue(1)))
    // `as any Shape` keeps the existential as the static type; without it the
    // generic initializer opens the value and boxes a `Circle`.
    let circle: any Shape = Circle(radius: 2)
    #expect(
      !TypedReuseValue(circle as any Shape).isEqual(to: TypedReuseValue(Circle(radius: 2))))
    #expect(TypedReuseValue(circle).isEqual(to: TypedReuseValue(Circle(radius: 2))))
  }

  @Test("a value is equal to itself whatever its type proves")
  func identicalBoxes() {
    let opaque = TypedReuseValue(Opaque(value: 1))
    #expect(opaque.isEqual(to: opaque))
  }

  @Test("the stored value and its diagnostics read back unchanged")
  func readsBack() {
    let plain = TypedReuseValue(Plain(value: 7))
    #expect(plain.value(as: Plain.self) == Plain(value: 7))
    #expect(plain.value(as: Int.self) == nil)
    #expect(plain.debugValue == String(reflecting: Plain(value: 7)))
    #expect(plain.valueTypeDescription == String(reflecting: Plain.self))

    let provided = TypedReuseValue(Provided(tag: 3, noise: 4))
    #expect(provided.value(as: Provided.self)?.noise == 4)
    #expect(provided.valueTypeDescription == String(reflecting: Provided.self))

    let optional = TypedReuseValue(Int?.none)
    #expect(optional.value(as: Int?.self) == .some(nil))
    #expect(optional.valueTypeDescription == String(reflecting: Int?.self))

    let opaque = TypedReuseValue(Opaque(value: 5))
    #expect(opaque.value(as: Opaque.self)?.value == 5)
    #expect(opaque.debugValue == String(reflecting: Opaque(value: 5)))
  }
}

@Suite("Environment snapshot equality memo")
struct EnvironmentSnapshotEqualityMemoTests {
  private enum FirstKey {}
  private enum SecondKey {}

  private func snapshot(first: Int, second: String) -> EnvironmentSnapshot {
    EnvironmentSnapshot(
      typedValues: [
        ObjectIdentifier(FirstKey.self): EnvironmentSnapshotValue(
          keyType: FirstKey.self, reuseValue: TypedReuseValue(first)),
        ObjectIdentifier(SecondKey.self): EnvironmentSnapshotValue(
          keyType: SecondKey.self, reuseValue: TypedReuseValue(second)),
      ]
    )
  }

  @Test("a pair of equal snapshots is compared value by value once")
  func equalPairIsComparedOnce() {
    let lhs = snapshot(first: 1, second: "a")
    let rhs = snapshot(first: 1, second: "a")
    var memo = EnvironmentSnapshot.EqualityMemo()
    var work = ComparisonWork()

    #expect(memo.areEqual(lhs, rhs, mode: CountComparisonWork.self, work: &work))
    let afterFirst = work
    #expect(afterFirst.environmentValues == 2)

    for _ in 0..<5 {
      #expect(memo.areEqual(lhs, rhs, mode: CountComparisonWork.self, work: &work))
    }
    #expect(work == afterFirst)
  }

  @Test("a shared snapshot is equal without a value comparison")
  func sharedSnapshot() {
    let shared = snapshot(first: 1, second: "a")
    var memo = EnvironmentSnapshot.EqualityMemo()
    var work = ComparisonWork()

    #expect(memo.areEqual(shared, shared, mode: CountComparisonWork.self, work: &work))
    #expect(work.environmentSharedStorage == 1)
    #expect(work.environmentValues == 0)
  }

  @Test("unequal snapshots stay unequal and are never remembered as equal")
  func unequalPair() {
    let lhs = snapshot(first: 1, second: "a")
    let rhs = snapshot(first: 2, second: "a")
    var memo = EnvironmentSnapshot.EqualityMemo()
    var work = ComparisonWork()

    #expect(!memo.areEqual(lhs, rhs, mode: SkipComparisonWork.self, work: &work))
    #expect(!memo.areEqual(lhs, rhs, mode: SkipComparisonWork.self, work: &work))
    #expect(memo.areEqual(lhs, lhs, mode: SkipComparisonWork.self, work: &work))
  }

  @Test("the memo agrees with == across more pairs than it remembers")
  func agreesWithEqualityPastItsCapacity() {
    let snapshots = (0..<4).flatMap { index in
      [snapshot(first: index, second: "s"), snapshot(first: index, second: "s")]
    }
    var memo = EnvironmentSnapshot.EqualityMemo()
    var work = ComparisonWork()

    for _ in 0..<3 {
      for lhs in snapshots {
        for rhs in snapshots {
          #expect(
            memo.areEqual(lhs, rhs, mode: SkipComparisonWork.self, work: &work) == (lhs == rhs))
        }
      }
    }
  }
}
