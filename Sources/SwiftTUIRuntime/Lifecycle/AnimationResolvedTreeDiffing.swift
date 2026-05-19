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
  var animationBox: AnimationBox
  var batchID: AnimationBatchID?
}

struct MatchedGeometryAnimationPlans {
  var animations: [MatchedGeometryAnimationPlan]
  var consumedKeys: Set<MatchedGeometryKey>
}

enum AnimationResolvedTreeDiffing {
  static func matchedGeometryPlans(
    newMatchedKeysByIdentity: [Identity: MatchedGeometryKey],
    previousMatchedKeyIdentities: [MatchedGeometryKey: Identity],
    previousMatchedGeometryBounds: [MatchedGeometryKey: CellRect],
    transaction: TransactionSnapshot
  ) -> MatchedGeometryAnimationPlans {
    guard case .animate(let box) = transaction.animationRequest else {
      return .init(animations: [], consumedKeys: [])
    }

    var animations: [MatchedGeometryAnimationPlan] = []
    var consumedKeys: Set<MatchedGeometryKey> = []
    for (identity, key) in newMatchedKeysByIdentity {
      if let previousIdentity = previousMatchedKeyIdentities[key],
        previousIdentity == identity
      {
        continue
      }
      guard let fromBounds = previousMatchedGeometryBounds[key] else {
        continue
      }
      animations.append(
        MatchedGeometryAnimationPlan(
          identity: identity,
          key: key,
          fromBounds: fromBounds,
          animationBox: box,
          batchID: transaction.animationBatchID
        )
      )
      consumedKeys.insert(key)
    }

    return .init(animations: animations, consumedKeys: consumedKeys)
  }
}
