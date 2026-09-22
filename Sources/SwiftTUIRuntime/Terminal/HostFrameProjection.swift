import SwiftTUICore

/// The host-neutral **serialization seam** for a ``SemanticHostFrame``.
///
/// Non-terminal hosts (WASI/WebHost, Android) serialize a committed frame
/// into the converged web-surface wire (`WebSurfaceFrameEncoder`; the legacy
/// Android keyed-JSON format retired with convergence Stage C4). The wire
/// serializes a defined **subset** of a frame: the raster, the sequence, the
/// focus, the damage, and exactly three of `SemanticSnapshot`'s ten fields —
/// accessibility nodes, announcements, and scroll routes. The remaining
/// semantic records (interaction/focus/navigation/selection regions, scroll
/// targets, named coordinate spaces, accessibility warnings) are
/// routing/diagnostic data that hosts do not serialize.
///
/// Historically each host's encoder reached into `SemanticHostFrame`/
/// `SemanticSnapshot` independently, so a field added to the host contract
/// had to be wired into two encoders by hand — and a forgotten one silently
/// dropped data on one host with no compile error. `HostFrameProjection` is
/// the single seam both encoders read a frame through.
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

  /// The frame's semantic snapshot. Carried whole so the shared
  /// ``HostWireFrameModel`` can derive the host-serialized surface
  /// (accessibility nodes, announcements, scroll routes, focus presentation)
  /// from it once per frame.
  package var semantics: SemanticSnapshot

  /// The focused identity, for per-node `isFocused` attribution.
  package var focusedIdentity: Identity?

  /// Per-frame raster damage relative to the previous committed frame.
  package var rasterDamage: PresentationDamage?

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
