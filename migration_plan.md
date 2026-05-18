# Production Code Humanization Plan

## Strategy

Use small, behavior-preserving slices. Each slice must have explicit file
ownership, a targeted validation command, and a rollback note before edits
begin. Start at the terminal rendering path because it is central production
infrastructure and contains the largest debt indicators by file size and
coupling.

## Discovery Lanes

Read-only subagents mapped:

- Terminal host and presentation internals.
- Runtime render pipeline and frame artifacts.
- Run-loop, scene, and CLI integration.
- Validation commands and existing terminal-rendering tests.

The first implementation packet was selected after checking those findings
against local source evidence.

## Candidate Packet Order

### Packet 1: Terminal Presentation Writer and Session State

- Objective: make terminal presentation submission state explicit and easier to
  review without changing behavior.
- Owned files:
  - `Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift`
  - `Sources/SwiftTUIRuntime/Terminal/TerminalPresentationState.swift`
- Scope: move and rename `PresentationFrame`, `PresentationWriter`, and
  `PresentationSession` into terminal-specific internal types. Preserve the
  "latest pending frame wins" writer behavior and the "dropped frame forces the
  next full repaint" session behavior.
- Dependencies: baseline status and subagent findings are complete.
- Invariants: terminal bytes, process cleanup, capability probing, writer
  batching, and cursor/focus commands remain stable.
- Required checks:
  - `swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 2: Terminal Presentation Emission

- Objective: make `TerminalHost.present(_:damage:)` read as orchestration by
  moving output assembly and metrics bookkeeping into named helpers.
- Owned files:
  - `Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift`
  - `Sources/SwiftTUIRuntime/Terminal/TerminalPresentationState.swift`
- Scope: preserve terminal output byte-for-byte while splitting full repaint,
  incremental row emission, Kitty graphics replay, synchronized-output wrapping,
  writer submission, and metrics construction into named units.
- Dependencies: Packet 1.
- Invariants: terminal bytes, graphics replay scope/count metrics, edit-operation
  lowering metrics, retained surface updates, synchronized-output wrapping, and
  Kitty image-id cache behavior remain stable.
- Required checks:
  - `swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 3: Frame Tail / Artifacts Readability

- Objective: make the frame-tail and artifact flow easier to trace while
  preserving phase products and frame-drop semantics.
- Likely owned files: pending discovery, expected to be inside
  `Sources/SwiftTUIRuntime/Rendering/` and `Sources/SwiftTUICore/Commit/`.
- Dependencies: Packet 2 only if shared presentation concepts are renamed or
  extracted.
- Invariants: phase order, retained frame reuse, damage hints, diagnostics, and
  async/sync parity remain stable.
- Required checks: pipeline/rendering focused tests first, then `bun run test`.
- Rollback: revert the packet commit/files only.

### Packet 4: RunLoop Presentation Path

- Objective: reduce cognitive load in frame acquisition, commit, and
  presentation handoff code.
- Likely owned files: pending discovery, expected to be inside
  `Sources/SwiftTUIRuntime/RunLoop/`.
- Dependencies: Packet 2 if presentation artifacts are clarified there.
- Invariants: lifecycle callbacks, drop decisions, accessibility, focus, and
  input responsiveness remain stable.
- Required checks: interactive runtime and pipeline tests first, then
  `bun run test`.
- Rollback: revert the packet commit/files only.

### Packet 5: Platform Entrypoint Clarity

- Objective: clarify how CLI/render-once entrypoints connect to runtime and
  terminal hosts.
- Likely owned files: pending discovery, expected to be inside
  `Platforms/CLI/Sources/SwiftTUICLI/`.
- Dependencies: terminal host concepts from Packet 1.
- Invariants: command-line behavior, exit behavior, and rendered text output
  remain stable.
- Required checks: focused CLI tests first, then `bun run test`.
- Rollback: revert the packet commit/files only.

## Human Checkpoints

Stop for approval before:

- Any public API change.
- Any intentional terminal-output, rendering, lifecycle, or frame-drop behavior
  change.
- Any fixture re-recording.
- Any example-app change.
- Any test weakening or broad test rewrite.
