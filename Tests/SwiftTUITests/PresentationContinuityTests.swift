import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUI
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct PresentationContinuityTests {
  @Test("alert activation keeps the displayed base identity stable")
  func alertActivationKeepsDisplayedBaseIdentityStable() throws {
    let renderer = DefaultRenderer()
    let rootIdentity = testIdentity("Root")

    let initialArtifacts = renderer.render(
      alertContinuityRoot(isPresented: false),
      context: .init(identity: rootIdentity),
      proposal: continuityProposal
    )
    let shownArtifacts = renderer.render(
      alertContinuityRoot(isPresented: true),
      context: .init(identity: rootIdentity),
      proposal: continuityProposal
    )
    let dismissedArtifacts = renderer.render(
      alertContinuityRoot(isPresented: false),
      context: .init(identity: rootIdentity),
      proposal: continuityProposal
    )

    let initialIdentity = try #require(
      initialArtifacts.resolvedTree.descendant(withText: "Base probe")?.identity
    )
    let shownIdentity = try #require(
      shownArtifacts.resolvedTree.descendant(withText: "Base probe")?.identity
    )
    let dismissedIdentity = try #require(
      dismissedArtifacts.resolvedTree.descendant(withText: "Base probe")?.identity
    )

    #expect(shownIdentity == initialIdentity)
    #expect(dismissedIdentity == initialIdentity)
    #expect(shownArtifacts.resolvedTree.descendant(withText: "Alert body") != nil)
  }

  @Test("sheet activation keeps the displayed base identity stable")
  func sheetActivationKeepsDisplayedBaseIdentityStable() throws {
    let renderer = DefaultRenderer()
    let rootIdentity = testIdentity("Root")

    let initialArtifacts = renderer.render(
      sheetContinuityRoot(isPresented: false),
      context: .init(identity: rootIdentity),
      proposal: continuityProposal
    )
    let shownArtifacts = renderer.render(
      sheetContinuityRoot(isPresented: true),
      context: .init(identity: rootIdentity),
      proposal: continuityProposal
    )
    let dismissedArtifacts = renderer.render(
      sheetContinuityRoot(isPresented: false),
      context: .init(identity: rootIdentity),
      proposal: continuityProposal
    )

    let initialIdentity = try #require(
      initialArtifacts.resolvedTree.descendant(withText: "Base probe")?.identity
    )
    let shownIdentity = try #require(
      shownArtifacts.resolvedTree.descendant(withText: "Base probe")?.identity
    )
    let dismissedIdentity = try #require(
      dismissedArtifacts.resolvedTree.descendant(withText: "Base probe")?.identity
    )

    #expect(shownIdentity == initialIdentity)
    #expect(dismissedIdentity == initialIdentity)
    #expect(shownArtifacts.resolvedTree.descendant(withText: "Sheet body") != nil)
  }

  @Test("sheet overlay lifecycle starts on presentation and stops on dismissal")
  func sheetOverlayLifecycleStartsAndStopsWithTheOverlay() throws {
    let renderer = DefaultRenderer()
    let rootIdentity = testIdentity("Root")

    _ = renderer.render(
      sheetLifecycleRoot(isPresented: false),
      context: .init(identity: rootIdentity),
      proposal: continuityProposal
    )
    let shownArtifacts = renderer.render(
      sheetLifecycleRoot(isPresented: true),
      context: .init(identity: rootIdentity),
      proposal: continuityProposal
    )

    let overlayIdentity = try #require(
      shownArtifacts.resolvedTree.descendant(withText: "Sheet overlay probe")?.identity
    )
    let shownOperations = lifecycleOperations(
      for: overlayIdentity,
      in: shownArtifacts
    )

    #expect(shownOperations.filter(isAppear).count == 1)
    #expect(shownOperations.filter(isTaskStart).count == 1)

    let dismissedArtifacts = renderer.render(
      sheetLifecycleRoot(isPresented: false),
      context: .init(identity: rootIdentity),
      proposal: continuityProposal
    )
    let dismissedOperations = lifecycleOperations(
      for: overlayIdentity,
      in: dismissedArtifacts
    )

    #expect(dismissedOperations.filter(isTaskCancel).count == 1)
    #expect(dismissedOperations.filter(isDisappear).count == 1)
  }

  @Test("toast activation keeps the focused base control identity stable")
  func toastActivationKeepsFocusedBaseControlIdentityStable() throws {
    let renderer = DefaultRenderer()
    let rootIdentity = testIdentity("Root")

    let initialArtifacts = renderer.render(
      toastContinuityRoot(isPresented: false),
      context: .init(identity: rootIdentity),
      proposal: continuityProposal
    )
    let shownArtifacts = renderer.render(
      toastContinuityRoot(isPresented: true),
      context: .init(identity: rootIdentity),
      proposal: continuityProposal
    )
    let dismissedArtifacts = renderer.render(
      toastContinuityRoot(isPresented: false),
      context: .init(identity: rootIdentity),
      proposal: continuityProposal
    )

    let initialFocusedIdentity = try #require(
      initialArtifacts.semanticSnapshot.focusRegions.first?.identity
    )
    let shownFocusedIdentity = try #require(
      shownArtifacts.semanticSnapshot.focusRegions.first?.identity
    )
    let dismissedFocusedIdentity = try #require(
      dismissedArtifacts.semanticSnapshot.focusRegions.first?.identity
    )

    #expect(shownFocusedIdentity == initialFocusedIdentity)
    #expect(dismissedFocusedIdentity == initialFocusedIdentity)
    #expect(
      shownArtifacts.rasterSurface.lines.joined(separator: "\n").contains("Saved successfully"))
  }

  @Test("sheet activation does not emit base lifecycle churn")
  func sheetActivationDoesNotEmitBaseLifecycleChurn() throws {
    let renderer = DefaultRenderer()
    let rootIdentity = testIdentity("Root")

    let initialArtifacts = renderer.render(
      baseLifecycleRoot(isPresented: false),
      context: .init(identity: rootIdentity),
      proposal: continuityProposal
    )
    let baseIdentity = try #require(
      initialArtifacts.resolvedTree.descendant(withText: "Base lifecycle probe")?.identity
    )

    let shownArtifacts = renderer.render(
      baseLifecycleRoot(isPresented: true),
      context: .init(identity: rootIdentity),
      proposal: continuityProposal
    )
    let dismissedArtifacts = renderer.render(
      baseLifecycleRoot(isPresented: false),
      context: .init(identity: rootIdentity),
      proposal: continuityProposal
    )

    #expect(lifecycleOperations(for: baseIdentity, in: shownArtifacts).isEmpty)
    #expect(lifecycleOperations(for: baseIdentity, in: dismissedArtifacts).isEmpty)
  }
}

private let continuityProposal = ProposedSize(width: .finite(40), height: .finite(10))

@MainActor
private func alertContinuityRoot(
  isPresented: Bool
) -> some View {
  Text("Base probe")
    .alert(
      "Delete project",
      isPresented: .constant(isPresented),
      actions: {
        Button("Delete") {}
      },
      message: {
        Text("Alert body")
      }
    )
    .frame(width: 40, height: 10, alignment: .topLeading)
}

@MainActor
private func sheetContinuityRoot(
  isPresented: Bool
) -> some View {
  Text("Base probe")
    .sheet(
      "Inspector",
      isPresented: .constant(isPresented)
    ) {
      Text("Sheet body")
    }
    .frame(width: 40, height: 10, alignment: .topLeading)
}

@MainActor
private func sheetLifecycleRoot(
  isPresented: Bool
) -> some View {
  Text("Base probe")
    .sheet(
      "Inspector",
      isPresented: .constant(isPresented)
    ) {
      Text("Sheet overlay probe")
        .onAppear {}
        .onDisappear {}
        .task(id: "overlay-load") {}
    }
    .frame(width: 40, height: 10, alignment: .topLeading)
}

@MainActor
private func toastContinuityRoot(
  isPresented: Bool
) -> some View {
  Button("Base button") {}
    .toast(
      "Saved successfully",
      isPresented: .constant(isPresented),
      style: .success,
      duration: nil
    )
    .frame(width: 40, height: 10, alignment: .topLeading)
}

@MainActor
private func baseLifecycleRoot(
  isPresented: Bool
) -> some View {
  Text("Base lifecycle probe")
    .onAppear {}
    .onDisappear {}
    .task(id: "base-load") {}
    .sheet(
      "Inspector",
      isPresented: .constant(isPresented)
    ) {
      Text("Sheet body")
    }
    .frame(width: 40, height: 10, alignment: .topLeading)
}

private func lifecycleOperations(
  for identity: Identity,
  in artifacts: FrameArtifacts
) -> [LifecycleCommitOperation] {
  artifacts.commitPlan.lifecycle
    .filter { $0.identity == identity }
    .map(\.operation)
}

private func isAppear(
  _ operation: LifecycleCommitOperation
) -> Bool {
  if case .appear = operation {
    return true
  }
  return false
}

private func isDisappear(
  _ operation: LifecycleCommitOperation
) -> Bool {
  if case .disappear = operation {
    return true
  }
  return false
}

private func isTaskStart(
  _ operation: LifecycleCommitOperation
) -> Bool {
  if case .taskStart = operation {
    return true
  }
  return false
}

private func isTaskCancel(
  _ operation: LifecycleCommitOperation
) -> Bool {
  if case .taskCancel = operation {
    return true
  }
  return false
}

extension ResolvedNode {
  fileprivate func descendant(
    withText text: String
  ) -> ResolvedNode? {
    if case .text(let value) = drawPayload, value == text {
      return self
    }

    for child in children {
      if let match = child.descendant(withText: text) {
        return match
      }
    }

    return nil
  }
}
