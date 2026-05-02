# Performance Evaluation

This repo uses `Tools/TermUIPerf` as the local performance lab for comparing
runtime CPU cost against input latency. Use it when changing async rendering,
frame scheduling, presentation, layout fallback behavior, or any runtime path
where a faster-feeling UI might also spend more total process CPU.

The tool runs deterministic scenarios through the composed runtime path and
writes one artifact directory per scenario and render mode:

```text
.perf/runs/<timestamp>-<scenario>-<mode>-<uuid>/
  run.json
  frames.tsv
  events.tsv
  cpu.tsv
  summary.json
```

`frames.tsv` comes from `FrameDiagnosticsLogger`; `events.tsv` records scripted
input and first matching visual output; `cpu.tsv` records sampled process CPU
deltas; `summary.json` contains the reducer output used by comparisons.

## When To Use It

Run the perf pipeline before making architectural claims about:

- `sync` versus `async` runtime rendering
- queued-tail cancellation and completed-frame drop policy
- worker layout or raster changes
- main-actor fallback reductions
- presentation cost versus render cost
- input latency regressions in gallery or layouts workflows

Do not use these runs as hard pass/fail budgets yet. The current purpose is to
collect comparable local evidence and CI artifacts until the noise floor is
known.

## Baseline Commands

List scenarios:

```bash
bun run perf:list
```

Run a debug smoke:

```bash
bun run perf:run -- --scenario gallery-animation-click --modes sync,async --iterations 3
```

Run a release-mode baseline:

```bash
swiftly run swift run --package-path Tools/TermUIPerf -c release termui-perf run \
  --scenario gallery-animation-click \
  --modes sync,async \
  --iterations 20 \
  --configuration release
```

The command prints the run directory paths. Compare the sync directory against
the async directory:

```bash
bun run perf:compare -- .perf/runs/<sync-run> .perf/runs/<async-run>
```

## Reading Results

Prefer `summary.json` and `termui-perf compare` for the first read:

- Lower input-to-present p50 and p95 means the user-visible response improved.
- Lower main-actor blocked ratio means async work is buying responsiveness.
- Higher total CPU seconds means the improvement has a CPU cost.
- Higher CPU/frame can mean extra bookkeeping, queue hops, or more frames.
- High fallback counts mean the async path did not actually move enough layout
  work off the main actor.
- Completed drops avoid stale presentation, but the tail CPU was already spent.
- Cancellation counts are only a CPU win when avoided work also reduces sampled
  CPU.

The intended tradeoff is explicit: latency down with CPU flat or down is a clear
win; latency down with CPU up can still be acceptable if the scenario is
representative; latency flat with CPU up is a regression unless another metric
explains the cost.

## Escalation

Escalate to Instruments or `xctrace` when the lightweight artifacts show a real
movement but not the cause:

- CPU rises and frame diagnostics do not identify worker, fallback, or
  presentation cost.
- `present_ms` dominates and terminal output needs deeper attribution.
- Worker enqueue time grows enough to suggest saturation.
- Scenario variance is too high for the summary to classify confidently.
- A release-mode run disagrees sharply with debug smoke behavior.

Keep Instruments traces as supporting evidence. The repo artifact remains the
`TermUIPerf` run directory so later commits can be compared with the same
schema.

## Archiving

Keep complete run directories when citing a result. For local handoff:

```bash
tar -czf termui-perf-runs.tgz .perf/runs/<run-a> .perf/runs/<run-b>
```

For PRs or CI, archive the full run directories, not only `summary.json`; the
TSV files are needed to explain why a comparison moved.
