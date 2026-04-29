import Testing

@testable import Core

@Suite
struct FocusPresentationTests {
  @Test("semantic snapshot reports no focus presentation without a focused identity")
  func noFocusPresentationWithoutFocusedIdentity() {
    let snapshot = SemanticSnapshot(
      focusRegions: [
        makeFocusRegion(
          "button",
          interactions: .activate
        )
      ]
    )

    #expect(snapshot.focusPresentation(for: nil) == .none)
  }

  @Test("semantic snapshot maps focused region interactions into focus presentation semantics")
  func mapsFocusedRegionInteractions() {
    let activateIdentity = testIdentity("button")
    let automaticIdentity = testIdentity("label")
    let editIdentity = testIdentity("field")
    let snapshot = SemanticSnapshot(
      focusRegions: [
        makeFocusRegion(
          activateIdentity,
          interactions: .activate
        ),
        makeFocusRegion(
          automaticIdentity,
          interactions: .automatic
        ),
        makeFocusRegion(
          editIdentity,
          interactions: .edit
        ),
      ]
    )

    let activatePresentation = snapshot.focusPresentation(for: activateIdentity)
    #expect(activatePresentation.focusedIdentity == activateIdentity)
    #expect(activatePresentation.semantics == .activate)
    #expect(activatePresentation.prefersTextInput == false)

    let editPresentation = snapshot.focusPresentation(for: editIdentity)
    #expect(editPresentation.focusedIdentity == editIdentity)
    #expect(editPresentation.semantics == .edit)
    #expect(editPresentation.prefersTextInput)

    let automaticPresentation = snapshot.focusPresentation(for: automaticIdentity)
    #expect(automaticPresentation.focusedIdentity == automaticIdentity)
    #expect(automaticPresentation.semantics == .automatic)
    #expect(automaticPresentation.prefersTextInput == false)
  }

  @Test("semantic snapshot reports no focus presentation when the focused identity is absent")
  func missingFocusedIdentityFallsBackToNoFocus() {
    let snapshot = SemanticSnapshot(
      focusRegions: [
        makeFocusRegion(
          "button",
          interactions: .activate
        )
      ]
    )

    #expect(
      snapshot.focusPresentation(for: testIdentity("missing")) == .none
    )
  }
}

private func makeFocusRegion(
  _ identity: Identity,
  interactions: FocusInteractions
) -> FocusRegion {
  FocusRegion(
    identity: identity,
    rect: CellRect(
      origin: CellPoint(x: 0, y: 0),
      size: CellSize(width: 1, height: 1)
    ),
    focusInteractions: interactions
  )
}

private func makeFocusRegion(
  _ identity: String,
  interactions: FocusInteractions
) -> FocusRegion {
  makeFocusRegion(
    testIdentity(identity),
    interactions: interactions
  )
}
