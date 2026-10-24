import Testing

@testable import SwiftTUICore

@MainActor
@Suite(.serialized)
struct AdversarialSetCGradientTests {
  @Test(arguments: [81, 82])
  func wholeGradientAssignment(id: Int) {
    let early = Gradient(stops: [
      .init(color: .red, location: 0), .init(color: .blue, location: 0.2),
    ])
    let late = Gradient(stops: [
      .init(color: .green, location: 0.8), .init(color: .white, location: 1),
    ])
    var actual = id == 81 ? early : late
    let target = id == 81 ? late : early
    actual.animatableData = target.animatableData
    if id == 81 {
      setCKnown("STUI-1127: per-element sorting changes later gradient stop indices") {
        #expect((actual.animatableData - target.animatableData).magnitudeSquared < 0.000_000_01)
      }
    } else {
      #expect((actual.animatableData - target.animatableData).magnitudeSquared < 0.000_000_01)
    }
  }

  @Test func setC083StopDataClampsLocationsWithoutChangingColor() {
    var stop = Gradient.Stop(color: .red, location: 0.5)
    let color = stop.color.animatableData
    for (input, expected) in [(-0.5, 0.0), (1.5, 1.0)] {
      var data = stop.animatableData
      data.second = input
      stop.animatableData = data
      #expect(stop.location == expected)
      #expect((stop.color.animatableData - color).magnitudeSquared < 0.000_000_01)
    }
  }

  @Test func setC084EmptyGradientRejectsDifferentCardinality() {
    var gradient = Gradient(colors: [])
    gradient.animatableData = Gradient(colors: []).animatableData
    #expect(gradient.stops.isEmpty)
    gradient.animatableData = Gradient(colors: [.red]).animatableData
    #expect(gradient.stops.isEmpty)
  }

  @Test func setC085SingleStopRetargetsBothComponents() {
    var gradient = Gradient(colors: [.red])
    for target in [
      Gradient(stops: [.init(color: .blue, location: 0.7)]),
      Gradient(stops: [.init(color: .green, location: 0.2)]),
    ] {
      gradient.animatableData = target.animatableData
      #expect((gradient.animatableData - target.animatableData).magnitudeSquared < 0.000_000_01)
    }
  }

  @Test func setC086LinearEndpointsRetargetIndependently() {
    var gradient = LinearGradient(
      colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
    for pair in [
      (UnitPoint(x: 0.2, y: 0.8), UnitPoint(x: 0.9, y: 0.1)),
      (UnitPoint(x: 0.7, y: 0.4), UnitPoint(x: 0.3, y: 0.6)),
    ] {
      let target = LinearGradient(gradient: gradient.gradient, startPoint: pair.0, endPoint: pair.1)
      gradient.animatableData = target.animatableData
      #expect(gradient.startPoint == pair.0)
      #expect(gradient.endPoint == pair.1)
    }
  }

  @Test func setC087RadialGeometryRetargetsIndependently() {
    var gradient = RadialGradient(colors: [.red, .blue], startRadius: 0, endRadius: 10)
    let target = RadialGradient(
      gradient: gradient.gradient, center: .init(x: 0.25, y: 0.75), startRadius: 3, endRadius: 17)
    gradient.animatableData = target.animatableData
    #expect(gradient.center == target.center)
    #expect(gradient.startRadius == 3)
    #expect(gradient.endRadius == 17)
  }

  @Test func setC088AngularGeometryPreservesUnwrappedTurns() {
    var gradient = AngularGradient(colors: [.red, .blue])
    let target = AngularGradient(
      gradient: gradient.gradient, center: .topLeading,
      startAngle: .radians(3 * .pi), endAngle: .radians(7 * .pi))
    gradient.animatableData = target.animatableData
    #expect(gradient.center == .topLeading)
    #expect(gradient.startAngle == target.startAngle)
    #expect(gradient.endAngle == target.endAngle)
  }

  @Test func setC089MeshCountRejectionIsAtomicAcrossComponents() {
    var mesh = MeshGradient(
      width: 2, height: 2,
      points: [.init(0, 0), .init(1, 0), .init(0, 1), .init(1, 1)],
      colors: [.red, .green, .blue, .white], background: .black)
    let original = mesh
    var data = mesh.animatableData
    data.first.first.elements[0].first = 0.25
    data.first.second.elements.removeLast()
    data.second = Color.white.animatableData
    mesh.animatableData = data
    #expect(mesh == original)
  }

  @Test func setC090EqualControlCountDoesNotImplySameMeshTopology() {
    let a = MeshGradient(
      width: 2, height: 3,
      points: [.init(0, 0), .init(1, 0), .init(0, 0.5), .init(1, 0.5), .init(0, 1), .init(1, 1)],
      colors: Array(repeating: .red, count: 6))
    let b = MeshGradient(
      width: 3, height: 2,
      points: [.init(0, 0), .init(0.5, 0), .init(1, 0), .init(0, 1), .init(0.5, 1), .init(1, 1)],
      colors: Array(repeating: .blue, count: 6))
    #expect(a.points.count == b.points.count)
    #expect(!a.isInterpolable(to: b))
  }
}
