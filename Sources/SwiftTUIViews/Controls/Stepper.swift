package import SwiftTUICore

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
    let isFocused = context.environmentValues.focusedIdentity(comparedAgainst: [context.identity]) == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isPressed = context.environmentValues.pressedIdentity(comparedAgainst: [context.identity]) == context.identity
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
    let chrome = styleEnvironment.rowChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect,
      isPressed: isPressed
    )
    let contentChrome = styleEnvironment.controlChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect,
      isPressed: isPressed
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
      intake.registerKeyHandler(identity: context.identity) { event in
        let deltaCount: Int
        switch event {
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
          return false
        }

        return updateBoundControlValue(
          binding,
          delta: wheelDelta,
          step: step,
          bounds: bounds
        )
      }
      intake.registerPointerHandler(routeID: decrementRouteID) { event in
        guard case .down(.primary) = event.kind else {
          return false
        }

        return updateBoundControlValue(
          binding,
          delta: -1,
          step: step,
          bounds: bounds
        )
      }
      intake.registerPointerHandler(routeID: incrementRouteID) { event in
        guard case .down(.primary) = event.kind else {
          return false
        }

        return updateBoundControlValue(
          binding,
          delta: 1,
          step: step,
          bounds: bounds
        )
      }
    }

    let child = stepperBody(
      controlIdentity: context.identity,
      value: currentValue,
      step: step,
      bounds: bounds,
      canDecrement: canDecrement,
      canIncrement: canIncrement,
      showsFocusRail: isFocused && showsFocusEffect,
      isHighlighted: (isFocused && showsFocusEffect) || isPressed,
      isActiveNavigation: (isFocused && showsFocusEffect) || isPressed,
      chrome: chrome,
      contentChrome: contentChrome
    ).resolve(
      in: context.child(component: .named("StepperBody"))
    )

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

  @ViewBuilder
  private func stepperBody<Value: AdjustableControlValue>(
    controlIdentity: Identity,
    value: Value,
    step: Value,
    bounds: ClosedRange<Value>?,
    canDecrement: Bool,
    canIncrement: Bool,
    showsFocusRail: Bool,
    isHighlighted: Bool,
    isActiveNavigation: Bool,
    chrome: ControlChrome,
    contentChrome: ControlChrome
  ) -> some View {
    let inactiveStyle = AnyShapeStyle(.placeholder)
    let controlForeground =
      isActiveNavigation
      ? contentChrome.foregroundStyle
      : chrome.foregroundStyle
    let controlAccent =
      isActiveNavigation
      ? contentChrome.borderStyle
      : AnyShapeStyle(.separator)
    let decrementControl = Text(canDecrement ? "◀" : "◁")
      .foregroundStyle(canDecrement ? controlAccent : inactiveStyle)
      .id(stepperDecrementIdentity(for: controlIdentity))
      .semanticMetadata(.init(participatesInPointerHitTesting: true))
    let incrementControl = Text(canIncrement ? "▶" : "▷")
      .foregroundStyle(canIncrement ? controlAccent : inactiveStyle)
      .id(stepperIncrementIdentity(for: controlIdentity))
      .semanticMetadata(.init(participatesInPointerHitTesting: true))
    let controls = HStack(alignment: .center, spacing: 1) {
      decrementControl
      Text(formattedControlValue(value, bounds: bounds, step: step))
        .foregroundStyle(controlForeground)
      incrementControl
    }
    .drawMetadata(.init(opacity: contentChrome.opacity))
    let controlsView = highlightedControlRow(
      controls,
      isHighlighted: isActiveNavigation,
      backgroundStyle: contentChrome.backgroundStyle
    )
    let row = controlFocusRow(
      showsRail: showsFocusRail,
      railStyle: chrome.borderStyle,
      isHighlighted: isHighlighted,
      backgroundStyle: chrome.backgroundStyle,
      reservesRailSpaceWhenHidden: true
    ) {
      label
        .foregroundStyle(.terminalBorder(.accent))
      controlsView
    }
    .drawMetadata(.init(opacity: chrome.opacity))
    row
  }
}
