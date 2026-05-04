import Testing

@testable import SwiftTUICore

@Test("EdgeInsets animatableData getter carries all four edges")
func edgeInsetsAnimatableGetter() {
  let insets = EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
  let data = insets.animatableData
  #expect(data.first.first == 1)
  #expect(data.first.second == 2)
  #expect(data.second.first == 3)
  #expect(data.second.second == 4)
}

@Test("EdgeInsets animatableData setter writes back to all four edges")
func edgeInsetsAnimatableSetter() {
  var insets = EdgeInsets()
  insets.animatableData = AnimatablePair(
    AnimatablePair(5, 6),
    AnimatablePair(7, 8)
  )
  #expect(insets.top == 5)
  #expect(insets.leading == 6)
  #expect(insets.bottom == 7)
  #expect(insets.trailing == 8)
}

@Test("EdgeInsets halfway interpolation via animatableData")
func edgeInsetsHalfwayInterpolation() {
  let from = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
  let to = EdgeInsets(top: 10, leading: 20, bottom: 30, trailing: 40)
  var delta = to.animatableData
  delta -= from.animatableData
  delta.scale(by: 0.5)
  var result = from
  var resultData = result.animatableData
  resultData += delta
  result.animatableData = resultData
  #expect(result.top == 5)
  #expect(result.leading == 10)
  #expect(result.bottom == 15)
  #expect(result.trailing == 20)
}
