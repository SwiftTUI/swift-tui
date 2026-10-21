public import SwiftTUICore

extension FocusState: HotReloadSlotDeclaring {
  package func hotReloadDeclaration(path: StateSlotPath) -> (StateSlotIdentifier, String)? {
    (
      .init(ordinal: box.currentOrdinal, path: path),
      String(reflecting: FocusStateStorage<Value>.self)
    )
  }
}

private struct FocusStateSnapshot<Value: Equatable>: Equatable {
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

private struct FocusStateStorage<Value: Equatable>: Equatable {
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

  mutating func requestValue(_ newValue: Value) {
    snapshot.value = newValue
    snapshot.hasPendingRequest = true
    snapshot.requestGeneration &+= 1
  }

  @discardableResult
  mutating func applyRuntimeValue(
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

extension FocusStateStorage: Encodable where Value: Encodable {
  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(snapshot.value)
  }
}

extension FocusStateStorage: Decodable where Value: Decodable {
  init(from decoder: any Decoder) throws {
    self.init(value: try decoder.singleValueContainer().decode(Value.self), hasPendingRequest: true)
  }
}

@MainActor
private final class FocusStateStorageCell<Value: Equatable> {
  private var storage: FocusStateStorage<Value>

  init(_ storage: FocusStateStorage<Value>) {
    self.storage = storage
  }

  func currentSnapshot() -> FocusStateSnapshot<Value> {
    storage.currentSnapshot()
  }

  func requestValue(_ newValue: Value) {
    storage.requestValue(newValue)
  }

  @discardableResult
  func applyRuntimeValue(
    _ newValue: Value,
    observedRequestGeneration: UInt64
  ) -> Bool {
    storage.applyRuntimeValue(
      newValue,
      observedRequestGeneration: observedRequestGeneration
    )
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
  let clearValue: Value

  private struct FallbackKey: Hashable {
    var owner: StateOwnerHandle
    var slot: StateSlotIdentifier
  }

  private let localStorage: FocusStateStorageCell<Value>
  private var locations: [FallbackKey: FocusStateLocation<Value>] = [:]
  private var selectedSlots: [StateOwnerHandle: StateSlotIdentifier] = [:]
  private var fallbackStorageByOwnerAndSlot: [FallbackKey: FocusStateStorageCell<Value>] = [:]

  init(
    seedValue: Value,
    slotOrdinal: Int
  ) {
    self.slotOrdinal = slotOrdinal
    clearValue = seedValue
    localStorage = FocusStateStorageCell(.init(value: seedValue))
  }

  func currentLocalSnapshot() -> FocusStateSnapshot<Value> {
    localStorage.currentSnapshot()
  }

  func requestLocalValue(_ newValue: Value) {
    localStorage.requestValue(newValue)
  }

  var localStorageCell: FocusStateStorageCell<Value> {
    localStorage
  }

  func remember(
    _ location: FocusStateLocation<Value>,
    for owner: StateOwnerHandle,
    path: StateSlotPath = .root
  ) {
    // Prepared copies and retained Bindings own their resolver locations.
    // The shared box caches only live owners, never retired graph nodes.
    let retired = selectedSlots.keys.filter { LiveViewGraphRegistry.node(for: $0) == nil }
    if !retired.isEmpty {
      let retired = Set(retired)
      selectedSlots = selectedSlots.filter { !retired.contains($0.key) }
      locations = locations.filter { !retired.contains($0.key.owner) }
      fallbackStorageByOwnerAndSlot = fallbackStorageByOwnerAndSlot.filter {
        !retired.contains($0.key.owner)
      }
    }
    let slot = StateSlotIdentifier(ordinal: slotOrdinal, path: path)
    locations[FallbackKey(owner: owner, slot: slot)] = location
    selectedSlots[owner] = slot
  }

  func currentLocation(for owner: StateOwnerHandle) -> FocusStateLocation<Value>? {
    guard let slot = selectedSlots[owner] else { return nil }
    return locations[FallbackKey(owner: owner, slot: slot)]
  }

  func location(for owner: StateOwnerHandle, path: StateSlotPath) -> FocusStateLocation<Value>? {
    locations[FallbackKey(owner: owner, slot: .init(ordinal: slotOrdinal, path: path))]
  }

  func currentPathQualifiedLocation(
    for owner: StateOwnerHandle
  ) -> FocusStateLocation<Value>? {
    guard let slot = selectedSlots[owner], !slot.path.isEmpty else { return nil }
    return locations[FallbackKey(owner: owner, slot: slot)]
  }

  var rememberedLocationCount: Int { locations.count }

  func fallbackStorageCell(
    for owner: StateOwnerHandle,
    slot: StateSlotIdentifier,
    seed: FocusStateStorage<Value>
  ) -> FocusStateStorageCell<Value> {
    let key = FallbackKey(owner: owner, slot: slot)
    if let storage = fallbackStorageByOwnerAndSlot[key] {
      return storage
    }
    let storage = FocusStateStorageCell(seed)
    fallbackStorageByOwnerAndSlot[key] = storage
    return storage
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
  // An indirect resolver, never a graph node or mutable graph-slot cell.
  private var capturedLocation: FocusStateLocation<Value>?
  package var focusDomain: FocusBindingDomain = .keyboard

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

  #if DEBUG
    package var rememberedLocationCountForTesting: Int { box.rememberedLocationCount }

    package var debugStorageObject: AnyObject {
      box
    }
  #endif

  private func activeLocation() -> FocusStateLocation<Value>? {
    // A prepared copy is authoritative even in a callback nested inside a
    // different evaluation. The location attributes reads to the actual
    // evaluating reader while resolving storage through this exact owner.
    if let capturedLocation {
      #if DEBUG
        if let owner = capturedLocation.bindingKey.owner,
          LiveViewGraphRegistry.node(for: owner) == nil
        {
          StateCaptureCensus.record(.focusRetired)
        }
      #endif
      return capturedLocation
    }
    StateCaptureCensus.record(.focusUnprepared)
    if let context = currentAuthoringContext(),
      let owner = stateStorageOwner(for: context)
    {
      // A path-qualified binding made by this evaluation's update pass wins
      // during resolve — re-making here has no ambient path and would claim
      // (and prime) the unqualified slot (see `State.activeLocation`).
      if ViewNodeContext.current != nil,
        let qualified = box.currentPathQualifiedLocation(for: owner)
      {
        return qualified
      }
      if ViewNodeContext.current == nil,
        let remembered = box.currentLocation(for: owner)
      {
        return remembered
      }
      let location = makeLocation(owner: owner)
      box.remember(location, for: owner)
      // Materialize the backing slot (seeded from the local box) without
      // recording a read: mentioning `$focus` hosts the storage, it does not
      // consume the value. Genuine reads go through `snapshot`.
      location.prime()
      return location
    }

    return nil
  }

  private func makeLocation(
    owner: StateOwnerHandle,
    path: StateSlotPath = .root
  ) -> FocusStateLocation<Value> {
    let slotIdentifier = StateSlotIdentifier(ordinal: box.currentOrdinal, path: path)
    let seedSnapshot = box.currentLocalSnapshot()
    let seedStorage = FocusStateStorage(
      value: seedSnapshot.value,
      hasPendingRequest: seedSnapshot.hasPendingRequest,
      requestGeneration: seedSnapshot.requestGeneration
    )

    if ViewNodeContext.current != nil,
      let viewNode = liveAuthoringOwnerNode(stateOwnerHandle: owner)
    {
      viewNode.recordStateSlotClaim(
        slotIdentifier,
        claimant: ObjectIdentifier(box),
        wrapperDescription: "@FocusState<\(Value.self)>"
      )
    }

    let bindingKey = FocusBindingKey(
      owner: owner,
      suffix: path.isEmpty
        ? .stateSlot(ordinal: slotIdentifier.ordinal)
        : .pathQualifiedStateSlot(slotIdentifier)
    )
    let bindingID =
      "graph:\(owner.graphScope.rawValue)/owner:\(owner.ownerLifetime.rawValue)"
      + "#FocusState[\(slotIdentifier)]"
    let readKey = StateSlotKey(owner: owner.ownerLifetime, slot: slotIdentifier)
    let fallbackStorage = box.fallbackStorageCell(
      for: owner,
      slot: slotIdentifier,
      seed: seedStorage
    )

    let liveStorage: @MainActor () -> (SwiftTUICore.ViewNode, FocusStateStorage<Value>)? = {
      guard let node = LiveViewGraphRegistry.node(for: owner) else {
        return nil
      }
      let storage = withPersistentDormantStateSlot {
        node.primedStateSlot(slotIdentifier, seed: seedStorage)
      }
      return (node, storage)
    }
    let storeAuthoredLiveStorage:
      @MainActor (
        SwiftTUICore.ViewNode,
        FocusStateStorage<Value>
      ) -> Void = { node, storage in
        withPersistentDormantStateSlot {
          node.setStateSlot(
            slotIdentifier,
            value: storage,
            invalidationIdentity: node.identity
          )
        }
      }
    let storeRuntimeLiveStorage:
      @MainActor (
        SwiftTUICore.ViewNode,
        FocusStateStorage<Value>
      ) -> Void = { node, storage in
        withPersistentDormantStateSlot {
          _ = node.setStateSlotRecordingMutationWithoutGenericInvalidation(
            slotIdentifier,
            value: storage
          )
        }
      }

    return FocusStateLocation(
      bindingKey: bindingKey,
      bindingID: bindingID,
      prime: {
        if liveStorage() == nil {
          _ = fallbackStorage.currentSnapshot()
        }
      },
      snapshot: {
        if let reader = ViewNodeContext.current {
          reader.recordStateReadDependency(readKey)
        }
        if let (_, storage) = liveStorage() {
          return storage.currentSnapshot()
        }
        return fallbackStorage.currentSnapshot()
      },
      bookkeepingSnapshot: {
        if let (_, storage) = liveStorage() {
          return storage.currentSnapshot()
        }
        return fallbackStorage.currentSnapshot()
      },
      requestValue: { newValue in
        guard let (node, current) = liveStorage() else {
          fallbackStorage.requestValue(newValue)
          return
        }
        var storage = current
        storage.requestValue(newValue)
        storeAuthoredLiveStorage(node, storage)
        node.requestInvalidation()
      },
      applyRuntimeValue: { newValue, observedRequestGeneration, registrationIdentity in
        guard let (node, current) = liveStorage(),
          current.currentSnapshot().requestGeneration == observedRequestGeneration
        else {
          // Runtime registrations are generation-specific and never mutate a
          // retired owner's fallback or a replacement lifetime.
          return false
        }
        var storage = current
        let didChange = storage.applyRuntimeValue(
          newValue,
          observedRequestGeneration: observedRequestGeneration
        )
        storeRuntimeLiveStorage(node, storage)
        if didChange {
          node.invalidateStateSlotReadersForRuntimeChange(
            slotIdentifier,
            registrationScope: registrationIdentity
          )
        }
        return didChange
      }
    )
  }

  private func localLocation() -> FocusStateLocation<Value> {
    let localStorage = box.localStorageCell
    return FocusStateLocation(
      bindingKey: FocusBindingKey(
        owner: nil,
        suffix: .local(ObjectIdentifier(localStorage))
      ),
      bindingID: "FocusState.local[\(ObjectIdentifier(localStorage))]",
      prime: {},
      snapshot: {
        localStorage.currentSnapshot()
      },
      bookkeepingSnapshot: {
        localStorage.currentSnapshot()
      },
      requestValue: { newValue in
        localStorage.requestValue(newValue)
      },
      applyRuntimeValue: { newValue, observedRequestGeneration, _ in
        localStorage.applyRuntimeValue(
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

extension FocusState: CaptureBindableDynamicProperty {
  package mutating func bindCapture(_ context: DynamicPropertyCaptureContext) {
    guard let slot = context.ownedSlot else {
      capturedLocation = nil
      return
    }
    if let existing = box.location(for: slot.owner, path: slot.path) {
      capturedLocation = existing
    } else {
      let location = makeLocation(owner: slot.owner, path: slot.path)
      box.remember(location, for: slot.owner, path: slot.path)
      capturedLocation = location
    }
  }
}

extension FocusState: DynamicProperty {
  /// Publishes the storage owner's request independently of mounted targets.
  /// Composed wrappers use their discovered-property path; top-level wrappers
  /// keep their existing unqualified FocusBindingKey.
  public func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    let path = DynamicPropertyPathScope.current
    guard
      ViewNodeContext.current != nil,
      let context = currentAuthoringContext(),
      let owner = stateStorageOwner(for: context)
    else {
      return .unchanged
    }
    let location = makeLocation(owner: owner, path: path)
    box.remember(location, for: owner, path: path)
    location.prime()
    let snapshot = location.bookkeepingSnapshot()
    let clearValue = box.clearValue
    let identity = context.viewIdentity
    ViewNodeContext.current?.recordFocusBindingSource(
      .init(
        identity: identity, bindingKey: location.bindingKey, domain: focusDomain,
        requestGeneration: snapshot.requestGeneration,
        hasPendingRequest: snapshot.hasPendingRequest,
        requestsClear: snapshot.value == clearValue,
        isCurrentRequest: {
          let current = location.bookkeepingSnapshot()
          return current.hasPendingRequest
            && current.requestGeneration == snapshot.requestGeneration
        },
        clearRuntimeValue: {
          location.applyRuntimeValue(clearValue, snapshot.requestGeneration, nil)
        }))
    return .unchanged
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
public struct BoolFocusBindingModifier: IterativePrimitiveViewModifier {
  var binding: FocusState<Bool>.Binding

  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    return content.resolveWork(in: context).map { completed in
      let node = completed
      let observedRequestGeneration = binding.requestGeneration
      let registrationIdentity = node.identity
      context.localFocusBindingRegistry?.register(
        identity: registrationIdentity,
        bindingKey: binding.bindingKey,
        bindingID: binding.bindingID,
        hasPendingRequest: binding.hasPendingRequest,
        isSelected: binding.registrationValue,
        requestGeneration: observedRequestGeneration,
        requestsClear: !binding.registrationValue,
        isCurrentRequest: {
          binding.hasPendingRequest && binding.requestGeneration == observedRequestGeneration
        },
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
}

@MainActor
public struct OptionalFocusBindingModifier<Value: Hashable>: IterativePrimitiveViewModifier {
  var binding: FocusState<Value?>.Binding
  var value: Value

  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    return content.resolveWork(in: context).map { completed in
      let node = completed
      let observedRequestGeneration = binding.requestGeneration
      let registrationIdentity = node.identity
      context.localFocusBindingRegistry?.register(
        identity: registrationIdentity,
        bindingKey: binding.bindingKey,
        bindingID: binding.bindingID,
        hasPendingRequest: binding.hasPendingRequest,
        isSelected: binding.registrationValue == value,
        requestGeneration: observedRequestGeneration,
        requestsClear: binding.registrationValue == nil,
        isCurrentRequest: {
          binding.hasPendingRequest && binding.requestGeneration == observedRequestGeneration
        },
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
}
