@_spi(Testing) import SwiftTUICore

struct AnimationResolvedIdentityDiff {
  var newIdentities: Set<Identity>
  var liveIdentities: Set<Identity>
  var insertedIdentities: Set<Identity>
  var removedIdentities: Set<Identity>

  static func make(
    newSnapshots: [Identity: AnimatableSnapshot],
    previousIdentities: Set<Identity>,
    removingIdentities: Set<Identity>
  ) -> AnimationResolvedIdentityDiff {
    let newIdentities = Set(newSnapshots.keys)
    let liveIdentities = previousIdentities.subtracting(removingIdentities)
    return AnimationResolvedIdentityDiff(
      newIdentities: newIdentities,
      liveIdentities: liveIdentities,
      insertedIdentities: newIdentities.subtracting(previousIdentities),
      removedIdentities: liveIdentities.subtracting(newIdentities)
    )
  }
}

struct MatchedGeometryAnimationPlan {
  var identity: Identity
  var key: MatchedGeometryKey
  var fromBounds: CellRect
  /// The destination instance's configuration governs what interpolates.
  var properties: MatchedGeometryProperties
  var anchor: UnitPoint
  var animationBox: AnimationBox
  var batchID: AnimationBatchID?
}

struct MatchedGeometryAnimationPlans {
  var animations: [MatchedGeometryAnimationPlan]
  /// The live identity that received each key consumed by a match this
  /// frame — the counterpart a departing instance's exit overlay travels
  /// toward while its transition plays.
  var destinationIdentityByKey: [MatchedGeometryKey: Identity]

  var consumedKeys: Set<MatchedGeometryKey> {
    Set(destinationIdentityByKey.keys)
  }
}

enum AnimationResolvedTreeDiffing {
  static func matchedGeometryPlans(
    newMatchedConfigsByIdentity: [Identity: MatchedGeometryConfig],
    previousMatchedKeyIdentities: [MatchedGeometryKey: Identity],
    previousMatchedGeometryBounds: [MatchedGeometryKey: CellRect],
    transactionForIdentity: (Identity) -> TransactionSnapshot
  ) -> MatchedGeometryAnimationPlans {
    var animations: [MatchedGeometryAnimationPlan] = []
    var destinationIdentityByKey: [MatchedGeometryKey: Identity] = [:]
    // A non-source that shares its key with a source *this frame* is
    // co-present: the placed pass positions it onto the source every frame
    // (adoption), so it never receives a swap. Without this skip an unrelated
    // animated write planned a match from the source's rect to its own slot
    // — the co-present instance flew in from its source — and the two
    // channels would double-apply.
    let keysWithSources = Set(
      newMatchedConfigsByIdentity.values.lazy.filter(\.isSource).map(\.key))
    for (identity, config) in newMatchedConfigsByIdentity {
      let key = config.key
      if !config.isSource, keysWithSources.contains(key) {
        continue
      }
      if let previousIdentity = previousMatchedKeyIdentities[key],
        previousIdentity == identity
      {
        continue
      }
      guard let fromBounds = previousMatchedGeometryBounds[key] else {
        continue
      }
      let transaction = transactionForIdentity(identity)
      guard case .animate(let box) = transaction.animationRequest else {
        continue
      }
      animations.append(
        MatchedGeometryAnimationPlan(
          identity: identity,
          key: key,
          fromBounds: fromBounds,
          properties: config.properties,
          anchor: config.anchor,
          animationBox: box,
          batchID: transaction.animationBatchID
        )
      )
      destinationIdentityByKey[key] = identity
    }

    return .init(animations: animations, destinationIdentityByKey: destinationIdentityByKey)
  }
}
