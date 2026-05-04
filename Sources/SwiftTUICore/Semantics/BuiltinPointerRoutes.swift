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
  for identity: Identity
) -> RouteID {
  RouteID(identity: identity)
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
