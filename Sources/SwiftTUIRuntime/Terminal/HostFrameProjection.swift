import SwiftTUICore

/// The host-neutral **serialization seam** for a ``SemanticHostFrame``.
///
/// Non-terminal hosts (WASI/WebHost, Android) each serialize a committed frame
/// into their own wire format — `WebSurfaceFrameEncoder` emits hand-rolled,
/// delta-encoded JSON; `AndroidHostFrameEncoder` emits `Codable` snapshots. The
/// two wire formats are unrelated, but they serialize the **same subset** of a
/// frame: the raster, the sequence, the focus, the damage, and exactly three of
/// `SemanticSnapshot`'s ten fields — accessibility nodes, announcements, and
/// scroll routes. The remaining semantic records (interaction/focus/navigation/
/// selection regions, scroll targets, named coordinate spaces, accessibility
/// warnings) are routing/diagnostic data that hosts do not serialize.
///
/// Historically each encoder reached into `SemanticHostFrame`/`SemanticSnapshot`
/// independently, so a field added to the host contract had to be wired into two
/// ~570-line encoders by hand — and a forgotten one silently dropped data on one
/// host with no compile error. `HostFrameProjection` is the single seam both
/// encoders read a frame through, and it names the host-serialized surface
/// explicitly:
/// - the host-serialized semantic lists are surfaced as the named accessors
///   ``accessibilityNodes`` / ``accessibilityAnnouncements`` / ``scrollRoutes``
///   (the enumerable "what a host emits" contract, anchored by
///   `HostFrameProjectionContractTests`);
/// - the focus presentation is **derived once here** so hosts that surface it
///   (Android) and hosts that surface only the focused identity (WASI) share one
///   derivation.
///
/// The projection carries values untransformed — each encoder keeps its own
/// serialization, so its exact wire bytes are unchanged. The shared
/// ``HostWireFrameModel`` builds on this seam: it derives every emitted
/// value once per frame, and the encoders are format adapters over it. It retains the full
/// ``semantics`` snapshot (not a copy of the subset) so snapshot-threaded
/// encoders pass it through identically.
///
/// `package`-scoped: an internal intermediate used inside the encoders, never
/// part of any host's public API.
package struct HostFrameProjection: Equatable, Sendable {
  /// Monotonic producer sequence; hosts use it to detect stale async work.
  package var sequence: UInt64

  /// The committed raster surface (size, cells, image attachments).
  package var raster: RasterSurface

  /// The measured pre-minimum window content size, for hosts negotiating with an
  /// outer layout system. `nil` when unavailable.
  package var preferredLayoutSize: CellSize?

  /// The frame's semantic snapshot. Carried whole so snapshot-threaded encoders
  /// (WASI) pass it through byte-identically; hosts should read the
  /// host-serialized fields via the named accessors below, not reach past them.
  package var semantics: SemanticSnapshot

  /// The focused identity, for per-node `isFocused` attribution.
  package var focusedIdentity: Identity?

  /// Per-frame raster damage relative to the previous committed frame.
  package var rasterDamage: PresentationDamage?

  /// Accessibility tree nodes — the host-serialized semantic surface (1 of 3)…
  package var accessibilityNodes: [AccessibilityNode] {
    semantics.accessibilityNodes
  }

  /// …live-region announcements (2 of 3)…
  package var accessibilityAnnouncements: [AccessibilityAnnouncement] {
    semantics.accessibilityAnnouncements
  }

  /// …and scroll regions (3 of 3).
  package var scrollRoutes: [ScrollRoute] {
    semantics.scrollRoutes
  }

  /// The derived focus presentation (focused identity + semantics + text-input
  /// preference), computed once so every host shares one derivation.
  package var focusPresentation: FocusPresentation {
    semantics.focusPresentation(for: focusedIdentity)
  }

  /// Projects `frame` for host serialization. The single seam through which both
  /// host encoders read frame/semantic data.
  package init(_ frame: SemanticHostFrame) {
    sequence = frame.sequence
    raster = frame.raster
    preferredLayoutSize = frame.preferredLayoutSize
    semantics = frame.semantics
    focusedIdentity = frame.focusedIdentity
    rasterDamage = frame.rasterDamage
  }
}

extension SemanticHostFrame {
  /// The host serialization projection of this frame. See ``HostFrameProjection``.
  package var hostProjection: HostFrameProjection {
    HostFrameProjection(self)
  }
}
