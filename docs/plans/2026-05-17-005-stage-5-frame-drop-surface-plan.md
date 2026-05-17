---
title: "refactor: close the completed-frame drop surface"
type: refactor
status: completed
date: 2026-05-17
depends_on:
  - "./2026-05-16-001-pipeline-driver-hardening-plan.md"
  - "./2026-05-17-003-stage-3-compose-pipeline-plan.md"
---

# Stage 5 Plan: Close The Completed-Frame Drop Surface

## Goal

Stop making completed-frame drop correctness depend directly on a long
diagnostic blocker enum. Keep `FrameDropEligibility.Blocker` as the
human-readable diagnostics vocabulary, but derive droppability from a smaller
closed impact product whose exhaustive blocker mapping must be updated whenever
the blocker surface changes.

Also make the default completed-frame policy honest: the renderer defaults to
the shipped visual-only stale-frame policy at the decision point instead of
storing a private hardcoded field that looks configurable.

## Current Source Anchors

- `Sources/SwiftTUICore/Pipeline/FrameDropEligibility.swift`
  - `Blocker` has the long correctness vocabulary.
  - `classify(_:)` currently decides `.canDropVisualOnly` from the absence of
    blockers when `hasCompleteBarrierSignals` is true.
- `Sources/SwiftTUIRuntime/RunLoop/SkippedFrameReconciliation.swift`
  - `CompletedFramePolicy` decides whether stale candidates may use
    `.emptyVisualOnly` reconciliation.
- `Sources/SwiftTUIRuntime/SwiftTUI.swift`
  - `DefaultRenderer` stores `completedFramePolicy = .dropCompletedVisualOnly`
    as a private constant-like field.
  - `completedFrameEligibility(...)` subtracts retained-baseline blockers only
    after previewing a completed candidate.
- `Tests/SwiftTUICoreTests/FrameDropEligibilityTests.swift`
  - Existing blocker tests should grow a closed-impact guard.
- `Tests/SwiftTUITests/PipelineContractTests.swift`
  - `frameDropClassificationIsClosedOverCommittedEffects()` is disabled for
    Stage 5 and must become active.

## Tests First

- Add `FrameDropEligibility` tests that prove every `Blocker.allCases` maps to
  a non-visual completed-frame impact category.
- Add tests that `canDropVisualOnly` is derived from visual-only impact, not
  from a raw empty diagnostics set alone.
- Replace the Stage 5 disabled contract placeholder with an active guard that
  all modeled committed side effects still force a non-droppable completed
  frame.
- Keep the existing stale completed-frame drop runtime tests green.

## Implementation Tasks

- Add `FrameDropEligibility.CompletedFrameImpact` with a small set of closed
  categories: lifecycle, runtime registrations, focus, scroll, preferences,
  animation, worker/cache, retained baselines, presentation recovery, and
  diagnostics.
- Make `FrameDropEligibility.classify(_:)` record both diagnostic blockers and
  the closed impact. A candidate can become `.canDropVisualOnly` only when the
  impact is visual-only and the caller has complete barrier signals.
- Keep `Blocker` as diagnostics output, but map every blocker into
  `CompletedFrameImpact` through an exhaustive switch so a new blocker requires
  an explicit impact decision at compile time.
- Remove `DefaultRenderer`'s stored `completedFramePolicy` field and default
  `makeCompletedFrameCandidate(...)` to `.dropCompletedVisualOnly` when no
  explicit policy override is supplied.
- Update async-rendering docs to describe the closed impact product and the
  fixed default stale completed-frame policy.

## Validation

- Passed: `swiftly run swift test --filter SwiftTUICoreTests.FrameDropEligibilityTests`
- Passed: `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
- Passed: `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
- Passed: `swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests`
- Passed: `swiftly run swift test --package-path Examples/gallery`
- Passed: `Scripts/generate_public_api_inventory.sh --check`
- Passed: `bun run test`
  - Full gate log: `/tmp/swift-tui-test-gate-20260517-041454-96113.log`

Note: an initial focused `PipelineContractTests` rerun crashed in the SwiftPM
testing helper while stale build artifacts were present. `swiftly run swift
package clean` followed by the same focused test and full suite passed.
An initial gallery test rerun hit the same helper signal-11 pattern; cleaning
`Examples/gallery` and rerunning the gallery suite passed.

## Exit Criteria

- Done: the completed-frame drop decision is derived from a closed impact
  product.
- Done: `Blocker` remains diagnostic and exhaustively maps into that product.
- Done: the Stage 5 pipeline contract is active and passing.
- Done: the default completed-frame policy is documented as fixed unless an explicit
  internal override is passed for tests or runtime modes.
- Done: Stage 5 status is reflected in the roadmap, tracker, and changelog.
