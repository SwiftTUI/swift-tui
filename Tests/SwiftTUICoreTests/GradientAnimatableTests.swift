import SwiftTUICore
import Testing

@Test("Gradient.Stop animatableData carries color and location")
func gradientStopAnimatableData() {
  let stop = Gradient.Stop(color: .red, location: 0.25)
  let data = stop.animatableData
  // color's animatableData is an AnimatablePair of pairs; location
  // is the second element of the outer pair.
  #expect(data.second == 0.25)
}

@Test("Gradient.Stop halfway interpolation")
func gradientStopInterpolation() {
  let from = Gradient.Stop(color: .red, location: 0.0)
  let to = Gradient.Stop(color: .blue, location: 1.0)
  var delta = to.animatableData
  delta -= from.animatableData
  delta.scale(by: 0.5)
  var result = from
  var resultData = result.animatableData
  resultData += delta
  result.animatableData = resultData
  #expect(abs(result.location - 0.5) < 0.001)
  // Color should be perceptual midpoint between red and blue.
  let expected = Color.red.interpolated(to: .blue, progress: 0.5)
  #expect(abs(result.color.red - expected.red) < 0.001)
  #expect(abs(result.color.blue - expected.blue) < 0.001)
}

@Test("Gradient animatableData count-mismatch is non-interpolable")
func gradientCountMismatchSnap() {
  let two = Gradient(colors: [.red, .blue])
  let three = Gradient(colors: [.red, .green, .blue])
  #expect(!two.animatableData.isInterpolable(to: three.animatableData))
}

@Test("Gradient animatableData matching counts interpolate element-wise")
func gradientMatchingCountsInterpolate() {
  let from = Gradient(colors: [.red, .blue])
  let to = Gradient(colors: [.blue, .red])
  #expect(from.animatableData.isInterpolable(to: to.animatableData))
  var delta = to.animatableData
  delta -= from.animatableData
  delta.scale(by: 0.5)
  var result = from
  var resultData = result.animatableData
  resultData += delta
  result.animatableData = resultData
  #expect(result.stops.count == 2)
  // Each stop should be halfway between its from and to.
  let firstExpected = Color.red.interpolated(to: .blue, progress: 0.5)
  #expect(abs(result.stops[0].color.red - firstExpected.red) < 0.001)
  // Second stop should also interpolate: blue → red halfway.
  let secondExpected = Color.blue.interpolated(to: .red, progress: 0.5)
  #expect(abs(result.stops[1].color.red - secondExpected.red) < 0.001)
  #expect(abs(result.stops[1].color.blue - secondExpected.blue) < 0.001)
}

@Test("Gradient.animatableData setter no-ops on count mismatch")
func gradientSetterMismatchNoOp() {
  var g = Gradient(colors: [.red, .blue])
  let originalStops = g.stops
  // Empty replacement has count 0, which is mismatched.
  g.animatableData = AnimatableArray([])
  #expect(g.stops == originalStops)
  // Longer replacement has count 3, still mismatched.
  let threeStop = Gradient(colors: [.red, .green, .blue])
  g.animatableData = threeStop.animatableData
  #expect(g.stops == originalStops)
}

@Test("LinearGradient animatableData interpolates gradient and endpoints")
func linearGradientInterpolation() {
  let from = LinearGradient(
    colors: [.red, .blue],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )
  let to = LinearGradient(
    colors: [.blue, .red],
    startPoint: .topTrailing,
    endPoint: .bottomLeading
  )
  var delta = to.animatableData
  delta -= from.animatableData
  delta.scale(by: 0.5)
  var result = from
  var resultData = result.animatableData
  resultData += delta
  result.animatableData = resultData
  // Start point should be halfway between (0,0) and (1,0).
  #expect(abs(result.startPoint.x - 0.5) < 0.001)
  #expect(abs(result.startPoint.y - 0) < 0.001)
  // End point should be halfway between (1,1) and (0,1).
  #expect(abs(result.endPoint.x - 0.5) < 0.001)
  #expect(abs(result.endPoint.y - 1) < 0.001)
}

@Test("RadialGradient animatableData interpolates center and radii")
func radialGradientInterpolation() {
  let from = RadialGradient(
    colors: [.red, .blue],
    center: .topLeading,
    startRadius: 0,
    endRadius: 10
  )
  let to = RadialGradient(
    colors: [.blue, .red],
    center: .bottomTrailing,
    startRadius: 5,
    endRadius: 20
  )
  var delta = to.animatableData
  delta -= from.animatableData
  delta.scale(by: 0.5)
  var result = from
  var resultData = result.animatableData
  resultData += delta
  result.animatableData = resultData
  #expect(abs(result.center.x - 0.5) < 0.001)
  #expect(abs(result.center.y - 0.5) < 0.001)
  #expect(abs(result.startRadius - 2.5) < 0.001)
  #expect(abs(result.endRadius - 15) < 0.001)
}
