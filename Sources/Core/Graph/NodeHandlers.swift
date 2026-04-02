package struct NodeHandlers: Equatable {
  package var actionIdentities: [Identity]
  package var keyHandlerIdentities: [Identity]
  package var keyPressHandlerIdentities: [Identity]
  package var pointerRouteIDs: [RouteID]
  package var hotkeyIdentities: [Identity]
  package var lifecycleHandlerIDs: [String]
  package var task: TaskDescriptor?

  package init(
    actionIdentities: [Identity] = [],
    keyHandlerIdentities: [Identity] = [],
    keyPressHandlerIdentities: [Identity] = [],
    pointerRouteIDs: [RouteID] = [],
    hotkeyIdentities: [Identity] = [],
    lifecycleHandlerIDs: [String] = [],
    task: TaskDescriptor? = nil
  ) {
    self.actionIdentities = actionIdentities
    self.keyHandlerIdentities = keyHandlerIdentities
    self.keyPressHandlerIdentities = keyPressHandlerIdentities
    self.pointerRouteIDs = pointerRouteIDs
    self.hotkeyIdentities = hotkeyIdentities
    self.lifecycleHandlerIDs = lifecycleHandlerIDs
    self.task = task
  }
}
