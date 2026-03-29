# Testing And Fixture Policy

Last updated: March 26, 2026

This policy keeps reliability work predictable in the current decomposed codebase.

## Policy Hooks

Structural repository guardrails that do not exercise runtime behavior now live in `prek`
hooks instead of the test suite:

- `Scripts/check_phase5_source_layout.zsh` enforces the standing Core and View source map,
  retired monolith removals, and line budgets.
- `Scripts/check_public_surface_policies.zsh` enforces public-surface guardrails, package
  product policy, and the docs that describe that policy.
- `Scripts/check_rendered_text_fixture_matrix.zsh` enforces that every committed rendered-text
  fixture directory contains the full supported terminal configuration matrix.

Keep runtime, integration, and behavioral guarantees in tests. Move pure repository-shape or
text-pattern checks into hooks when they can fail earlier and more locally.

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
- The standing enforcement lives in `Phase5ReliabilityGatesTests` and the targeted scenario suites.

## Architecture Gates

- Do not let a single file accumulate multiple unrelated subsystem responsibilities again.
- If a new file becomes a catch-all, split it or document why the exception is temporary.
- The source map in [SOURCE_LAYOUT.md](SOURCE_LAYOUT.md) is the current ownership reference; keep it in sync with any future file moves.
- The standing enforcement lives in `Scripts/check_phase5_source_layout.zsh` via `prek`.

## Review Checklist

- Does the change belong to the subsystem it touches most?
- Did the relevant fixture or benchmark update because behavior changed, not because the implementation drifted?
- Do the docs still describe the current file map and the current fallback cases?
- Is there still at least one local test that can fail without needing the whole integration suite?
