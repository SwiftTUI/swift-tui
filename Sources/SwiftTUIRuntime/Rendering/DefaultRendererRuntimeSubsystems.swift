import SwiftTUICore
import SwiftTUIViews

/// Returns the authored content root from the portal-hosted graph root.
func renderPipelineTree(
  from graphRoot: ResolvedNode
) -> ResolvedNode {
  guard graphRoot.kind == .view("PresentationPortalRoot"),
    graphRoot.children.count == 1,
    let contentRoot = graphRoot.children.first
  else {
    return graphRoot
  }

  return contentRoot
}

@MainActor
final class CommittedPresentationDismissStack {
  private var stack = DismissStack()

  func topmostEscapeDismissAction() -> (@MainActor @Sendable () -> Void)? {
    stack.topmostEscapeDismissAction()
  }

  func store(_ stack: DismissStack) {
    self.stack = stack
  }
}

@MainActor
final class DebugObservationBridgeTracker {
  weak var bridge: ObservationBridge?

  func store(_ bridge: ObservationBridge?) {
    self.bridge = bridge
  }
}

package struct RuntimeSubsystemSnapshot: Equatable {
  package struct PresentationPortalSnapshot: Equatable {
    package struct EntrySnapshot: Equatable {
      package var id: String
      package var ordering: PortalOrdering
      package var kindName: String
      package var modalPolicy: PortalModalPolicy
      package var acceptsEscape: Bool
      package var hasDismissAction: Bool
    }

    package var overlayEntries: [EntrySnapshot]
  }

  package struct ObservationBridgeSnapshot: Equatable {
    package var currentPass: UInt64
    package var observedPasses: [Identity: UInt64]
    package var invalidatorID: ObjectIdentifier?
    package var viewGraphID: ObjectIdentifier?
  }

  package var viewGraph: ViewGraph.DebugTotalStateSnapshot
  package var frameState: FrameResolveState.DebugStateSnapshot
  package var frameInputs: FrameResolveInputBox.DebugStateSnapshot
  package var presentationPortalState: PresentationPortalSnapshot
  package var observationBridge: ObservationBridgeSnapshot?
  package var animationController: AnimationController.DebugStateSnapshot
}
