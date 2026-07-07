/// Bridges into MainActor-isolated state from a `nonisolated` context with a
/// **release-checked** isolation assertion.
///
/// A bare `MainActor.assumeIsolated` only verifies isolation in debug builds, so
/// a `nonisolated` accessor over MainActor-only state that is mistakenly reached
/// off the main actor — e.g. a frame-tail layout worker that
/// `FrameTailLayoutOffloadEligibility` mis-classified — proceeds and races in
/// release, the suspected mechanism behind the run-loop SIGSEGV flake (#1).
/// Routing the access through here calls `MainActor.preconditionIsolated` first,
/// turning that silent off-main data race into a loud, attributable crash in
/// release builds too.
///
/// The diagnostic is passed to `preconditionIsolated` as an autoclosure, so it
/// is only built on the trap path; the only success-path cost over a bare
/// `assumeIsolated` is the executor-identity check itself.
///
/// This is the shared, instrumented form of the guard the (since-deleted)
/// `LayoutProxyBox` pioneered for the same hazard; prefer it over a bare
/// `MainActor.assumeIsolated` at every `nonisolated` bridge into
/// `@MainActor`-only state.
@inline(__always)
package func withCheckedMainActorAccess<T: Sendable>(
  _ accessor: StaticString,
  _ body: @MainActor () -> T
) -> T {
  MainActor.preconditionIsolated(
    "\(accessor) reached off the main actor — a nonisolated bridge to "
      + "MainActor-isolated state ran on a background executor "
      + "(see FrameTailLayoutOffloadEligibility, SIGSEGV flake #1)."
  )
  return MainActor.assumeIsolated(body)
}
