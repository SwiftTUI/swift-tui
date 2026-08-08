import SwiftTUICore

/// One presented frame's scroll state: every live route's offset and viewport
/// rect, plus the surface size — exactly what the translation diff compares.
///
/// The ledger lives run-loop-side, keyed to *presented* frames, because the
/// registry records no deltas (`scrollBy` reads, clamps, and applies) and the
/// pipeline's own damage baselines answer a different question (raster reuse,
/// written-surface diffs). Retained only while the frame's snapshot has scroll
/// routes; a route-free frame clears it.
package struct ScrollTranslationFrameLedger: Equatable {
  package struct RouteState: Equatable {
    package var offset: CellPoint
    package var viewportRect: CellRect

    package init(
      offset: CellPoint,
      viewportRect: CellRect
    ) {
      self.offset = offset
      self.viewportRect = viewportRect
    }
  }

  /// The run-loop frame ordinal this ledger was captured for (the same
  /// ordinal `frames.tsv` reports).
  package var frameOrdinal: Int
  package var surfaceSize: CellSize
  package var routes: [Identity: RouteState]

  package init(
    frameOrdinal: Int,
    surfaceSize: CellSize,
    routes: [Identity: RouteState]
  ) {
    self.frameOrdinal = frameOrdinal
    self.surfaceSize = surfaceSize
    self.routes = routes
  }

  /// The scroll-translation candidate for advancing from `previous` to
  /// `current`, or `nil` when the frame pair does not describe a pure
  /// single-route vertical translation.
  ///
  /// Produces a candidate only when ALL of these hold; any other difference
  /// between the ledgers — a route appearing or departing, two routes moving,
  /// viewport geometry shifting, a surface resize, a horizontal component —
  /// declines conservatively:
  /// - the surface size is unchanged,
  /// - the route sets are identical,
  /// - exactly one route's state changed, and only in its `offset.y`
  ///   (viewport rect identical, `offset.x` identical),
  /// - the shift is smaller than the band: `0 < |dy| < band height` (a
  ///   band-sized jump shares no rows with the baseline, so there is nothing
  ///   to translate),
  /// - the band, clamped to the surface, is non-empty.
  ///
  /// A momentum `@State`-echo frame (offsets unchanged) produces `nil`
  /// through the exactly-one-change rule.
  package static func candidate(
    advancing previous: Self?,
    to current: Self
  ) -> ScrollTranslationCandidate? {
    guard let previous,
      previous.surfaceSize == current.surfaceSize,
      previous.routes.count == current.routes.count
    else {
      return nil
    }

    var changed: (previous: RouteState, current: RouteState)?
    for (identity, currentState) in current.routes {
      guard let previousState = previous.routes[identity] else {
        // Same count with a missing key: the route set changed structurally.
        return nil
      }
      guard previousState != currentState else {
        continue
      }
      guard changed == nil else {
        // Two routes moved in one frame — no single-band translation.
        return nil
      }
      changed = (previousState, currentState)
    }

    guard let changed else {
      // Nothing moved (a momentum @State-echo frame): no candidate.
      return nil
    }
    guard changed.previous.viewportRect == changed.current.viewportRect,
      changed.previous.offset.x == changed.current.offset.x
    else {
      return nil
    }

    let dy = changed.previous.offset.y - changed.current.offset.y
    let surfaceBounds = CellRect(origin: .zero, size: current.surfaceSize)
    guard dy != 0,
      let band = changed.current.viewportRect.intersection(surfaceBounds),
      abs(dy) < band.size.height
    else {
      return nil
    }

    return ScrollTranslationCandidate(
      band: band,
      dy: dy,
      baselineFrameOrdinal: previous.frameOrdinal
    )
  }
}

extension RunLoop {
  /// Produces this frame's scroll-translation candidate (R2.2) plus the
  /// ledger to retain once the frame is presented.
  ///
  /// Offsets come from the live scroll-position registry over the frame's
  /// semantic scroll routes — the same currency the `SemanticHostFrame`
  /// enrichment publishes to non-terminal hosts — read on the main actor at
  /// present time. Cost is proportional to the frame's route count (almost
  /// always 0 or 1), so a route-free frame pays one `isEmpty` check.
  ///
  /// Production only: nothing acts on the candidate in this slice. It is
  /// recorded in `frames.tsv` (`translation_candidate`) and carried through
  /// the present call chain for the scroll-region planner and translation
  /// blit to consume, gated there by the presentation trust latch
  /// (`TerminalPresentationSession.presentationTranslationCandidate`).
  func scrollTranslation(
    for artifacts: FrameArtifacts,
    frameOrdinal: Int
  ) -> (candidate: ScrollTranslationCandidate?, ledger: ScrollTranslationFrameLedger?) {
    let scrollRoutes = artifacts.semanticSnapshot.scrollRoutes
    guard !scrollRoutes.isEmpty else {
      return (nil, nil)
    }

    let enrichedRoutes = localScrollPositionRegistry.routesWithCurrentOffsets(scrollRoutes)
    var routes: [Identity: ScrollTranslationFrameLedger.RouteState] = [:]
    routes.reserveCapacity(enrichedRoutes.count)
    for route in enrichedRoutes {
      routes[route.identity] = .init(
        offset: route.contentOffset,
        viewportRect: route.viewportRect
      )
    }
    let ledger = ScrollTranslationFrameLedger(
      frameOrdinal: frameOrdinal,
      surfaceSize: artifacts.rasterSurface.size,
      routes: routes
    )
    let candidate = ScrollTranslationFrameLedger.candidate(
      advancing: previousPresentedScrollLedger,
      to: ledger
    )
    return (candidate, ledger)
  }
}
