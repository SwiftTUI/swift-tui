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
