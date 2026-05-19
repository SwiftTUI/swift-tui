import SwiftTUICore

// Layout-offload eligibility for the frame-tail renderer.
//
// The frame tail can run its layout pass on a background worker, but only when
// the resolved tree contains nothing that must run on the main actor. This
// file owns that classification: the public eligibility queries the run loop
// consults before scheduling, and the recursive tree scans that back them.
//
// Three independent disqualifiers are checked:
//
//  - custom layouts whose handle reports `canRunOnWorker == false`,
//  - indexed child sources that cannot run on a worker,
//  - layout-dependent content, which needs a prepared graph mid-layout.
//
// Visibility note: the `contains*` scans are file-internal rather than
// `private` so `renderLayoutAsync` in `FrameTailRenderer.swift` can reuse
// `containsLayoutDependentContent` directly.
extension FrameTailRenderer {
  func canOffloadLayout(
    _ input: FrameTailInput
  ) -> Bool {
    !containsMainActorOnlyCustomLayout(input.resolved)
      && !containsMainActorOnlyIndexedChildSource(input.resolved)
      && !containsLayoutDependentContent(input.resolved)
  }

  func needsIndexedChildSourceWorkerSnapshot(
    _ input: FrameTailInput
  ) -> Bool {
    !containsMainActorOnlyCustomLayout(input.resolved)
      && containsMainActorOnlyIndexedChildSource(input.resolved)
      && !containsLayoutDependentContent(input.resolved)
  }

  func needsPreparedGraphDuringLayout(
    _ input: FrameTailInput
  ) -> Bool {
    containsLayoutDependentContent(input.resolved)
  }

  func containsMainActorOnlyCustomLayout(
    _ node: ResolvedNode
  ) -> Bool {
    if case .custom(let handle) = node.layoutBehavior,
      !handle.canRunOnWorker
    {
      return true
    }
    if let workerChildren = node.indexedChildSource?.workerResolvedChildren,
      workerChildren.contains(where: containsMainActorOnlyCustomLayout)
    {
      return true
    }
    return node.children.contains { containsMainActorOnlyCustomLayout($0) }
  }

  func containsMainActorOnlyIndexedChildSource(
    _ node: ResolvedNode
  ) -> Bool {
    if let source = node.indexedChildSource {
      if !source.canRunOnWorker {
        return true
      }
      if let workerChildren = source.workerResolvedChildren,
        workerChildren.contains(where: containsMainActorOnlyIndexedChildSource)
      {
        return true
      }
    }
    return node.children.contains { containsMainActorOnlyIndexedChildSource($0) }
  }

  func containsLayoutDependentContent(
    _ node: ResolvedNode
  ) -> Bool {
    if node.layoutDependentContent != nil {
      return true
    }
    if let workerChildren = node.indexedChildSource?.workerResolvedChildren,
      workerChildren.contains(where: containsLayoutDependentContent)
    {
      return true
    }
    return node.children.contains { containsLayoutDependentContent($0) }
  }
}
