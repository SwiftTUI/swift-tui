package import Core

@MainActor
package struct AuthoringContext {
  /// Owner identity — used for invalidation routing, `@State` ownership,
  /// and follow-up identity captured by control action closures. Stable
  /// across per-iteration content expansion inside containers like
  /// `ForEach`; identifies the view struct currently authoring, not the
  /// structural position of a repeated child.
  var viewIdentity: Identity
  /// Structural identity — the authoring "position" in the view tree.
  /// Identity-deriving modifiers such as `.panel()` read this so they
  /// can distinguish per-iteration instances inside a `ForEach`. At the
  /// outermost authoring scope this equals `viewIdentity`; container
  /// iteration (e.g. `ForEach`) is the only context that diverges them.
  var structuralIdentity: Identity
  var focusedValues: FocusedValues
  var viewNode: Core.ViewNode?
  var ordinalTracker: AuthoringOrdinalTracker = .init()

  /// Primary initializer. `structuralIdentity` defaults to `viewIdentity`
  /// so non-iterating construction sites (the common case) need not
  /// distinguish the two — they're equal. `ForEach` is the only writer
  /// that currently diverges them by supplying a per-iteration
  /// `structuralIdentity`.
  init(
    viewIdentity: Identity,
    structuralIdentity: Identity? = nil,
    focusedValues: FocusedValues,
    viewNode: Core.ViewNode? = nil,
    ordinalTracker: AuthoringOrdinalTracker = .init()
  ) {
    self.viewIdentity = viewIdentity
    self.structuralIdentity = structuralIdentity ?? viewIdentity
    self.focusedValues = focusedValues
    self.viewNode = viewNode
    self.ordinalTracker = ordinalTracker
  }
}

package enum AuthoringContextStorage {
  @TaskLocal static var current: AuthoringContext?
}

@MainActor
package func currentAuthoringContext() -> AuthoringContext? {
  AuthoringContextStorage.current
}

@MainActor
package func makeAuthoringContext(
  for context: ResolveContext,
  viewNode: Core.ViewNode? = ViewNodeContext.current
) -> AuthoringContext {
  AuthoringContext(
    viewIdentity: context.identity,
    focusedValues: context.focusedValues,
    viewNode: viewNode,
    ordinalTracker: .init()
  )
}

@MainActor
package func dynamicPropertyAuthoringContext(
  for context: ResolveContext,
  current: AuthoringContext? = currentAuthoringContext(),
  viewNode: Core.ViewNode? = ViewNodeContext.current
) -> AuthoringContext {
  if let current, current.viewNode === viewNode {
    return AuthoringContext(
      viewIdentity: context.identity,
      focusedValues: context.focusedValues,
      viewNode: viewNode,
      ordinalTracker: current.ordinalTracker
    )
  }

  return makeAuthoringContext(
    for: context,
    viewNode: viewNode
  )
}

@MainActor
package func makeDeferredAuthoringContext(
  from context: AuthoringContext? = currentAuthoringContext()
) -> AuthoringContext? {
  guard let context else {
    return nil
  }

  let ordinalTracker = AuthoringOrdinalTracker()
  ordinalTracker.freeze()
  return AuthoringContext(
    viewIdentity: context.viewIdentity,
    focusedValues: context.focusedValues,
    viewNode: context.viewNode,
    ordinalTracker: ordinalTracker
  )
}

@MainActor
package func withAuthoringContext<Result>(
  _ context: AuthoringContext?,
  _ apply: () -> Result
) -> Result {
  AuthoringContextStorage.$current.withValue(context) {
    apply()
  }
}

@MainActor
package func withAuthoringContext<Result>(
  _ context: AuthoringContext?,
  _ apply: () async -> Result
) async -> Result {
  await AuthoringContextStorage.$current.withValue(context) {
    await apply()
  }
}

@MainActor
package final class AuthoringOrdinalTracker {
  private(set) var nextOrdinal = 0
  private var frozen = false

  package init() {}

  /// Prevents new ordinal claims.  Existing cached ordinals on `StateBox`
  /// instances are unaffected — only first-time claims are blocked.
  package func freeze() {
    frozen = true
  }

  package func claimOrdinal() -> Int? {
    guard !frozen else { return nil }
    defer {
      nextOrdinal += 1
    }
    return nextOrdinal
  }
}

package enum StateSlotOrdinals {
  private static let authoredColumnBits = 16
  private static let changeModifierBase = -1_000_000
  private static let defaultFocusBase = -2_000_000
  private static let valueAnimationOrdinal = -3_000_000

  package static func authored(
    line: UInt,
    column: UInt
  ) -> Int {
    (Int(line) << authoredColumnBits) | Int(column)
  }

  package static func changeModifier(
    _ ordinal: Int
  ) -> Int {
    changeModifierBase - ordinal
  }

  package static func defaultFocus(
    _ ordinal: Int
  ) -> Int {
    defaultFocusBase - ordinal
  }

  package static var valueAnimation: Int {
    valueAnimationOrdinal
  }
}

@MainActor
private struct DynamicStateLocation<Value> {
  var getValue: @MainActor () -> Value
  var setValue: @MainActor (Value) -> Void

  var binding: Binding<Value> {
    Binding(
      mainActorGet: getValue,
      set: setValue
    )
  }
}

@MainActor
private final class StateBox<Value> {
  private let slotOrdinal: Int
  private var seedValue: Value
  private var boundLocationsByIdentity: [Identity: DynamicStateLocation<Value>]
  private var lastBoundIdentity: Identity?
  private var retainedValuesByIdentity: [Identity: Value]

  init(
    seedValue: Value,
    slotOrdinal: Int
  ) {
    self.slotOrdinal = slotOrdinal
    self.seedValue = seedValue
    boundLocationsByIdentity = [:]
    lastBoundIdentity = nil
    retainedValuesByIdentity = [:]
  }

  func currentSeedValue() -> Value {
    seedValue
  }

  func updateSeedValue(_ newValue: Value) {
    seedValue = newValue
  }

  /// Stores `location` under the concrete view identity it targets so the
  /// same box can serve multiple renderers of the same view struct without
  /// overwriting each other's storage, and so callers whose task-local
  /// authoring context doesn't include the @State's owning view (the classic
  /// case: a closure captured inside a wrapper view) can still find a
  /// valid location to mutate.
  func remember(_ location: DynamicStateLocation<Value>, for identity: Identity) {
    boundLocationsByIdentity[identity] = location
    lastBoundIdentity = identity
  }

  /// Looks up a previously-remembered location for exactly `identity`.
  func rememberedLocation(for identity: Identity) -> DynamicStateLocation<Value>? {
    boundLocationsByIdentity[identity]
  }

  /// The most recently remembered location across all identities — the
  /// fallback used when the current task-local context doesn't resolve
  /// to any known binding (e.g. the caller is a wrapper view whose
  /// identity isn't the @State's owner).
  func currentLocation() -> DynamicStateLocation<Value>? {
    guard let lastBoundIdentity else { return nil }
    return boundLocationsByIdentity[lastBoundIdentity]
  }

  func retainedValue(
    for identity: Identity
  ) -> Value? {
    retainedValuesByIdentity[identity]
  }

  func storeRetainedValue(
    _ value: Value,
    for identity: Identity
  ) {
    retainedValuesByIdentity[identity] = value
  }

  var currentOrdinal: Int {
    slotOrdinal
  }
}

@propertyWrapper
@MainActor
/// Local value storage owned by a view identity.
///
/// `@State` persistence is keyed by the view's identity path plus source
/// location within that view.
public struct State<Value> {
  private let box: StateBox<Value>

  /// Creates state with the supplied initial wrapped value.
  public init(
    wrappedValue: Value,
    line: UInt = #line,
    column: UInt = #column
  ) {
    box = StateBox(
      seedValue: wrappedValue,
      slotOrdinal: StateSlotOrdinals.authored(
        line: line,
        column: column
      )
    )
  }

  public init(
    initialValue: Value,
    line: UInt = #line,
    column: UInt = #column
  ) {
    box = StateBox(
      seedValue: initialValue,
      slotOrdinal: StateSlotOrdinals.authored(
        line: line,
        column: column
      )
    )
  }

  public var wrappedValue: Value {
    get {
      activeLocation()?.getValue() ?? box.currentSeedValue()
    }
    nonmutating set {
      if let location = activeLocation() {
        location.setValue(newValue)
      } else {
        box.updateSeedValue(newValue)
      }
    }
  }

  public var projectedValue: Binding<Value> {
    return activeLocation()?.binding
      ?? Binding(
        mainActorGet: { wrappedValue },
        set: { wrappedValue = $0 }
      )
  }

  private func activeLocation() -> DynamicStateLocation<Value>? {
    if let context = AuthoringContextStorage.current {
      // We're in a resolve pass (the current view's body is being
      // evaluated). Build — or refresh — the location bound to that
      // view's identity. Refreshing on every resolve is important
      // because the same view struct can be hosted by several
      // independent renderers/ViewGraphs concurrently, and each render
      // pass in each graph needs to bind the @State to *its* ViewNode
      // rather than whichever graph resolved last.
      if ViewNodeContext.current != nil {
        let location = makeLocation(for: context)
        box.remember(location, for: context.viewIdentity)
        _ = location.getValue()
        return location
      }
      // Not in a resolve pass — we're inside an action or lifecycle
      // callback. Look up the location bound to whichever view identity
      // the task-local context is scoped to. If that identity never
      // touched this @State directly (the classic case: a Button inside
      // a wrapper view whose action closure captured `self` from the
      // wrapper's *parent*), there will be no entry. Fall back to the
      // most recently bound identity, which is the @State's true owning
      // view.
      if let existing = box.rememberedLocation(for: context.viewIdentity) {
        return existing
      }
    }

    return box.currentLocation()
  }

  private func makeLocation(
    for context: AuthoringContext
  ) -> DynamicStateLocation<Value> {
    let ordinal = box.currentOrdinal
    let retainedSeed = box.retainedValue(for: context.viewIdentity) ?? box.currentSeedValue()

    if let viewNode = context.viewNode {
      return DynamicStateLocation(
        getValue: {
          viewNode.stateSlot(
            ordinal: ordinal,
            seed: retainedSeed
          )
        },
        setValue: { newValue in
          viewNode.setStateSlot(ordinal: ordinal, value: newValue)
          box.storeRetainedValue(newValue, for: context.viewIdentity)
        }
      )
    }

    return DynamicStateLocation(
      getValue: { box.currentSeedValue() },
      setValue: { newValue in
        box.updateSeedValue(newValue)
      }
    )
  }
}

extension View {
  @MainActor
  func resolveBody(
    in context: ResolveContext,
    body makeBody: () -> Body
  ) -> [ResolvedNode] {
    if let authoringContext = currentAuthoringContext() {
      let body = context.trackingObservableAccess {
        makeBody()
      }
      return withAuthoringContext(authoringContext) {
        body.resolveElements(in: context)
      }
    }

    let authoringContext = makeAuthoringContext(for: context)
    return withAuthoringContext(authoringContext) {
      let body = context.trackingObservableAccess {
        makeBody()
      }
      return body.resolveElements(in: context)
    }
  }
}
