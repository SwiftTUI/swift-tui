package import SwiftTUICore

private struct FocusStateSnapshot<Value: Equatable> {
  var value: Value
  var hasPendingRequest: Bool
  /// Monotonic count of authored requests (`requestValue` calls). Runtime
  /// re-application carries the generation its resolve-time registration
  /// observed; `applyRuntimeValue` refuses to touch a storage holding a NEWER
  /// authored request. Without this, focus-sync's per-frame binding re-derive
  /// clobbers a request that lands between a frame's resolve and its commit
  /// (an async tail suspension, a mid-frame task write): the value is
  /// overwritten and `hasPendingRequest` cleared before any resolve ever
  /// observes the request. The skipped application is not lost — every
  /// authored request also queues its owner dirty, so a follow-up resolve
  /// re-registers with the new generation and consumes it there.
  var requestGeneration: UInt64
}

@MainActor
private final class FocusStateStorage<Value: Equatable> {
  private var snapshot: FocusStateSnapshot<Value>

  init(
    value: Value,
    hasPendingRequest: Bool = false,
    requestGeneration: UInt64 = 0
  ) {
    snapshot = .init(
      value: value,
      hasPendingRequest: hasPendingRequest,
      requestGeneration: requestGeneration
    )
  }

  func currentSnapshot() -> FocusStateSnapshot<Value> {
    snapshot
  }

  func requestValue(_ newValue: Value) {
    snapshot.value = newValue
    snapshot.hasPendingRequest = true
    snapshot.requestGeneration &+= 1
  }

  @discardableResult
  func applyRuntimeValue(
    _ newValue: Value,
    observedRequestGeneration: UInt64
  ) -> Bool {
    guard observedRequestGeneration == snapshot.requestGeneration else {
      // An authored request landed after the caller's registration was
      // resolved. Consuming it here would destroy a request no resolve has
      // seen yet (see ``FocusStateSnapshot/requestGeneration``); leave the
      // storage untouched and let the request's own invalidation drive the
      // follow-up resolve that consumes it.
      return false
    }
    let didChange = snapshot.value != newValue
    snapshot.value = newValue
    snapshot.hasPendingRequest = false
    return didChange
  }
}

@MainActor
private struct FocusStateLocation<Value: Equatable> {
  var bindingKey: FocusBindingKey
  var bindingID: String
  /// Ensures the backing slot storage exists (seeded from the local box)
  /// WITHOUT recording a read: merely mentioning `$focus` in a body hosts
  /// the storage but presents nothing derived from it, so the touch must not
  /// make the owner a recorded reader of its own slot — that would put the
  /// owner's whole cone back into every runtime flip's reader-attributed
  /// invalidation.
  var prime: () -> Void
  var snapshot: () -> FocusStateSnapshot<Value>
  /// `snapshot` without read attribution, for registry bookkeeping (the
  /// `.focused()` registration's captured `isSelected`/`hasPendingRequest`/
  /// generation): those captures parameterize the focus registry, not the
  /// resolved output — the flip path keeps them fresh by invalidating the
  /// registration identity itself, so recording them as value reads would
  /// only re-broaden the flip cone to the registration's whole hosting node.
  var bookkeepingSnapshot: () -> FocusStateSnapshot<Value>
  var requestValue: (Value) -> Void
  /// Applies a runtime focus flip. `registrationIdentity` is the resolved
  /// identity of the `.focused()` registration site that received the flip;
  /// on a genuine change it is invalidated (alongside the slot's recorded
  /// value readers) so the site re-registers with fresh bookkeeping.
  var applyRuntimeValue:
    (Value, _ observedRequestGeneration: UInt64, _ registrationIdentity: Identity?) -> Bool
}

@MainActor
private final class FocusStateBox<Value: Equatable> {
  private let slotOrdinal: Int

  private struct Storage {
    var localStorage: FocusStateStorage<Value>
    var boundLocation: FocusStateLocation<Value>?
  }

  private var storage: Storage

  init(
    seedValue: Value,
    slotOrdinal: Int
  ) {
    self.slotOrdinal = slotOrdinal
    storage = Storage(
      localStorage: .init(value: seedValue),
      boundLocation: nil
    )
  }

  func currentLocalSnapshot() -> FocusStateSnapshot<Value> {
    storage.localStorage.currentSnapshot()
  }

  func requestLocalValue(_ newValue: Value) {
    storage.localStorage.requestValue(newValue)
  }

  @discardableResult
  func applyRuntimeLocalValue(
    _ newValue: Value,
    observedRequestGeneration: UInt64
  ) -> Bool {
    storage.localStorage.applyRuntimeValue(
      newValue,
      observedRequestGeneration: observedRequestGeneration
    )
  }

  func remember(_ location: FocusStateLocation<Value>) {
    storage.boundLocation = location
  }

  func currentLocation() -> FocusStateLocation<Value>? {
    storage.boundLocation
  }

  var currentOrdinal: Int {
    slotOrdinal
  }
}

@propertyWrapper
@MainActor
/// A focus-owned value synchronized with the runtime focus system.
public struct FocusState<Value: Equatable> {
  /// A projection used by `.focused(...)` modifiers.
  public struct Binding {
    private let location: FocusStateLocation<Value>

    fileprivate init(
      location: FocusStateLocation<Value>
    ) {
      self.location = location
    }

    /// The current authored focus value.
    @MainActor
    public var wrappedValue: Value {
      get { location.snapshot().value }
      nonmutating set { location.requestValue(newValue) }
    }

    public var projectedValue: Self {
      self
    }
  }

  private let box: FocusStateBox<Value>

  private init(
    seedValue: Value,
    line: UInt,
    column: UInt
  ) {
    box = FocusStateBox(
      seedValue: seedValue,
      slotOrdinal: StateSlotOrdinals.authored(
        line: line,
        column: column
      )
    )
  }

  /// Creates a boolean focus state with a default value of `false`.
  public init(
    line: UInt = #line,
    column: UInt = #column
  ) where Value == Bool {
    self.init(
      seedValue: false,
      line: line,
      column: column
    )
  }

  /// Creates an optional focus state with a default value of `nil`.
  public init<Wrapped: Hashable>(
    line: UInt = #line,
    column: UInt = #column
  ) where Value == Wrapped? {
    self.init(
      seedValue: nil,
      line: line,
      column: column
    )
  }

  public var wrappedValue: Value {
    get {
      activeLocation()?.snapshot().value ?? box.currentLocalSnapshot().value
    }
    nonmutating set {
      if let location = activeLocation() {
        location.requestValue(newValue)
      } else {
        box.requestLocalValue(newValue)
      }
    }
  }

  public var projectedValue: Binding {
    Binding(location: activeLocation() ?? localLocation())
  }

  private func activeLocation() -> FocusStateLocation<Value>? {
    if let context = currentAuthoringContext() {
      let location = makeLocation(for: context)
      box.remember(location)
      // Materialize the backing slot (seeded from the local box) without
      // recording a read: mentioning `$focus` hosts the storage, it does not
      // consume the value. Genuine reads go through `snapshot`.
      location.prime()
      return location
    }

    return box.currentLocation()
  }

  private func makeLocation(
    for context: AuthoringContext
  ) -> FocusStateLocation<Value> {
    let ordinal = box.currentOrdinal
    let seedSnapshot = box.currentLocalSnapshot()

    // Imperative contexts (a `.task` loop, an action callback) carry the
    // owner by ID with no live node reference; recover the node the same
    // way `@State`'s imperative location does, so a `$focus` write from a
    // task reaches the live slot instead of silently landing in the
    // detached local box.
    let ownerNode =
      context.viewNode
      ?? liveAuthoringOwnerNode(
        ownerNodeID: context.ownerNodeID,
        stateGraphScope: context.stateGraphScope
      )
    if let viewNode = ownerNode {
      let bindingKey = FocusBindingKey(
        ownerNodeID: viewNode.viewNodeID,
        suffix: .stateSlot(ordinal: ordinal)
      )
      let bindingID = "\(viewNode.identity.path)#FocusState[\(ordinal)]"
      // Resolve the slot storage at CALL time, not capture time: a location's
      // closures outlive the body evaluation that created them (focus-binding
      // registrations are restored across selective frames), while commit-time
      // checkpoint restores can replace the node's stored slot instance. A
      // captured instance goes stale after such a restore — a runtime focus
      // flip would then write a detached ghost and only reach the live slot a
      // frame late, once a re-registration re-captured it.
      //
      // Storage resolution is read-attribution-free (`primedStateSlot`):
      // infrastructure touches (the prime, focus-sync's runtime
      // re-application) are not value reads. Genuine reads record through
      // the `snapshot` closure below.
      let seedValue = seedSnapshot.value
      let seedHasPendingRequest = seedSnapshot.hasPendingRequest
      let seedRequestGeneration = seedSnapshot.requestGeneration
      let liveStorage: @MainActor () -> FocusStateStorage<Value> = {
        viewNode.primedStateSlot(
          ordinal: ordinal,
          seed: FocusStateStorage(
            value: seedValue,
            hasPendingRequest: seedHasPendingRequest,
            requestGeneration: seedRequestGeneration
          )
        )
      }
      let readKey = StateSlotKey(owner: viewNode.viewNodeID, ordinal: ordinal)

      return FocusStateLocation(
        bindingKey: bindingKey,
        bindingID: bindingID,
        prime: {
          _ = liveStorage()
        },
        snapshot: {
          // A value read is a genuine dependency of the node evaluating it
          // (a body read records on the body). Outside resolve there is no
          // evaluated output that could go stale (imperative reads see live
          // storage at call time), so nothing is recorded.
          if let reader = ViewNodeContext.current {
            reader.recordStateReadDependency(readKey)
          }
          return liveStorage().currentSnapshot()
        },
        bookkeepingSnapshot: {
          liveStorage().currentSnapshot()
        },
        requestValue: { newValue in
          liveStorage().requestValue(newValue)
          // An authored request must reach a re-resolve of the registration
          // site to be consumed (`hasPendingRequest` is published at
          // resolve); the owner cone guarantees that regardless of reader
          // attribution.
          viewNode.requestInvalidation()
        },
        applyRuntimeValue: { newValue, observedRequestGeneration, registrationIdentity in
          let didChange = liveStorage().applyRuntimeValue(
            newValue,
            observedRequestGeneration: observedRequestGeneration
          )
          if didChange {
            // Focus-sync applied a runtime flip: invalidate the receiving
            // registration site (so it re-registers with fresh bookkeeping)
            // plus the slot's recorded value readers — not the owner's
            // whole identity cone.
            viewNode.invalidateStateSlotReadersForRuntimeChange(
              ordinal: ordinal,
              registrationScope: registrationIdentity
            )
          }
          return didChange
        }
      )
    }

    return localLocation()
  }

  private func localLocation() -> FocusStateLocation<Value> {
    FocusStateLocation(
      bindingKey: FocusBindingKey(
        ownerNodeID: nil,
        suffix: .local(ObjectIdentifier(box))
      ),
      bindingID: "FocusState.local[\(ObjectIdentifier(box))]",
      prime: {},
      snapshot: {
        box.currentLocalSnapshot()
      },
      bookkeepingSnapshot: {
        box.currentLocalSnapshot()
      },
      requestValue: { newValue in
        box.requestLocalValue(newValue)
      },
      applyRuntimeValue: { newValue, observedRequestGeneration, _ in
        box.applyRuntimeLocalValue(
          newValue,
          observedRequestGeneration: observedRequestGeneration
        )
      }
    )
  }
}

@MainActor
extension FocusState.Binding {
  package var bindingKey: FocusBindingKey {
    location.bindingKey
  }

  package var bindingID: String {
    location.bindingID
  }

  /// Registry bookkeeping (attribution-free): what the `.focused()`
  /// registration captures. These parameterize the focus registry, not the
  /// resolved output; the flip path keeps them fresh by invalidating the
  /// registration identity, so they must not mark the registering node a
  /// value reader.
  package var hasPendingRequest: Bool {
    location.bookkeepingSnapshot().hasPendingRequest
  }

  /// The storage's current value, read attribution-free for registration
  /// bookkeeping (`isSelected`). See ``hasPendingRequest``.
  package var registrationValue: Value {
    location.bookkeepingSnapshot().value
  }

  /// The storage's current authored-request generation. Registration sites
  /// capture this at resolve and pass it back through
  /// ``applyRuntimeValue(_:observedRequestGeneration:registrationIdentity:)``
  /// so runtime re-application can never consume a request the registration
  /// predates.
  package var requestGeneration: UInt64 {
    location.bookkeepingSnapshot().requestGeneration
  }

  package func applyRuntimeValue(
    _ newValue: Value,
    observedRequestGeneration: UInt64,
    registrationIdentity: Identity?
  ) -> Bool {
    location.applyRuntimeValue(
      newValue,
      observedRequestGeneration,
      registrationIdentity
    )
  }
}

extension View {
  public func focused(
    _ binding: FocusState<Bool>.Binding
  ) -> some View {
    modifier(BoolFocusBindingModifier(binding: binding))
  }

  public func focused<Value: Hashable>(
    _ binding: FocusState<Value?>.Binding,
    equals value: Value
  ) -> some View {
    modifier(
      OptionalFocusBindingModifier(
        binding: binding,
        value: value
      )
    )
  }
}

@MainActor
public struct BoolFocusBindingModifier: PrimitiveViewModifier {
  var binding: FocusState<Bool>.Binding

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let node = content.resolve(in: context)
    let observedRequestGeneration = binding.requestGeneration
    let registrationIdentity = node.identity
    context.localFocusBindingRegistry?.register(
      identity: registrationIdentity,
      bindingKey: binding.bindingKey,
      bindingID: binding.bindingID,
      hasPendingRequest: binding.hasPendingRequest,
      isSelected: binding.registrationValue,
      applyRuntimeFocus: { isFocused in
        binding.applyRuntimeValue(
          isFocused,
          observedRequestGeneration: observedRequestGeneration,
          registrationIdentity: registrationIdentity
        )
      }
    )
    return [node]
  }
}

@MainActor
public struct OptionalFocusBindingModifier<Value: Hashable>: PrimitiveViewModifier {
  var binding: FocusState<Value?>.Binding
  var value: Value

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let node = content.resolve(in: context)
    let observedRequestGeneration = binding.requestGeneration
    let registrationIdentity = node.identity
    context.localFocusBindingRegistry?.register(
      identity: registrationIdentity,
      bindingKey: binding.bindingKey,
      bindingID: binding.bindingID,
      hasPendingRequest: binding.hasPendingRequest,
      isSelected: binding.registrationValue == value,
      applyRuntimeFocus: { isFocused in
        if isFocused {
          return binding.applyRuntimeValue(
            value,
            observedRequestGeneration: observedRequestGeneration,
            registrationIdentity: registrationIdentity
          )
        }
        guard binding.registrationValue == value else {
          return false
        }
        return binding.applyRuntimeValue(
          nil,
          observedRequestGeneration: observedRequestGeneration,
          registrationIdentity: registrationIdentity
        )
      }
    )
    return [node]
  }
}
