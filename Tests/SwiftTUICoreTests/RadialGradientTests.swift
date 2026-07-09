import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@Test("RadialGradient preserves stops and radii")
func radialGradientStoresFields() {
  let g = RadialGradient(
    colors: [.red, .blue],
    center: .center,
    startRadius: 1,
    endRadius: 5
  )
  #expect(g.gradient.stops.count == 2)
  #expect(g.startRadius == 1)
  #expect(g.endRadius == 5)
}

@Test("RadialGradient erases to .radialGradient AnyShapeStyle")
func radialGradientErases() {
  let g = RadialGradient(colors: [.red, .blue], endRadius: 5)
  let any = AnyShapeStyle(g)
  if case .radialGradient(let inner) = any {
    #expect(inner.endRadius == 5)
  } else {
    Issue.record("expected .radialGradient case")
  }
}

@Test("RadialGradient is Equatable")
func radialGradientEquatable() {
  let a = RadialGradient(colors: [.red, .blue], startRadius: 0, endRadius: 5)
  let b = RadialGradient(colors: [.red, .blue], startRadius: 0, endRadius: 5)
  let c = RadialGradient(colors: [.red, .green], startRadius: 0, endRadius: 5)
  #expect(a == b)
  #expect(a != c)
}

@Test("RadialGradient opacity preserves shape")
func radialGradientOpacity() {
  let g = RadialGradient(colors: [.red, .blue], endRadius: 5)
  let faded = g.opacity(0.5)
  if case .radialGradient = faded {
    // Good — opacity preserved the case rather than wrapping in .opacity.
  } else {
    Issue.record("expected opacity to preserve radial gradient case")
  }
}
