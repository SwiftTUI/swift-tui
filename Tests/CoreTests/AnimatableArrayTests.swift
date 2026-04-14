import Testing

@testable import Core

@Test("AnimatableArray element-wise addition with equal counts")
func animatableArrayEqualCountAddition() {
  let a = AnimatableArray<Double>([1.0, 2.0, 3.0])
  let b = AnimatableArray<Double>([0.5, 0.5, 0.5])
  let sum = a + b
  #expect(sum.elements == [1.5, 2.5, 3.5])
}

@Test("AnimatableArray element-wise subtraction with equal counts")
func animatableArrayEqualCountSubtraction() {
  let a = AnimatableArray<Double>([1.0, 2.0, 3.0])
  let b = AnimatableArray<Double>([0.5, 0.5, 0.5])
  let diff = a - b
  #expect(diff.elements == [0.5, 1.5, 2.5])
}

@Test("AnimatableArray mismatched counts snap to empty")
func animatableArrayMismatchedCountSnap() {
  let a = AnimatableArray<Double>([1.0, 2.0, 3.0])
  let b = AnimatableArray<Double>([0.5, 0.5])
  let sum = a + b
  #expect(sum.elements.isEmpty)
  #expect(!a.isInterpolable(to: b))
  #expect(a.isInterpolable(to: AnimatableArray<Double>([9, 9, 9])))
}

@Test("AnimatableArray scale mutates in place")
func animatableArrayScale() {
  var a = AnimatableArray<Double>([1.0, 2.0, 3.0])
  a.scale(by: 0.5)
  #expect(a.elements == [0.5, 1.0, 1.5])
}

@Test("AnimatableArray magnitudeSquared sums element magnitudes")
func animatableArrayMagnitudeSquared() {
  let a = AnimatableArray<Double>([1.0, 2.0, 3.0])
  #expect(a.magnitudeSquared == 1.0 + 4.0 + 9.0)
}

@Test("AnimatableArray zero is an empty array")
func animatableArrayZero() {
  let z: AnimatableArray<Double> = .zero
  #expect(z.elements.isEmpty)
}

@Test("AnimatableArray compound assignment operators")
func animatableArrayCompoundAssignment() {
  var a = AnimatableArray<Double>([1.0, 2.0])
  a += AnimatableArray<Double>([0.5, 0.5])
  #expect(a.elements == [1.5, 2.5])
  a -= AnimatableArray<Double>([0.25, 0.25])
  #expect(a.elements == [1.25, 2.25])
}

@Test("AnimatableArray nested AnimatablePair composition")
func animatableArrayNestedPair() {
  let a = AnimatableArray<AnimatablePair<Double, Double>>([
    .init(1.0, 2.0),
    .init(3.0, 4.0),
  ])
  let b = AnimatableArray<AnimatablePair<Double, Double>>([
    .init(0.5, 0.5),
    .init(0.5, 0.5),
  ])
  let sum = a + b
  #expect(sum.elements[0].first == 1.5)
  #expect(sum.elements[0].second == 2.5)
  #expect(sum.elements[1].first == 3.5)
  #expect(sum.elements[1].second == 4.5)
}

@Test("AnimatableArray scale by zero zeros all elements")
func animatableArrayScaleByZero() {
  var a = AnimatableArray<Double>([1.0, 2.0, 3.0])
  a.scale(by: 0)
  #expect(a.elements == [0, 0, 0])
}

@Test("AnimatableArray scale by negative factor negates elements")
func animatableArrayScaleByNegative() {
  var a = AnimatableArray<Double>([1.0, 2.0, 3.0])
  a.scale(by: -1)
  #expect(a.elements == [-1.0, -2.0, -3.0])
}

@Test("AnimatableArray empty plus empty is empty")
func animatableArrayEmptyPlusEmpty() {
  let a: AnimatableArray<Double> = .zero
  let b: AnimatableArray<Double> = .zero
  let sum = a + b
  #expect(sum.elements.isEmpty)
  #expect(a.isInterpolable(to: b))
}

@Test("AnimatableArray empty magnitudeSquared is zero")
func animatableArrayEmptyMagnitudeSquared() {
  let a: AnimatableArray<Double> = .init([])
  #expect(a.magnitudeSquared == 0)
}

@Test("AnimatableArray mismatched counts on subtraction snap to empty")
func animatableArrayMismatchedSubtractionSnap() {
  let a = AnimatableArray<Double>([1.0, 2.0, 3.0])
  let b = AnimatableArray<Double>([0.5, 0.5])
  let diff = a - b
  #expect(diff.elements.isEmpty)
}
