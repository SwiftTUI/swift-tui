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

  @Test("BorderBlend perimeter samples a closed palette without duplicating at the seam")
  func borderBlendClosedLoop() {
    // For a closed palette like [red, blue, red], the gradient wraps
    // continuously around the perimeter. The last cell is at
    // t = (total - 1) / total (just-before-red), NOT red itself — if
    // it *were* red, the adjacent cell 0 (which is also red) would
    // produce a visible two-cell seam at the top-left corner.
    let blend = BorderBlend([Color.red, Color.blue, Color.red])
    let samples = blend.samplePerimeter(width: 10, height: 5, phase: 0)
    // Perimeter cell count for 10x5 is 2 * (10 + 5) - 4 = 26.
    #expect(samples.count == 26)
    // Cell 0 is at t = 0: pure red.
    #expect(samples[0] == Color.red)
    // Cell 13 is at t = 0.5: approximately blue (perceptual mid).
    // It should NOT be red.
    #expect(samples[13] != Color.red)
    // Cell (total - 1) is at t = 25/26 ≈ 0.96: close to, but NOT,
    // pure red. If this collides with cell 0 (which is red) we have a
    // duplicate-color seam.
    #expect(samples[25] != Color.red)
  }

  @Test("BorderBlend samplePerimeter spaces cells uniformly at 1/total apart")
  func borderBlendUniformSpacing() {
    // For a two-stop gradient [red, blue], each cell samples at
    // t = i / total. The difference in t between cell i and cell
    // i + 1 is exactly 1 / total regardless of perimeter size. We
    // can't observe t directly, but we can test that a phase shift of
    // exactly 1 / total produces the same color as moving forward one
    // cell: `samples_at_phase_0[i + 1] == samples_at_phase_1/N[i]`.
    let blend = BorderBlend([Color.red, Color.blue])
    let phase0 = blend.samplePerimeter(width: 10, height: 5, phase: 0)
    let total = phase0.count  // 26
    let phaseOneCell = blend.samplePerimeter(
      width: 10,
      height: 5,
      phase: 1.0 / Double(total)
    )
    // Cell i + 1 at phase 0 should equal cell i at phase 1/total
    // (modulo wrap). Check every pair except the wrap-around slot.
    // Use a small deltaE tolerance because perceptual blending goes
    // through Lab/linear-sRGB round-trips that accumulate sub-ULP
    // noise for "same" sample points.
    for i in 0..<(total - 1) {
      #expect(phase0[i + 1].isApproximatelyEqual(to: phaseOneCell[i], deltaE: 0.01))
    }
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
