import SwiftTUICore
import SwiftTUIViews

package enum PresentationSurfaceRoleError: Error, Equatable, Sendable {
  case missingTerminalCommandSurface
  case missingRasterPresentationSurface
}

extension RunLoop {
  package var usesTerminalCursorForTextInput: Bool {
    runtimeConfiguration.output == .tui
      && presentationSurface is any TerminalCursorFocusPresentationSurface
  }

  package func presentCommittedFrame(
    _ artifacts: FrameArtifacts,
    damage: PresentationDamage?
  ) throws -> TerminalPresentationMetrics {
    if runtimeConfiguration.output == .json {
      return try presentJSONFrame(
        artifacts,
        focusedIdentity: focusTracker.currentFocusIdentity
      )
    }

    if runtimeConfiguration.output == .accessible {
      return try presentLinearAccessibilityFrame(
        semanticSnapshot: artifacts.semanticSnapshot
      )
    }

    let metrics: TerminalPresentationMetrics
    if let semanticHostFrameSurface =
      presentationSurface as? any SemanticHostFramePresentationSurface
    {
      let sequence = nextSemanticHostFrameSequence
      nextSemanticHostFrameSequence &+= 1
      metrics = try semanticHostFrameSurface.present(
        SemanticHostFrame(
          sequence: sequence,
          raster: artifacts.rasterSurface,
          semantics: semanticSnapshotWithScrollOffsets(artifacts.semanticSnapshot),
          focusedIdentity: focusTracker.currentFocusIdentity,
          rasterDamage: damage,
          preferredLayoutSize: preferredHostLayoutSize(for: artifacts)
        )
      )
    } else if let damageAwareHost = presentationSurface as? any DamageAwarePresentationSurface {
      metrics = try damageAwareHost.present(
        artifacts.rasterSurface,
        damage: damage
      )
    } else if let rasterSurface = presentationSurface as? any RasterPresentationSurface {
      metrics = try rasterSurface.present(artifacts.rasterSurface)
    } else {
      throw PresentationSurfaceRoleError.missingRasterPresentationSurface
    }
    try applyTerminalCursorFocusPolicy(semanticSnapshot: artifacts.semanticSnapshot)
    return metrics
  }

  /// Returns the snapshot with each scroll route's `contentOffset` populated
  /// from the live scroll-position registry, so every `SemanticHostFrame` host
  /// (web, Android, native SwiftUI) can publish per-region scroll-extent
  /// metadata: viewport rect, live offset, and content size. Hosts use it for
  /// scroll-chaining (web) and may use it for native nested-scroll routing.
  /// Returns the snapshot unchanged when it has no scrollable regions. Applied
  /// only on the `SemanticHostFrame` presentation path; the stored/committed
  /// snapshot is left untouched so frame-reuse equality is unaffected. See
  /// `docs/proposals/EMBEDDED_WEB_SCROLL_CHAINING.md` and
  /// `docs/plans/2026-06-19-001-cross-host-scrolling-plan.md` in the
  /// coordination root.
  private func semanticSnapshotWithScrollOffsets(
    _ snapshot: SemanticSnapshot
  ) -> SemanticSnapshot {
    guard !snapshot.scrollRoutes.isEmpty else {
      return snapshot
    }
    var enriched = snapshot
    enriched.scrollRoutes = localScrollPositionRegistry.routesWithCurrentOffsets(
      snapshot.scrollRoutes
    )
    return enriched
  }

  private func applyTerminalCursorFocusPolicy(
    semanticSnapshot: SemanticSnapshot
  ) throws {
    guard runtimeConfiguration.output == .tui else {
      return
    }
    guard
      let terminalSurface = presentationSurface as? any TerminalCursorFocusPresentationSurface
    else {
      return
    }

    let focusedNode = focusedAccessibilityNode(in: semanticSnapshot)
    let usesTextInputCursor =
      focusedNode?.cursorAnchor != nil
      || currentFocusPresentation.prefersTextInput
    guard runtimeConfiguration.cursorFollowsFocus || usesTextInputCursor else {
      return
    }

    let cursorPoint =
      if runtimeConfiguration.cursorFollowsFocus {
        AccessibilityRuntimePolicy().focusedCursorPoint(
          in: semanticSnapshot,
          focusedIdentity: focusTracker.currentFocusIdentity
        )
      } else {
        focusedNode?.cursorAnchor
      }
    try terminalSurface.presentAccessibilityCursorFocus(at: cursorPoint)
  }

  private func focusedAccessibilityNode(
    in semanticSnapshot: SemanticSnapshot
  ) -> AccessibilityNode? {
    guard let focusedIdentity = focusTracker.currentFocusIdentity else {
      return nil
    }
    return semanticSnapshot.accessibilityNodes.first { node in
      node.identity == focusedIdentity
    }
  }

  private func presentJSONFrame(
    _ artifacts: FrameArtifacts,
    focusedIdentity: Identity?
  ) throws -> TerminalPresentationMetrics {
    let output = JSONFrameRenderer().render(
      surface: artifacts.rasterSurface,
      semanticSnapshot: artifacts.semanticSnapshot,
      focusedIdentity: focusedIdentity
    )
    guard
      let terminalCommandSurface =
        presentationSurface as? any TerminalCommandPresentationSurface
    else {
      throw PresentationSurfaceRoleError.missingTerminalCommandSurface
    }
    try terminalCommandSurface.write(output)
    return metrics(forWrittenOutput: output)
  }

  private func presentLinearAccessibilityFrame(
    semanticSnapshot: SemanticSnapshot
  ) throws -> TerminalPresentationMetrics {
    let output =
      LinearAccessibilityRenderer().render(semanticSnapshot)
      + liveRegionAnnouncer.renderAnnouncements(for: semanticSnapshot)
    guard !output.isEmpty else {
      return TerminalPresentationMetrics()
    }

    guard
      let terminalCommandSurface =
        presentationSurface as? any TerminalCommandPresentationSurface
    else {
      throw PresentationSurfaceRoleError.missingTerminalCommandSurface
    }
    try terminalCommandSurface.write(output)
    return metrics(forWrittenOutput: output)
  }

  private func metrics(
    forWrittenOutput output: String
  ) -> TerminalPresentationMetrics {
    let bytesWritten = output.utf8.count
    let linesTouched = output.utf8.reduce(0) { partial, byte in
      partial + (byte == 0x0A ? 1 : 0)
    }
    return TerminalPresentationMetrics(
      bytesWritten: bytesWritten,
      linesTouched: linesTouched,
      cellsChanged: max(0, bytesWritten - linesTouched),
      strategy: .fullRepaint
    )
  }
}

private func preferredHostLayoutSize(
  for artifacts: FrameArtifacts
) -> CellSize? {
  preferredWindowContentSize(
    resolved: artifacts.resolvedTree,
    measured: artifacts.measuredTree
  )
}

private func preferredWindowContentSize(
  resolved: ResolvedNode,
  measured: MeasuredNode
) -> CellSize? {
  if isWindowHostLayout(resolved) {
    let childMeasurements = measured.childMeasurements
    guard !childMeasurements.isEmpty else {
      return measured.measuredSize
    }

    return childMeasurements.reduce(into: CellSize.zero) { partial, child in
      partial.width = max(partial.width, child.measuredSize.width)
      partial.height = max(partial.height, child.measuredSize.height)
    }
  }

  for (resolvedChild, measuredChild) in zip(resolved.children, measured.childMeasurements) {
    if let size = preferredWindowContentSize(
      resolved: resolvedChild,
      measured: measuredChild
    ) {
      return size
    }
  }

  return nil
}

private func isWindowHostLayout(
  _ node: ResolvedNode
) -> Bool {
  guard case .view("WindowHostLayout") = node.kind else {
    return false
  }
  return true
}
