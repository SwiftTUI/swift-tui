import Testing

@testable import SwiftTUI
@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite
struct PresentationActionScopeTests {
  @Test("Sheet content's focus regions include the presentation identity on scopePath")
  func sheetContributesToScopePath() throws {
    let rootIdentity = testIdentity("Root")
    let sheetLeafIdentity = testIdentity("SheetLeaf")

    let artifacts = DefaultRenderer().render(
      Text("Base")
        .sheet(
          "Inspector",
          isPresented: .constant(true)
        ) {
          Text("Sheet body")
            .focusable(true)
            .id(sheetLeafIdentity)
        }
        .frame(width: 40, height: 10, alignment: .topLeading),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 40, height: 10)
    )

    let surfaceIdentity = try #require(
      presentationSurfaceIdentity(
        in: artifacts.resolvedTree,
        containing: sheetLeafIdentity
      ),
      "No focus-scope-boundary ancestor found above the sheet content leaf."
    )

    let leafRegion = try #require(
      artifacts.semanticSnapshot.focusRegions.first { region in
        region.identity == sheetLeafIdentity
      },
      "Sheet leaf produced no focus region."
    )

    #expect(leafRegion.scopePath.contains(surfaceIdentity))
  }

  @Test("Alert content's focus regions include the presentation identity on scopePath")
  func alertContributesToScopePath() throws {
    let rootIdentity = testIdentity("Root")
    let alertButtonIdentity = testIdentity("AlertButton")

    let artifacts = DefaultRenderer().render(
      Text("Base")
        .alert(
          "Delete project",
          isPresented: .constant(true),
          actions: {
            Button("Delete") {}
              .id(alertButtonIdentity)
          },
          message: {
            Text("Are you sure?")
          }
        )
        .frame(width: 40, height: 10, alignment: .topLeading),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 40, height: 10)
    )

    let surfaceIdentity = try #require(
      presentationSurfaceIdentity(
        in: artifacts.resolvedTree,
        containing: alertButtonIdentity
      ),
      "No focus-scope-boundary ancestor found above the alert button."
    )

    let buttonRegion = try #require(
      artifacts.semanticSnapshot.focusRegions.first { region in
        region.identity == alertButtonIdentity
      },
      "Alert button produced no focus region."
    )

    #expect(buttonRegion.scopePath.contains(surfaceIdentity))
  }

  @Test(
    "Confirmation-dialog content's focus regions include the presentation identity on scopePath"
  )
  func confirmationDialogContributesToScopePath() throws {
    let rootIdentity = testIdentity("Root")
    let actionIdentity = testIdentity("ConfirmAction")

    let artifacts = DefaultRenderer().render(
      Text("Base")
        .confirmationDialog(
          "Archive task",
          isPresented: .constant(true),
          actions: {
            Button("Archive") {}
              .id(actionIdentity)
          },
          message: {
            Text("Move the task out of the active list.")
          }
        )
        .frame(width: 40, height: 10, alignment: .topLeading),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 40, height: 10)
    )

    let surfaceIdentity = try #require(
      presentationSurfaceIdentity(
        in: artifacts.resolvedTree,
        containing: actionIdentity
      ),
      "No focus-scope-boundary ancestor found above the dialog action button."
    )

    let actionRegion = try #require(
      artifacts.semanticSnapshot.focusRegions.first { region in
        region.identity == actionIdentity
      },
      "Dialog action produced no focus region."
    )

    #expect(actionRegion.scopePath.contains(surfaceIdentity))
  }

  @Test(
    "Modal presentations trap focus and restore the pre-modal focus",
    arguments: ModalPresentationKind.allCases
  )
  func modalPresentationsTrapAndRestoreFocus(kind: ModalPresentationKind) throws {
    let tracker = FocusTracker(invalidationIdentities: [testIdentity("Root")])
    let backgroundOne = testIdentity("BackgroundOne")
    let backgroundTwo = testIdentity("BackgroundTwo")
    let rootIdentity = testIdentity("Root")
    let proposal = ProposedSize(width: .finite(48), height: .finite(12))

    let closedArtifacts = DefaultRenderer().render(
      modalFocusFixture(kind: kind, isPresented: false),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )

    #expect(!tracker.updateRegions(closedArtifacts.semanticSnapshot.focusRegions))
    #expect(tracker.setFocus(to: backgroundTwo))

    let openArtifacts = DefaultRenderer().render(
      modalFocusFixture(kind: kind, isPresented: true),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )
    let openFocusIdentities = Set(openArtifacts.semanticSnapshot.focusRegions.map(\.identity))

    #expect(tracker.updateRegions(openArtifacts.semanticSnapshot.focusRegions))
    #expect(!openFocusIdentities.contains(backgroundOne))
    #expect(!openFocusIdentities.contains(backgroundTwo))

    let initialModalFocus = try #require(tracker.currentFocusIdentity)
    #expect(openFocusIdentities.contains(initialModalFocus))

    for _ in 0..<(openFocusIdentities.count + 1) {
      _ = tracker.focusNext()
      let currentFocus = try #require(tracker.currentFocusIdentity)
      #expect(openFocusIdentities.contains(currentFocus))
    }

    #expect(tracker.updateRegions(closedArtifacts.semanticSnapshot.focusRegions))
    #expect(tracker.currentFocusIdentity == backgroundTwo)
  }

  @Test(
    """
    Leaf inside a sheet within a WindowHostView has scene identity first \
    and sheet identity later on scopePath
    """
  )
  func sheetScopePathOrderedWithSceneAtRoot() throws {
    let sceneIdentity = testIdentity("App", "test-window")
    let sheetLeafIdentity = testIdentity("SheetLeaf")

    let artifacts = DefaultRenderer().render(
      WindowHostView(
        content: Text("Base")
          .sheet(
            "Inspector",
            isPresented: .constant(true)
          ) {
            Text("Sheet body")
              .focusable(true)
              .id(sheetLeafIdentity)
          }
      ),
      context: .init(identity: sceneIdentity),
      proposal: .init(width: 40, height: 10)
    )

    let sheetSurfaceIdentity = try #require(
      presentationSurfaceIdentity(
        in: artifacts.resolvedTree,
        containing: sheetLeafIdentity
      ),
      "No focus-scope-boundary ancestor found above the sheet content leaf."
    )

    let leafRegion = try #require(
      artifacts.semanticSnapshot.focusRegions.first { region in
        region.identity == sheetLeafIdentity
      },
      "Sheet leaf produced no focus region."
    )

    // Scene identity must land BEFORE the sheet identity: a
    // scene-level `keyCommand` must be reachable from the sheet's
    // leaf `scopePath` for shallowest-wins resolution to route it.
    #expect(leafRegion.scopePath.first == sceneIdentity)

    let sceneIndex = try #require(
      leafRegion.scopePath.firstIndex(of: sceneIdentity),
      "Scene identity missing from sheet leaf scopePath."
    )
    let sheetIndex = try #require(
      leafRegion.scopePath.firstIndex(of: sheetSurfaceIdentity),
      "Sheet surface identity missing from sheet leaf scopePath."
    )
    #expect(sceneIndex < sheetIndex)
  }
}

enum ModalPresentationKind: CaseIterable, CustomStringConvertible, Sendable {
  case sheet
  case alert
  case confirmationDialog

  var description: String {
    switch self {
    case .sheet:
      "sheet"
    case .alert:
      "alert"
    case .confirmationDialog:
      "confirmationDialog"
    }
  }
}

@MainActor
@ViewBuilder
private func modalFocusFixture(
  kind: ModalPresentationKind,
  isPresented: Bool
) -> some View {
  let base = VStack(alignment: .leading, spacing: 1) {
    Button("Background One") {}
      .id(testIdentity("BackgroundOne"))
    Button("Background Two") {}
      .id(testIdentity("BackgroundTwo"))
  }
  .frame(width: 48, height: 12, alignment: .topLeading)

  switch kind {
  case .sheet:
    base.sheet("Inspector", isPresented: .constant(isPresented)) {
      Button("Close Inspector") {}
        .id(testIdentity("ModalAction"))
    }
  case .alert:
    base.alert(
      "Delete project",
      isPresented: .constant(isPresented),
      actions: {
        Button("Delete") {}
          .id(testIdentity("ModalAction"))
        Button("Cancel") {}
          .id(testIdentity("ModalCancel"))
      },
      message: {
        Text("This cannot be undone.")
      }
    )
  case .confirmationDialog:
    base.confirmationDialog(
      "Archive task",
      isPresented: .constant(isPresented),
      actions: {
        Button("Archive") {}
          .id(testIdentity("ModalAction"))
        Button("Cancel") {}
          .id(testIdentity("ModalCancel"))
      },
      message: {
        Text("Move the task out of the active list.")
      }
    )
  }
}

/// Walks the resolved tree searching for the nearest ancestor of
/// `leafIdentity` that marks itself `focusScopeBoundary` — this is the
/// presentation surface's scope identity.
@MainActor
private func presentationSurfaceIdentity(
  in root: ResolvedNode,
  containing leafIdentity: Identity
) -> Identity? {
  var result: Identity?
  _ = findPresentationSurfaceIdentity(
    node: root,
    leafIdentity: leafIdentity,
    ancestorBoundary: nil,
    result: &result
  )
  return result
}

@MainActor
private func findPresentationSurfaceIdentity(
  node: ResolvedNode,
  leafIdentity: Identity,
  ancestorBoundary: Identity?,
  result: inout Identity?
) -> Bool {
  if node.identity == leafIdentity {
    result = ancestorBoundary
    return true
  }

  let nextBoundary: Identity? =
    node.semanticMetadata.focusScopeBoundary
    ? node.identity
    : ancestorBoundary

  for child in node.children {
    if findPresentationSurfaceIdentity(
      node: child,
      leafIdentity: leafIdentity,
      ancestorBoundary: nextBoundary,
      result: &result
    ) {
      return true
    }
  }
  return false
}
