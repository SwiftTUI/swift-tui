package import SwiftTUICore

// F16 — the single authoring-context capture point for runtime handler
// registration.
//
// Before this seam existed, every registration site hand-rolled three steps:
// capture an `ImperativeAuthoringContextSnapshot`, stamp the authoritative
// `ResolveContext.environmentValues` over the ambient task-local, and bake
// `withImperativeAuthoringContext` into the stored closure. Five divergent
// patterns had accumulated (see docs/plans/2026-07-06-010 in the org root):
// sites that skipped the environment stamp read default `@Environment` values
// at dispatch, and the legacy full-`AuthoringContext` sites additionally
// retained the resolve-time `ViewNode` and never recovered live focused
// values. A missed capture is the stale-`@State`-binding bug family
// (`7e17a984`, `678cc78e`, `c32bf74a`).
//
// `HandlerDescriptorIntake` owns all three steps and the registry forwarding.
// A registration site constructs the intake from its `ResolveContext` and
// hands over the *raw* user closure; the intake wraps it so dispatch always
// runs under the registration-time authoring scope and environment. Sites
// never call `withImperativeAuthoringContext` or a registry `register`
// directly — the totality guard in `HandlerDescriptorIntakeTotalityTests`
// enforces that by source scrape.
//
// The two initializers encode the two capture-preference orders that exist in
// the tree. They differ only in which scope wins when BOTH are available:
//
// - `preferringAuthoringScope:` — the construction-time authoring scope (the
//   enclosing body that owns the handler's dynamic properties) wins; the
//   resolve-time ambient context is the fallback. Control-family order
//   (Button): the user's action closure captures the *enclosing* view's
//   `@State`, so the enclosing body's scope is the correct mutation target.
// - `fallbackAuthoringScope:` / `fallbackSnapshot:` — the resolve-time
//   ambient context wins; the stored scope/snapshot from the public API call
//   site is the fallback for registrations that resolve outside an authoring
//   pass. Modifier-family order (keyCommand, toggle, lifecycle).

@MainActor
package struct HandlerDescriptorIntake {
  /// The captured registration scope every handler this intake registers
  /// dispatches under. Exposed for the two seams that carry the scope as a
  /// value instead of registering directly: gesture recognizer decorators
  /// (the closure fires from recognizer state machines, not a registry
  /// dispatch) and toolbar item configs (pre-wrapped at construction).
  package let dispatchScope: ImperativeAuthoringContextSnapshot?

  private let context: ResolveContext

  package init(
    context: ResolveContext,
    preferringAuthoringScope authoringScope: AuthoringContext?
  ) {
    self.context = context
    let scope = authoringScope ?? currentAuthoringContext()
    dispatchScope =
      (ImperativeAuthoringContextSnapshot(scope)
      ?? currentImperativeAuthoringContextSnapshot())?
      .withEnvironmentValues(context.environmentValues)
  }

  package init(
    context: ResolveContext,
    fallbackAuthoringScope authoringScope: AuthoringContext? = nil
  ) {
    self.context = context
    dispatchScope =
      (currentImperativeAuthoringContextSnapshot()
      ?? ImperativeAuthoringContextSnapshot(authoringScope))?
      .withEnvironmentValues(context.environmentValues)
  }

  package init(
    context: ResolveContext,
    fallbackSnapshot snapshot: ImperativeAuthoringContextSnapshot?
  ) {
    self.context = context
    dispatchScope =
      (currentImperativeAuthoringContextSnapshot() ?? snapshot)?
      .withEnvironmentValues(context.environmentValues)
  }

  /// Control-family order for a site that captured its snapshot at the public
  /// API call: the construction-time snapshot (the enclosing body that owns
  /// the handler's dynamic properties) wins; the resolve-time ambient is the
  /// fallback. A user closure capturing the enclosing view's `@State` must
  /// dispatch under that body's scope — the ambient during a modifier's
  /// resolve names the node currently evaluating, which below a child node
  /// boundary is NOT the closure's owner (the stale-`@State` family).
  package init(
    context: ResolveContext,
    preferringSnapshot snapshot: ImperativeAuthoringContextSnapshot?
  ) {
    self.context = context
    dispatchScope =
      (snapshot ?? currentImperativeAuthoringContextSnapshot())?
      .withEnvironmentValues(context.environmentValues)
  }

  /// The identity a fired handler's follow-up invalidation should target:
  /// the view that authored the registration.
  package var followUpInvalidationIdentity: Identity? {
    dispatchScope?.viewIdentity
  }

  // MARK: Dispatch wrapping

  package func wrapping<Result>(
    _ body: @escaping @MainActor () -> Result
  ) -> @MainActor () -> Result {
    let scope = dispatchScope
    return {
      withImperativeAuthoringContext(scope) {
        body()
      }
    }
  }

  package func wrappingSendable<Result>(
    _ body: @escaping @MainActor @Sendable () -> Result
  ) -> @MainActor @Sendable () -> Result {
    let scope = dispatchScope
    return {
      withImperativeAuthoringContext(scope) {
        body()
      }
    }
  }

  /// Establishes this intake's stamped registration environment as the
  /// ambient storage while `build` runs, leaving the ambient authoring
  /// context untouched. For seams whose handler capture happens inside
  /// nested value builders (gesture recognizer decorators) rather than at a
  /// registry call: the builders self-capture from the ambient, and at a
  /// modifier boundary that ambient environment can predate the attachment
  /// point's environment edits (the c32bf74a gotcha) — this scope makes the
  /// self-capture see the resolve context's authoritative environment.
  package func withRegistrationEnvironmentScope<Result>(
    _ build: () -> Result
  ) -> Result {
    guard let environmentValues = dispatchScope?.environmentValues else {
      return build()
    }
    return EnvironmentValuesStorage.$current.withValue(environmentValues) {
      build()
    }
  }

  // MARK: Action family

  package func registerAction(
    identity: Identity,
    followUpInvalidationIdentity followUp: Identity?? = nil,
    handler: @escaping @MainActor () -> Bool
  ) {
    let scope = dispatchScope
    context.localActionRegistry?.register(
      identity: identity,
      handler: {
        withImperativeAuthoringContext(scope) {
          handler()
        }
      },
      followUpInvalidationIdentity: followUp ?? followUpInvalidationIdentity
    )
  }

  // MARK: Key-event family

  package func registerKeyHandler(
    identity: Identity,
    handler: @escaping @MainActor (KeyEvent) -> Bool
  ) {
    let scope = dispatchScope
    context.localKeyHandlerRegistry?.register(
      identity: identity,
      handler: { event in
        withImperativeAuthoringContext(scope) {
          handler(event)
        }
      }
    )
  }

  package func registerKeyPressHandler(
    identity: Identity,
    handler: @escaping @MainActor (KeyPress) -> Bool
  ) {
    let scope = dispatchScope
    context.localKeyHandlerRegistry?.register(
      identity: identity,
      keyPressHandler: { press in
        withImperativeAuthoringContext(scope) {
          handler(press)
        }
      }
    )
  }

  package func registerPasteHandler(
    identity: Identity,
    handler: @escaping @MainActor (String) -> Bool
  ) {
    let scope = dispatchScope
    context.localKeyHandlerRegistry?.register(
      identity: identity,
      pasteHandler: { content in
        withImperativeAuthoringContext(scope) {
          handler(content)
        }
      }
    )
  }

  // MARK: Pointer family

  package func registerPointerHandler(
    routeID: RouteID,
    handler: @escaping @MainActor (LocalPointerEvent) -> Bool
  ) {
    let scope = dispatchScope
    context.localPointerHandlerRegistry?.register(
      routeID: routeID,
      handler: { event in
        withImperativeAuthoringContext(scope) {
          handler(event)
        }
      }
    )
  }

  package func registerPointerHoverHandler(
    routeID: RouteID,
    handler: @escaping @MainActor @Sendable (HoverPhase) -> Void
  ) {
    let scope = dispatchScope
    context.localPointerHandlerRegistry?.registerHover(
      routeID: routeID,
      handler: { phase in
        withImperativeAuthoringContext(scope) {
          handler(phase)
        }
      }
    )
  }

  // MARK: Termination family

  package func registerTerminationHandler(
    identity: Identity,
    handler: @escaping @MainActor (TerminationRequest) -> TerminationDisposition
  ) {
    let scope = dispatchScope
    context.localTerminationRegistry?.register(
      identity: identity,
      handler: { request in
        withImperativeAuthoringContext(scope) {
          handler(request)
        }
      }
    )
  }

  // MARK: Command family

  package func registerKeyCommand(
    at scope: Identity,
    binding: KeyBinding,
    description: String,
    isEnabled: Bool,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    let dispatchScope = dispatchScope
    context.commandRegistry?.registerKeyCommand(
      at: scope,
      binding: binding,
      description: description,
      isEnabled: isEnabled,
      action: {
        withImperativeAuthoringContext(dispatchScope) {
          action()
        }
      }
    )
  }

  // MARK: Drop-destination family

  package func registerDropDestination(
    at scope: Identity,
    handler: @escaping @MainActor @Sendable ([DroppedPath], DropContext) -> Bool
  ) {
    let dispatchScope = dispatchScope
    context.dropDestinationRegistry?.register(
      at: scope,
      handler: { paths, dropContext in
        withImperativeAuthoringContext(dispatchScope) {
          handler(paths, dropContext)
        }
      }
    )
  }

  // MARK: Scroll-position family

  /// `currentOffset` is a read-only projection consulted during layout and
  /// deliberately not wrapped; `applyOffset` mutates authored state and
  /// dispatches under the captured scope.
  package func registerScrollPosition(
    identity: Identity,
    currentOffset: @escaping @MainActor () -> ScrollOffset,
    applyOffset: @escaping @MainActor (ScrollOffset) -> Void
  ) {
    let scope = dispatchScope
    context.localScrollPositionRegistry?.register(
      identity: identity,
      currentOffset: currentOffset,
      applyOffset: { offset in
        withImperativeAuthoringContext(scope) {
          applyOffset(offset)
        }
      }
    )
  }

  // MARK: Lifecycle family

  package func registerAppearHandler(
    identity: Identity,
    ordinal: Int,
    handler: @escaping @MainActor @Sendable () -> Void
  ) -> String? {
    let scope = dispatchScope
    return context.localLifecycleRegistry?.registerAppear(
      identity: identity,
      ordinal: ordinal,
      handler: {
        withImperativeAuthoringContext(scope) {
          handler()
        }
      }
    )
  }

  package func registerDisappearHandler(
    identity: Identity,
    ordinal: Int,
    handler: @escaping @MainActor @Sendable () -> Void
  ) -> String? {
    let scope = dispatchScope
    return context.localLifecycleRegistry?.registerDisappear(
      identity: identity,
      ordinal: ordinal,
      handler: {
        withImperativeAuthoringContext(scope) {
          handler()
        }
      }
    )
  }

  package func registerChangeHandler(
    identity: Identity,
    ordinal: Int,
    handler: @escaping @MainActor @Sendable () -> Void
  ) -> String? {
    let scope = dispatchScope
    return context.localLifecycleRegistry?.registerChange(
      identity: identity,
      ordinal: ordinal,
      handler: {
        withImperativeAuthoringContext(scope) {
          handler()
        }
      }
    )
  }

  // MARK: Task family

  package func registerTask(
    identity: Identity,
    descriptor: TaskDescriptor,
    operation: @escaping @MainActor @Sendable () async -> Void
  ) {
    let scope = dispatchScope
    context.localTaskRegistry?.register(
      identity: identity,
      registration: .init(
        descriptor: descriptor,
        operation: {
          await withImperativeAuthoringContext(scope) {
            await operation()
          }
        }
      )
    )
  }

  // MARK: Preference-observation family

  package func registerPreferenceObservation<K: PreferenceKey>(
    identity: Identity,
    key: K.Type,
    value: K.Value,
    action: @escaping @MainActor (K.Value) -> Void
  ) where K.Value: Equatable {
    let scope = dispatchScope
    context.localPreferenceObservationRegistry?.register(
      identity: identity,
      key: key,
      value: value,
      action: { newValue in
        withImperativeAuthoringContext(scope) {
          action(newValue)
        }
      }
    )
  }
}
