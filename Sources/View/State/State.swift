package import Core

@MainActor
package struct AuthoringContext {
  var viewIdentity: Identity
  var focusedValues: FocusedValues
  var viewNode: Core.ViewNode?
  var ordinalTracker: AuthoringOrdinalTracker = .init()
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
  private static let changeModifierBase = -1_000_000_000
  private static let defaultFocusBase = -2_000_000_000
  private static let valueAnimationOrdinal = -3_000_000_000

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
  private var boundLocation: DynamicStateLocation<Value>?
  private var retainedValuesByIdentity: [Identity: Value]

  init(
    seedValue: Value,
    slotOrdinal: Int
  ) {
    self.slotOrdinal = slotOrdinal
    self.seedValue = seedValue
    boundLocation = nil
    retainedValuesByIdentity = [:]
  }

  func currentSeedValue() -> Value {
    seedValue
  }

  func updateSeedValue(_ newValue: Value) {
    seedValue = newValue
  }

  func remember(_ location: DynamicStateLocation<Value>) {
    boundLocation = location
  }

  func currentLocation() -> DynamicStateLocation<Value>? {
    boundLocation
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
    activeLocation()?.binding
      ?? Binding(
        mainActorGet: { wrappedValue },
        set: { wrappedValue = $0 }
      )
  }

  private func activeLocation() -> DynamicStateLocation<Value>? {
    if let context = AuthoringContextStorage.current {
      let location = makeLocation(for: context)
      box.remember(location)
      _ = location.getValue()
      return location
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
