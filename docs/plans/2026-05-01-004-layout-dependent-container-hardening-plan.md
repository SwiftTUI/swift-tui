---
title: "test: harden layout-dependent container geometry"
type: test
status: shipped
date: 2026-05-01
depends_on:
  - "2026-05-01-003-layout-dependent-container-audit.md"
---

# test: harden layout-dependent container geometry

## Goal

Turn the container-audit gaps into regression coverage and author-facing
documentation. The work should keep the placement-time geometry seam intact and
avoid reopening resolve-time `terminalSize` shims.

## Tracker

- [x] `safeAreaInset` geometry coverage: base and inset `GeometryReader`
  branches see their placed sizes, and the safe-area environment contract is
  explicit.
- [x] `ViewThatFits` geometry coverage: unselected layout-dependent candidates
  do not realize, while the selected candidate realizes with its placed size.
- [x] `ScrollView` geometry coverage: local `GeometryReader.frame(in: .global)`
  shifts with scroll position and records no geometry misses.
- [x] Lazy-stack geometry coverage: scroll-hosted indexed lazy stacks realize
  visible geometry rows without realizing off-screen geometry rows.
- [x] Custom `Layout` docs: explain that measurement probes do not realize
  `GeometryReader` content, while `LayoutSubview.place(... proposal:)`
  establishes child-local geometry and worker eligibility.
- [x] Verification: run focused geometry/container tests and update this plan
  with exact commands and results.

## Progress Log

- 2026-05-01: Added the repo tracker and documentation-index link.
- 2026-05-01: Added `safeAreaInset` regression coverage for paired base and
  inset `GeometryReader` realization with placed bounds and safe-area values.
- 2026-05-01: Added `ViewThatFits` selected-candidate coverage alongside the
  existing unselected-candidate non-realization test.
- 2026-05-01: Added `ScrollView` and indexed `LazyVStack` regression tests for
  scroll-shifted global frames and visible-only lazy geometry realization.
- 2026-05-01: Documented custom `Layout` measurement/place geometry boundaries
  in the Geometry and Preferences DocC page.

## Verification Log

- `swiftly run swift test --filter 'TerminalUITests\.(SafeAreaSurfaceTests|ViewThatFitsSurfaceTests|LayoutDependentContainerHardeningTests)'`
  - passed, 13 tests in 3 suites.
- `swiftly run swift test --filter 'TerminalUITests\.(SafeAreaSurfaceTests|ViewThatFitsSurfaceTests|LayoutDependentContainerHardeningTests|AnchorPreferenceSurfaceTests|GeometryReaderSurfaceTests|AsyncFrameTailRenderingTests)|CoreTests\.LayoutEngineTests'`
  - passed, 88 tests in 7 suites.
- `git diff --check` - passed.
- `bun run test` - passed. Full log:
  `/tmp/swift-terminal-ui-test-all-20260501-150017-28148.log`.
