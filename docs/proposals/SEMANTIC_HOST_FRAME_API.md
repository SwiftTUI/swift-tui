# Semantic Host-Frame API

**Status:** Proposal draft. This is not an approved implementation plan.
It formalizes the damage-bearing semantic presentation contract that now exists
across retained native hosts, WebHost, WASI, and runtime accessibility output.

**Owner:** unassigned.

**Related docs:** [TERMINOLOGY.md](../TERMINOLOGY.md),
[HOST_RENDERING_PIPELINES.md](../HOST_RENDERING_PIPELINES.md),
[ACCESSIBILITY.md](../ACCESSIBILITY.md),
[PUBLIC_SURFACE_POLICY.md](../PUBLIC_SURFACE_POLICY.md),
[plans/2026-05-13-001-host-presentation-damage-plan.md](../plans/2026-05-13-001-host-presentation-damage-plan.md).

## Summary

SwiftTUI now has a frame-shaped value that carries raster output, semantic data,
focused identity, and raster damage together. That is the right direction, but
the surrounding protocol is still named after one historical optimization:
`DamageAwareSemanticPresentationSurface`.

The formal API should instead describe the broader contract:

```text
RunLoop producer -> semantic host frame -> host-frame presentation surface consumer
```

A semantic host frame is a committed presentation record for non-terminal and
hybrid hosts. It is not an accessibility-only payload and it is not a raster
damage protocol. It is the atomic handoff from the SwiftTUI runtime to a host
that needs both drawn pixels and semantic routes for native accessibility,
browser ARIA, hit testing, focus, selection, scroll, diagnostics, testing, and
future host-side rendering decisions.

## Current Shape

The current implementation already has the important parts:

| Role | Current code | Notes |
|---|---|---|
| Producer | `RunLoop.presentCommittedFrame` | Builds one `SemanticPresentationFrame` after semantics and rasterization, before terminal cursor focus policy. |
| Frame value | `SemanticPresentationFrame` | Public value containing `RasterSurface`, `SemanticSnapshot`, focused `Identity?`, and optional `PresentationDamage`. |
| Semantic frame consumer protocol | `DamageAwareSemanticPresentationSurface` | SPI protocol; the name wrongly makes damage sound like the primary capability. |
| Retained native consumer | `HostedRasterSurface` | Public retained surface used by `HostedSceneSession` and SwiftUIHost. |
| WebHost consumer | `WebSocketSurfaceTransport` | Serializes semantic frames over the localhost WebSocket bridge. |
| WASI/browser consumer | `WebSurfaceTransport` | Serializes semantic frames through the `web-surface` transport. |
| Announcement side effect | `AccessibilityAnnouncementRuntime` | Currently publishes queued announcements when output is `.accessible` or the presentation surface conforms to the semantic-damage protocol. |

That gives us a working protocol but not yet a well-named public model.

## Goals

- Name the API around the semantic host-frame contract, not around damage.
- Keep the frame atomic: raster output, semantic snapshot, focused identity, and
  raster damage are delivered together for one committed frame.
- Treat `PresentationDamage` as a raster repaint hint only. It is not a
  semantic-tree diff, accessibility diff, or interaction-region diff.
- Define producer and consumer responsibilities explicitly enough that new hosts
  do not need to reverse-engineer WebHost or SwiftUIHost.
- Make the API broad enough for native hosts, browser hosts, remoting,
  diagnostics, snapshot tests, and future host-side renderers.
- Keep V1 simple: full semantic snapshot per committed frame, with optional
  raster damage.
- Move accessibility-announcement publication away from a hidden protocol-name
  side effect.
- Preserve the seven-phase pipeline boundary:

```text
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

## Non-Goals

- Do not introduce semantic deltas in V1. A future proposal can add semantic
  diffing once there are clear consumers and invalidation rules.
- Do not make terminal ANSI output consume semantic host frames by default.
  Terminal-native presentation can stay raster-only or raster-damage-aware.
- Do not move input delivery into the frame API. The frame carries semantic
  routes that input systems use, but event ingestion remains a separate host
  responsibility.
- Do not make every host declare a filtered semantic payload. V1 frames should
  be complete and consumers may ignore fields.
- Do not publish package-private runtime internals as part of this proposal.

## Terminology

### Semantic Host Frame

A semantic host frame is one committed runtime presentation record for hosts
that consume raster output together with semantic routes.

It contains:

- the full `RasterSurface` for the current committed frame
- the full `SemanticSnapshot` produced during the semantics phase
- the runtime-focused `Identity?`
- optional `PresentationDamage` describing changed raster ranges

### Producer

The producer is the runtime component that owns frame assembly and ordering.
Today this is `RunLoop` at the commit boundary. Producers must deliver frames in
commit order and must not split raster and semantic data into independent
callbacks for the same consumer.

### Consumer

A consumer is a presentation surface that receives semantic host frames. It may
draw pixels, serialize frames, maintain accessibility overlays, mount browser
ARIA, route native focus, record diagnostics, or expose inspection state.

### Bridge

A bridge is host-specific code behind a consumer. Examples include SwiftUIHost's
native accessibility overlay and the browser runtime that turns Web/WASI frame
records into canvas and ARIA state.

## Proposed API Shape

The formal API should be named around host frames:

```swift
public struct SemanticHostFrame: Equatable, Sendable {
  public var raster: RasterSurface
  public var semantics: SemanticSnapshot
  public var focusedIdentity: Identity?
  public var rasterDamage: PresentationDamage?
}

@_spi(Runners)
public protocol SemanticHostFramePresentationSurface: PresentationSurface {
  var semanticHostFrameCapabilities: SemanticHostFrameCapabilities { get }

  @discardableResult
  func present(_ frame: SemanticHostFrame) throws -> PresentationMetrics
}
```

The exact source-compatibility strategy can be decided during implementation.
Two acceptable paths:

- Rename `SemanticPresentationFrame` to `SemanticHostFrame` before the public
  release locks this surface.
- Keep `SemanticPresentationFrame` as the public type, add host-frame
  terminology in docs, and rename only the protocol to
  `SemanticHostFramePresentationSurface`.

The proposal prefers the first path because it makes the API self-describing.
If source compatibility is already more important than naming cleanup, the
second path still fixes the most dangerous part: the protocol should not keep
`DamageAware` in its formal name.

### Capability Declaration

Capabilities should describe the side effects a consumer wants the runtime to
perform, not which fields the frame contains. V1 frames remain complete.

```swift
public struct SemanticHostFrameCapabilities: OptionSet, Sendable {
  public static let rasterDamage
  public static let accessibilityTree
  public static let accessibilityAnnouncements
  public static let interactionRouting
  public static let focusRouting
}
```

For example, `HostedRasterSurface` and browser transports would likely declare
`.accessibilityAnnouncements` because the host bridge can surface live-region
announcements. A diagnostics-only consumer might receive frames without asking
the runtime to queue announcement-invalidating frames.

The current logic:

```swift
presentationSurface is any DamageAwareSemanticPresentationSurface
```

should become a capability check. That prevents protocol conformance from
silently changing accessibility behavior.

### Metrics Naming

The existing method returns `TerminalPresentationMetrics`. A broad host-frame
API should not permanently expose terminal vocabulary at the host boundary.
Implementation can keep the underlying type while introducing one of:

```swift
public typealias PresentationMetrics = TerminalPresentationMetrics
```

or a future neutral value such as `PresentationCommitMetrics`.

The proposal recommends adding a neutral name as part of the formalization even
if it is initially a typealias. That keeps this migration focused on names and
contracts instead of metrics redesign.

## Frame Contract

### Atomicity

A semantic host-frame consumer receives exactly one payload for one committed
frame. The runtime must not send raster first and semantics later for the same
frame. Hosts that need to schedule work on a platform main actor may do so after
receiving the frame, but the SwiftTUI runtime handoff is one value.

### Ordering

Frames are delivered in commit order. If a future async host drops stale frames,
it must drop whole frames. It must not combine raster from one committed frame
with semantics from another.

### Raster Damage

`rasterDamage == nil` means the producer has no usable incremental raster hint
for the consumer. The consumer should repaint the full raster surface or use
its own comparison.

`rasterDamage != nil` describes changed raster rows/ranges relative to the
previous committed raster frame for that same surface. It says nothing about
semantic changes.

### Semantic Snapshot

The frame carries the full semantic snapshot. Consumers may use any subset of:

- accessibility nodes, announcements, warnings, and live-region metadata
- focus regions and focus eligibility
- interaction regions for pointer and keyboard routing
- action routes
- selection routes
- scroll routes
- navigation routes
- diagnostics surfaced through semantic or frame-side metadata

The full-snapshot rule is intentional. It keeps host bridges deterministic while
the semantic model is still evolving.

### Focused Identity

`focusedIdentity` stays separate from `SemanticSnapshot` in V1. It is runtime
state chosen by the focus tracker, while the snapshot records semantic regions
that can participate in focus. Keeping it separate avoids mutating semantic
extraction output during commit.

## Implementation Plan

1. Add the neutral API names.
   Introduce `SemanticHostFramePresentationSurface` and either
   `SemanticHostFrame` or a documented alias for `SemanticPresentationFrame`.

2. Move existing consumers.
   Update `HostedRasterSurface`, `WebSocketSurfaceTransport`, and
   `WebSurfaceTransport` to conform to the new protocol. Keep the old
   `DamageAwareSemanticPresentationSurface` name only as a temporary SPI alias
   if needed by in-flight branches.

3. Add capabilities.
   Give semantic host-frame consumers a default capability set and replace the
   current announcement-publication conformance check with an explicit
   `.accessibilityAnnouncements` check.

4. Neutralize metrics naming.
   Add `PresentationMetrics` as the host-facing name for the existing metrics
   value, or introduce a small adapter if a direct typealias is too confusing.

5. Document producer and consumer rules.
   Update `TERMINOLOGY.md`, `HOST_RENDERING_PIPELINES.md`, and the DocC host
   integration page to describe semantic host frames as the non-terminal host
   contract.

6. Delete transitional names.
   Once all in-repo consumers and tests use the formal names, remove
   `DamageAwareSemanticPresentationSurface`.

## Test Plan

- Runtime dispatch test: a semantic host-frame surface receives the frame path
  before raster-damage and raster-only fallback surfaces.
- Atomic payload test: the received frame contains the raster surface, semantic
  snapshot, focused identity, and raster damage from the same committed frame.
- Announcement capability test: queued accessibility announcements publish for
  `.accessible` output and for consumers declaring `.accessibilityAnnouncements`,
  but not merely because a surface conforms to an unrelated protocol.
- WebHost/WASI serialization tests: serialized frame records still contain full
  semantic data and optional raster damage.
- SwiftUIHost test: retained native host state updates from one host frame and
  does not rely on separate semantic or damage callbacks.
- Public API baseline update: the final names are intentional and no
  `DamageAwareSemanticPresentationSurface` entry remains.

## Open Questions

- Should the final value type be `SemanticHostFrame` or should the existing
  `SemanticPresentationFrame` name be retained for compatibility?
- Should `semanticSnapshot` be renamed to `semantics` in the final public type?
- Should capabilities stay SPI until external host authors appear, or should
  they be public with the first formal host-frame API?
- Is `PresentationMetrics` sufficient as a typealias, or should metrics be
  split into terminal-specific and host-neutral components?
- Do host-frame consumers need an explicit frame sequence number in V1, or is
  call ordering enough until stale-frame dropping is introduced?

## Acceptance Criteria

- The formal semantic host-frame protocol is not named after damage.
- New host integrations can discover one documented producer-consumer contract
  instead of copying WebHost or SwiftUIHost internals.
- Accessibility announcement publication is governed by explicit capability,
  not incidental protocol conformance.
- `PresentationDamage` is documented and tested as a raster-only hint.
- In-repo consumers use the formal names, and transitional names are removed or
  clearly marked as temporary SPI compatibility.
