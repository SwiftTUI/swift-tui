package struct EntityRoutingTable: Equatable, Sendable {
  package private(set) var nodeIDByEntity: [EntityIdentity: ViewNodeID]
  package private(set) var entityByNodeID: [ViewNodeID: EntityIdentity]

  package init(
    nodeIDByEntity: [EntityIdentity: ViewNodeID] = [:],
    entityByNodeID: [ViewNodeID: EntityIdentity] = [:]
  ) {
    self.nodeIDByEntity = nodeIDByEntity
    self.entityByNodeID = entityByNodeID
  }

  package func route(_ entity: EntityIdentity) -> ViewNodeID? {
    nodeIDByEntity[entity]
  }

  package mutating func bind(
    _ entity: EntityIdentity,
    to viewNodeID: ViewNodeID
  ) {
    if let previousEntity = entityByNodeID[viewNodeID],
      previousEntity != entity
    {
      nodeIDByEntity.removeValue(forKey: previousEntity)
    }
    if let previousNodeID = nodeIDByEntity[entity],
      previousNodeID != viewNodeID
    {
      entityByNodeID.removeValue(forKey: previousNodeID)
    }
    nodeIDByEntity[entity] = viewNodeID
    entityByNodeID[viewNodeID] = entity
  }

  package mutating func release(_ viewNodeID: ViewNodeID) {
    guard let entity = entityByNodeID.removeValue(forKey: viewNodeID) else {
      return
    }
    if nodeIDByEntity[entity] == viewNodeID {
      nodeIDByEntity.removeValue(forKey: entity)
    }
  }

  package mutating func releaseEntities(
    notIn activeEntities: Set<EntityIdentity>
  ) {
    let staleBindings = nodeIDByEntity.filter { entity, _ in
      !activeEntities.contains(entity)
    }
    for (entity, viewNodeID) in staleBindings {
      nodeIDByEntity.removeValue(forKey: entity)
      if entityByNodeID[viewNodeID] == entity {
        entityByNodeID.removeValue(forKey: viewNodeID)
      }
    }
  }

  package mutating func releaseNodes(
    notIn liveNodeIDs: Set<ViewNodeID>
  ) {
    let staleNodeIDs = entityByNodeID.keys.filter { !liveNodeIDs.contains($0) }
    for viewNodeID in staleNodeIDs {
      release(viewNodeID)
    }
  }
}
