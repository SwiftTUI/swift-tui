/// Stage-budgeted variants of the poll-free test signals.
///
/// The plain `wait()` / `wait(until:)` calls suspend with no timeout at all —
/// a deliberate trade made by the CI flake fix, since a starved producer must
/// never *fail* a waiter. These overloads add back a failure bound, but a
/// deterministic one: instead of "give up after N wall-clock seconds" they
/// mean "give up after the runtime has made N stages of progress." That bound
/// is identical on fast and slow hardware, so it never fails spuriously.

extension AsyncEvent {
  /// Waits for the event to fire, throwing `StageBudgetExceeded` if `budget`
  /// stages of `clock` elapse first.
  @_spi(Testing) public func wait(
    for label: String,
    within budget: ProgressBudget,
    on clock: some StageClock
  ) async throws {
    try await withStageBudget(label, within: budget, on: clock) {
      await self.wait()
    }
  }
}

extension MainActorConditionSignal {
  /// Waits until `predicate` holds, throwing `StageBudgetExceeded` if `budget`
  /// stages of `clock` elapse first.
  @_spi(Testing) public func wait(
    until predicate: @escaping @Sendable () -> Bool,
    for label: String,
    within budget: ProgressBudget,
    on clock: some StageClock
  ) async throws {
    try await withStageBudget(label, within: budget, on: clock) {
      await self.wait(until: predicate)
    }
  }
}
