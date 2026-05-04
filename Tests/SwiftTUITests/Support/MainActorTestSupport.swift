import Foundation

/// Returns `true` iff this synchronous call site is executing on the main
/// actor.
///
/// **Use this instead of `Thread.isMainThread` in tests.** `Thread.isMainThread`
/// is *not* a portable proxy for main-actor isolation — on Linux's
/// swift-corelibs Foundation, it returns `false` for code synchronously
/// invoked from a `@MainActor`-isolated context, even though that code is
/// provably on the main actor's executor. See `LINUX_ISSUES.md` issue #2.
///
/// How it works: the `isolation` parameter defaults to `#isolation`, the
/// Swift 6 expression that captures the caller's static actor isolation
/// (SE-0420). When the caller is `@MainActor`-isolated, `isolation` is
/// `MainActor.shared` and we return `true` immediately — no thread inspection
/// required. When the caller is non-isolated (or isolated to some other
/// actor), we fall back to `Thread.isMainThread`, which is reliable for
/// distinguishing the OS main thread from worker threads on both platforms.
///
/// The matrix this resolves:
///
/// | Caller isolation     | Runs on main thread? | Returns |
/// |----------------------|----------------------|---------|
/// | `@MainActor`         | yes (Apple)          | `true`  |
/// | `@MainActor`         | yes (Linux, but `Thread.isMainThread` lies) | `true` |
/// | non-isolated         | yes                  | `true`  |
/// | non-isolated         | no (worker)          | `false` |
/// | other actor          | varies               | `false` |
///
/// > Note: this is a best-effort runtime check intended for test
/// > instrumentation. For invariant enforcement in production code, use
/// > `MainActor.assertIsolated()` or `MainActor.preconditionIsolated()`.
public func currentlyOnMainActor(
  isolation: isolated (any Actor)? = #isolation
) -> Bool {
  if isolation === MainActor.shared {
    return true
  }
  // thread-ismain-ok: this helper is the single canonical use of
  // `Thread.isMainThread` in the project. Every other use must be justified
  // with a `thread-ismain-ok:` comment per Scripts/check_main_thread_usage.sh.
  // The check above already handled MainActor-isolated callers; this branch
  // only runs for non-isolated callers, where `Thread.isMainThread` is a
  // reliable platform-agnostic answer to "am I on the OS main thread?".
  return Thread.isMainThread
}
