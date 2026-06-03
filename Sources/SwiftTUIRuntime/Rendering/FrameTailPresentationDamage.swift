import SwiftTUICore

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
