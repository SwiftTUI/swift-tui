/// Execution mode advertised by a custom layout.
package enum CustomLayoutExecutionCapability: Equatable, Sendable {
  case mainActorOnly
  case worker
}

/// Vocabulary-only façade over a custom layout, stored in `LayoutBehavior.custom`
/// so a graph node can carry a custom layout without naming the render engine.
/// The engine-typed measurement/placement surface lives on the render-side
/// conformer (`CustomLayoutHandle`); the layout engine downcasts to reach it.
/// This is the custom-layout analog of the `PlacedNode`→`ViewportVisibilitySummary`
/// seam: the engine coupling is inverted behind an abstract token.
package protocol CustomLayoutToken: AnyObject, Sendable {
  var debugName: String { get }
  var executionCapability: CustomLayoutExecutionCapability { get }
  var canRunOnWorker: Bool { get }
  var measurementReuseSignature: String? { get }
  var placementReuseSignature: String? { get }
}
