# CPU And Latency Evaluation Pipeline

## Status

Proposed. This document defines the measurement system needed to evaluate
async rendering and future runtime optimizations by their CPU cost and latency
benefit. It is a proposal for repo tooling and process, not a change to runtime
rendering behavior by itself.

The current runtime already has useful frame diagnostics through
`FrameDiagnosticsLogger`: phase timings, worker enqueue and compute time,
main-actor blocked and suspended time, presentation metrics, cancellation and
drop policy state, and total frame duration. Those diagnostics are a strong
attribution layer, but they are not yet an evaluation pipeline.

What is missing is the outer harness:

- repeatable scenarios,
- same-binary comparison between full-main and async rendering modes,
- input-to-paint latency probes,
- process CPU sampling,
- release-build runs,
- stored run metadata,
- summary and comparison tooling,
- a documented process for deciding whether a CPU increase is justified by a
  latency improvement.

## Problem

The async rendering work changes where work runs and when work can be skipped.
That is not the same as reducing total CPU. A frame-tail worker can improve
responsiveness by moving eligible layout and raster work off the main actor, but
it can also increase aggregate CPU through queue hops, draft/checkpoint
bookkeeping, cancellation checks, diagnostics, and increased frame throughput.

Without a repeatable evaluation process, the project cannot answer the questions
that matter:

- Did main-actor blocked time fall?
- Did input-to-present latency improve?
- Did total process CPU rise?
- If CPU rose, was the latency gain worth it?
- Did async rendering actually offload layout for this workload, or did it fall
  back to the main actor?
- Did queued-tail cancellation avoid real work, or are completed drops only
  avoiding stale presentation?
- Is the bottleneck render work, presentation, authored view evaluation, layout
  fallback, animation scheduling, or terminal I/O?

Ad hoc manual runs and one-off Instruments traces are useful for investigation,
but they are not enough for architectural decisions. The repo needs a durable
performance lab that can be rerun across commits and branches.

## Goals

- Compare full-main, async, async-without-cancellation, and async-without-drop
  behavior in the same binary.
- Measure input-to-paint latency, not only per-frame phase timing.
- Measure process CPU seconds and CPU per committed frame.
- Preserve the existing frame diagnostics as the attribution layer.
- Record enough run metadata that results are comparable later.
- Keep normal benchmark runs low-overhead and scriptable.
- Use Instruments or `xctrace` as an optional deep-dive path, not the default
  gate.
- Produce summaries that support CPU-versus-latency tradeoff decisions instead
  of a single opaque score.

## Non-Goals

- Do not make wall-clock benchmark thresholds part of the ordinary correctness
  gate before variance is measured.
- Do not treat async rendering as inherently lower CPU.
- Do not use Instruments traces as the primary pipeline artifact.
- Do not compare only branch A against branch B when the same-binary render mode
  switch can avoid unrelated-code noise.
- Do not require real terminal presentation for every scenario. Deterministic
  recording-host scenarios should be the default; PTY-backed scenarios are a
  separate presentation-cost track.

## Proposed Architecture

Create a small repo performance lab with four layers:

1. Runtime mode control.
2. Scenario execution.
3. Metrics capture.
4. Summary and comparison.

### Runtime Mode Control

Add an explicit runtime render mode that can be selected from code and from the
environment:

```text
TERMUI_RENDER_MODE=sync
TERMUI_RENDER_MODE=async
TERMUI_RENDER_MODE=async-no-cancel
TERMUI_RENDER_MODE=async-no-drop
```

The modes should run in one binary so that comparisons avoid branch-level and
build-level drift.

- `sync`: full-main render loop. This is the control path.
- `async`: current async runtime behavior.
- `async-no-cancel`: async worker path with queued-tail cancellation disabled.
- `async-no-drop`: async worker path with completed visual-only stale drops
  disabled.

The exact internal representation can be package-local, but the perf harness
needs a stable way to select it.

### Scenario Execution

Add a deterministic CLI harness, likely as a small package under
`Tools/TermUIPerf`, with commands such as:

```bash
swiftly run swift run --package-path Tools/TermUIPerf termui-perf run \
  --scenario gallery-animation-click \
  --mode async \
  --iterations 20

swiftly run swift run --package-path Tools/TermUIPerf termui-perf compare \
  .perf/runs/base .perf/runs/candidate
```

Initial scenarios should cover both real composed paths and synthetic stress
paths:

- `gallery-animation-click`: click a real gallery animation control and measure
  one-shot animation input-to-present latency and frame jitter.
- `gallery-tab-burst`: switch tabs repeatedly and measure interaction latency,
  render coalescing, and cancellation/drop behavior.
- `layout-scroll-burst`: scroll through layout-heavy content with worker-safe
  layout.
- `lazy-scroll-burst`: scroll through lazy content to expose snapshot and
  fallback costs.
- `geometry-reader-fallback`: force layout-dependent realization and confirm
  main-actor fallback cost.
- `canvas-heavy-raster`: isolate raster-heavy visual work.
- `presentation-full-repaint`: measure full repaint presentation cost.
- `presentation-incremental`: measure incremental presentation cost.

Default runs should use injected input and a recording terminal host so the
latency path is deterministic. A separate PTY-backed mode can be used when the
question is real terminal presentation cost.

### Data Artifacts

Every run should write a self-contained directory:

```text
.perf/runs/2026-05-02T12-34-56Z-gallery-animation-click-async/
  run.json
  frames.tsv
  events.tsv
  cpu.tsv
  summary.json
```

`run.json` should include:

- git SHA,
- dirty worktree flag,
- render mode,
- scenario,
- iteration count,
- build configuration,
- Swift version,
- OS version,
- hardware model and CPU core count when available,
- terminal size,
- harness version,
- start/end timestamps.

`frames.tsv` should contain current `FrameDiagnosticsLogger` rows plus any
additional timing columns needed to correlate frames with scripted events.

`events.tsv` should contain:

- scripted event id,
- event type,
- dispatch timestamp,
- expected visual marker,
- first matching presented frame,
- first matching timestamp,
- final settled frame when relevant.

`cpu.tsv` should contain sampled process CPU:

- monotonic timestamp,
- user CPU seconds,
- system CPU seconds,
- total CPU seconds,
- wall-clock delta,
- estimated process CPU percent.

`summary.json` should contain the reducer output:

- p50/p95/p99 input-to-present latency,
- p50/p95/p99 input-to-settled latency when relevant,
- frame interval p50/p95/p99,
- total CPU seconds,
- CPU seconds per committed frame,
- CPU seconds per input event,
- main-actor blocked ratio,
- main-actor suspended ratio,
- worker enqueue and compute summaries,
- presentation duration summaries,
- cancellation count,
- completed-drop count,
- fallback counts,
- committed frame count,
- skipped frame count.

### CPU Collection

Use two levels of CPU collection:

1. Low-overhead process counters for every benchmark run.
2. Optional Instruments or `xctrace` profiles for attribution.

The default collector should sample process CPU using platform APIs such as
`getrusage` and, on Darwin, task information where needed. The key default
metric is CPU seconds over the measured interval, not instantaneous CPU percent.
Instantaneous CPU percent is useful as a derived diagnostic, but CPU seconds are
more stable for comparisons.

Thread-level CPU is useful but should be a second stage. The first version only
needs process-level CPU plus existing frame diagnostics that split main-actor
blocked/suspended time from worker timing.

### Latency Collection

The harness should measure latency from scripted input to visible output:

- input dispatched,
- input handled when the harness can observe it,
- frame prepared,
- frame presented,
- first frame containing the expected visual marker,
- final settled frame for animations or scroll bursts.

The primary latency metric is input-to-present for the first matching frame.
`total_ms` in frame diagnostics remains useful, but it does not answer whether
the user-visible response arrived sooner.

### Interpretation Rules

Use a tradeoff table instead of a single score:

| Result | Interpretation |
| --- | --- |
| Latency down, CPU same or down | Clear win. |
| Latency down, CPU slightly up | Usually acceptable; record the exchange rate. |
| Latency flat, CPU up | Regression unless another metric explains the cost. |
| Main-actor blocked down, total CPU up | Async is buying responsiveness through parallel work. |
| Worker enqueue high | Worker saturation or too much serialized worker work. |
| Layout fallback high | Async path is not actually getting layout off-main. |
| Presentation high | Render work is probably not the bottleneck. |
| Cancellation high with CPU down | Queued work is being avoided. |
| Completed drops high with CPU flat | Stale presentation is avoided, but tail CPU was already spent. |

For async rendering specifically, the expected successful shape is lower
main-actor blocked time and lower input-to-present latency. Total process CPU
may stay flat or rise. That is acceptable only when the latency improvement is
large enough and the scenario is representative.

## Process

Start with baselining, not gates.

1. Build release binaries.
2. Run each scenario multiple times per mode.
3. Alternate modes within the same command where possible:
   `sync, async, sync, async`, not all sync followed by all async.
4. Record the first week of variance.
5. Add non-failing CI artifact uploads once the results are stable enough to
   read.
6. Add warning thresholds after variance is understood.
7. Add failing thresholds only for focused, low-variance scenarios.

Initial local commands should look like:

```bash
swiftly run swift run --package-path Tools/TermUIPerf termui-perf run \
  --scenario gallery-animation-click \
  --modes sync,async \
  --iterations 20 \
  --configuration release

swiftly run swift run --package-path Tools/TermUIPerf termui-perf compare \
  .perf/runs/<sync-run> .perf/runs/<async-run>
```

CI should initially archive `.perf/runs/**/summary.json` and print comparisons
without failing pull requests. Failing budgets should be introduced only after
the repo has a known noise floor.

## First Implementation Tranche

The first tranche should deliver the smallest useful loop:

1. Add a render mode switch.
2. Add `Tools/TermUIPerf`.
3. Add two scenarios:
   - `gallery-animation-click`
   - `layout-scroll-burst`
4. Reuse `FrameDiagnosticsLogger`, but write frame diagnostics to the run
   artifact directory.
5. Add process CPU sampling.
6. Add `summary.json`.
7. Add `termui-perf compare`.
8. Document the local workflow.

This is enough to decide whether async rendering is moving work off the main
actor, whether total CPU changed, and whether the latency gain justifies that
CPU profile.

## Open Questions

- Should the first render mode switch be public, SPI, package-local, or
  environment-only?
- Should real example packages be benchmarked through a separate tool package
  that depends on `Examples/gallery` and `Examples/layouts`, or should the first
  scenarios be synthetic and root-package-only?
- How much of `FrameDiagnosticsLogger` should be reused directly versus copied
  into an in-memory sink to avoid file I/O perturbing CPU measurements?
- When should thread-level CPU be added?
- Which scenarios are stable enough for CI warnings after the first variance
  pass?
