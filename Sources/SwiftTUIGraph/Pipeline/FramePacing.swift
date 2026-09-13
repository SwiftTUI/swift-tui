import SwiftTUIPrimitives

/// A readiness gate for sustained invalidation pressure. All other wakes bypass it.
package struct MergePressurePacingPolicy: Sendable {
  package var gapNumerator = 1
  package var gapDenominator = 2
  package var gapCeiling: Duration = .milliseconds(50)
  package var pressureWindow: Duration = .seconds(1)
  package init() {}
}

/// Captured when the scheduler consumes a frame, before that frame feeds its cost.
package struct FramePacingSnapshot: Sendable, Equatable {
  package var ewmaFrameCost: Duration = .zero
  package var gap: Duration = .zero
  package var engaged = false
  package var mergeAge: Duration?
  package init(
    ewmaFrameCost: Duration = .zero, gap: Duration = .zero,
    engaged: Bool = false, mergeAge: Duration? = nil
  ) {
    self.ewmaFrameCost = ewmaFrameCost
    self.gap = gap
    self.engaged = engaged
    self.mergeAge = mergeAge
  }
}

package protocol CommittedFrameCostRecording: AnyObject {
  var mergePressurePacingEnabled: Bool { get }
  func recordCommittedFrame(cost: Duration, at instant: MonotonicInstant)
}
