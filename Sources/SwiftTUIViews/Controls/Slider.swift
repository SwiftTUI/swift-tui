package import SwiftTUICore

/// Adjusts a numeric binding along a bounded linear range.
public struct Slider<Label: View>: PrimitiveView, ResolvableView {
  private enum ValueStorage {
    case integer(Binding<Int>, bounds: ClosedRange<Int>, step: Int)
    case double(Binding<Double>, bounds: ClosedRange<Double>, step: Double)
  }

  private var valueStorage: ValueStorage
  private var label: Label

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
  }

  public init<S: StringProtocol>(
    _ title: S,
    value: Binding<Double>,
    in bounds: ClosedRange<Double>,
    step: Double = 1
  ) where Label == Text {
    valueStorage = .double(
      value,
      bounds: bounds,
      step: Double.sanitizedControlStep(step)
    )
    label = Text(String(title))
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
  }

  public init(
    value: Binding<Double>,
    in bounds: ClosedRange<Double>,
    step: Double = 1,
    @ViewBuilder label: () -> Label
  ) {
    valueStorage = .double(
      value,
      bounds: bounds,
      step: Double.sanitizedControlStep(step)
    )
    self.label = label()
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
    bounds: ClosedRange<Value>,
    step: Value,
    in context: ResolveContext
  ) -> ResolvedNode {
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let isFocused = context.environmentValues.focusedIdentity == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isPressed = context.environmentValues.pressedIdentity == context.identity
    let isEnabled = context.environmentValues.isEnabled
    let currentValue = clampedControlValue(binding.wrappedValue, to: bounds)
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
      let dynamicPropertyScope = currentAuthoringContext()
      context.localActionRegistry?.register(
        identity: context.identity,
        handler: {
          withAuthoringContext(dynamicPropertyScope) {
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
        },
        followUpInvalidationIdentity: dynamicPropertyScope?.viewIdentity
      )
      context.localKeyHandlerRegistry?.register(identity: context.identity) { event in
        let deltaCount: Int
        switch event {
        case .arrowLeft:
          deltaCount = -1
        case .arrowRight:
          deltaCount = 1
        default:
          return false
        }

        return withAuthoringContext(dynamicPropertyScope) {
          updateBoundControlValue(
            binding,
            delta: deltaCount,
            step: step,
            bounds: bounds
          )
        }
      }

      let rootRouteID = primaryRouteID(for: context.identity)
      let trackRouteID = primaryRouteID(
        for: sliderTrackIdentity(for: context.identity)
      )

      context.localPointerHandlerRegistry?.register(routeID: rootRouteID) { event in
        guard case .scrolled(let deltaX, let deltaY) = event.kind,
          let wheelDelta = pointerValueDelta(deltaX: deltaX, deltaY: deltaY)
        else {
          return false
        }

        return withAuthoringContext(dynamicPropertyScope) {
          updateBoundControlValue(
            binding,
            delta: wheelDelta,
            step: step,
            bounds: bounds
          )
        }
      }
      context.localPointerHandlerRegistry?.register(routeID: trackRouteID) { event in
        switch event.kind {
        case .down(.primary), .dragged(.primary), .up(.primary):
          return withAuthoringContext(dynamicPropertyScope) {
            binding.wrappedValue = sliderValue(
              at: event.location.location.x,
              in: event.targetRect,
              bounds: bounds,
              step: step
            )
            return true
          }
        case .scrolled(let deltaX, let deltaY):
          guard let wheelDelta = pointerValueDelta(deltaX: deltaX, deltaY: deltaY) else {
            return false
          }

          return withAuthoringContext(dynamicPropertyScope) {
            updateBoundControlValue(
              binding,
              delta: wheelDelta,
              step: step,
              bounds: bounds
            )
          }
        default:
          return false
        }
      }
    }

    let child = sliderBody(
      controlIdentity: context.identity,
      value: currentValue,
      bounds: bounds,
      step: step,
      showsFocusRail: isFocused && showsFocusEffect,
      isHighlighted: (isFocused && showsFocusEffect) || isPressed,
      isActiveNavigation: (isFocused && showsFocusEffect) || isPressed,
      chrome: chrome,
      contentChrome: contentChrome
    ).resolve(
      in: context.child(component: .named("SliderBody"))
    )

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

  @ViewBuilder
  private func sliderBody<Value: AdjustableControlValue>(
    controlIdentity: Identity,
    value: Value,
    bounds: ClosedRange<Value>,
    step: Value,
    showsFocusRail: Bool,
    isHighlighted: Bool,
    isActiveNavigation: Bool,
    chrome: ControlChrome,
    contentChrome: ControlChrome
  ) -> some View {
    let track = sliderTrack(value: value, bounds: bounds)
    let trackStyle =
      isActiveNavigation
      ? contentChrome.borderStyle
      : AnyShapeStyle(.separator)
    let valueStyle =
      isActiveNavigation
      ? contentChrome.foregroundStyle
      : chrome.foregroundStyle
    let trackView = Text(track)
      .foregroundStyle(trackStyle)
      .id(sliderTrackIdentity(for: controlIdentity))
      .semanticMetadata(.init(participatesInPointerHitTesting: true, captureOnPress: true))
    let controls = HStack(alignment: .center, spacing: 1) {
      trackView
      Text(formattedControlValue(value, bounds: bounds, step: step))
        .foregroundStyle(valueStyle)
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
