/// Public committed-frame product for one-shot rendering.
///
/// `RenderSnapshot` is the stable inspection surface for previews, snapshots,
/// diagnostics, and host adapters. The phase trees used to build it remain
/// package-only implementation detail.
public struct RenderSnapshot: Equatable, Sendable {
  public var rasterSurface: RasterSurface
  public var semanticSnapshot: SemanticSnapshot
  public var presentationDamage: PresentationDamage?
  public var diagnostics: FrameDiagnostics
  package var phaseArtifacts: FrameArtifacts?

  public init(
    rasterSurface: RasterSurface,
    semanticSnapshot: SemanticSnapshot,
    presentationDamage: PresentationDamage? = nil,
    diagnostics: FrameDiagnostics = .init()
  ) {
    self.rasterSurface = rasterSurface
    self.semanticSnapshot = semanticSnapshot
    self.presentationDamage = presentationDamage
    self.diagnostics = diagnostics
    phaseArtifacts = nil
  }

  package init(artifacts: FrameArtifacts) {
    rasterSurface = artifacts.rasterSurface
    semanticSnapshot = artifacts.semanticSnapshot
    presentationDamage = artifacts.presentationDamage
    diagnostics = artifacts.diagnostics
    phaseArtifacts = artifacts
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.rasterSurface == rhs.rasterSurface
      && lhs.semanticSnapshot == rhs.semanticSnapshot
      && lhs.presentationDamage == rhs.presentationDamage
  }
}

extension RenderSnapshot {
  package var resolvedTree: ResolvedNode {
    requirePhaseArtifacts().resolvedTree
  }

  package var measuredTree: MeasuredNode {
    requirePhaseArtifacts().measuredTree
  }

  package var placedTree: PlacedNode {
    requirePhaseArtifacts().placedTree
  }

  package var drawTree: DrawNode {
    requirePhaseArtifacts().drawTree
  }

  package var commitPlan: CommitPlan {
    requirePhaseArtifacts().commitPlan
  }

  package var drawnIdentities: Set<Identity> {
    requirePhaseArtifacts().drawnIdentities
  }

  private func requirePhaseArtifacts() -> FrameArtifacts {
    guard let phaseArtifacts else {
      preconditionFailure("This RenderSnapshot was not produced by DefaultRenderer.")
    }
    return phaseArtifacts
  }
}

extension FrameArtifacts {
  package var renderSnapshot: RenderSnapshot {
    RenderSnapshot(artifacts: self)
  }
}
