import Testing

@testable import Core
@testable import View

@Suite
struct EnvironmentRuntimeStateTests {
  @Test("runtime focus and press state do not affect environment equality")
  func runtimeStateDoesNotAffectEquality() {
    var left = EnvironmentValues()
    left.parallelFocusedIdentity = testIdentity("Root", "Left")
    left.parallelPressedIdentity = testIdentity("Root", "Pressed")

    var right = EnvironmentValues()
    right.parallelFocusedIdentity = testIdentity("Root", "Right")
    right.parallelPressedIdentity = nil

    #expect(left == right)

    let leftContext = ResolveContext(
      identity: testIdentity("Root"),
      environmentValues: left
    )
    let rightContext = ResolveContext(
      identity: testIdentity("Root"),
      environmentValues: right
    )

    #expect(leftContext.environment == rightContext.environment)
    #expect(leftContext.environmentValues == rightContext.environmentValues)

    var stable = EnvironmentValues()
    stable.isFocusEffectEnabled = false

    #expect(left != stable)
  }
}
