import Testing

@testable import Core

@Test("UnitPoint named constants match unit-coordinate specification")
func unitPointNamedConstants() {
  #expect(UnitPoint.topLeading == UnitPoint(x: 0, y: 0))
  #expect(UnitPoint.top == UnitPoint(x: 0.5, y: 0))
  #expect(UnitPoint.topTrailing == UnitPoint(x: 1, y: 0))
  #expect(UnitPoint.leading == UnitPoint(x: 0, y: 0.5))
  #expect(UnitPoint.center == UnitPoint(x: 0.5, y: 0.5))
  #expect(UnitPoint.trailing == UnitPoint(x: 1, y: 0.5))
  #expect(UnitPoint.bottomLeading == UnitPoint(x: 0, y: 1))
  #expect(UnitPoint.bottom == UnitPoint(x: 0.5, y: 1))
  #expect(UnitPoint.bottomTrailing == UnitPoint(x: 1, y: 1))
}

@Test("UnitPoint zero static property")
func unitPointZero() {
  #expect(UnitPoint.zero == UnitPoint(x: 0, y: 0))
}

@Test("UnitPoint is Equatable and Hashable")
func unitPointEquatableHashable() {
  let a = UnitPoint(x: 0.25, y: 0.75)
  let b = UnitPoint(x: 0.25, y: 0.75)
  let c = UnitPoint(x: 0.25, y: 0.5)
  #expect(a == b)
  #expect(a != c)
  #expect(a.hashValue == b.hashValue)
}

@Test("UnitPoint animatableData getter returns (x, y) pair")
func unitPointAnimatableDataGetter() {
  let p = UnitPoint(x: 0.25, y: 0.75)
  #expect(p.animatableData.first == 0.25)
  #expect(p.animatableData.second == 0.75)
}

@Test("UnitPoint animatableData setter writes back to x and y")
func unitPointAnimatableDataSetter() {
  var p = UnitPoint(x: 0, y: 0)
  p.animatableData = AnimatablePair(0.1, 0.9)
  #expect(p.x == 0.1)
  #expect(p.y == 0.9)
}

@Test("UnitPoint interpolation via animatableData arithmetic")
func unitPointInterpolation() {
  let from = UnitPoint.topLeading
  let to = UnitPoint.bottomTrailing
  var delta = to.animatableData
  delta -= from.animatableData
  delta.scale(by: 0.5)
  var result = from
  var resultData = result.animatableData
  resultData += delta
  result.animatableData = resultData
  #expect(result == UnitPoint.center)
}
