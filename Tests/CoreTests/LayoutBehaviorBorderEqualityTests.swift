import Testing

@testable import Core

@Suite
struct LayoutBehaviorBorderEqualityTests {
  @Test("LayoutBehavior.border is equal when all fields match")
  func layoutBehaviorBorderEquality() {
    let a = LayoutBehavior.border(
      .single,
      foreground: BorderEdgeStyle(Color.red),
      background: nil,
      blend: nil,
      blendPhase: 0.5,
      sides: .all
    )
    let b = LayoutBehavior.border(
      .single,
      foreground: BorderEdgeStyle(Color.red),
      background: nil,
      blend: nil,
      blendPhase: 0.5,
      sides: .all
    )
    #expect(a == b)
  }

  @Test("LayoutBehavior.border differs when set differs")
  func layoutBehaviorBorderDifferentSet() {
    let a = LayoutBehavior.border(
      .single,
      foreground: nil,
      background: nil,
      blend: nil,
      blendPhase: 0,
      sides: .all
    )
    let b = LayoutBehavior.border(
      .rounded,
      foreground: nil,
      background: nil,
      blend: nil,
      blendPhase: 0,
      sides: .all
    )
    #expect(a != b)
  }

  @Test("LayoutBehavior.border differs when phase differs")
  func layoutBehaviorBorderDifferentPhase() {
    let a = LayoutBehavior.border(
      .single,
      foreground: nil,
      background: nil,
      blend: nil,
      blendPhase: 0,
      sides: .all
    )
    let b = LayoutBehavior.border(
      .single,
      foreground: nil,
      background: nil,
      blend: nil,
      blendPhase: 0.5,
      sides: .all
    )
    #expect(a != b)
  }

  @Test("LayoutBehavior.border differs when sides differ")
  func layoutBehaviorBorderDifferentSides() {
    let a = LayoutBehavior.border(
      .single,
      foreground: nil,
      background: nil,
      blend: nil,
      blendPhase: 0,
      sides: .all
    )
    let b = LayoutBehavior.border(
      .single,
      foreground: nil,
      background: nil,
      blend: nil,
      blendPhase: 0,
      sides: .horizontal
    )
    #expect(a != b)
  }

  @Test("LayoutBehavior.border differs when foreground differs (nil vs non-nil)")
  func layoutBehaviorBorderDifferentForeground() {
    let a = LayoutBehavior.border(
      .single,
      foreground: nil,
      background: nil,
      blend: nil,
      blendPhase: 0,
      sides: .all
    )
    let b = LayoutBehavior.border(
      .single,
      foreground: BorderEdgeStyle(Color.red),
      background: nil,
      blend: nil,
      blendPhase: 0,
      sides: .all
    )
    #expect(a != b)
  }
}
