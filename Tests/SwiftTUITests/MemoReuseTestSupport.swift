@testable import SwiftTUICore

/// Runs `body` with the memoized-body reuse gate forced to `enabled`, restoring
/// the previous setting afterward. Makes the memo-reuse tests deterministic
/// regardless of the ambient `SWIFTTUI_MEMO_REUSE` environment — the A/B
/// measurement run sets that variable process-wide, which would otherwise flip
/// the gate-off assertions.
@MainActor
func withMemoReuse<Result>(
  _ enabled: Bool,
  _ body: () -> Result
) -> Result {
  let previous = MemoReuseConfiguration.isEnabled
  MemoReuseConfiguration.isEnabled = enabled
  defer { MemoReuseConfiguration.isEnabled = previous }
  return body()
}
