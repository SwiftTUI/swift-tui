/// A per-presented-frame claim that exactly one scroll route's viewport
/// content moved vertically by a whole-cell delta between the previously
/// presented frame and this one, with everything else unchanged.
///
/// The candidate is a *hypothesis*, not a verified fact: its producer (the run
/// loop's presented-frame scroll ledger) compares only registry offsets and
/// viewport geometry, never surface cells. Any consumer that wants to act on
/// it — scroll-region emission, raster band blits — must first verify the
/// translation against the actual surfaces, cell-for-cell, and must discard
/// the candidate whenever the presentation baseline is stale
/// (`requestedDamageTrustsBaseline == false`): after a writer drop the run
/// loop's presented baseline is one frame ahead of the rolled-back written
/// baseline, so the claim is unsound for exactly that recovery frame.
package struct ScrollTranslationCandidate: Equatable, Sendable {
  /// The scroll route's viewport rect in surface coordinates, clamped to the
  /// surface — the rows and columns the translation claim covers.
  ///
  /// For hosted collections (list, table) this is the drawn-content rect
  /// (chrome and overflow-indicator lines excluded). For a plain `ScrollView`
  /// it is the content viewport, excluding content insets and reserved
  /// indicator tracks. Overlaid indicators can still lie inside that viewport.
  /// Consumers verify both translated content and any flanking cells moved by
  /// a whole-row copy before serving the candidate.
  package var band: CellRect
  /// Screen-space rows the band's content moved: negative when the user
  /// scrolled down (offset increased, content slid up), positive when the
  /// user scrolled up. Computed as `previousOffset.y - currentOffset.y`.
  package var dy: Int
  /// The run-loop frame ordinal of the presented frame the claim is relative
  /// to — the same ordinal `frames.tsv` reports — so a consumer can check
  /// that the claim's baseline is the frame it thinks it is diffing against.
  package var baselineFrameOrdinal: Int

  package init(
    band: CellRect,
    dy: Int,
    baselineFrameOrdinal: Int
  ) {
    self.band = band
    self.dy = dy
    self.baselineFrameOrdinal = baselineFrameOrdinal
  }
}

/// The tail-time sibling of ``ScrollTranslationCandidate`` (scroll-latency
/// R3.2a): the same "exactly one scroll route translated vertically" claim,
/// but derived from *committed placed products* instead of live registry
/// offsets read at present time.
///
/// Provenance is the point. The present-time candidate reads the scroll
/// registry after the frame tail finished, so async-mode input dispatched
/// mid-tail can stamp offsets ahead of the pixels the frame actually shows.
/// This value is computed inside the frame tail by diffing the previous
/// committed frame's ``CommittedScrollRouteTable`` against the current one —
/// both ends of the diff are products of the same pipeline run that produced
/// the surfaces being compared, so the async-skew class cannot occur. It
/// remains a *hypothesis* about cell content (a route can translate while a
/// row inside it also changes — selection moves, hover styles); any consumer
/// must still verify against surfaces or draw trees before acting.
package struct CommittedScrollTranslation: Equatable, Sendable {
  /// The moved route, so consumers (and the nested-secondary relaxation) can
  /// name which route the claim is about.
  package var routeIdentity: Identity
  /// The route's committed viewport rect intersected with the surface —
  /// same clamping as ``ScrollTranslationCandidate/band``.
  package var band: CellRect
  /// Screen-space rows the band's content moved; same sign convention as
  /// ``ScrollTranslationCandidate/dy``.
  package var dy: Int

  package init(
    routeIdentity: Identity,
    band: CellRect,
    dy: Int
  ) {
    self.routeIdentity = routeIdentity
    self.band = band
    self.dy = dy
  }

  /// The claim clamped to a concrete surface, or `nil` when the clamped band
  /// cannot support a translation (empty intersection, or a shift at least as
  /// tall as the visible band — no baseline row survives inside it).
  package func clamped(toSurface surfaceSize: CellSize) -> Self? {
    let surfaceBounds = CellRect(origin: .zero, size: surfaceSize)
    guard let clampedBand = band.intersection(surfaceBounds),
      dy != 0,
      abs(dy) < clampedBand.size.height
    else {
      return nil
    }
    return Self(routeIdentity: routeIdentity, band: clampedBand, dy: dy)
  }
}

/// A stable key for one piece of scroll-route content whose committed
/// position can be compared across frames.
///
/// Scroll containers commit their content position in two shapes: a plain
/// `ScrollView` places its content child at `viewportOrigin − clampedOffset`
/// (the child's committed origin encodes the offset exactly), while hosted
/// collections commit a visible-layout line model whose lines carry dataset
/// indices and content-relative offsets. Both shapes reduce to "a keyed
/// content element at an absolute position", which is what this key names.
package enum CommittedScrollContentAnchorKey: Hashable, Sendable {
  /// A direct placed child of the route node, keyed by identity.
  case placedChild(Identity)
  /// A hosted-list display line, keyed by its dataset coordinates.
  case listLine(kind: UInt8, isHeader: Bool, section: Int?, row: Int?, item: Int?)
  /// A hosted-table display line, keyed by role and dataset row.
  case tableLine(role: UInt8, row: Int?)
}

/// Committed scroll-route state for one frame: every scroll route's viewport
/// rect plus the absolute committed positions of its keyed content anchors —
/// the products a tail-time translation diff compares (scroll-latency R3.2a).
package struct CommittedScrollRouteTable: Equatable, Sendable {
  package struct RouteState: Equatable, Sendable {
    package var viewportRect: CellRect
    /// Absolute committed position per stable content anchor. Keys that
    /// appeared more than once in the frame are removed at construction —
    /// an ambiguous anchor must not pair across frames.
    package var contentAnchors: [CommittedScrollContentAnchorKey: CellPoint]

    package init(
      viewportRect: CellRect,
      contentAnchors: [CommittedScrollContentAnchorKey: CellPoint]
    ) {
      self.viewportRect = viewportRect
      self.contentAnchors = contentAnchors
    }
  }

  package var routes: [Identity: RouteState]
  /// A route identity appeared on more than one placed node. The table is
  /// then unusable for cross-frame pairing (last-writer-wins storage may mix
  /// siblings), and candidate derivation declines.
  package var hasDuplicateRouteIdentities: Bool

  package init(
    routes: [Identity: RouteState],
    hasDuplicateRouteIdentities: Bool = false
  ) {
    self.routes = routes
    self.hasDuplicateRouteIdentities = hasDuplicateRouteIdentities
  }

  /// Extracts the committed scroll-route table from a placed tree.
  ///
  /// Explicit stack, not recursion: placed trees are as deep as the authored
  /// view hierarchy and the frame tail runs on 512 KiB worker stacks.
  package init(placedRoot: PlacedNode) {
    var routes: [Identity: RouteState] = [:]
    var hasDuplicates = false
    var stack: [PlacedNode] = [placedRoot]
    while let node = stack.popLast() {
      if node.semanticMetadata.scrollRole != nil {
        let state = RouteState(
          viewportRect: node.scrollViewportRect ?? node.bounds,
          contentAnchors: Self.contentAnchors(for: node)
        )
        if routes.updateValue(state, forKey: node.identity) != nil {
          hasDuplicates = true
        }
      }
      stack.append(contentsOf: node.children)
    }
    self.init(routes: routes, hasDuplicateRouteIdentities: hasDuplicates)
  }

  /// The committed-translation candidate for advancing from `previous` to
  /// `current`, before surface clamping.
  ///
  /// Mirrors ``ScrollTranslationFrameLedger``'s production rules on committed
  /// products, relaxed for carried nested routes (R3.2d); any other
  /// difference declines conservatively:
  /// - the route sets are identical and free of duplicate identities,
  /// - exactly one route is a *primary mover*: viewport rect unchanged, at
  ///   least one shared content anchor, every shared anchor moved by the
  ///   same purely-vertical, non-zero delta smaller than the viewport height,
  /// - every other changed route is *carried* by the primary's shift: its
  ///   viewport rect translated by exactly `dy` and its anchors translated
  ///   by exactly `dy` too — a nested scrollable riding inside the moving
  ///   band with its own offset unchanged. The R3.2b draw-walk (or R2.3's
  ///   cell verification) remains the soundness backstop for its content.
  ///
  /// A momentum `@State`-echo frame (anchors unmoved) yields equal states and
  /// therefore no candidate. A route whose cell *content* changed at fixed
  /// positions (selection move, hover) also yields equal states — the
  /// candidate is a translation hypothesis, and its verifier owns that case.
  package static func candidate(
    advancing previous: CommittedScrollRouteTable?,
    to current: CommittedScrollRouteTable
  ) -> CommittedScrollTranslation? {
    guard let previous,
      !previous.hasDuplicateRouteIdentities,
      !current.hasDuplicateRouteIdentities,
      previous.routes.count == current.routes.count
    else {
      return nil
    }

    var changed: [(identity: Identity, previous: RouteState, current: RouteState)] = []
    for (identity, currentState) in current.routes {
      guard let previousState = previous.routes[identity] else {
        // Same count with a missing key: the route set changed structurally.
        return nil
      }
      guard previousState != currentState else {
        continue
      }
      changed.append((identity, previousState, currentState))
    }
    guard !changed.isEmpty else {
      return nil
    }

    var primary: (identity: Identity, band: CellRect, dy: Int)?
    var secondaries: [(previous: RouteState, current: RouteState)] = []
    for (identity, previousState, currentState) in changed {
      if previousState.viewportRect == currentState.viewportRect,
        let delta = Self.uniformAnchorDelta(from: previousState, to: currentState),
        delta.x == 0,
        delta.y != 0,
        abs(delta.y) < currentState.viewportRect.size.height
      {
        guard primary == nil else {
          // Two independent movers in one frame — no single-band translation.
          return nil
        }
        primary = (identity, currentState.viewportRect, delta.y)
      } else {
        secondaries.append((previousState, currentState))
      }
    }
    guard let primary else {
      return nil
    }
    for secondary in secondaries {
      guard
        secondary.current.viewportRect
          == secondary.previous.viewportRect.offsetBy(dy: primary.dy),
        let delta = Self.uniformAnchorDelta(from: secondary.previous, to: secondary.current),
        delta.x == 0,
        delta.y == primary.dy
      else {
        return nil
      }
    }

    return CommittedScrollTranslation(
      routeIdentity: primary.identity,
      band: primary.band,
      dy: primary.dy
    )
  }

  /// The single delta every shared content anchor moved by, or `nil` when no
  /// anchor is shared or the anchors disagree (not a rigid translation).
  private static func uniformAnchorDelta(
    from previous: RouteState,
    to current: RouteState
  ) -> CellPoint? {
    var delta: CellPoint?
    for (key, currentPoint) in current.contentAnchors {
      guard let previousPoint = previous.contentAnchors[key] else {
        continue
      }
      let anchorDelta = CellPoint(
        x: currentPoint.x - previousPoint.x,
        y: currentPoint.y - previousPoint.y
      )
      if let delta {
        guard delta == anchorDelta else {
          return nil
        }
      } else {
        delta = anchorDelta
      }
    }
    return delta
  }

  /// The keyed content anchors of one scroll-route node.
  ///
  /// Hosted collections anchor on their committed visible-layout lines —
  /// only lines that move with the content (dataset rows, headers,
  /// separators), never viewport-pinned chrome such as table borders or
  /// overflow indicators, which would report a zero delta and veto every
  /// scroll as non-rigid. Plain scroll containers anchor on their direct
  /// placed children's origins (the content child is placed at
  /// `viewportOrigin − clampedOffset`, so its origin commits the offset).
  private static func contentAnchors(
    for node: PlacedNode
  ) -> [CommittedScrollContentAnchorKey: CellPoint] {
    var anchors: [CommittedScrollContentAnchorKey: CellPoint] = [:]
    var collided: Set<CommittedScrollContentAnchorKey> = []
    func record(_ key: CommittedScrollContentAnchorKey, at point: CellPoint) {
      if anchors.updateValue(point, forKey: key) != nil {
        collided.insert(key)
      }
    }

    if let layout = node.hostedListVisibleLayout {
      for line in layout.lines {
        guard line.rowIndex != nil || line.sectionIndex != nil || line.itemIndex != nil else {
          continue
        }
        let kind: UInt8 =
          switch line.kind {
          case .text: 0
          case .row: 1
          case .separator: 2
          }
        record(
          .listLine(
            kind: kind,
            isHeader: line.isHeader,
            section: line.sectionIndex,
            row: line.rowIndex,
            item: line.itemIndex
          ),
          at: CellPoint(
            x: layout.contentBounds.origin.x,
            y: layout.contentBounds.origin.y + line.yOffset
          )
        )
      }
    } else if let layout = node.hostedTableVisibleLayout {
      for line in layout.lines {
        guard let rowIndex = line.rowIndex else {
          continue
        }
        let role: UInt8 =
          switch line.role {
          case .row: 1
          case .rowSeparator: 2
          default: 0
          }
        // Only body rows move with the content; borders, the header pair,
        // and overflow indicators are viewport-pinned.
        guard role != 0 else {
          continue
        }
        record(
          .tableLine(role: role, row: rowIndex),
          at: CellPoint(
            x: layout.contentBounds.origin.x,
            y: layout.contentBounds.origin.y + line.yOffset
          )
        )
      }
    } else {
      for child in node.children {
        record(.placedChild(child.identity), at: child.bounds.origin)
      }
    }

    for key in collided {
      anchors.removeValue(forKey: key)
    }
    return anchors
  }
}
