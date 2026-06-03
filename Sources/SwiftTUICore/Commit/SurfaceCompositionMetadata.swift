/// Describes how a node participates in final surface composition.
///
/// This is not a terminal concept. It is shared metadata used by the render
/// pipeline to decide whether retained-layout raster reuse is compatible with
/// the previous committed frame.
package struct SurfaceCompositionMetadata: Equatable, Sendable {
  private var bits: UInt8
  private var stableKeyStorage: SurfaceTopologyKeyStorage?

  package var role: SurfaceCompositionRole {
    get {
      SurfaceCompositionRole(rawTopologyValue: bits & 0x0f) ?? .normal
    }
    set {
      bits = (bits & 0xf0) | newValue.rawTopologyValue
    }
  }

  package var stableKey: String? {
    get {
      stableKeyStorage?.value
    }
    set {
      stableKeyStorage = newValue.map(SurfaceTopologyKeyStorage.init(_:))
    }
  }

  package var surfaceTopologyKey: SurfaceTopologyKey? {
    guard let value = stableKeyStorage?.value else {
      return nil
    }
    return SurfaceTopologyKey(value)
  }

  package var invalidationScope: SurfaceInvalidationScope {
    get {
      SurfaceInvalidationScope(rawTopologyValue: (bits >> 4) & 0x0f) ?? .localBounds
    }
    set {
      bits = (bits & 0x0f) | (newValue.rawTopologyValue << 4)
    }
  }

  package init(
    role: SurfaceCompositionRole = .normal,
    stableKey: String? = nil,
    invalidationScope: SurfaceInvalidationScope = .localBounds
  ) {
    bits = 0
    stableKeyStorage = nil
    self.role = role
    self.invalidationScope = invalidationScope
    self.stableKey = stableKey
  }

  package static let normal = Self()

  package var participatesInTopologySignature: Bool {
    role != .normal || surfaceTopologyKey != nil || invalidationScope != .localBounds
  }
}

private final class SurfaceTopologyKeyStorage: Equatable, Sendable {
  let value: String

  init(_ value: String) {
    self.value = value
  }

  static func == (lhs: SurfaceTopologyKeyStorage, rhs: SurfaceTopologyKeyStorage) -> Bool {
    lhs === rhs || lhs.value == rhs.value
  }
}

package struct SurfaceTopologyKey: Equatable, Sendable, Comparable, CustomStringConvertible {
  private var storedValue: String

  package init(_ stableKey: String) {
    storedValue = stableKey
  }

  package var value: String {
    storedValue
  }

  package var description: String {
    value
  }

  package static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.value < rhs.value
  }
}

package enum SurfaceCompositionRole: Equatable, Sendable {
  case normal
  case stackingContext
  case detachedOverlayRoot
  case detachedOverlayHost
  case detachedOverlayEntry
  case isolatedCompositingGroup
  case transientRemovalOverlay
  case viewportBarrier

  fileprivate var rawTopologyValue: UInt8 {
    switch self {
    case .normal: 0
    case .stackingContext: 1
    case .detachedOverlayRoot: 2
    case .detachedOverlayHost: 3
    case .detachedOverlayEntry: 4
    case .isolatedCompositingGroup: 5
    case .transientRemovalOverlay: 6
    case .viewportBarrier: 7
    }
  }

  fileprivate init?(rawTopologyValue: UInt8) {
    switch rawTopologyValue {
    case 0: self = .normal
    case 1: self = .stackingContext
    case 2: self = .detachedOverlayRoot
    case 3: self = .detachedOverlayHost
    case 4: self = .detachedOverlayEntry
    case 5: self = .isolatedCompositingGroup
    case 6: self = .transientRemovalOverlay
    case 7: self = .viewportBarrier
    default: return nil
    }
  }
}

package typealias StructuralEdgeRole = SurfaceCompositionRole

package enum SurfaceInvalidationScope: Equatable, Sendable {
  case localBounds
  case compositedBounds
  case fullSurfaceDiff

  fileprivate var rawTopologyValue: UInt8 {
    switch self {
    case .localBounds: 0
    case .compositedBounds: 1
    case .fullSurfaceDiff: 2
    }
  }

  fileprivate init?(rawTopologyValue: UInt8) {
    switch rawTopologyValue {
    case 0: self = .localBounds
    case 1: self = .compositedBounds
    case 2: self = .fullSurfaceDiff
    default: return nil
    }
  }
}

package struct SurfaceTopologySignature: Equatable, Sendable {
  package var entries: [SurfaceTopologyEntry]

  package init(entries: [SurfaceTopologyEntry] = []) {
    self.entries = entries.sorted()
  }

  package init(placedRoot: PlacedNode) {
    var entries: [SurfaceTopologyEntry] = []
    Self.collect(from: placedRoot, into: &entries)
    self.init(entries: entries)
  }

  package func differs(from previous: Self?) -> Bool {
    guard let previous else {
      return false
    }
    return self != previous
  }

  private static func collect(
    from node: PlacedNode,
    into entries: inout [SurfaceTopologyEntry]
  ) {
    var stack: [PlacedNode] = [node]
    while let node = stack.popLast() {
      appendEntry(from: node, into: &entries)
      stack.append(contentsOf: node.children.reversed())
    }
  }

  private static func appendEntry(
    from node: PlacedNode,
    into entries: inout [SurfaceTopologyEntry]
  ) {
    if node.surfaceComposition.participatesInTopologySignature {
      entries.append(
        SurfaceTopologyEntry(
          role: node.surfaceComposition.role,
          stableKey: node.surfaceComposition.stableKey,
          invalidationScope: node.surfaceComposition.invalidationScope,
          bounds: node.bounds,
          zIndex: node.zIndex
        )
      )
    }
  }
}

package struct SurfaceTopologyEntry: Equatable, Sendable, Comparable {
  // Deliberately carries no runtime `Identity`: a `ViewNodeID` re-key of a
  // portal/overlay root must not perturb the topology signature (which would
  // force a spurious full-surface diff). Participating nodes are distinguished
  // by their structural `stableKey` (Stage 4) plus role/scope/geometry.
  package var role: SurfaceCompositionRole
  package var stableKey: String?
  package var invalidationScope: SurfaceInvalidationScope
  package var bounds: CellRect
  package var zIndex: Double

  package static func < (lhs: Self, rhs: Self) -> Bool {
    comparisonTuple(lhs).lexicographicallyPrecedes(comparisonTuple(rhs))
  }

  private static func comparisonTuple(_ entry: Self) -> [String] {
    [
      entry.stableKey.map { "1:\($0)" } ?? "0:",
      String(describing: entry.role),
      String(describing: entry.invalidationScope),
      "\(entry.bounds.origin.x),\(entry.bounds.origin.y)",
      "\(entry.bounds.size.width),\(entry.bounds.size.height)",
      "\(entry.zIndex)",
    ]
  }
}
