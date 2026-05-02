---
title: "chore: CPU latency evaluation pipeline"
type: chore
status: active
date: 2026-05-02
proposal: "../proposals/CPU_LATENCY_EVALUATION_PIPELINE.md"
depends_on:
  - "../ASYNC_RENDERING.md"
  - "../proposals/CPU_LATENCY_EVALUATION_PIPELINE.md"
---

# CPU Latency Evaluation Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking. Commit after every task that reaches a green checkpoint.

**Goal:** Build a repeatable repo-local performance lab for evaluating CPU cost
against input latency across full-main and async runtime rendering modes.

**Architecture:** Keep runtime behavior unchanged by default, but add an
explicit render-mode selection path for measurement. Build the measurement
pipeline as a separate `Tools/TermUIPerf` Swift package that drives deterministic
runtime scenarios, captures frame diagnostics and process CPU samples, writes
run artifacts, and compares summaries.

**Tech Stack:** Swift 6.3, SwiftPM, `TerminalUI`, `FrameDiagnosticsLogger`,
`RunLoop`, `InjectedTerminalInputReader`, recording `TerminalHosting`
implementations, `getrusage`/Darwin task information, JSON and TSV artifacts,
and optional `xctrace` for manual deep dives.

---

## File Map

- Create: `Sources/TerminalUI/RuntimeRenderMode.swift`
  - Defines runtime render modes and environment parsing.
- Modify: `Sources/TerminalUI/RunLoop.swift`
  - Stores the selected render mode.
- Modify: `Sources/TerminalUI/RunLoop+Rendering.swift`
  - Selects sync, async, async-without-cancellation, and async-without-drop paths.
- Modify: `Sources/TerminalUI/TerminalUI.swift`
  - Exposes package-level policy hooks needed by the render mode switch.
- Modify: `Tests/TerminalUITests/AsyncFrameTailRenderingTests.swift`
  - Verifies each render mode selects the intended cancellation/drop behavior.
- Create: `Tools/TermUIPerf/Package.swift`
  - Defines the standalone `termui-perf` executable package.
- Create: `Tools/TermUIPerf/Sources/TermUIPerf/main.swift`
  - CLI entry point for `run` and `compare`.
- Create: `Tools/TermUIPerf/Sources/TermUIPerf/PerfRunConfig.swift`
  - Parses command-line options and run configuration.
- Create: `Tools/TermUIPerf/Sources/TermUIPerf/PerfArtifacts.swift`
  - Defines `run.json`, `events.tsv`, `cpu.tsv`, and `summary.json` models.
- Create: `Tools/TermUIPerf/Sources/TermUIPerf/CPUSampler.swift`
  - Samples process CPU during a scenario run.
- Create: `Tools/TermUIPerf/Sources/TermUIPerf/PerfTerminalHost.swift`
  - Recording terminal host used by deterministic scenarios.
- Create: `Tools/TermUIPerf/Sources/TermUIPerf/FrameDiagnosticsSink.swift`
  - Owns frame diagnostics output inside a run directory.
- Create: `Tools/TermUIPerf/Sources/TermUIPerf/Scenarios/*.swift`
  - Scenario implementations and shared scenario protocol.
- Create: `Tools/TermUIPerf/Sources/TermUIPerf/SummaryReducer.swift`
  - Aggregates frames, events, and CPU samples into `summary.json`.
- Create: `Tools/TermUIPerf/Sources/TermUIPerf/CompareCommand.swift`
  - Prints same-scenario summary deltas.
- Create: `Tools/TermUIPerf/Tests/TermUIPerfTests/*.swift`
  - Unit tests for parsing, CPU deltas, summaries, and comparison output.
- Modify: `package.json`
  - Adds convenience scripts for local perf runs if useful.
- Modify: `docs/README.md`
  - Links the proposal and plan while the work is active.
- Create or modify: `docs/PERFORMANCE_EVALUATION.md`
  - Documents the finalized local workflow once the first tranche lands.

## Task 1: Add Runtime Render Mode Selection

**Files:**
- Create: `Sources/TerminalUI/RuntimeRenderMode.swift`
- Modify: `Sources/TerminalUI/RunLoop.swift`
- Modify: `Sources/TerminalUI/RunLoop+Rendering.swift`
- Modify: `Sources/TerminalUI/TerminalUI.swift`
- Test: `Tests/TerminalUITests/AsyncFrameTailRenderingTests.swift`

- [x] **Step 1: Add a failing test for sync mode**

  Add a test proving `TERMUI_RENDER_MODE=sync` or an explicit run-loop
  property bypasses `renderAsyncCancellable` and produces no queued-tail
  cancellation or completed-drop diagnostics under a scenario that would
  otherwise be cancellable.

  Run:

  ```bash
  swiftly run swift test --filter TerminalUITests.AsyncFrameTailRenderingTests/runtimeRenderModeSyncBypassesAsyncCancellation
  ```

  Expected: fail because no render mode exists yet.

- [x] **Step 2: Implement the render mode type**

  Add `RuntimeRenderMode` with cases:

  ```swift
  public enum RuntimeRenderMode: String, Sendable {
    case sync
    case async
    case asyncNoCancel = "async-no-cancel"
    case asyncNoDrop = "async-no-drop"
  }
  ```

  Include an environment parser for `TERMUI_RENDER_MODE`, defaulting to
  `.async` to preserve current behavior.

- [x] **Step 3: Thread the mode into `RunLoop`**

  Add a `public var renderMode: RuntimeRenderMode` property on `RunLoop`.
  Initialize it from the environment so CLI apps can be switched without code
  changes. Keep explicit assignment available for tests and the perf harness.

- [x] **Step 4: Split run-loop render selection**

  In `RunLoop+Rendering.swift`, choose:

  - `.sync`: synchronous render path.
  - `.async`: current cancellable async path.
  - `.asyncNoCancel`: async path with `shouldCancelQueued` returning `false`.
  - `.asyncNoDrop`: async path with completed visual-only dropping disabled.

  Started or completed worker work must still commit in order in every mode
  except the already-shipped visual-only drop path.

- [x] **Step 5: Add mode coverage**

  Add tests that prove:

  - `sync` does not produce `tail_job_state=cancelled_before_start`.
  - `async` can still cancel a queued tail.
  - `async-no-cancel` commits started/completed work in order and does not
    cancel queued work.
  - `async-no-drop` logs stale completed visual-only candidates as ordered
    commits rather than `drop_completed_visual_only`.

- [x] **Step 6: Verify and commit**

  Run:

  ```bash
  swiftly run swift test --filter TerminalUITests.AsyncFrameTailRenderingTests
  git add Sources/TerminalUI Tests/TerminalUITests/AsyncFrameTailRenderingTests.swift
  git commit -m "feat(runtime): add render mode selection"
  ```

## Task 2: Add The TermUIPerf Tool Package Skeleton

**Files:**
- Create: `Tools/TermUIPerf/Package.swift`
- Create: `Tools/TermUIPerf/Sources/TermUIPerf/main.swift`
- Create: `Tools/TermUIPerf/Sources/TermUIPerf/PerfRunConfig.swift`
- Create: `Tools/TermUIPerf/Tests/TermUIPerfTests/PerfRunConfigTests.swift`

- [x] **Step 1: Create the package**

  Create a standalone SwiftPM package that depends on:

  - `../../` for `TerminalUI`,
  - `../../Examples/gallery` for `GalleryDemoViews`,
  - `../../Examples/layouts` for `Layouts`.

  This avoids adding benchmark-only dependencies to the root package.

- [x] **Step 2: Add CLI parsing**

  Implement a small hand-rolled parser with commands:

  ```text
  termui-perf run --scenario <name> --mode <mode> --iterations <n>
  termui-perf compare <base-run-dir> <candidate-run-dir>
  termui-perf list-scenarios
  ```

  Keep dependencies minimal. Do not add `ArgumentParser` unless the repo already
  accepts that dependency for tooling.

- [x] **Step 3: Add parser tests**

  Cover mode parsing, comma-separated mode lists, iteration defaults, artifact
  root defaults, and error messages for unknown scenarios.

- [x] **Step 4: Verify and commit**

  Run:

  ```bash
  swiftly run swift test --package-path Tools/TermUIPerf
  git add Tools/TermUIPerf
  git commit -m "chore(perf): add termui-perf package skeleton"
  ```

## Task 3: Define Run Artifacts And Summary Schema

**Files:**
- Create: `Tools/TermUIPerf/Sources/TermUIPerf/PerfArtifacts.swift`
- Create: `Tools/TermUIPerf/Sources/TermUIPerf/SummaryReducer.swift`
- Create: `Tools/TermUIPerf/Tests/TermUIPerfTests/SummaryReducerTests.swift`

- [ ] **Step 1: Define artifact models**

  Add Codable models for:

  - `PerfRunMetadata`
  - `PerfEventRecord`
  - `PerfCPUSample`
  - `PerfSummary`

  Include git SHA, dirty flag, render mode, scenario, iteration count,
  configuration, Swift version, OS, hardware, terminal size, and timestamps.

- [ ] **Step 2: Add TSV writers**

  Add deterministic TSV writers for `events.tsv` and `cpu.tsv`. Keep field
  order stable and include a header row.

- [ ] **Step 3: Add summary reducers**

  Implement percentile reducers for latency, frame interval, CPU seconds,
  CPU/frame, worker timings, main-actor blocked ratio, cancellation counts,
  completed-drop counts, and fallback counts.

- [ ] **Step 4: Test schema stability**

  Add tests that assert:

  - known input samples produce expected p50/p95 values,
  - CPU seconds per frame is computed from CPU deltas and committed frames,
  - missing optional frame fields do not crash reduction,
  - JSON key names remain stable.

- [ ] **Step 5: Verify and commit**

  Run:

  ```bash
  swiftly run swift test --package-path Tools/TermUIPerf --filter TermUIPerfTests.SummaryReducerTests
  git add Tools/TermUIPerf
  git commit -m "chore(perf): define run artifact schema"
  ```

## Task 4: Add Process CPU Sampling

**Files:**
- Create: `Tools/TermUIPerf/Sources/TermUIPerf/CPUSampler.swift`
- Create: `Tools/TermUIPerf/Tests/TermUIPerfTests/CPUSamplerTests.swift`

- [ ] **Step 1: Add CPU sample model tests**

  Test delta calculation from two samples:

  - user CPU delta,
  - system CPU delta,
  - total CPU delta,
  - wall delta,
  - derived CPU percent.

- [ ] **Step 2: Implement platform sampler**

  Use `getrusage(RUSAGE_SELF)` for the first implementation. Add Darwin task
  information later only if process-level CPU is insufficient.

- [ ] **Step 3: Add periodic collection**

  Add an async sampler loop with configurable sample interval, defaulting to
  50 ms. The sampler should start immediately before the scenario and stop
  immediately after the final expected output.

- [ ] **Step 4: Verify and commit**

  Run:

  ```bash
  swiftly run swift test --package-path Tools/TermUIPerf --filter TermUIPerfTests.CPUSamplerTests
  git add Tools/TermUIPerf
  git commit -m "chore(perf): sample process CPU"
  ```

## Task 5: Add Deterministic Scenario Infrastructure

**Files:**
- Create: `Tools/TermUIPerf/Sources/TermUIPerf/PerfTerminalHost.swift`
- Create: `Tools/TermUIPerf/Sources/TermUIPerf/FrameDiagnosticsSink.swift`
- Create: `Tools/TermUIPerf/Sources/TermUIPerf/Scenarios/PerfScenario.swift`
- Create: `Tools/TermUIPerf/Sources/TermUIPerf/Scenarios/GalleryAnimationClickScenario.swift`
- Create: `Tools/TermUIPerf/Sources/TermUIPerf/Scenarios/LayoutScrollBurstScenario.swift`
- Create: `Tools/TermUIPerf/Tests/TermUIPerfTests/ScenarioSmokeTests.swift`

- [ ] **Step 1: Implement `PerfTerminalHost`**

  Implement public `TerminalHosting` with:

  - fixed surface size,
  - capability profile configuration,
  - captured raster frames,
  - presentation metrics,
  - monotonic presentation timestamps.

  Keep this host deterministic and in-memory. Real PTY presentation can be a
  later mode.

- [ ] **Step 2: Wrap frame diagnostics**

  Reuse `FrameDiagnosticsLogger` by writing `frames.tsv` into each run
  directory. If file I/O proves too noisy, add an in-memory sink in a later
  tranche.

- [ ] **Step 3: Define scenario protocol**

  Add a protocol that returns:

  - scenario name,
  - default terminal size,
  - setup view,
  - scripted input events,
  - visual marker matchers,
  - settling criteria.

- [ ] **Step 4: Add `gallery-animation-click`**

  Drive the real gallery animation path through `RunLoop.run()` using
  `GalleryDemoViews`. Record input dispatch time, first intermediate frame, and
  final settled frame.

- [ ] **Step 5: Add `layout-scroll-burst`**

  Drive a layout-heavy scroll scenario through injected input. Record scroll
  event timestamps, first matching viewport movement, worker layout timing, and
  main-actor fallback counts.

- [ ] **Step 6: Add smoke tests**

  Assert that each scenario writes:

  - `run.json`,
  - `frames.tsv`,
  - `events.tsv`,
  - `cpu.tsv`,
  - `summary.json`.

- [ ] **Step 7: Verify and commit**

  Run:

  ```bash
  swiftly run swift test --package-path Tools/TermUIPerf
  git add Tools/TermUIPerf
  git commit -m "chore(perf): add deterministic runtime scenarios"
  ```

## Task 6: Implement Run And Compare Commands

**Files:**
- Modify: `Tools/TermUIPerf/Sources/TermUIPerf/main.swift`
- Create: `Tools/TermUIPerf/Sources/TermUIPerf/RunCommand.swift`
- Create: `Tools/TermUIPerf/Sources/TermUIPerf/CompareCommand.swift`
- Create: `Tools/TermUIPerf/Tests/TermUIPerfTests/CompareCommandTests.swift`

- [ ] **Step 1: Implement `run`**

  The command should:

  - create a timestamped run directory,
  - write `run.json`,
  - start CPU sampling,
  - install frame diagnostics,
  - run the scenario for the requested iterations and modes,
  - write `events.tsv`,
  - write `cpu.tsv`,
  - write `summary.json`,
  - print the run directory path.

- [ ] **Step 2: Implement `compare`**

  Compare two `summary.json` files and print:

  - p50/p95 input latency delta,
  - total CPU seconds delta,
  - CPU/frame delta,
  - main-actor blocked ratio delta,
  - worker enqueue/compute changes,
  - cancellation/drop count changes,
  - fallback count changes.

- [ ] **Step 3: Add textual interpretation**

  Print a short classification:

  - clear win,
  - latency win with CPU cost,
  - CPU regression,
  - no meaningful movement,
  - inconclusive due to missing data.

- [ ] **Step 4: Verify and commit**

  Run:

  ```bash
  swiftly run swift test --package-path Tools/TermUIPerf
  swiftly run swift run --package-path Tools/TermUIPerf termui-perf list-scenarios
  git add Tools/TermUIPerf
  git commit -m "chore(perf): add run and compare commands"
  ```

## Task 7: Document And Wire The Local Workflow

**Files:**
- Create: `docs/PERFORMANCE_EVALUATION.md`
- Modify: `docs/README.md`
- Modify: `package.json`

- [ ] **Step 1: Add workflow docs**

  Document:

  - when to use the perf pipeline,
  - how to run release-mode baselines,
  - how to compare modes,
  - how to interpret CPU-versus-latency tradeoffs,
  - when to escalate to Instruments or `xctrace`,
  - how to archive run artifacts.

- [ ] **Step 2: Add convenience scripts**

  Add package scripts if they remain thin wrappers:

  ```json
  {
    "perf:list": "swiftly run swift run --package-path Tools/TermUIPerf termui-perf list-scenarios",
    "perf:run": "swiftly run swift run --package-path Tools/TermUIPerf termui-perf run",
    "perf:compare": "swiftly run swift run --package-path Tools/TermUIPerf termui-perf compare"
  }
  ```

- [ ] **Step 3: Verify docs and commit**

  Run:

  ```bash
  bun run Scripts/check_doc_frontmatter.ts
  git diff --check
  git add docs/PERFORMANCE_EVALUATION.md docs/README.md package.json
  git commit -m "docs(perf): document CPU latency evaluation workflow"
  ```

## Task 8: Add Non-Failing CI Artifact Collection

**Files:**
- Modify: `.github/workflows/run-tests-linux.yml` or add a dedicated perf workflow
- Create: `Scripts/run_perf_smoke.sh`

- [ ] **Step 1: Add a short smoke command**

  The smoke command should run one low-iteration scenario in release mode and
  write artifacts under `.perf/runs`.

- [ ] **Step 2: Upload artifacts without failing on budget deltas**

  CI should archive summaries and run directories. Do not add failing CPU or
  latency budgets until variance has been collected.

- [ ] **Step 3: Verify and commit**

  Run the script locally:

  ```bash
  sh Scripts/run_perf_smoke.sh
  git add .github/workflows Scripts/run_perf_smoke.sh
  git commit -m "ci(perf): archive CPU latency smoke artifacts"
  ```

## Validation Gates Before Calling The Tranche Complete

- `swiftly run swift test --filter TerminalUITests.AsyncFrameTailRenderingTests`
- `swiftly run swift test --package-path Tools/TermUIPerf`
- `swiftly run swift run --package-path Tools/TermUIPerf termui-perf list-scenarios`
- `swiftly run swift run --package-path Tools/TermUIPerf termui-perf run --scenario gallery-animation-click --modes sync,async --iterations 3 --configuration release`
- `swiftly run swift run --package-path Tools/TermUIPerf termui-perf compare <sync-run> <async-run>`
- `bun run test` before merging runtime or shared-tooling changes.

## Initial Success Criteria

- A same-binary run can compare `sync` and `async`.
- The first two scenarios write complete artifact directories.
- `summary.json` reports latency, CPU seconds, CPU/frame, main-actor blocked
  ratio, worker timing, fallback counts, cancellation counts, and drop counts.
- The compare command can identify whether async improved latency at the cost of
  higher CPU.
- CI archives smoke artifacts without enforcing premature budgets.
