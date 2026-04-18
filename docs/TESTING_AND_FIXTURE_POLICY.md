# Testing And Fixture Policy

This policy keeps reliability work predictable in the current decomposed
codebase.

## Policy Hooks

Structural guardrails that do not need to execute the runtime live in `prek`
hooks instead of the Swift test suite:

- `swift-format`: formats staged Swift files
- `no-foundation-in-library-products`: inline `prek.toml` check that forbids `Foundation` imports in the Foundation-free `Core`, `View`, and `TerminalUI` library layers
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
- `Tests/TerminalUITests`: runtime, rendering, fixture, and benchmark scenarios
- `Runners/TerminalUICLI/Tests/TerminalUICLITests`: terminal-native runner, attach, socket, and pty behavior
- `Runners/TerminalUIWASI/Tests/TerminalUIWASITests`: WASI runner and manifest-mode behavior

Prefer the smallest target that can prove the behavior under test. Keep
cross-layer coverage in `TerminalUITests` and the runner-package test suites,
not as the default place for every new assertion.

## Principles

- Prefer focused subsystem tests over large cross-cutting assertions when a failure can be localized cleanly.
- Keep one or two end-to-end smoke suites for whole-pipeline confidence.
- Treat fixture changes as evidence, not as housekeeping.
- Keep performance checks deterministic and scenario-based.

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
