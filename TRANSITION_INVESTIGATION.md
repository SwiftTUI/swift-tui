# TRANSITION_INVESTIGATION: Fade-Out Demo Loops on Tab Entry

## Bug
In the Gallery app's Animations tab, the "fade out" transition demo
(`TextFigure("FADE")` with `.transition(.opacity)`) plays a fade-in
animation on a loop when the user navigates to the tab. The figure
should appear at full opacity without any animation.

## Root Cause

Three independent mechanisms interact to produce the loop:

### 1. Frame-level animation transaction is global
`withAnimation` in `WithAnimation.swift` writes the animation request
to `AnimationContextStorage.currentRequest` (a task-local). The state
mutation then calls `FrameScheduler.requestInvalidation(of:animation:batchID:)`,
which stores the request as `pendingAnimationRequest`
(`Scheduler.swift:207–209`). When the scheduler produces a
`ScheduledFrame`, this request becomes the **frame-level** transaction
(`RunLoop+Rendering.swift:279`).

Every node in the resolved tree inherits this transaction unless it
carries its own explicit override. In SwiftUI, `withAnimation`'s
transaction is scoped to views that *observe* the mutated state; here
it is broadcast to the entire frame. This means the PhaseAnimator's
`withAnimation { currentPhase = nextPhase }` (`PhaseAnimator.swift:167`)
sets the animation intent for *every* identity in the tree, not just
the PhaseAnimator's content.

### 2. `dominantActiveRequest()` injection on tick frames
`RunLoop+Rendering.swift:288–292`:
```swift
if transactionSnapshot.animationRequest == .inherit,
  let active = renderer.internalAnimationController.dominantActiveRequest()
{
  transactionSnapshot.animationRequest = active
}
```
Tick frames (deadline-driven, no user interaction) start with
`.inherit`. Because the PhaseAnimator keeps animations in flight
continuously, `dominantActiveRequest()` always returns a non-nil
`.animate(box)`. The injection makes *every* tick frame carry an
animation transaction. Any identity that happens to appear as
"inserted" on a tick frame gets its insertion transition animated.

### 3. Stale `activeAnimations` survive identity removal
When the user switches away from the Animations tab, the
PhaseAnimator's content identities are removed from the resolved tree.
The `AnimationController` creates `RemovalEntry` records for
identities that carry a `.transition(...)`, but in-flight
`activeAnimations` entries for identities *without* transitions (e.g.
the PhaseAnimator's foreground-color and offset-X animations) are
**never cleaned up**. They linger in `activeAnimations` until they
naturally complete.

If the user navigates back to the Animations tab before those stale
animations have elapsed, `dominantActiveRequest()` returns a non-nil
box from the stale entry. The tab-entry frame's transaction is
upgraded from `.inherit` to `.animate(staleBox)`. On this frame:

- All Animations-tab identities are "inserted" (they were absent
  while the other tab was active).
- `transitionsByIdentity` contains the fade figure's `.opacity`
  (full evaluation re-registers all transitions).
- `enqueueInsertionAnimation` fires with `.animate`, creating an
  opacity 0 → 1 animation.

### Why it loops
After the initial fade-in fires, the PhaseAnimator's `.task` launches
`runPhaseLoop()`, which immediately calls `withAnimation` for its
first phase advance. From that point on:

1. The PhaseAnimator keeps `activeAnimations` non-empty → every
   subsequent frame inherits `.animate` via `dominantActiveRequest()`.
2. Any event that causes a full re-evaluation while `.animate` is the
   frame transaction—focus-sync rerenders
   (`environmentRequiresRootEvaluation`, triggered by pressed-identity
   or focus-identity changes), terminal resizes, or observable-object
   invalidations—will re-register the fade figure's transition and
   potentially re-insert its identity (if the tree structure shifts
   even transiently).
3. The `beginTransitionCollection` / `finishTransitionCollection` cycle
   (`AnimationController.swift:715–721`) loses transition
   registrations for identities whose subtrees were not re-evaluated
   on the current frame. When a full evaluation later re-registers
   them, the combination of a fresh registration and the inherited
   `.animate` transaction re-triggers the insertion animation.

The net effect is a repeating opacity 0 → 1 fade driven by the
PhaseAnimator's cadence.

## Affected Code Paths

| File | Lines | Role |
|---|---|---|
| `RunLoop+Rendering.swift` | 288–292 | `dominantActiveRequest()` injection |
| `AnimationController.swift` | 703–706 | `dominantActiveRequest()` impl |
| `AnimationController.swift` | 776 | `insertedIdentities` detection |
| `AnimationController.swift` | 815–833 | insertion transition dispatch |
| `AnimationController.swift` | 1021–1079 | `enqueueInsertionAnimation` |
| `AnimationController.swift` | 715–721 | transition registration lifecycle |
| `Scheduler.swift` | 195–214 | animation-request coalescing |
| `PhaseAnimator.swift` | 126–141 | `runPhaseLoop` + `withAnimation` |

## Proposed Fix

### Primary: scope insertion-transition guard to explicit user interaction
The insertion-transition path should only fire when the inserted
identity's *parent* was already present in the previous frame—
indicating a conditional toggle—not when both the parent and child
are freshly inserted together (structural first appearance, e.g. tab
switch).

In `AnimationController.processResolvedTree`, after computing
`insertedIdentities`, filter out identities whose parent was also
just inserted:

```swift
// AnimationController.swift, inside the insertion loop (~line 819)
for identity in insertedIdentities {
  // Skip structural first-appearances: the parent is also new,
  // so this identity appeared because its container was mounted,
  // not because a conditional toggled inside withAnimation.
  if let parent = newParentByIdentity[identity],
     insertedIdentities.contains(parent) {
    continue
  }
  // ... existing matched-geometry skip, transition lookup,
  //     enqueueInsertionAnimation ...
}
```

This mirrors SwiftUI's semantics: `.transition()` only fires when
the view's *conditional presence* changes inside a `withAnimation`,
not when the entire parent container appears for the first time.

### Secondary: clean up `activeAnimations` for removed identities
At the end of `processResolvedTree`, after processing removals, purge
`activeAnimations` entries whose identity is no longer in the live
tree and has no removal overlay:

```swift
// After line 948 (removingIdentities[identity] = RemovalEntry(...))
let orphanedKeys = activeAnimations.keys.filter { key in
  !newIdentities.contains(key.identity)
    && removingIdentities[key.identity] == nil
}
for key in orphanedKeys {
  if let entry = activeAnimations.removeValue(forKey: key) {
    releaseBatch(entry.batchID)
  }
}
```

This prevents stale animations from making `dominantActiveRequest()`
return a non-nil value after their owning view has left the tree.

### Tertiary: scope `dominantActiveRequest()` injection
Rather than injecting any active animation's box into every `.inherit`
frame, limit the injection to identities that are actually in flight.
The frame-level transaction should remain `.inherit` unless the
scheduled frame explicitly carried `.animate`. The per-node
`effectiveAnimationRequest` already allows subtree-level overrides via
`TransactionSnapshot`; retargeting can be handled there instead of at
the frame level.

This is a larger change and may affect retargeting semantics for
interrupted animations, so it should be validated against the existing
animation test suite before merging.

## Quick App-Level Workaround
Change the initial state of `showOpacityFigure` from `true` to
`false` in `AnimationsTab.swift:21`. The fade figure will not be
present on tab entry, so there is nothing to "insert" and no
insertion transition fires. The demo then starts with a "fade in"
button, which is arguably a better initial state for the demo anyway.
