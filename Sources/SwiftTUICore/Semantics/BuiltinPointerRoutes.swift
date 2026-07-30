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

package func childRouteID(
  parent: Identity,
  component: IdentityComponent
) -> RouteID {
  primaryRouteID(for: parent.child(component))
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

package func listRowIdentity(
  for controlIdentity: Identity,
  rowIndex: Int
) -> Identity {
  controlIdentity.child(BuiltinPointerRouteComponent.listRow(rowIndex).identityComponent)
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
  guard identity.parent == container,
    let component = identity.lastComponent
  else {
    return nil
  }
  return builtinRouteRowIndex(in: component, kind: "ListRow")
}

/// The row index encoded in `identity`, when it is `container`'s table-row
/// identity. The inverse of ``tableRowIdentity(for:rowIndex:)``.
package func tableRowIndex(
  parsedFrom identity: Identity,
  container: Identity
) -> Int? {
  guard identity.parent == container,
    let component = identity.lastComponent
  else {
    return nil
  }
  return builtinRouteRowIndex(in: component, kind: "TableRow")
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

package func tableRowIdentity(
  for controlIdentity: Identity,
  rowIndex: Int
) -> Identity {
  controlIdentity.child(BuiltinPointerRouteComponent.tableRow(rowIndex).identityComponent)
}

package func routeIDHasTerminalComponent(
  _ routeID: RouteID,
  hasTerminalComponent component: BuiltinPointerRouteComponent
) -> Bool {
  routeID.kind == .primary
    && routeID.identity.lastComponent == component.identityComponent.rawValue
}
