import SwiftTUICore

struct AnimationPlacedTreeCapture {
  var root: PlacedNode
  var matchedBounds: [MatchedGeometryKey: CellRect]
  var matchedIdentities: [MatchedGeometryKey: Identity]
  /// The co-present pairs in this tree (plan 2026-08-25-003 Stage A). The
  /// sampler derives the frame's adoption offsets from them; the controller
  /// keeps the time-free offsets so a departing adoptee's exit overlay is
  /// frozen where it was drawn, not at its layout slot.
  var adoptionPairs: [MatchedGeometryAdoptionPair]
  var adoptionOffsets: [Identity: PlacedAnimationOverlayOffset]

  /// One walk of the baseline placed tree: records the bounds and identity
  /// of every *source* node per key (a non-source never supplies the
  /// `from` geometry of a later swap; the last-walked source wins) and
  /// pairs every non-source with its key's single source for adoption.
  static func capture(_ placed: PlacedNode) -> AnimationPlacedTreeCapture {
    var entries: [MatchedGeometryPlacedEntry] = []
    AnimationTreeQueries.collectMatchedGeometryEntries(placed, into: &entries)
    var matchedBounds: [MatchedGeometryKey: CellRect] = [:]
    var matchedIdentities: [MatchedGeometryKey: Identity] = [:]
    for entry in entries where entry.config.isSource {
      matchedBounds[entry.config.key] = entry.bounds
      matchedIdentities[entry.config.key] = entry.identity
    }
    let pairs = MatchedGeometryAdoption.pairs(from: entries)
    var adoptionOffsets: [Identity: PlacedAnimationOverlayOffset] = [:]
    for offset in MatchedGeometryAdoption.offsets(for: pairs) {
      adoptionOffsets[offset.identity] = offset
    }
    return .init(
      root: placed,
      matchedBounds: matchedBounds,
      matchedIdentities: matchedIdentities,
      adoptionPairs: pairs,
      adoptionOffsets: adoptionOffsets
    )
  }
}
