import SwiftTUICore

/// Adjusts a numeric binding along a bounded linear range.
public struct Slider<Label: View>: PrimitiveView, ResolvableView {
  private enum ValueStorage {
    case integer(Binding<Int>, bounds: ClosedRange<Int>, step: Int)
    case double(Binding<Double>, bounds: ClosedRange<Double>, step: Double?)
  }

  private var valueStorage: ValueStorage
  private var label: Label
  private let authoringScope: AuthoringContext?

  public init<S: StringProtocol>(
    _ title: S,
    value: Binding<Int>,
    in bounds: ClosedRange<Int>,
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
    in bounds: ClosedRange<Double>,
    step: Double? = nil
  ) where Label == Text {
    valueStorage = .double(
      value,
      bounds: bounds,
      step: step.map(Double.sanitizedControlStep)
    )
    label = Text(String(title))
    authoringScope = currentAuthoringContext()
  }

  public init(
    value: Binding<Int>,
    in bounds: ClosedRange<Int>,
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
    in bounds: ClosedRange<Double>,
    step: Double? = nil,
    @ViewBuilder label: () -> Label
  ) {
    valueStorage = .double(
      value,
      bounds: bounds,
      step: step.map(Double.sanitizedControlStep)
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

extension Slider {
  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    switch valueStorage {
    case .integer(let binding, let bounds, let step):
      return resolvedNode(
        value: binding,
        bounds: bounds,
        trackStep: step,
        adjustmentStep: step,
        in: context
      )
    case .double(let binding, let bounds, let step):
      let steps =
        step.map { (track: $0, adjustment: $0) }
        ?? continuousSliderSteps(for: bounds)
      return resolvedNode(
        value: binding,
        bounds: bounds,
        trackStep: steps.track,
        adjustmentStep: steps.adjustment,
        in: context
      )
    }
  }

  private func resolvedNode<Value: AdjustableControlValue>(
    value binding: Binding<Value>,
    bounds: ClosedRange<Value>,
    trackStep: Value,
    adjustmentStep: Value,
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
    if isEnabled {
      let bounds = bounds
      let adjustmentStep = adjustmentStep
      let intake = HandlerDescriptorIntake(
        context: context,
        fallbackAuthoringScope: authoringScope
      )
      intake.registerAction(identity: context.identity) {
        let next = steppedControlValue(
          from: binding.wrappedValue,
          delta: 1,
          step: adjustmentStep,
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
          step: adjustmentStep,
          bounds: bounds
        )
      }

      let rootRouteID = runtimePrimaryRouteID(for: context.identity)
      let trackRouteID = runtimePrimaryRouteID(
        for: sliderTrackIdentity(for: context.identity)
      )

      let trackStep = trackStep
      intake.registerPointerHandler(routeID: rootRouteID) { event in
        guard case .scrolled(let deltaX, let deltaY) = event.kind,
          let wheelDelta = pointerValueDelta(deltaX: deltaX, deltaY: deltaY)
        else {
          return .ignored
        }

        let handled = updateBoundControlValue(
          binding,
          delta: wheelDelta,
          step: adjustmentStep,
          bounds: bounds
        )
        return handled ? .claimed : .ignored
      }
      intake.registerPointerHandler(routeID: trackRouteID) { event in
        switch event.kind {
        case .down(.primary), .dragged(.primary), .up(.primary):
          binding.wrappedValue = sliderValue(
            at: event.location.location.x,
            in: event.targetRect,
            bounds: bounds,
            step: trackStep
          )
          return .claimed
        case .scrolled(let deltaX, let deltaY):
          guard let wheelDelta = pointerValueDelta(deltaX: deltaX, deltaY: deltaY) else {
            return .ignored
          }

          let handled = updateBoundControlValue(
            binding,
            delta: wheelDelta,
            step: adjustmentStep,
            bounds: bounds
          )
          return handled ? .claimed : .ignored
        default:
          return .ignored
        }
      }
    }

    let formatted = formattedControlValue(currentValue, bounds: bounds, step: trackStep)
    var configuration = SliderStyleConfiguration(
      label: .init(authoringContext: authoringScope) { label },
      valueLabel: .init(authoringContext: authoringScope) { Text(formatted) },
      fractionCompleted: sliderFraction(value: currentValue, bounds: bounds),
      trackCellCount: 8,
      isEnabled: isEnabled,
      isFocused: isFocused,
      showsFocusEffect: showsFocusEffect,
      isPressed: isPressed,
      canDecrement: stepperCanAdjust(currentValue, delta: -1, step: adjustmentStep, bounds: bounds),
      canIncrement: stepperCanAdjust(currentValue, delta: 1, step: adjustmentStep, bounds: bounds),
      styleEnvironment: styleEnvironment)
    configuration.bindRoutes(to: context.identity)
    let child = context.environmentValues.sliderStyle.resolveBody(
      configuration: configuration, in: context.child(component: .named("SliderBody")))

    return ResolvedNode(
      identity: context.identity,
      kind: .view("Slider"),
      children: [child],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: focusableControlMetadata(
        focusInteractions: .edit,
        accessibilityRole: .slider
      )
    )
  }
}
