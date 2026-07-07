package import SwiftTUICore

/// Frame-scoped record of every presentation declaration emitter resolved
/// this head attempt, used by the frame head to decide whether the
/// presentation portal root must re-reconcile after a selective evaluation.
///
/// Declarative presentations register through a preference that only the
/// portal root's own resolve consumes. The frame head used to force-queue the
/// portal root whenever the frame's invalidation set was non-empty so an
/// activation flip could never be missed — at the cost of a root-rooted
/// frontier on every invalidation frame. Emitters now report each resolve
/// here instead, and the head escalates to a portal-root evaluation only when
/// an observation (or a departed declared source) proves the overlay-entry
/// set may have changed.
///
/// The log lives on ``PresentationPortalState`` (stable across frames) so
/// evaluator closures captured on earlier frames keep reporting into the
/// current frame's log; the frame head resets it at every head attempt.
@MainActor
package final class PresentationTriggerObservationLog {
  package struct Observation: Sendable {
    package var sourceIdentity: Identity
    package var isActive: Bool

    package init(
      sourceIdentity: Identity,
      isActive: Bool
    ) {
      self.sourceIdentity = sourceIdentity
      self.isActive = isActive
    }
  }

  private(set) package var observations: [Observation] = []

  /// Sticky map from a declaration's source identity to the emitter node that
  /// reports it (the presentation trigger leaf; the emitting node itself for
  /// inline emitters like toasts). Unlike ``observations`` this survives
  /// ``reset()``: the frame head consults it *before* planning a selective
  /// frame — a dirty emitter for a declared source is guaranteed to re-resolve
  /// and re-observe, so the head can root the plan at the portal directly
  /// instead of running a narrow plan whose work the escalation re-does.
  private(set) package var emitterIdentitiesBySource: [Identity: Identity] = [:]

  package init() {}

  package func record(
    sourceIdentity: Identity,
    isActive: Bool,
    emitterIdentity: Identity? = nil
  ) {
    observations.append(
      Observation(
        sourceIdentity: sourceIdentity,
        isActive: isActive
      )
    )
    if let emitterIdentity {
      emitterIdentitiesBySource[sourceIdentity] = emitterIdentity
    }
  }

  package func reset() {
    observations.removeAll(keepingCapacity: true)
  }
}
