package import Core

/// Increments or decrements an integer binding.
public struct Stepper: View, ResolvableView {
  public var value: Binding<Int>
  public var bounds: ClosedRange<Int>?
  public var step: Int
  private var labelViews: [AnyView]

  public init<S: StringProtocol>(
    _ title: S,
    value: Binding<Int>,
    in bounds: ClosedRange<Int>? = nil,
    step: Int = 1
  ) {
    self.value = value
    self.bounds = bounds
    self.step = max(1, step)
    labelViews = [AnyView(Text(String(title)))]
  }

  public init<Label: View>(
    value: Binding<Int>,
    in bounds: ClosedRange<Int>? = nil,
    step: Int = 1,
    @ViewBuilder label: () -> Label
  ) {
    self.value = value
    self.bounds = bounds
    self.step = max(1, step)
    labelViews = declaredBuilderChildren(from: label())
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
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let isFocused = context.environmentValues.focusedIdentity == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isPressed = context.environmentValues.pressedIdentity == context.identity
    let isEnabled = context.environmentValues.isEnabled
    let currentValue = clampedControlValue(value.wrappedValue, to: bounds)
    let canDecrement = stepperCanAdjust(currentValue, delta: -step, bounds: bounds)
    let canIncrement = stepperCanAdjust(currentValue, delta: step, bounds: bounds)
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
      let binding = value
      let bounds = bounds
      let step = step
      let dynamicPropertyScope = currentDynamicPropertyScope()
      context.localActionRegistry?.register(
        identity: context.identity,
        handler: {
          withDynamicPropertyScope(dynamicPropertyScope) {
            let next = steppedControlValue(
              from: binding.wrappedValue,
              delta: step,
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
        let delta: Int
        switch event {
        case .arrowLeft:
          delta = -step
        case .arrowRight:
          delta = step
        default:
          return false
        }

        return withDynamicPropertyScope(dynamicPropertyScope) {
          updateBoundIntControlValue(
            binding,
            delta: delta,
            bounds: bounds
          )
        }
      }

      let rootRouteID = primaryRouteID(for: context.identity)
      let decrementRouteID = primaryRouteID(
        for: stepperDecrementIdentity(for: context.identity)
      )
      let incrementRouteID = primaryRouteID(
        for: stepperIncrementIdentity(for: context.identity)
      )

      context.localPointerHandlerRegistry?.register(routeID: rootRouteID) { event in
        guard case .scrolled(let deltaX, let deltaY) = event.kind,
          let wheelDelta = pointerValueDelta(deltaX: deltaX, deltaY: deltaY)
        else {
          return false
        }

        return withDynamicPropertyScope(dynamicPropertyScope) {
          updateBoundIntControlValue(
            binding,
            delta: wheelDelta * step,
            bounds: bounds
          )
        }
      }
      context.localPointerHandlerRegistry?.register(routeID: decrementRouteID) { event in
        guard case .down(.primary) = event.kind else {
          return false
        }

        return withDynamicPropertyScope(dynamicPropertyScope) {
          updateBoundIntControlValue(
            binding,
            delta: -step,
            bounds: bounds
          )
        }
      }
      context.localPointerHandlerRegistry?.register(routeID: incrementRouteID) { event in
        guard case .down(.primary) = event.kind else {
          return false
        }

        return withDynamicPropertyScope(dynamicPropertyScope) {
          updateBoundIntControlValue(
            binding,
            delta: step,
            bounds: bounds
          )
        }
      }
    }

    let child = stepperBody(
      controlIdentity: context.identity,
      value: currentValue,
      canDecrement: canDecrement,
      canIncrement: canIncrement,
      isFocused: (isFocused && showsFocusEffect) || isPressed,
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
        presentationRole: .stepper
      )
    )
  }

  private func stepperBody(
    controlIdentity: Identity,
    value: Int,
    canDecrement: Bool,
    canIncrement: Bool,
    isFocused: Bool,
    isActiveNavigation: Bool,
    chrome: ControlChrome,
    contentChrome: ControlChrome
  ) -> AnyView {
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
    let controls = AnyView(
      HStack(alignment: .center, spacing: 1) {
        decrementControl
        Text("\(value)")
          .foregroundStyle(controlForeground)
        incrementControl
      }
      .drawMetadata(.init(opacity: contentChrome.opacity))
    )
    let decoratedControls =
      if isActiveNavigation {
        AnyView(
          controls.background {
            Rectangle().fill(contentChrome.backgroundStyle)
          }
        )
      } else {
        controls
      }
    let row = AnyView(
      HStack(alignment: .center, spacing: 1) {
        if !labelViews.isEmpty {
          combinedView(from: labelViews, kindName: "StepperLabel")
            .foregroundStyle(.terminalBorder(.accent))
        }
        decoratedControls
      }
      .drawMetadata(.init(opacity: chrome.opacity))
    )

    let body =
      if isFocused {
        AnyView(
          row.background {
            Rectangle().fill(chrome.backgroundStyle)
          }
        )
      } else {
        row
      }

    return body
  }
}

/// Adjusts an integer binding along a bounded linear range.
public struct Slider: View, ResolvableView {
  public var value: Binding<Int>
  public var bounds: ClosedRange<Int>
  public var step: Int
  private var labelViews: [AnyView]

  public init<S: StringProtocol>(
    _ title: S,
    value: Binding<Int>,
    in bounds: ClosedRange<Int>,
    step: Int = 1
  ) {
    self.value = value
    self.bounds = bounds
    self.step = max(1, step)
    labelViews = [AnyView(Text(String(title)))]
  }

  public init<Label: View>(
    value: Binding<Int>,
    in bounds: ClosedRange<Int>,
    step: Int = 1,
    @ViewBuilder label: () -> Label
  ) {
    self.value = value
    self.bounds = bounds
    self.step = max(1, step)
    labelViews = declaredBuilderChildren(from: label())
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
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let isFocused = context.environmentValues.focusedIdentity == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isPressed = context.environmentValues.pressedIdentity == context.identity
    let isEnabled = context.environmentValues.isEnabled
    let currentValue = clampedControlValue(value.wrappedValue, to: bounds)
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
      let binding = value
      let bounds = bounds
      let step = step
      let dynamicPropertyScope = currentDynamicPropertyScope()
      context.localActionRegistry?.register(
        identity: context.identity,
        handler: {
          withDynamicPropertyScope(dynamicPropertyScope) {
            let next = steppedControlValue(
              from: binding.wrappedValue,
              delta: step,
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
        let delta: Int
        switch event {
        case .arrowLeft:
          delta = -step
        case .arrowRight:
          delta = step
        default:
          return false
        }

        return withDynamicPropertyScope(dynamicPropertyScope) {
          updateBoundIntControlValue(
            binding,
            delta: delta,
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

        return withDynamicPropertyScope(dynamicPropertyScope) {
          updateBoundIntControlValue(
            binding,
            delta: wheelDelta * step,
            bounds: bounds
          )
        }
      }
      context.localPointerHandlerRegistry?.register(routeID: trackRouteID) { event in
        switch event.kind {
        case .down(.primary), .dragged(.primary), .up(.primary):
          return withDynamicPropertyScope(dynamicPropertyScope) {
            binding.wrappedValue = sliderValue(
              at: event.location.x,
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

          return withDynamicPropertyScope(dynamicPropertyScope) {
            updateBoundIntControlValue(
              binding,
              delta: wheelDelta * step,
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
      isFocused: (isFocused && showsFocusEffect) || isPressed,
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
        presentationRole: .slider
      )
    )
  }

  private func sliderBody(
    controlIdentity: Identity,
    value: Int,
    isFocused: Bool,
    isActiveNavigation: Bool,
    chrome: ControlChrome,
    contentChrome: ControlChrome
  ) -> AnyView {
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
      .semanticMetadata(.init(participatesInPointerHitTesting: true))
    let controls = AnyView(
      HStack(alignment: .center, spacing: 1) {
        trackView
        Text("\(value)")
          .foregroundStyle(valueStyle)
      }
      .drawMetadata(.init(opacity: contentChrome.opacity))
    )
    let decoratedControls =
      if isActiveNavigation {
        AnyView(
          controls.background {
            Rectangle().fill(contentChrome.backgroundStyle)
          }
        )
      } else {
        controls
      }
    let row = AnyView(
      HStack(alignment: .center, spacing: 1) {
        if !labelViews.isEmpty {
          combinedView(from: labelViews, kindName: "SliderLabel")
            .foregroundStyle(.terminalBorder(.accent))
        }
        decoratedControls
      }
      .drawMetadata(.init(opacity: chrome.opacity))
    )

    let body =
      if isFocused {
        AnyView(
          row.background {
            Rectangle().fill(chrome.backgroundStyle)
          }
        )
      } else {
        row
      }

    return body
  }

  private func sliderTrack(
    value: Int,
    bounds: ClosedRange<Int>
  ) -> String {
    let segmentCount = 8
    let span = max(1, bounds.upperBound - bounds.lowerBound)
    let normalized = Double(value - bounds.lowerBound) / Double(span)
    let position = min(
      max(0, Int((normalized * Double(segmentCount - 1)).rounded())),
      segmentCount - 1
    )

    var characters = Array(repeating: Character("─"), count: segmentCount)
    for index in 0..<position {
      characters[index] = Character("━")
    }
    characters[position] = Character("●")
    return String(characters)
  }
}

@MainActor
private func updateBoundIntControlValue(
  _ binding: Binding<Int>,
  delta: Int,
  bounds: ClosedRange<Int>?
) -> Bool {
  let next = steppedControlValue(
    from: binding.wrappedValue,
    delta: delta,
    bounds: bounds
  )
  guard next != binding.wrappedValue else {
    return false
  }
  binding.wrappedValue = next
  return true
}
