package enum BuiltinPointerRouteComponent {
  case sliderTrack
  case stepperDecrement
  case stepperIncrement
  case pickerTrigger
  case verticalScrollIndicator
  case horizontalScrollIndicator
  case pickerOption(Int)
  case listRow(Int)
  case tableRow(Int)

  package var identityComponent: IdentityComponent {
    switch self {
    case .sliderTrack:
      .named("SliderTrack")
    case .stepperDecrement:
      .named("StepperDecrement")
    case .stepperIncrement:
      .named("StepperIncrement")
    case .pickerTrigger:
      .named("PickerTrigger")
    case .verticalScrollIndicator:
      .named("VerticalScrollIndicator")
    case .horizontalScrollIndicator:
      .named("HorizontalScrollIndicator")
    case .pickerOption(let index):
      .indexed("PickerOption", index: index)
    case .listRow(let rowIndex):
      .indexed("ListRow", index: rowIndex)
    case .tableRow(let rowIndex):
      .indexed("TableRow", index: rowIndex)
    }
  }
}

package func primaryRouteID(
  for identity: Identity,
  ownerNodeID: ViewNodeID? = nil
) -> RouteID {
  RouteID(identity: identity, ownerNodeID: ownerNodeID)
}

@MainActor
package func runtimePrimaryRouteID(
  for identity: Identity
) -> RouteID {
  primaryRouteID(
    for: identity,
    ownerNodeID: ViewNodeContext.current?.viewNodeID
  )
}

package func sliderTrackIdentity(
  for controlIdentity: Identity
) -> Identity {
  controlIdentity.child(BuiltinPointerRouteComponent.sliderTrack.identityComponent)
}

package func stepperDecrementIdentity(
  for controlIdentity: Identity
) -> Identity {
  controlIdentity.child(BuiltinPointerRouteComponent.stepperDecrement.identityComponent)
}

package func stepperIncrementIdentity(
  for controlIdentity: Identity
) -> Identity {
  controlIdentity.child(BuiltinPointerRouteComponent.stepperIncrement.identityComponent)
}

package func pickerTriggerIdentity(
  for controlIdentity: Identity
) -> Identity {
  controlIdentity.child(BuiltinPointerRouteComponent.pickerTrigger.identityComponent)
}

package func verticalScrollIndicatorIdentity(
  for controlIdentity: Identity
) -> Identity {
  controlIdentity.child(BuiltinPointerRouteComponent.verticalScrollIndicator.identityComponent)
}

package func horizontalScrollIndicatorIdentity(
  for controlIdentity: Identity
) -> Identity {
  controlIdentity.child(BuiltinPointerRouteComponent.horizontalScrollIndicator.identityComponent)
}

package func pickerOptionIdentity(
  for controlIdentity: Identity,
  index: Int
) -> Identity {
  controlIdentity.child(BuiltinPointerRouteComponent.pickerOption(index).identityComponent)
}

/// `rowIdentity` is the row's own identity. A later duplicate's row (one
/// whose identity carries an `ID[x#n]` occurrence) keeps those occurrence
/// components after the index component, so its route, which is also its
/// selector's action identity and its keyboard focus identity, carries the
/// occurrence as a duplicate button's identity does (STUI-1296). A unique
/// row's route is unchanged.
package func listRowIdentity(
  for controlIdentity: Identity,
  rowIndex: Int,
  rowIdentity: Identity? = nil
) -> Identity {
  controlIdentity.child(BuiltinPointerRouteComponent.listRow(rowIndex).identityComponent)
    .appendingRowOccurrences(of: rowIdentity, below: controlIdentity)
}

/// The row index encoded in `identity`, when it is `container`'s list-row
/// identity. The inverse of ``listRowIdentity(for:rowIndex:)``.
///
/// Resolving the focused row by minting an identity per row until one matches
/// is O(dataset) per frame (register item D18); the identity already carries
/// the answer.
package func listRowIndex(
  parsedFrom identity: Identity,
  container: Identity
) -> Int? {
  guard let route = rowRoute(of: identity, container: container),
    let component = route.lastComponent
  else {
    return nil
  }
  return builtinRouteRowIndex(in: component, kind: "ListRow")
}

/// `identity` without the occurrence components a later duplicate's row
/// route carries after its index component, when it is a child route of
/// `container`.
private func rowRoute(of identity: Identity, container: Identity) -> Identity? {
  var route = identity
  while route.parent != container {
    guard let last = route.lastComponent,
      !Identity(components: [last]).entityOccurrenceComponents.isEmpty,
      let parent = route.parent
    else { return nil }
    route = parent
  }
  return route
}

extension Identity {
  /// Only the occurrences below the collection count: a collection that is
  /// itself a later duplicate already carries its occurrence in every route.
  fileprivate func appendingRowOccurrences(
    of rowIdentity: Identity?, below container: Identity
  ) -> Identity {
    guard let rowIdentity else { return self }
    let own =
      container.isAncestor(of: rowIdentity)
      ? Identity(components: Array(rowIdentity.components.dropFirst(container.components.count)))
      : rowIdentity
    return own.entityOccurrenceComponents.reduce(self) { $0.child($1) }
  }
}

private func builtinRouteRowIndex(
  in component: String,
  kind: String
) -> Int? {
  // `IdentityComponent.indexed` encodes as `Kind[n]`.
  guard component.count > kind.count + 2,
    component.hasPrefix(kind + "["),
    component.hasSuffix("]")
  else {
    return nil
  }
  let digits = component.dropFirst(kind.count + 1).dropLast()
  return Int(digits)
}

/// See ``listRowIdentity(for:rowIndex:rowIdentity:)`` for `rowIdentity`.
package func tableRowIdentity(
  for controlIdentity: Identity,
  rowIndex: Int,
  rowIdentity: Identity? = nil
) -> Identity {
  controlIdentity.child(BuiltinPointerRouteComponent.tableRow(rowIndex).identityComponent)
    .appendingRowOccurrences(of: rowIdentity, below: controlIdentity)
}

package func routeIDHasTerminalComponent(
  _ routeID: RouteID,
  hasTerminalComponent component: BuiltinPointerRouteComponent
) -> Bool {
  routeID.kind == .primary
    && routeID.identity.lastComponent == component.identityComponent.rawValue
}
