import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

// The frame-input refresh (`applyingCurrentFrameResolveInputs`) keeps captured
// evaluator contexts in sync with frame-level focus/press so finite
// suppression scopes can replace root-forced evaluation. These tests pin the
// provenance contract: frame-level values refresh, authored `.environment` /
// `.transformEnvironment` writes win below their modifier.
@MainActor
@Suite
struct ResolveContextFrameInputRefreshTests {
  @Test("frame-level focus and press refresh from current-frame inputs")
  func frameLevelFocusAndPressRefreshFromInputs() {
    let previousFocus = testIdentity("Root", "Previous")
    let currentFocus = testIdentity("Root", "Current")
    let pressed = testIdentity("Root", "Pressed")
    var context = resolveContext(focusedIdentity: previousFocus)
    context.frameInputs = inputBox(
      focusedIdentity: currentFocus,
      pressedIdentity: pressed
    )

    let refreshed = context.applyingCurrentFrameResolveInputs()

    #expect(refreshed.environmentValues.focusedIdentity == currentFocus)
    #expect(refreshed.environmentValues.pressedIdentity == pressed)
  }

  @Test("authored focus environment write survives the frame-input refresh")
  func authoredFocusWriteSurvivesRefresh() {
    let authoredFocus = testIdentity("Root", "Authored")
    let frameFocus = testIdentity("Root", "FrameLevel")
    let framePressed = testIdentity("Root", "FramePressed")
    var context = resolveContext()
      .settingEnvironment(\.focusedIdentity, to: authoredFocus)
    context.frameInputs = inputBox(
      focusedIdentity: frameFocus,
      pressedIdentity: framePressed
    )

    let refreshed = context.applyingCurrentFrameResolveInputs()

    #expect(refreshed.environmentValues.focusedIdentity == authoredFocus)
    #expect(refreshed.environmentValues.pressedIdentity == framePressed)
  }

  @Test("authored press environment write survives the frame-input refresh")
  func authoredPressWriteSurvivesRefresh() {
    let authoredPressed = testIdentity("Root", "AuthoredPressed")
    let frameFocus = testIdentity("Root", "FrameLevel")
    var context = resolveContext()
      .settingEnvironment(\.pressedIdentity, to: authoredPressed)
    context.frameInputs = inputBox(
      focusedIdentity: frameFocus,
      pressedIdentity: nil
    )

    let refreshed = context.applyingCurrentFrameResolveInputs()

    #expect(refreshed.environmentValues.pressedIdentity == authoredPressed)
    #expect(refreshed.environmentValues.focusedIdentity == frameFocus)
  }

  @Test("authored focus transform survives the frame-input refresh")
  func authoredFocusTransformSurvivesRefresh() {
    let authoredFocus = testIdentity("Root", "Authored")
    var context = resolveContext()
      .transformingEnvironment(\.focusedIdentity) { focus in
        focus = authoredFocus
      }
    context.frameInputs = inputBox(focusedIdentity: nil, pressedIdentity: nil)

    let refreshed = context.applyingCurrentFrameResolveInputs()

    #expect(refreshed.environmentValues.focusedIdentity == authoredFocus)
  }

  @Test("whole-values transform writing focus survives the frame-input refresh")
  func wholeValuesTransformWritingFocusSurvivesRefresh() {
    let authoredFocus = testIdentity("Root", "Authored")
    var context = resolveContext()
      .transformingEnvironment(\.self) { values in
        values.focusedIdentity = authoredFocus
      }
    context.frameInputs = inputBox(focusedIdentity: nil, pressedIdentity: nil)

    let refreshed = context.applyingCurrentFrameResolveInputs()

    #expect(refreshed.environmentValues.focusedIdentity == authoredFocus)
  }

  @Test("derived child contexts inherit the authored override across the refresh")
  func derivedChildContextsInheritAuthoredOverride() {
    let authoredFocus = testIdentity("Root", "Authored")
    let frameFocus = testIdentity("Root", "FrameLevel")
    var child = resolveContext()
      .settingEnvironment(\.focusedIdentity, to: authoredFocus)
      .child(component: IdentityComponent(rawValue: "Interior"))
      .child(component: IdentityComponent(rawValue: "Leaf"))
    child.frameInputs = inputBox(
      focusedIdentity: frameFocus,
      pressedIdentity: nil
    )

    let refreshed = child.applyingCurrentFrameResolveInputs()

    #expect(refreshed.environmentValues.focusedIdentity == authoredFocus)
  }

  @Test("refresh re-derives isFocused against the surviving authored focus")
  func refreshRederivesIsFocusedAgainstAuthoredFocus() {
    let authoredFocus = testIdentity("Root", "Focusable")
    var context = resolveContext()
      .settingEnvironment(\.focusedIdentity, to: authoredFocus)
      .replacingIdentity(with: authoredFocus)
    context.frameInputs = inputBox(focusedIdentity: nil, pressedIdentity: nil)

    let refreshed = context.applyingCurrentFrameResolveInputs()

    #expect(refreshed.environmentValues.focusedIdentity == authoredFocus)
    #expect(refreshed.environmentValues.isFocused)
  }
}

private func resolveContext(
  focusedIdentity: Identity? = nil,
  pressedIdentity: Identity? = nil
) -> ResolveContext {
  var environmentValues = EnvironmentValues()
  environmentValues.focusedIdentity = focusedIdentity
  environmentValues.pressedIdentity = pressedIdentity
  return ResolveContext(
    identity: testIdentity("Root"),
    environmentValues: environmentValues,
    applyEnvironmentValues: true
  )
}

@MainActor
private func inputBox(
  focusedIdentity: Identity?,
  pressedIdentity: Identity?
) -> FrameResolveInputBox {
  var environmentValues = EnvironmentValues()
  environmentValues.focusedIdentity = focusedIdentity
  environmentValues.pressedIdentity = pressedIdentity
  let box = FrameResolveInputBox()
  box.store(
    FrameResolveInputs(
      invalidatedIdentities: [],
      invalidationSummary: .init(invalidatedIdentities: []),
      environmentValues: environmentValues,
      environment: .init(),
      focusedValues: .init(),
      transaction: .init(),
      resolveWorkTracker: nil,
      proposal: ProposedSize(width: 80, height: 24),
      usesSelectiveEvaluation: true,
      environmentRequiresRootEvaluation: false
    )
  )
  return box
}
