# Testing And Fixture Policy

This policy keeps reliability work predictable in the current decomposed
codebase.

## Policy Hooks

Structural guardrails that do not need to execute the runtime live in `prek`
hooks instead of the Swift test suite:

- `swift-format`: formats staged Swift files
- `no-foundation-in-library-products`: inline `prek.toml` check that forbids `Foundation` imports in the Foundation-free `Core`, `View`, and `SwiftTUI` library layers
- `Scripts/check_public_surface_policies.sh`: enforces public-surface guardrails, actor-isolation documentation, and related docs
- `Scripts/check_concurrency_safety_policies.sh`: forbids `@unchecked Sendable` and `nonisolated(unsafe)` in checked-in Swift sources so concurrency-safety regressions fail before test execution

Keep runtime, integration, and behavioral guarantees in tests. Move pure
repository-shape or text-pattern checks into hooks when they can fail earlier
and more locally.

There is not currently a dedicated checked-in source-layout hook. The source
map in [SOURCE_LAYOUT.md](SOURCE_LAYOUT.md) is therefore kept in sync through
review, docs maintenance, and the broader public-surface policy checks.

Rendered-text fixture matrix completeness is currently enforced by
`RenderedTextFixtureSupportTests` and the fixture-verification helpers in the
test suite, not by a separate pre-commit hook.

## Test Topology

- `Tests/CoreTests`: pipeline, layout, raster, and low-level infrastructure
- `Tests/ViewTests`: authoring-surface, environment, and actor-isolation behavior
- `Tests/SwiftTUITests`: runtime, rendering, fixture, and benchmark scenarios
- `Platforms/CLI/Tests/SwiftTUICLITests`: terminal-native runner, attach, socket, and pty behavior
- `Platforms/WASI/Tests/SwiftTUIWASITests`: WASI runner and manifest-mode behavior

Prefer the smallest target that can prove the behavior under test. Keep
cross-layer coverage in `SwiftTUITests` and the runner-package test suites,
not as the default place for every new assertion.

## Principles

- Prefer focused subsystem tests over large cross-cutting assertions when a failure can be localized cleanly.
- Keep one or two end-to-end smoke suites for whole-pipeline confidence.
- Treat fixture changes as evidence, not as housekeeping.
- Keep performance checks deterministic and scenario-based.
- When behavior depends on input dispatch, selective invalidation, or
  presentation timing, reproduce and assert through the real runtime path
  instead of only invoking direct handlers.
- Add composed-path regressions for wrapper-hosted, scene-hosted, or
  otherwise nested runtime bugs; plain inner-content canaries often miss
  host-reconciliation failures.
- Use bounded condition-based waits for async and animation coverage instead
  of fixed sleeps or guessed frame counts.
- Focused suites are for triage and localization. `bun run test` remains the
  completion gate for changes that touch shared runtime behavior, repo-wide
  test infrastructure, or tooling.

## Fixture Updates

Fixture updates are expected when:

- A layout or presentation change is intentional and documented.
- The rendered output changes because the architecture now behaves differently and the behavior is correct.
- A terminal-capability path needs a new baseline, as long as the capability matrix is rerun.

Fixture updates need an explanation when:

- Multiple fixtures change without a shared cause.
- The diff crosses unrelated subsystems.
- A change alters the output of a scenario that was supposed to stay stable.

When updating fixtures:

1. Capture the reason for the change in the commit or PR description.
2. Re-run the relevant capability matrix or scenario set.
3. Check for accidental drift in adjacent fixtures.
4. Prefer the smallest possible fixture rewrite that proves the intended behavior.

## Performance Gates

- Keep deterministic benchmark scenarios as standing checks for idle, control-state, and input-update paths.
- Treat a new full repaint in a previously incremental scenario as a regression unless [RUNTIME.md](RUNTIME.md) explicitly calls out a fallback case.
- Keep performance gates deterministic. They should assert work volume and presentation shape, not wall-clock timing.
- When paint-path work changes, prefer explicit write-shape assertions (`linesTouched`, `cellsChanged`, `FrameDiagnostics.presentationDamage`, emitted cursor/script shape, synchronized framing, graphics replay scope, edit-op lowering) over broad "smaller than before" checks alone.
- The standing enforcement lives in `Phase5ReliabilityGatesTests` and the targeted scenario suites.

## Architecture Gates

- Do not let a single file accumulate multiple unrelated subsystem responsibilities again.
- If a new file becomes a catch-all, split it or document why the exception is temporary.
- Keep the source map in [SOURCE_LAYOUT.md](SOURCE_LAYOUT.md) aligned with file moves and target-boundary changes.
- When a new repository-shape rule becomes important enough to enforce mechanically, add the actual hook and document it here in the same change.

## Review Checklist

- Does the change belong to the subsystem it touches most?
- Did the relevant fixture or benchmark update because behavior changed, not because the implementation drifted?
- Do the docs still describe the current file map and the current fallback cases?
- Is there still at least one local test that can fail without needing the whole integration suite?
- If the bug depended on runtime composition, did the regression exercise the
  real hosted path that failed in practice?
- If the test waits for runtime progress, does it wait on an observable
  condition with a timeout instead of sleeping for a guessed duration?
- If the change touched shared runtime behavior or repo tooling, did the final tree pass `bun run test`?
