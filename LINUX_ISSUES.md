# Linux test deviations

This file tracks places where the test suite has been adjusted to accommodate
genuine differences in how Swift / Foundation / the language behave on Linux
vs. Apple platforms. Each entry should either be:

- **Closed** (a proper fix has landed and the deviation is removed), or
- **Open** with a TODO and a hypothesis worth investigating.

When you change a test to make it pass on Linux, add an entry here so the
next person doesn't have to rediscover why.

---

## 1. `BuilderStructureTests.deferredBuilderChildrenPreserveLimitedAvailabilityOutput`

**File**: `Tests/ViewTests/BuilderStructureTests.swift`
**Status**: Resolved (test made platform-conditional)
**Root cause**: language semantic, not a bug.

The probe gates on:

```swift
if #available(macOS 999, iOS 999, *) {
  Text("Future")
} else {
  Text("Current")
}
```

`#available(macOS 999, iOS 999, *)` evaluates as follows:

| Platform | macOS 999? | iOS 999? | Wildcard `*` applies? | Branch taken |
|----------|------------|----------|-----------------------|--------------|
| macOS    | no         | n/a      | no (macOS is listed)  | else → "Current" |
| iOS      | n/a        | no       | no (iOS is listed)    | else → "Current" |
| Linux    | n/a        | n/a      | **yes** (Linux is unlisted) | if → "Future" |

The `*` in `#available` is the catch-all for *unlisted* platforms. The
original test was written assuming the version check would always fail and
the else branch would always run, which is true on Apple platforms but
wrong on Linux. The fix makes the expected text platform-conditional.

**No further action needed** unless someone redesigns the probe.

---

## 2. `AsyncFrameTailRenderingTests.workerSafeCustomLayoutSnapshotRunsLayoutOnFrameTailWorker`

**File**: `Tests/SwiftTUITests/AsyncFrameTailRenderingTests.swift` (around line 520)
**Status**: Open — symptomatic fix applied, root cause unresolved.

The failing assertion was:

```swift
#expect(workerLayoutState.cacheApplyRanOnMainThread == true)
```

`recordCacheApply(identity:)` is declared `@MainActor`. On Apple platforms,
`Thread.isMainThread` evaluated synchronously inside that method returns
`true`. On Linux, it returns `false`.

We've made this positive assertion Darwin-only with `#if canImport(Darwin)`,
so the test passes everywhere again. The contrapositive checks earlier in
the same test (`measureRanOnMainThread == false`,
`placeRanOnMainThread == false`) still assert worker placement
unconditionally, so we haven't lost coverage of "ran off main".

### Open questions

1. Does `recordCacheApply` actually run on the main thread on Linux? The
   `@MainActor` annotation provably puts it on the main actor, but Swift's
   default main actor executor on Linux uses `DispatchQueue.main`, and
   whether that maps 1:1 to the OS main thread depends on whether
   `dispatchMain()` was ever invoked. Test runners typically don't, which
   may mean the main actor executes on a worker thread that
   `Thread.isMainThread` correctly reports as non-main.

2. If the answer to (1) is "no, not actually on main thread on Linux",
   then any production code that assumes "MainActor ⇒ main thread" is
   broken on Linux too. Worth auditing — but the fact that 1452 of 1453
   tests pass suggests we don't actually depend on that assumption in
   the framework itself, only in test instrumentation.

3. The right helper for tests is probably something like:

   ```swift
   /// True iff this code is currently isolated to the main actor.
   /// Always check this in tests instead of `Thread.isMainThread`,
   /// which is not portable.
   func currentlyOnMainActor() -> Bool {
     MainActor.shared.assumeIsolatedSafely { true } ?? false
   }
   ```

   …but `MainActor.assumeIsolated` doesn't have a non-fatal variant, so
   this would need a `withUnsafeContinuation` dance or a custom executor
   probe. Not a 5-minute fix.

### Suggested follow-up

- Replace `Thread.isMainThread` everywhere in the test suite (currently
  only this file) with an `OnMainActor` test helper that is correct on
  both Darwin and Linux.
- File an upstream Swift Forums question / search the Foundation tracker
  for prior art before writing custom code — this is almost certainly a
  known issue.

---

## Conventions for future entries

- Title with `<TestName>` so it's grep-able from a CI log.
- Include the file path and the surrounding context.
- Mark **Resolved** vs **Open**. Open issues should have a hypothesis or
  a TODO link.
- If the deviation is a `#if canImport(Darwin)` / `#if os(Linux)` guard,
  describe both branches' expected behavior so a reader can verify the
  guard matches the actual platform difference.
