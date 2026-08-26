@_spi(Testing) package import SwiftTUICore

/// One co-present matched pair: an `isSource: false` instance and the single
/// source instance that shares its key in the same placed tree.
///
/// SwiftUI positions a non-source instance onto its source while both are on
/// screen. SwiftTUI applies that as a placed-level, per-frame override — the
/// non-source is laid out at its own slot and *rendered* at the adopted rect
/// (plan 2026-08-25-003 Stage A). Adoption is a position, not a curve: it
/// takes no clock, plans no animation, and leaves the retained layout
/// baseline untouched.
package struct MatchedGeometryAdoptionPair: Sendable, Equatable {
  package var nonSource: Identity
  package var nonSourceBounds: CellRect
  /// The non-source's own `properties` and `anchor`, as SwiftUI reads the
  /// non-source's configuration.
  package var properties: MatchedGeometryProperties
  package var anchor: UnitPoint
  package var source: Identity
  package var sourceBounds: CellRect

  package init(
    nonSource: Identity,
    nonSourceBounds: CellRect,
    properties: MatchedGeometryProperties,
    anchor: UnitPoint,
    source: Identity,
    sourceBounds: CellRect
  ) {
    self.nonSource = nonSource
    self.nonSourceBounds = nonSourceBounds
    self.properties = properties
    self.anchor = anchor
    self.source = source
    self.sourceBounds = sourceBounds
  }
}

/// A matched-geometry node collected from one placed-tree walk.
package struct MatchedGeometryPlacedEntry: Sendable, Equatable {
  package var identity: Identity
  package var bounds: CellRect
  package var config: MatchedGeometryConfig

  package init(identity: Identity, bounds: CellRect, config: MatchedGeometryConfig) {
    self.identity = identity
    self.bounds = bounds
    self.config = config
  }
}

package enum MatchedGeometryAdoption {
  /// Pairs every non-source with its key's source, from one pre-order walk
  /// of `tree`. Transient nodes (exit overlays) are frozen clones, never
  /// sources or adoptees. A key with zero or several sources adopts nothing.
  package static func pairs(in tree: PlacedNode) -> [MatchedGeometryAdoptionPair] {
    var entries: [MatchedGeometryPlacedEntry] = []
    AnimationTreeQueries.collectMatchedGeometryEntries(tree, into: &entries)
    return pairs(from: entries)
  }

  /// Pairs from an already-collected walk (the controller's capture reuses
  /// its own walk). Order follows the non-sources' pre-order position.
  package static func pairs(
    from entries: [MatchedGeometryPlacedEntry]
  ) -> [MatchedGeometryAdoptionPair] {
    var sourceCounts: [MatchedGeometryKey: Int] = [:]
    var sourceByKey: [MatchedGeometryKey: MatchedGeometryPlacedEntry] = [:]
    var hasNonSource = false
    for entry in entries {
      if entry.config.isSource {
        sourceCounts[entry.config.key, default: 0] += 1
        sourceByKey[entry.config.key] = entry
      } else {
        hasNonSource = true
      }
    }
    guard hasNonSource else { return [] }
    var pairs: [MatchedGeometryAdoptionPair] = []
    for entry in entries where !entry.config.isSource {
      guard sourceCounts[entry.config.key] == 1,
        let source = sourceByKey[entry.config.key]
      else { continue }
      pairs.append(
        .init(
          nonSource: entry.identity,
          nonSourceBounds: entry.bounds,
          properties: entry.config.properties,
          anchor: entry.config.anchor,
          source: source.identity,
          sourceBounds: source.bounds
        ))
    }
    return pairs
  }

  /// The placed deltas that move (and resize) each non-source onto its
  /// source. `sourceRectOverrides` names the rect a source is *drawn* at
  /// this frame when a live offset moves it (its own matched or insertion
  /// animation), so an adoptee follows a source mid-flight; the time-free
  /// capture passes none and reads the baseline.
  package static func offsets(
    for pairs: [MatchedGeometryAdoptionPair],
    sourceRectOverrides: [Identity: CellRect] = [:]
  ) -> [PlacedAnimationOverlayOffset] {
    pairs.map { pair in
      let target = sourceRectOverrides[pair.source] ?? pair.sourceBounds
      let rect = adoptedRect(
        nonSource: pair.nonSourceBounds,
        source: target,
        properties: pair.properties,
        anchor: pair.anchor
      )
      return .init(
        identity: pair.nonSource,
        dx: rect.origin.x - pair.nonSourceBounds.origin.x,
        dy: rect.origin.y - pair.nonSourceBounds.origin.y,
        size: pair.properties.contains(.size) ? rect.size : nil
      )
    }
  }

  /// The rect a non-source renders at: the non-source as if it had just
  /// received its key from `source` (progress 0 of a source→non-source
  /// match under the non-source's `properties`/`anchor`), so `.position`
  /// tracks the source's anchor point at the non-source's size, `.size`
  /// takes the source's size around the non-source's own anchor, and
  /// `.frame` is the source's rect.
  package static func adoptedRect(
    nonSource: CellRect,
    source: CellRect,
    properties: MatchedGeometryProperties,
    anchor: UnitPoint
  ) -> CellRect {
    PlacedAnimationOverlaySampling.interpolatedMatchedRect(
      from: source,
      to: nonSource,
      properties: properties,
      anchor: anchor,
      progress: 0
    )
  }
}
