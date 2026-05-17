---
title: "refactor: Stage 7 - split host presentation seam"
type: refactor
status: shipped
date: 2026-05-17
depends_on:
  - "2026-05-16-001-pipeline-driver-hardening-plan.md"
  - "2026-05-17-002-stage-0-contract-guards-plan.md"
  - "2026-05-13-001-host-presentation-damage-plan.md"
  - "../proposals/PIPELINE_DRIVER_AUDIT.md"
  - "../proposals/SEMANTIC_HOST_FRAME_API.md"
  - "../HOST_RENDERING_PIPELINES.md"
---

# Stage 7 - Split Host Presentation Seam Implementation Plan

> **For agentic workers:** Execute this plan task-by-task with
> `superpowers:executing-plans` or the local equivalent. This is **Stage 7** of
> [`2026-05-16-001-pipeline-driver-hardening-plan.md`](./2026-05-16-001-pipeline-driver-hardening-plan.md);
> it addresses audit proposal **P9** (Finding 15).

**Goal:** Decompose `PresentationSurface` so semantic host-frame consumers can
receive committed frames without implementing terminal raw-mode, cursor, or text
write obligations. Existing terminal hosts remain behavior-compatible through a
composed aggregate protocol.

**Architecture:** The current `PresentationSurface` mixes five roles: metrics
provider, terminal command writer, raster presenter, damage-aware raster
presenter, and semantic host-frame presenter. `RunLoop.presentCommittedFrame`
already has the right dispatch order, but its type constraints force non-terminal
semantic hosts to inherit terminal-shaped methods. Stage 7 keeps
`PresentationSurface` as the terminal aggregate for source compatibility while
moving runtime dispatch and semantic host-frame presentation onto narrower roles.

**Tech Stack:** Swift 6.3 strict concurrency, Swift Testing, `SwiftTUIRuntime`,
host platform packages (`SwiftUIHost`, `SwiftTUIWebHost`, WASI
`WebSurfaceTransport`), public API baseline generation, and the repo-wide
`bun run test` gate.

---

## Current Source Anchors

- `Sources/SwiftTUIRuntime/Terminal/PresentationSurface.swift`
  - `PresentationSurface` currently owns metrics, terminal commands, and raster
    presentation.
  - `DamageAwarePresentationSurface` and `SemanticHostFramePresentationSurface`
    both inherit that terminal-shaped aggregate.
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop.swift`
  - The run loop stores `presentationSurface` as `any PresentationSurface` and
    enables raw mode unconditionally for `.tui` output.
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift`
  - Environment resolution needs metrics only.
  - JSON/accessibility output needs a terminal command writer.
  - Frame commit should prefer semantic host-frame consumers, then damage-aware
    raster consumers, then plain raster consumers.
- `Sources/SwiftTUIRuntime/Scenes/HostedRasterSurface.swift`,
  `Platforms/WebHost/.../WebSocketSurfaceTransport.swift`, and
  `Platforms/WASI/.../WebSurfaceTransport.swift`
  - These are semantic non-terminal hosts that currently carry no-op terminal
    obligations only to satisfy the aggregate.

## Task 1 - Establish The Baseline

- [x] Run the Stage 0 presentation contract guard:

```bash
swiftly run swift test --filter SwiftTUITests.AccessibilityRuntimePolicyTests/runLoopPrefersSemanticHostFrameSurfaceOverRasterDamageSurface
```

- [x] Run current host transport tests:

```bash
swiftly run swift test --filter SwiftTUITests.HostedSceneSessionTests
swiftly run swift test --filter SwiftTUIWebHostTests.WebSocketSurfaceTransportTests
swiftly run swift test --filter WASISurfaceBridgeTests.WebSurfaceTransportTests
```

Expected: all pass before the protocol split starts.

## Task 2 - Split The Protocol Roles

- [x] In `PresentationSurface.swift`, introduce focused public roles:
  - metrics provider;
  - terminal command surface;
  - raster presentation surface.
- [x] Keep `PresentationSurface` as the composed terminal aggregate so existing
  terminal hosts and tests remain source-compatible.
- [x] Move `DamageAwarePresentationSurface` to the raster role instead of the
  terminal aggregate.
- [x] Move `SemanticHostFramePresentationSurface` to the metrics role instead of
  the terminal aggregate.
- [x] Keep compatibility defaults for optional theme, graphics, pointer, hover,
  and terminal full-repaint raster presentation behavior.

## Task 3 - Re-point Runtime Consumers

- [x] Store the run loop and scene-session resource surface as the metrics role.
- [x] Gate raw-mode, pointer-hover, JSON, accessible, and fallback raster output
  through role casts that name the required capability.
- [x] Preserve semantic-host commit ordering:
  `SemanticHostFramePresentationSurface` before `DamageAwarePresentationSurface`
  before `RasterPresentationSurface`.
- [x] Keep semantic host-frame sequence generation in `RunLoop` and preserve
  advisory `PresentationDamage` threading.

## Task 4 - Convert Non-terminal Hosts To Narrow Roles

- [x] Convert `HostedRasterSurface` to metrics + raster + semantic roles, not the
  terminal aggregate.
- [x] Convert WebHost and WASI web-surface transports similarly.
- [x] Remove terminal raw/write/cursor no-op methods from those semantic hosts.
- [x] Keep terminal `TerminalHost` and `WebTerminalHost` on the aggregate
  protocol.

## Task 5 - Add Regression Coverage

- [x] Add a semantic-only host-frame test surface that does **not** conform to
  `PresentationSurface`, `RasterPresentationSurface`, or terminal command roles.
- [x] Drive it through `RunLoop` and assert it receives a `SemanticHostFrame`
  with sequence, raster, semantics, focused identity, and damage threading.
- [x] Keep the existing Stage 0 dispatch guard green, proving semantic hosts still
  win over damage-aware raster hosts when a surface supports both.

## Task 6 - Document And Verify

- [x] Create ADR 0019 recording the host presentation role split.
- [x] Update `HOST_RENDERING_PIPELINES.md`, `SOURCE_LAYOUT.md`, and API inventory
  text where they describe the presentation seam.
- [x] Regenerate the public API baseline if public protocol symbols changed:

```bash
./Scripts/generate_public_api_inventory.sh
```

- [x] Run focused suites:

```bash
swiftly run swift test --filter SwiftTUITests.AccessibilityRuntimePolicyTests
swiftly run swift test --filter SwiftTUITests.HostedSceneSessionTests
swiftly run swift test --filter SwiftTUIWebHostTests.WebSocketSurfaceTransportTests
swiftly run swift test --filter WASISurfaceBridgeTests.WebSurfaceTransportTests
```

- [x] Run the repo gate:

```bash
bun run test
```

## Exit Criteria

Stage 7 is complete when:

- `PresentationSurface` is a composed terminal aggregate over narrower host
  presentation roles.
- Semantic host-frame consumers no longer need terminal raw-mode/write/cursor
  methods to receive committed frames.
- Existing terminal hosts remain behavior-compatible.
- `RunLoop.presentCommittedFrame` dispatch is explicit and ordered by role.
- Host docs and public API baselines are current.
- The focused suites and `bun run test` pass.

## Shipped Record

Stage 7 shipped on 2026-05-17 with the following durable changes:

- `PresentationSurface` remains the source-compatible terminal aggregate over
  metrics, terminal command, and raster presentation roles.
- `RunLoop` and `SceneSessionResources` store the metrics role, then cast to the
  exact capability needed for raw mode, pointer hover, JSON/accessibility
  output, semantic host frames, damage-aware raster frames, or plain raster
  frames.
- `HostedRasterSurface`, `WebSocketSurfaceTransport`, and `WebSurfaceTransport`
  use the non-terminal metrics/raster/semantic role set and no longer carry
  no-op terminal command methods.
- `ADR-0019` records the role split, and the host rendering, source-layout,
  terminology, runtime, API inventory, and generated public API baseline docs
  describe the shipped seam.

Validation:

```bash
swiftly run swift test --filter SwiftTUITests.AccessibilityRuntimePolicyTests/runLoopPrefersSemanticHostFrameSurfaceOverRasterDamageSurface
swiftly run swift test --filter SwiftTUITests.HostedSceneSessionTests
swiftly run swift test --filter SwiftTUIWebHostTests.WebSocketSurfaceTransportTests
swiftly run swift test --filter WASISurfaceBridgeTests.WebSurfaceTransportTests
swiftly run swift test --filter SwiftTUITests.AccessibilityRuntimePolicyTests
./Scripts/generate_public_api_inventory.sh
./Scripts/check_public_surface_policies.sh
bun run test
```

## Non-goals

- Do not change the raster, semantic, or damage frame products.
- Do not alter web-surface JSON encoding.
- Do not change terminal sanitization or ANSI byte emission.
- Do not implement Stage 6 worker/recursion hardening in this stage.
