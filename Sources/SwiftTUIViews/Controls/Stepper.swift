import SwiftTUICore

/// Increments or decrements a numeric binding.
public struct Stepper<Label: View>: PrimitiveView, ResolvableView {
  private enum ValueStorage {
    case integer(Binding<Int>, bounds: ClosedRange<Int>?, step: Int)
    case double(Binding<Double>, bounds: ClosedRange<Double>?, step: Double)
  }

  private var valueStorage: ValueStorage
  private var label: Label
  private let authoringScope: AuthoringContext?

  public init<S: StringProtocol>(
    _ title: S,
    value: Binding<Int>,
    in bounds: ClosedRange<Int>? = nil,
    step: Int = 1
  ) where Label == Text {
    valueStorage = .integer(
      value,
      bounds: bounds,
      step: Int.sanitizedControlStep(step)
    )
    label = Text(String(title))
    authoringScope = currentAuthoringContext()
  }

  public init<S: StringProtocol>(
    _ title: S,
    value: Binding<Double>,
    in bounds: ClosedRange<Double>? = nil,
    step: Double = 1
  ) where Label == Text {
    valueStorage = .double(
      value,
      bounds: bounds,
      step: Double.sanitizedControlStep(step)
    )
    label = Text(String(title))
    authoringScope = currentAuthoringContext()
  }

  public init(
    value: Binding<Int>,
    in bounds: ClosedRange<Int>? = nil,
    step: Int = 1,
    @ViewBuilder label: () -> Label
  ) {
    valueStorage = .integer(
      value,
      bounds: bounds,
      step: Int.sanitizedControlStep(step)
    )
    self.label = label()
    authoringScope = currentAuthoringContext()
  }

  public init(
    value: Binding<Double>,
    in bounds: ClosedRange<Double>? = nil,
    step: Double = 1,
    @ViewBuilder label: () -> Label
  ) {
    valueStorage = .double(
      value,
      bounds: bounds,
      step: Double.sanitizedControlStep(step)
    )
    self.label = label()
    authoringScope = currentAuthoringContext()
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    [resolvedNode(in: context)]
  }
}

extension Stepper {
  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    switch valueStorage {
    case .integer(let binding, let bounds, let step):
      resolvedNode(
        value: binding,
        bounds: bounds,
        step: step,
        in: context
      )
    case .double(let binding, let bounds, let step):
      resolvedNode(
        value: binding,
        bounds: bounds,
        step: step,
        in: context
      )
    }
  }

  private func resolvedNode<Value: AdjustableControlValue>(
    value binding: Binding<Value>,
    bounds: ClosedRange<Value>?,
    step: Value,
    in context: ResolveContext
  ) -> ResolvedNode {
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let isFocused =
      context.environmentValues.focusedIdentity(comparedAgainst: [context.identity])
      == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isPressed =
      context.environmentValues.pressedIdentity(comparedAgainst: [context.identity])
      == context.identity
    let isEnabled = context.environmentValues.isEnabled
    let currentValue = clampedControlValue(binding.wrappedValue, to: bounds)
    let canDecrement = stepperCanAdjust(
      currentValue,
      delta: -1,
      step: step,
      bounds: bounds
    )
    let canIncrement = stepperCanAdjust(
      currentValue,
      delta: 1,
      step: step,
      bounds: bounds
    )
    if isEnabled {
      let bounds = bounds
      let step = step
      let intake = HandlerDescriptorIntake(
        context: context,
        fallbackAuthoringScope: authoringScope
      )
      let adjust: @MainActor @Sendable (Int) -> Bool = { delta in
        // Use the display's clamping rule against the live binding: several
        // inputs may arrive through this registration before the next render.
        // An inactive direction must not normalize an out-of-range model.
        let value = clampedControlValue(binding.wrappedValue, to: bounds)
        guard stepperCanAdjust(value, delta: delta, step: step, bounds: bounds) else {
          return false
        }
        return updateBoundControlValue(
          binding,
          delta: delta,
          step: step,
          bounds: bounds
        )
      }
      intake.registerAction(identity: context.identity) {
        adjust(1)
      }
      registerValueAdjustmentInput(intake: intake, identity: context.identity, adjust: adjust)
      let decrementRouteID = runtimePrimaryRouteID(
        for: stepperDecrementIdentity(for: context.identity)
      )
      let incrementRouteID = runtimePrimaryRouteID(
        for: stepperIncrementIdentity(for: context.identity)
      )

      // Each half claims its press whether or not the value can move: a click
      // on the affordance is an interaction owned by that route even at a
      // bound. The action is press-driven, but the same route owns the
      // release, so the Stepper's root activation action cannot fire the
      // opposite half on the `.up`.
      func registerActionHalf(routeID: RouteID, delta: Int) {
        intake.registerPointerHandler(routeID: routeID) { event in
          switch event.kind {
          case .down(.primary):
            _ = adjust(delta)
            return .claimed
          case .up(.primary):
            return .claimed
          default:
            return .ignored
          }
        }
      }
      registerActionHalf(routeID: decrementRouteID, delta: -1)
      registerActionHalf(routeID: incrementRouteID, delta: 1)
    }

    let formatted = formattedControlValue(currentValue, bounds: bounds, step: step)
    var configuration = StepperStyleConfiguration(
      label: .init(authoringContext: authoringScope) { label.authoredAccessibilityLabel() },
      valueLabel: .init(authoringContext: authoringScope) { Text(formatted) },
      canDecrement: canDecrement,
      canIncrement: canIncrement,
      isEnabled: isEnabled,
      isFocused: isFocused,
      showsFocusEffect: showsFocusEffect,
      isPressed: isPressed,
      styleEnvironment: styleEnvironment)
    configuration.bindRoutes(to: context.identity)
    let child = context.environmentValues.stepperStyle.resolveBody(
      configuration: configuration, in: context.child(component: .named("StepperBody")))

    return ResolvedNode(
      identity: context.identity,
      kind: .view("Stepper"),
      children: [child],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: focusableControlMetadata(
        focusInteractions: .edit,
        accessibilityRole: .stepper
      ).namingControl(with: label)
    )
  }
}
