import Testing

@testable import Core

@Suite
struct BorderBlendTests {
  @Test("BorderBlend empty stops returns nil color")
  func borderBlendEmptyColor() {
    let blend = BorderBlend(stops: [])
    #expect(blend.color(at: 0.5) == nil)
  }

  @Test("BorderBlend single stop returns that color at every t")
  func borderBlendSingleStop() {
    let blend = BorderBlend([Color.red])
    #expect(blend.color(at: 0) == Color.red)
    #expect(blend.color(at: 0.5) == Color.red)
    #expect(blend.color(at: 1) == Color.red)
  }

  @Test("BorderBlend two stops interpolates at halfway")
  func borderBlendHalfway() {
    let blend = BorderBlend([Color.red, Color.blue])
    let mid = blend.color(at: 0.5)
    // Halfway should not equal either endpoint.
    #expect(mid != Color.red)
    #expect(mid != Color.blue)
  }

  @Test("BorderBlend clamps t out of range")
  func borderBlendClamp() {
    let blend = BorderBlend([Color.red, Color.blue])
    #expect(blend.color(at: -0.5) == Color.red)
    #expect(blend.color(at: 1.5) == Color.blue)
  }

  @Test("BorderBlend closes the loop with repeated first color")
  func borderBlendClosedLoop() {
    // Start and end colors are identical so phase rotation produces
    // a smooth closed loop.
    let blend = BorderBlend([Color.red, Color.blue, Color.red])
    let samples = blend.samplePerimeter(width: 10, height: 5, phase: 0)
    #expect(samples.first == samples.last)
  }

  @Test("BorderBlend samplePerimeter 4x3 has 10 cells")
  func borderBlendPerimeter4x3() {
    let blend = BorderBlend([Color.red, Color.blue])
    let samples = blend.samplePerimeter(width: 4, height: 3, phase: 0)
    #expect(samples.count == 10)
  }

  @Test("BorderBlend samplePerimeter 1x1 has 1 cell")
  func borderBlendPerimeter1x1() {
    let blend = BorderBlend([Color.red, Color.blue])
    let samples = blend.samplePerimeter(width: 1, height: 1, phase: 0)
    #expect(samples.count == 1)
  }

  @Test("BorderBlend samplePerimeter 1xN has N cells")
  func borderBlendPerimeter1xN() {
    let blend = BorderBlend([Color.red, Color.blue])
    let samples = blend.samplePerimeter(width: 1, height: 5, phase: 0)
    #expect(samples.count == 5)
  }

  @Test("BorderBlend samplePerimeter Nx1 has N cells")
  func borderBlendPerimeterNx1() {
    let blend = BorderBlend([Color.red, Color.blue])
    let samples = blend.samplePerimeter(width: 7, height: 1, phase: 0)
    #expect(samples.count == 7)
  }

  @Test("BorderBlend samplePerimeter phase rotation shifts samples")
  func borderBlendPhaseRotation() {
    let blend = BorderBlend([Color.red, Color.green, Color.blue, Color.red])
    let phase0 = blend.samplePerimeter(width: 10, height: 5, phase: 0)
    let phaseHalf = blend.samplePerimeter(width: 10, height: 5, phase: 0.5)
    // Same number of cells at both phases.
    #expect(phase0.count == phaseHalf.count)
    // Some cell must differ between phase 0 and phase 0.5 (otherwise
    // phase has no effect).
    var differ = false
    for i in 0..<phase0.count where phase0[i] != phaseHalf[i] {
      differ = true
      break
    }
    #expect(differ)
  }

  @Test("BorderBlend zero dimensions returns empty array")
  func borderBlendZeroDims() {
    let blend = BorderBlend([Color.red, Color.blue])
    #expect(blend.samplePerimeter(width: 0, height: 5, phase: 0).isEmpty)
    #expect(blend.samplePerimeter(width: 5, height: 0, phase: 0).isEmpty)
  }

  @Test("BorderBlend stops are sorted by location")
  func borderBlendStopsSorted() {
    let blend = BorderBlend(stops: [
      .init(color: Color.blue, location: 1.0),
      .init(color: Color.red, location: 0.0),
      .init(color: Color.green, location: 0.5),
    ])
    #expect(blend.stops.map(\.location) == [0.0, 0.5, 1.0])
    #expect(blend.stops[0].color == Color.red)
    #expect(blend.stops[1].color == Color.green)
    #expect(blend.stops[2].color == Color.blue)
  }
}
