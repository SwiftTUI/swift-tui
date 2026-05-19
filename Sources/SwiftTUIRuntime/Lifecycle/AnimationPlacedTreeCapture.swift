import SwiftTUICore

struct AnimationPlacedTreeCapture {
  var root: PlacedNode
  var matchedBounds: [MatchedGeometryKey: CellRect]
  var matchedIdentities: [MatchedGeometryKey: Identity]

  static func capture(_ placed: PlacedNode) -> AnimationPlacedTreeCapture {
    var matchedBounds: [MatchedGeometryKey: CellRect] = [:]
    var matchedIdentities: [MatchedGeometryKey: Identity] = [:]
    AnimationTreeQueries.collectMatchedGeometry(
      placed,
      bounds: &matchedBounds,
      identities: &matchedIdentities
    )
    return .init(
      root: placed,
      matchedBounds: matchedBounds,
      matchedIdentities: matchedIdentities
    )
  }
}
