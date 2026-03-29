package enum BuiltinPointerRouteComponent {
  package static let sliderTrack = "SliderTrack"
  package static let stepperDecrement = "StepperDecrement"
  package static let stepperIncrement = "StepperIncrement"
  package static let pickerTrigger = "PickerTrigger"
  package static let verticalScrollIndicator = "VerticalScrollIndicator"
  package static let horizontalScrollIndicator = "HorizontalScrollIndicator"

  package static func pickerOption(
    _ index: Int
  ) -> String {
    "PickerOption[\(index)]"
  }

  package static func listRow(
    _ rowIndex: Int
  ) -> String {
    "ListRow[\(rowIndex)]"
  }

  package static func tableRow(
    _ rowIndex: Int
  ) -> String {
    "TableRow[\(rowIndex)]"
  }
}

package func parallelPrimaryRouteID(
  for identity: Identity
) -> RouteID {
  RouteID(identity: identity)
}

package func parallelChildRouteID(
  parent: Identity,
  component: String
) -> RouteID {
  parallelPrimaryRouteID(for: parent.child(component))
}

package func parallelSliderTrackIdentity(
  for controlIdentity: Identity
) -> Identity {
  controlIdentity.child(BuiltinPointerRouteComponent.sliderTrack)
}

package func parallelStepperDecrementIdentity(
  for controlIdentity: Identity
) -> Identity {
  controlIdentity.child(BuiltinPointerRouteComponent.stepperDecrement)
}

package func parallelStepperIncrementIdentity(
  for controlIdentity: Identity
) -> Identity {
  controlIdentity.child(BuiltinPointerRouteComponent.stepperIncrement)
}

package func parallelPickerTriggerIdentity(
  for controlIdentity: Identity
) -> Identity {
  controlIdentity.child(BuiltinPointerRouteComponent.pickerTrigger)
}

package func parallelVerticalScrollIndicatorIdentity(
  for controlIdentity: Identity
) -> Identity {
  controlIdentity.child(BuiltinPointerRouteComponent.verticalScrollIndicator)
}

package func parallelHorizontalScrollIndicatorIdentity(
  for controlIdentity: Identity
) -> Identity {
  controlIdentity.child(BuiltinPointerRouteComponent.horizontalScrollIndicator)
}

package func parallelPickerOptionIdentity(
  for controlIdentity: Identity,
  index: Int
) -> Identity {
  controlIdentity.child(BuiltinPointerRouteComponent.pickerOption(index))
}

package func parallelListRowIdentity(
  for controlIdentity: Identity,
  rowIndex: Int
) -> Identity {
  controlIdentity.child(BuiltinPointerRouteComponent.listRow(rowIndex))
}

package func parallelTableRowIdentity(
  for controlIdentity: Identity,
  rowIndex: Int
) -> Identity {
  controlIdentity.child(BuiltinPointerRouteComponent.tableRow(rowIndex))
}

package func parallelRouteID(
  _ routeID: RouteID,
  hasTerminalComponent component: String
) -> Bool {
  routeID.kind == .primary
    && routeID.identity.lastComponent == component
}
