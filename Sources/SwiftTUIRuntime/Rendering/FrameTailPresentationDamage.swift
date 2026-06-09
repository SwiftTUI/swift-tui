import SwiftTUICore

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#endif

/// Computes a conservative private raster reuse hint for a frame tail.
///
/// The returned damage may be passed to the rasterizer so it can reuse clean
/// rows from the previous raster surface. This is not the host-facing damage
/// contract; committed artifacts derive that contract from the actual previous
/// and current raster surfaces after rasterization.
enum FrameTailPresentationDamageResolver {
  static func resolve(
    rootIdentity: Identity,
    placed: PlacedNode,
    retainedLayout: RetainedLayoutSession?,
    previousSurfaceTopology: SurfaceTopologySignature?
  ) -> FrameTailRasterReusePlan {
    let currentSurfaceTopology = SurfaceTopologySignature(placedRoot: placed)
    if currentSurfaceTopology.differs(from: previousSurfaceTopology) {
      // PROTOTYPE (opt-in via SWIFTTUI_OVERLAY_INCREMENTAL_DAMAGE): when the only
      // topology change is a presentation overlay stack appearing on top of an
      // otherwise-unchanged background, re-raster just the overlay's painted rows
      // (plus the directly-invalidated trigger) instead of forcing a full fresh
      // re-raster of the whole surface. Falls back to the conservative full-diff
      // for any other topology change.
      if overlayIncrementalDamageEnabled,
        let bounded = additiveOverlayBoundedDamage(
          rootIdentity: rootIdentity,
          placed: placed,
          retainedLayout: retainedLayout,
          previousSurfaceTopology: previousSurfaceTopology,
          currentSurfaceTopology: currentSurfaceTopology
        )
      {
        return .init(damage: bounded, barriers: [])
      }
      return .init(damage: nil, barriers: [.surfaceTopologyChanged])
    }

    guard let retainedLayout,
      let previousFrameIndex = retainedLayout.previousFrameIndex
    else {
      return .init(damage: nil, barriers: [.missingRetainedFrame])
    }

    let directlyInvalidated = retainedLayout.invalidationSummary.directlyInvalidated
    guard !directlyInvalidated.isEmpty else {
      return .init(damage: nil, barriers: [.emptyInvalidation])
    }
    guard !directlyInvalidated.contains(rootIdentity) else {
      return .init(damage: nil, barriers: [.rootInvalidated])
    }

    var currentPlacedByIdentity: [Identity: PlacedNode] = [:]
    indexPlacedNodes(placed, into: &currentPlacedByIdentity)

    var textRowRanges: [Int: [Range<Int>]] = [:]
    for identity in directlyInvalidated {
      guard previousFrameIndex.resolvedNode(for: identity) != nil else {
        return .init(damage: nil, barriers: [.unresolvedInvalidatedIdentity])
      }
      guard
        let previousPath = previousFrameIndex.placedPath(to: identity),
        let currentPath = placedPath(
          to: identity,
          in: currentPlacedByIdentity
        )
      else {
        return .init(damage: nil, barriers: [.unresolvedInvalidatedIdentity])
      }
      guard
        cleanSiblingBoundsAreStable(
          previousPath: previousPath,
          currentPath: currentPath
        )
      else {
        return .init(damage: nil, barriers: [.unstableCleanSiblingBounds])
      }

      if let previousBounds = previousPath.last?.bounds {
        textRows(for: previousBounds, into: &textRowRanges)
      }
      if let currentBounds = currentPath.last?.bounds {
        textRows(for: currentBounds, into: &textRowRanges)
      }
    }

    return .init(
      damage: PresentationDamage(
        textRows: textRowRanges.keys.sorted().map { row in
          .init(
            row: row,
            columnRanges: textRowRanges[row] ?? []
          )
        }
      ),
      barriers: []
    )
  }

  private static func placedPath(
    to identity: Identity,
    in index: [Identity: PlacedNode]
  ) -> [PlacedNode]? {
    var identities: [Identity] = []
    var currentIdentity: Identity? = identity

    while let current = currentIdentity {
      guard index[current] != nil else {
        return nil
      }
      identities.append(current)
      currentIdentity = current.parent
    }

    return identities.reversed().compactMap { index[$0] }
  }

  private static func cleanSiblingBoundsAreStable(
    previousPath: [PlacedNode],
    currentPath: [PlacedNode]
  ) -> Bool {
    guard previousPath.count == currentPath.count,
      previousPath.count > 1
    else {
      return previousPath.count == currentPath.count
    }

    for index in previousPath.indices.dropLast() {
      let previousAncestor = previousPath[index]
      let currentAncestor = currentPath[index]
      let dirtyChildIdentity = previousPath[index + 1].identity
      let previousChildren = previousAncestor.children
      let currentChildren = currentAncestor.children

      guard previousChildren.map(\.identity) == currentChildren.map(\.identity) else {
        return false
      }

      for (previousChild, currentChild) in zip(previousChildren, currentChildren)
      where previousChild.identity != dirtyChildIdentity {
        guard previousChild.bounds == currentChild.bounds else {
          return false
        }
      }
    }

    return true
  }

  private static func indexPlacedNodes(
    _ node: PlacedNode,
    into storage: inout [Identity: PlacedNode]
  ) {
    storage[node.identity] = node
    for child in node.children {
      indexPlacedNodes(child, into: &storage)
    }
  }

  private static func textRows(
    for bounds: CellRect,
    into textRowRanges: inout [Int: [Range<Int>]]
  ) {
    guard bounds.size.width > 0,
      bounds.size.height > 0
    else {
      return
    }

    let lowerBound = max(0, bounds.origin.y)
    let upperBound = max(lowerBound, bounds.origin.y + bounds.size.height)
    let leadingColumn = max(0, bounds.origin.x)
    let trailingColumn = max(leadingColumn, bounds.origin.x + bounds.size.width)
    guard leadingColumn < trailingColumn else {
      return
    }

    for row in lowerBound..<upperBound {
      textRowRanges[row, default: []].append(leadingColumn..<trailingColumn)
    }
  }

  // MARK: - Additive-overlay bounded damage (prototype, opt-in)

  /// Opt-in flag. Default `false` keeps the conservative full-surface re-raster
  /// on every topology change, so this prototype never affects the default
  /// build. Set `SWIFTTUI_OVERLAY_INCREMENTAL_DAMAGE=1` to enable. Validate with
  /// `SWIFTTUI_RASTER_VERIFY_INCREMENTAL=1`, which re-rasters fresh and asserts
  /// the incremental surface is byte-identical (catching any under-reported
  /// damage).
  private static let overlayIncrementalDamageEnabled: Bool =
    environmentFlagIsEnabled(environmentValue(named: "SWIFTTUI_OVERLAY_INCREMENTAL_DAMAGE"))

  /// Roles emitted *only* by the presentation overlay machinery
  /// (`OverlayStack` / `PresentationPortalRoot`). No background view produces
  /// these, so filtering them out isolates the background's contribution to the
  /// surface-topology signature.
  private static func isOverlayPresentationRole(
    _ role: SurfaceCompositionRole
  ) -> Bool {
    switch role {
    case .stackingContext, .detachedOverlayHost, .detachedOverlayEntry, .detachedOverlayRoot:
      true
    default:
      false
    }
  }

  /// Returns bounded raster-reuse damage when the surface-topology change is
  /// purely the appearance of a presentation overlay over an unchanged
  /// background. Returns `nil` (the caller then forces a full re-raster) for any
  /// other change, so this only ever *relaxes* the full-diff in the safe case.
  ///
  /// Soundness rests on the same model the stable-topology incremental path
  /// already trusts — `directlyInvalidated` is the complete set of changed
  /// background identities — plus two overlay-specific facts: (1) the new
  /// overlay only adds ink within the leaf bounds of its `.detachedOverlayHost`
  /// subtree (a full-surface translucent backdrop is itself a full-surface leaf,
  /// so it correctly expands damage to every row), and (2) inserting the overlay
  /// does not reflow the background (the base keeps an identical pass-through
  /// placement at origin `.zero`). The background's special-node topology being
  /// byte-identical is checked explicitly below.
  private static func additiveOverlayBoundedDamage(
    rootIdentity: Identity,
    placed: PlacedNode,
    retainedLayout: RetainedLayoutSession?,
    previousSurfaceTopology: SurfaceTopologySignature?,
    currentSurfaceTopology: SurfaceTopologySignature
  ) -> PresentationDamage? {
    guard let retainedLayout,
      let previousFrameIndex = retainedLayout.previousFrameIndex,
      let previousSurfaceTopology
    else {
      return nil
    }

    // 1) The background's topology contribution must be byte-identical: with the
    //    overlay-presentation roles stripped, both signatures must be equal.
    guard backgroundTopologyMatches(
      previous: previousSurfaceTopology,
      current: currentSurfaceTopology
    ) else {
      return nil
    }

    // 2) Rows the new overlay content actually paints (leaf bounds under the
    //    `.detachedOverlayHost` subtree).
    var dirtyRows: Set<Int> = []
    var foundOverlayHost = false
    collectOverlayPaintedRows(placed, into: &dirtyRows, foundOverlayHost: &foundOverlayHost)
    guard foundOverlayHost else {
      return nil
    }

    // 3) Union the directly-invalidated trigger (the control whose state toggled
    //    the presentation), previous + current bounds, so its own repaint is not
    //    dropped.
    let directlyInvalidated = retainedLayout.invalidationSummary.directlyInvalidated
    guard !directlyInvalidated.contains(rootIdentity) else {
      return nil
    }
    var currentPlacedByIdentity: [Identity: PlacedNode] = [:]
    indexPlacedNodes(placed, into: &currentPlacedByIdentity)
    for identity in directlyInvalidated {
      if let current = currentPlacedByIdentity[identity] {
        addRows(current.bounds, into: &dirtyRows)
      }
      if let previous = previousFrameIndex.placedNode(for: identity) {
        addRows(previous.bounds, into: &dirtyRows)
      }
    }

    guard !dirtyRows.isEmpty else {
      return nil
    }
    return PresentationDamage(dirtyRows: dirtyRows)
  }

  private static func backgroundTopologyMatches(
    previous: SurfaceTopologySignature,
    current: SurfaceTopologySignature
  ) -> Bool {
    let previousBackground = previous.entries.filter { !isOverlayPresentationRole($0.role) }
    let currentBackground = current.entries.filter { !isOverlayPresentationRole($0.role) }
    return previousBackground == currentBackground
  }

  private static func collectOverlayPaintedRows(
    _ node: PlacedNode,
    into rows: inout Set<Int>,
    foundOverlayHost: inout Bool
  ) {
    if node.surfaceComposition.role == .detachedOverlayHost {
      foundOverlayHost = true
      collectLeafRows(node, into: &rows)
      return
    }
    for child in node.children {
      collectOverlayPaintedRows(child, into: &rows, foundOverlayHost: &foundOverlayHost)
    }
  }

  private static func collectLeafRows(
    _ node: PlacedNode,
    into rows: inout Set<Int>
  ) {
    if node.children.isEmpty {
      addRows(node.bounds, into: &rows)
      return
    }
    for child in node.children {
      collectLeafRows(child, into: &rows)
    }
  }

  private static func addRows(
    _ bounds: CellRect,
    into rows: inout Set<Int>
  ) {
    guard bounds.size.width > 0, bounds.size.height > 0 else {
      return
    }
    let lowerRow = max(0, bounds.origin.y)
    let upperRow = max(lowerRow, bounds.maxY)
    guard lowerRow < upperRow else {
      return
    }
    for row in lowerRow..<upperRow {
      rows.insert(row)
    }
  }

  private static func environmentFlagIsEnabled(_ value: String?) -> Bool {
    guard let value else {
      return false
    }
    switch value.lowercased() {
    case "1", "true", "yes", "on":
      return true
    default:
      return false
    }
  }

  private static func environmentValue(named name: String) -> String? {
    unsafe name.withCString { cName in
      guard let rawValue = unsafe getenv(cName) else {
        return nil
      }
      return unsafe String(cString: rawValue)
    }
  }
}

struct FrameTailRasterReusePlan: Sendable {
  var damage: PresentationDamage?
  var barriers: Set<FrameTailRasterReuseBarrier>
}

enum FrameTailRasterReuseBarrier: Hashable, Sendable {
  case missingRetainedFrame
  case rootInvalidated
  case emptyInvalidation
  case unresolvedInvalidatedIdentity
  case unstableCleanSiblingBounds
  case surfaceTopologyChanged
}
