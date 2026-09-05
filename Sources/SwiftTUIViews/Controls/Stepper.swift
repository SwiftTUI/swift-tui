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
      intake.registerAction(identity: context.identity) {
        let next = steppedControlValue(
          from: binding.wrappedValue,
          delta: 1,
          step: step,
          bounds: bounds
        )
        guard next != binding.wrappedValue else {
          return false
        }
        binding.wrappedValue = next
        return true
      }
      intake.registerKeyPressHandler(identity: context.identity) { keyPress in
        guard keyPress.modifiers.isEmpty else {
          return false
        }
        let deltaCount: Int
        switch keyPress.key {
        case .arrowLeft:
          deltaCount = -1
        case .arrowRight:
          deltaCount = 1
        default:
          return false
        }

        return updateBoundControlValue(
          binding,
          delta: deltaCount,
          step: step,
          bounds: bounds
        )
      }

      let rootRouteID = runtimePrimaryRouteID(for: context.identity)
      let decrementRouteID = runtimePrimaryRouteID(
        for: stepperDecrementIdentity(for: context.identity)
      )
      let incrementRouteID = runtimePrimaryRouteID(
        for: stepperIncrementIdentity(for: context.identity)
      )

      intake.registerPointerHandler(routeID: rootRouteID) { event in
        guard case .scrolled(let deltaX, let deltaY) = event.kind,
          let wheelDelta = pointerValueDelta(deltaX: deltaX, deltaY: deltaY)
        else {
          return .ignored
        }

        let handled = updateBoundControlValue(
          binding,
          delta: wheelDelta,
          step: step,
          bounds: bounds
        )
        return handled ? .claimed : .ignored
      }
      intake.registerPointerHandler(routeID: decrementRouteID) { event in
        switch event.kind {
        case .down(.primary):
          // Claim the press whether or not the value can move. A click on the
          // decrement affordance is an interaction owned by this route even
          // at a bound.
          _ = updateBoundControlValue(
            binding,
            delta: -1,
            step: step,
            bounds: bounds
          )
          return .claimed
        case .up(.primary):
          // The action is press-driven, but the same route owns the release.
          // Claim it so the Stepper's root activation action cannot increment.
          return .claimed
        default:
          return .ignored
        }
      }
      intake.registerPointerHandler(routeID: incrementRouteID) { event in
        switch event.kind {
        case .down(.primary):
          _ = updateBoundControlValue(
            binding,
            delta: 1,
            step: step,
            bounds: bounds
          )
          return .claimed
        case .up(.primary):
          return .claimed
        default:
          return .ignored
        }
      }
    }

    let formatted = formattedControlValue(currentValue, bounds: bounds, step: step)
    var configuration = StepperStyleConfiguration(
      label: .init(authoringContext: authoringScope) { label },
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
      )
    )
  }
}
