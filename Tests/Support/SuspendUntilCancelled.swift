/// Suspends until the surrounding task is cancelled, without occupying a core.
///
/// Long-lived fixture tasks — the body of a `.task(id:)` a test churns to prove
/// cancellation and restart behaviour — used to spin on `Task.isCancelled`,
/// yielding each turn. That reads like an idle wait and is the opposite of one:
/// `Task.yield()` re-enqueues the task on the cooperative pool **without
/// releasing its thread**, so each such fixture task spins a core for its entire
/// lifetime.
///
/// The pool has only as many threads as the machine has cores. A stress fixture
/// that churns two dozen `.task(id:)` generations can therefore hold every one
/// of them at once, and once the pool is saturated nothing else in the process
/// makes progress. That does not present as a test failure — it presents as the
/// whole lane going silent, which is how it was found (`Run SwiftTUI runtime
/// tests`, KNOWN-TEST-FLAKES.md entry 9).
///
/// This suspends on a signal that is never fired, so it costs nothing until
/// cancellation resumes it. `AsyncEvent.wait()` installs a cancellation handler,
/// so the resume is prompt and `.task(id:)` teardown is still exercised exactly
/// as before.
@_spi(Testing) public func suspendUntilCancelled() async {
  await AsyncEvent().wait()
}
