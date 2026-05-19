import SwiftTUICore
import SwiftTUIViews

// Runtime environment-action factories (focus reset, clipboard read/write)
// live in `RunLoop+EnvironmentActions.swift`.
extension RunLoop {
  package func resolveContext(
    for scheduledFrame: ScheduledFrame
  ) -> ResolveContext {
    let causeSummary = scheduledFrame.causes
      .map(\.rawValue)
      .sorted()
      .joined(separator: "+")
    var effectiveEnvironmentValues = environmentValues
    effectiveEnvironmentValues.terminalAppearance = presentationSurface.appearance
    effectiveEnvironmentValues.theme = presentationSurface.theme
    effectiveEnvironmentValues.terminalSize = presentationSurface.surfaceSize
    if let cellPixelSize = presentationSurface.graphicsCapabilities.cellPixelSize {
      effectiveEnvironmentValues.cellPixelMetrics = CellPixelMetrics(
        width: cellPixelSize.width,
        height: cellPixelSize.height,
        source: .reported
      )
    } else {
      effectiveEnvironmentValues.cellPixelMetrics = .estimated
    }
    effectiveEnvironmentValues.pointerInputCapabilities =
      presentationSurface.pointerInputCapabilities
    effectiveEnvironmentValues.focusedIdentity = focusTracker.currentFocusIdentity
    effectiveEnvironmentValues.focusedValues = currentFocusedValues
    effectiveEnvironmentValues.pressedIdentity = pressedIdentity
    effectiveEnvironmentValues.accessibilityReduceMotion = runtimeConfiguration.motion == .reduced
    effectiveEnvironmentValues.suppressesProgress = runtimeConfiguration.noProgress
    effectiveEnvironmentValues.cursorFollowsFocus =
      runtimeConfiguration.cursorFollowsFocus
      || usesTerminalCursorForTextInput
    if effectiveEnvironmentValues.openLinkAction.isPlaceholder {
      effectiveEnvironmentValues.openLinkAction = systemOpenLinkAction()
    }
    if effectiveEnvironmentValues.resetFocus.isPlaceholder {
      effectiveEnvironmentValues.resetFocus = runtimeResetFocusAction()
    }
    if effectiveEnvironmentValues.clipboardWriteAction.isPlaceholder {
      effectiveEnvironmentValues.clipboardWriteAction = runtimeClipboardWriteAction()
    }
    if effectiveEnvironmentValues.clipboardReadAction.isPlaceholder {
      effectiveEnvironmentValues.clipboardReadAction = runtimeClipboardReadAction()
    }
    var transactionSnapshot = TransactionSnapshot(debugSignature: causeSummary)
    if runtimeConfiguration.motion == .reduced {
      transactionSnapshot.animationRequest = .disabled
      transactionSnapshot.animationBatchID = nil
    } else {
      transactionSnapshot.animationRequest = scheduledFrame.animationRequest
      transactionSnapshot.animationBatchID = scheduledFrame.animationBatchID
    }
    // Phase 3's ``diffAndEnqueue`` retargets in-flight animations correctly via
    // ``sample(existing, at:)`` + ``effectiveFrom``. The scheduler stays
    // animation-unaware; all retarget state lives on the controller.
    var context = ResolveContext(
      identity: rootIdentity,
      environment: environment,
      environmentValues: effectiveEnvironmentValues,
      transaction: transactionSnapshot,
      invalidatedIdentities: scheduledFrame.invalidatedIdentities,
      localActionRegistry: localActionRegistry,
      localKeyHandlerRegistry: localKeyHandlerRegistry,
      localLifecycleRegistry: localLifecycleRegistry,
      localTaskRegistry: localTaskRegistry,
      applyEnvironmentValues: true
    )
    context.forceRootEvaluation = scheduledFrame.forceRootEvaluation
    context.localPointerHandlerRegistry = localPointerHandlerRegistry
    context.localTerminationRegistry = localTerminationRegistry
    context.localGestureRegistry = localGestureRegistry
    context.localGestureStateRegistry = localGestureStateRegistry
    context.localDefaultFocusRegistry = localDefaultFocusRegistry
    context.localFocusBindingRegistry = localFocusBindingRegistry
    context.localFocusedValuesRegistry = localFocusedValuesRegistry
    context.localScrollPositionRegistry = localScrollPositionRegistry
    context.localPreferenceObservationRegistry = localPreferenceObservationRegistry
    context.commandRegistry = commandRegistry
    context.dropDestinationRegistry = dropDestinationRegistry
    context.invalidationProxy = .init(invalidator: scheduler)
    context.observationBridge = observationBridge
    context.requestDeadline = { [weak scheduler] instant in
      scheduler?.requestDeadline(instant)
    }
    return context
  }

  package func proposal() -> ProposedSize {
    if let proposalOverride {
      return proposalOverride
    }

    let size = presentationSurface.surfaceSize
    return .init(width: size.width, height: size.height)
  }
}
