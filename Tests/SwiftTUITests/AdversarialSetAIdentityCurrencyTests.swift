@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized, FailOnSoundnessViolationGrowth(), .timeLimit(.minutes(1)))
struct AdversarialSetAIdentityCurrencyTests {
  @Test func setA751DistinctComponentSequencesRemainTotallyOrdered() {
    // Hypothesis: joined display paths make two unequal public Identity values incomparable.
    // Identity publicly promises Comparable; neither init(components:) nor child(String) restricts slashes.
    let left = Identity(components: ["workspace/files", "item"])
    let right = Identity(components: ["workspace", "files/item"])
    #expect(left.path == right.path)
    #expect(left != right)
    #expect(Set([left, right]).count == 2)
    do {
      #expect(left < right || right < left)
    }
  }

  @Test func setA752EscapedExplicitIDsCannotAliasLiteralEscapeSequences() {
    // Hypothesis: percent escaping happens after slash escaping, collapsing a slash and an authored percent sequence.
    let root = testIdentity("SetA752")
    let slash = root.explicitID("a/b")
    let percent = root.explicitID("a%2Fb")
    let nested = root.explicitID("a").child("b")
    #expect(Set([slash, percent, nested]).count == 3)
    #expect(slash.components.count == root.components.count + 1)
    #expect(!slash.lastComponent!.contains("/"))
    #expect(percent.lastComponent!.contains("%252F"))
    #expect(slash.parent == root && percent.parent == root)
  }

  @Test func setA753OccurrenceStrippingPreservesAnAuthoredDebugIDSuffix() {
    // Hypothesis: a custom Hashable ID's unquoted debug text ending in #digits is mistaken for a generated occurrence.
    // GeometryTypes promises authored # characters survive; semantic extraction applies this helper to every node.
    let root = testIdentity("SetA753")
    let authored = root.explicitID(SetACurrencyDebugID(value: "entry#12"))
    let repeated = root.explicitID(SetACurrencyDebugID(value: "entry#12"), occurrence: 2)
    #expect(authored != root.explicitID(SetACurrencyDebugID(value: "entry")))
    #expect(repeated.strippingEntityOccurrences == authored)
    do {
      #expect(authored.strippingEntityOccurrences == authored)
    }
  }

  @Test func setA754ErasedIDsKeepConcreteTypesAndCollidingValuesDistinct() {
    // Hypothesis: type-erased identity uses only a hash or coerces equal-looking numeric types into one owner.
    let one = AnyID(SetACurrencyCollidingID(value: 1))
    let two = AnyID(SetACurrencyCollidingID(value: 2))
    let same = AnyID(SetACurrencyCollidingID(value: 1))
    #expect(one == same && one.hashValue == same.hashValue)
    #expect(one != two)
    let values: Set<AnyID> = [one, two, same, AnyID(Int(1)), AnyID(Int8(1))]
    #expect(values.count == 4)
  }

  @Test func setA755AnInitializedNilSlotDoesNotEvaluateItsReplacementSeed() {
    // Hypothesis: an initialized Optional.none is treated as empty storage and evaluates a later lazy seed.
    var slot = AnyStateSlot(Optional<Int>.none)
    var seedEvaluations = 0
    func replacement() -> Int? {
      seedEvaluations += 1
      return 47
    }
    slot.initializeIfNeeded(with: replacement())
    #expect(slot.isInitialized && slot.stores(Int?.self))
    #expect(slot.value(as: Int?.self) == nil)
    #expect(seedEvaluations == 0)
  }

  @Test func setA756DormantReconstructionKeepsItsEquatableComparator() throws {
    // Hypothesis: reconstructing type-erased dormant storage replaces its concrete comparator with always-changed equality.
    let slot = withPersistentDormantStateSlot { AnyStateSlot(SetACurrencyPair(x: 2, y: 9)) }
    let snapshot = try #require(slot.dormantSnapshot())
    var restored = AnyStateSlot(restoringDormant: snapshot)
    let unchanged = restored.set(SetACurrencyPair(x: 2, y: 9))
    let changed = restored.set(SetACurrencyPair(x: 2, y: 10))
    let repeated = restored.set(SetACurrencyPair(x: 2, y: 10))
    #expect(!unchanged)
    #expect(changed)
    #expect(!repeated)
    #expect(restored.value(as: SetACurrencyPair.self) == .init(x: 2, y: 10))
  }

  @Test func setA757EquatableReferencePayloadsCannotCertifyScalarMemoReads() {
    // Hypothesis: an Equatable container containing a mutable reference is certified by its slot's unchanged store token.
    let model = SetACurrencyModel(value: 3)
    let slot = AnyStateSlot(SetACurrencyReferenceEnvelope(model: model))
    let token = slot.valueIdentity
    #expect(AnyStateSlot(3).memoReadVersion != nil)
    #expect(slot.memoReadVersion == nil)
    model.value = 8
    #expect(slot.valueIdentity === token)
    #expect(slot.value(as: SetACurrencyReferenceEnvelope.self).model.value == 8)
    #expect(slot.memoReadVersion == nil)
  }

  @Test func setA758AStoredSlotsDormancyPolicySurvivesWritesFromAnotherScope() throws {
    // Hypothesis: an imperative write adopts the current policy scope and silently reclassifies existing persistent state.
    var persistent = withPersistentDormantStateSlot { AnyStateSlot(1) }
    var transient = withTransientDormantStateSlot { AnyStateSlot(2) }
    withTransientDormantStateSlot { _ = persistent.set(7) }
    withOwnedDormantStateSlot { _ = transient.set(8) }
    #expect(persistent.dormantPolicy == .persistent)
    #expect(transient.dormantPolicy == .transient)
    let archived = try #require(persistent.dormantSnapshot())
    #expect(AnyStateSlot(restoringDormant: archived).value(as: Int.self) == 7)
    #expect(transient.dormantSnapshot() == nil)
  }

  @Test func setA759NestedComposedPropertiesKeepTheirQualifiedSlotsDistinct() throws {
    // Hypothesis: two nested instances sharing an inner State source location collapse onto the same discovered-property path.
    let h = try make(759) { SetACurrencyComposedHost() }
    defer { h.shutdown() }
    try h.clickText("Increment first")
    try h.clickText("Increment second")
    try h.clickText("Increment second")
    #expect(h.frame.contains("first=1 second=2"), "\(h.frame)")
    try h.clickText("Increment first")
    #expect(h.frame.contains("first=2 second=2"), "\(h.frame)")
  }

  @Test func setA760AWorkingCopyMutationReachesTheLaterInputClosure() throws {
    // Hypothesis: DynamicProperty.update mutates the body's copy but the registered input closure captures the authored copy.
    let probe = SetACurrencyIntProbe()
    let h = try make(760) { SetACurrencyPreparedHost(probe: probe) }
    defer { h.shutdown() }
    try #require(h.frame.contains("prepared=1"))
    try h.clickText("Read prepared")
    #expect(probe.values == [1])
  }

  @Test func setA761TwoMountsOfTheSameAuthoredViewValueKeepSeparateState() throws {
    // Hypothesis: shared State boxes select their most recently bound graph instead of the input callback's exact owner.
    let shared = SetACurrencySharedCounter()
    let first = try make(761) { shared }
    defer { first.shutdown() }
    let second = try make(1_761) { shared }
    defer { second.shutdown() }
    try first.clickText("Increment shared")
    try second.clickText("Increment shared")
    try second.clickText("Increment shared")
    #expect(first.frame.contains("count=1"))
    #expect(second.frame.contains("count=2"))
    try first.clickText("Increment shared")
    #expect(first.frame.contains("count=2"))
    #expect(second.frame.contains("count=2"))
  }

  @Test func setA762ARetiredBindingCannotWriteIntoTheRemountedOwner() throws {
    // Hypothesis: a retained location refreshes by structural identity and writes into a new owner after committed removal.
    let probe = SetACurrencyRetiredProbe()
    let h = try make(762) { SetACurrencyRetiredHost(probe: probe) }
    defer { h.shutdown() }
    try h.clickText("Increment live")
    let old = try #require(probe.original)
    try #require(old.wrappedValue == 1)
    try h.clickText("Toggle child")
    try #require(!h.frame.contains("Increment live"))
    try h.clickText("Toggle child")
    let current = try #require(probe.current)
    try #require(current.wrappedValue == 0)
    try #require(current.bindingSourceID != old.bindingSourceID)
    // The retired location weakly holds its original StateBox. A write may be
    // dropped after that box is released; it must never reach the new owner.
    old.wrappedValue = 99
    try h.render()
    #expect(current.wrappedValue == 0)
    #expect(h.frame.contains("live=0"))
    try h.clickText("Increment live")
    #expect(current.wrappedValue == 1)
    #expect(h.frame.contains("live=1"))
  }

  @Test func setA763ARetainedNestedMemberWritePreservesTheLatestSiblings() {
    // Hypothesis: a member binding captures its initial enclosing value and overwrites later edits to neighboring fields.
    let box = SetACurrencyBox(SetACurrencyEnvelope(pair: .init(x: 1, y: 2), title: "old"))
    let member = box.binding.pair.x
    box.value = .init(pair: .init(x: 5, y: 8), title: "current")
    member.wrappedValue = 13
    #expect(box.value == .init(pair: .init(x: 13, y: 8), title: "current"))
    #expect(box.writes == 1)
  }

  @Test func setA764AProjectedTransactionOverridesItsBasesStoredTransactionOnce() {
    // Hypothesis: nested member write-back reapplies the base transaction over a replacement transaction on the projection.
    let probe = SetACurrencyTransactionProbe()
    let original = Animation.easeIn(duration: .milliseconds(70))
    let replacement = Animation.linear(duration: .milliseconds(130))
    var transaction = Transaction(animation: replacement)
    transaction.isContinuous = true
    transaction.tracksVelocity = true
    let projection = probe.binding.animation(original).x.transaction(transaction)
    projection.wrappedValue = 4
    #expect(probe.value == .init(x: 4, y: 0))
    #expect(probe.requests == [.animate(replacement.animationBox)])
    #expect(probe.continuity == [true] && probe.velocity == [true])
    #expect(AnimationContextStorage.currentRequest == .inherit)
  }

  @Test func setA765APositionalBindingStillAddressesItsIndexAfterReordering() {
    // Hypothesis: collection Binding's positional projection accidentally adopts ForEach's ID-relocation semantics.
    let box = SetACurrencyBox([
      SetACurrencyRow(id: 1, name: "A"), SetACurrencyRow(id: 2, name: "B"),
    ])
    let position = box.binding[1]
    box.value.reverse()
    #expect(position.wrappedValue.id == 1)
    position.name.wrappedValue = "edited"
    #expect(box.value.map(\.id) == [2, 1])
    #expect(box.value.map(\.name) == ["B", "edited"])
  }

  @Test func setA766ANilOptionalProjectionWriteCannotReplaceTheBaseValueCurrency() throws {
    // Hypothesis: an ignored nil write still stores the base's existing value and rotates its replacement token.
    let state = State(wrappedValue: 6)
    let base = state.projectedValue
    let token = try #require(base.valueIdentity?())
    let wrapped = Binding<Int?>(base)
    wrapped.wrappedValue = nil
    #expect(base.wrappedValue == 6)
    #expect(base.valueIdentity?() === token)
    wrapped.wrappedValue = 9
    #expect(base.wrappedValue == 9)
    #expect(base.valueIdentity?() !== token)
  }

  @Test func setA767NestedProjectionsCannotMutateAConstantValueBinding() {
    // Hypothesis: key-path write-back bypasses a constant binding's ignored setter and mutates its captured value.
    let original = SetACurrencyEnvelope(pair: .init(x: 1, y: 2), title: "fixed")
    let constant = Binding.constant(original)
    constant.pair.x.wrappedValue = 91
    constant.title.wrappedValue = "changed"
    #expect(constant.wrappedValue == original)
  }

  @Test func setA768ARetainedRowBindingUsesTheCurrentSliceIndexSpace() throws {
    // Hypothesis: identity lookup stores a zero-based offset and reuses it after ArraySlice's startIndex changes.
    let probe = SetACurrencyRowsProbe<ArraySlice<SetACurrencyRow>>()
    let h = try make(768) { SetACurrencySliceHost(probe: probe) }
    defer { h.shutdown() }
    let collection = try #require(probe.collection)
    try #require(collection.wrappedValue.startIndex == 1)
    try #require(probe.retained?.wrappedValue.name == "B")
    try h.clickText("Rebase slice")
    #expect(collection.wrappedValue.startIndex == 2)
    try h.clickText("Edit retained")
    #expect(collection.wrappedValue.map(\.id) == [1, 2])
    #expect(collection.wrappedValue.map(\.name) == ["A", "edited"])
    #expect(h.frame.contains("edited"))
  }

  @Test func setA769ComputedIDsCannotReuseAnUnchangedCollectionStoreToken() throws {
    // Hypothesis: computed IDs inherit array currency even though their reference-backed inputs change without an array store.
    let probe = SetACurrencyRowsProbe<[SetACurrencyComputedRow]>()
    let h = try make(769) { SetACurrencyComputedHost(probe: probe) }
    defer { h.shutdown() }
    let collection = try #require(probe.collection)
    let retained = try #require(probe.retained)
    let token = try #require(collection.valueIdentity?())
    try h.clickText("Change computed IDs")
    try #require(collection.valueIdentity?() === token)
    #expect(retained.valueIdentity == nil)
    #expect(retained.wrappedValue.name == "Other")
    try h.clickText("Edit computed")
    #expect(collection.wrappedValue.map(\.name) == ["edited", "Ada"])
  }

  @Test func setA770ATransformingSourceSetterCannotLeaveARowLookupAtItsOldPosition() throws {
    // Hypothesis: a retained ForEach binding trusts its optimistic write position after the source setter reorders the collection.
    let probe = SetACurrencyRowsProbe<[SetACurrencyRow]>()
    let h = try make(770) { SetACurrencyTransformingHost(probe: probe) }
    defer { h.shutdown() }
    let collection = try #require(probe.collection)
    try h.clickText("Edit retained A")
    try #require(collection.wrappedValue.map(\.id) == [3, 2, 1])
    #expect(collection.wrappedValue.map(\.name) == ["C", "B", "A!"])
    try h.clickText("Edit retained A")
    #expect(collection.wrappedValue.map(\.id) == [1, 2, 3])
    #expect(collection.wrappedValue.map(\.name) == ["A!!", "B", "C"])
  }

  @Test func setA771AWrittenMissingOccurrenceDoesNotResurrectOrAliasASurvivor() throws {
    // Hypothesis: a removed duplicate's retained element binding falls back to its ID's surviving first occurrence.
    let probe = SetACurrencyRowsProbe<[SetACurrencyRow]>()
    let h = try make(771) { SetACurrencyMissingOccurrenceHost(probe: probe) }
    defer { h.shutdown() }
    let collection = try #require(probe.collection)
    let removed = try #require(probe.retained)
    try h.clickText("Remove second duplicate")
    try #require(collection.wrappedValue.map(\.name) == ["A", "C"])
    removed.wrappedValue = .init(id: 1, name: "ghost")
    #expect(collection.wrappedValue.map(\.name) == ["A", "C"])
    #expect(
      ImperativeRuntimeIssueQueue.pending.contains {
        $0.code == "forEach.staleElementBindingWrite"
      })
    // Drain the dispatch warning through a real frame; never read the retired row binding.
    try h.renderAfterExternalMutation()
    #expect(!h.frame.contains("ghost"))
  }

  @Test func setA772AnOptionalNilRegistryPayloadStillParticipatesInPruning() {
    // Hypothesis: generic registry pruning mistakes a present nil payload for an absent dictionary entry.
    var store = IdentityKeyedRegistryStorage<Int?>()
    let empty = testIdentity("SetA772", "Empty")
    let kept = testIdentity("SetA772", "Kept")
    store.set(nil, for: empty, owner: .init(identity: empty))
    store.set(8, for: kept, owner: .init(identity: kept))
    #expect(store.values.keys.contains(empty))
    var visited: Set<Identity> = []
    store.removeUnjustified { identity, _ in
      visited.insert(identity)
      return identity != empty
    }
    #expect(visited == [empty, kept])
    #expect(!store.values.keys.contains(empty))
    #expect(store.ownersByIdentity[empty] == nil)
    #expect(store.values.keys.contains(kept))
  }

  @Test func setA773RegistryOverlayReplacesOwnerMetadataWithoutCreatingGhostValues() {
    // Hypothesis: overlaying a value preserves its old lifetime owner or imports orphan owner-map entries as registrations.
    var store = IdentityKeyedRegistryStorage<Int>()
    let key = testIdentity("SetA773", "PublishedKey")
    let sibling = testIdentity("SetA773", "Sibling")
    let oldOwner = testIdentity("SetA773", "OldOwner")
    let newOwner = testIdentity("SetA773", "NewOwner")
    let ghost = testIdentity("SetA773", "Ghost")
    store.set(1, for: key, owner: .init(viewNodeID: .init(rawValue: 1), identity: oldOwner))
    store.set(9, for: sibling, owner: .init(identity: sibling))
    let restored = RuntimeRegistrationOwnerKey(viewNodeID: .init(rawValue: 2), identity: newOwner)
    store.restore([key: 7], ownersByIdentity: [key: restored, ghost: restored])
    #expect(store.ownersByIdentity[key] == restored)
    #expect(store.ownersByIdentity[ghost] == nil && store[ghost] == nil)
    store.removeSubtrees(rootedAt: [oldOwner])
    #expect(store[key] == 7 && store[sibling] == 9)
    store.removeSubtrees(rootedAt: [newOwner])
    #expect(store[key] == nil && store[sibling] == 9)
  }

  @Test func setA774ReplacingOneRegistryChangesItsAggregatePublicationTarget() {
    // Hypothesis: publication-target currency identifies the aggregate wrapper rather than every persistent member registry.
    let action = LocalActionRegistry()
    let keys = LocalKeyHandlerRegistry()
    let original = RuntimeRegistrationSet(actionRegistry: action, keyHandlerRegistry: keys)
    let sameMembers = RuntimeRegistrationSet(actionRegistry: action, keyHandlerRegistry: keys)
    let replacement = RuntimeRegistrationSet(
      actionRegistry: LocalActionRegistry(), keyHandlerRegistry: keys)
    let baseline = original.targetIdentity
    #expect(sameMembers.targetIdentity == baseline)
    #expect(replacement.targetIdentity != baseline)
    action.register(identity: testIdentity("SetA774")) { true }
    #expect(original.targetIdentity == baseline)
  }

  @Test func setA775ASparseScratchSetCopiesMembershipWithoutSharingRegistryStorage() throws {
    // Hypothesis: a sparse publication scratch either invents absent families or shares a live member's mutable registrations.
    let action = LocalActionRegistry()
    let target = RuntimeRegistrationSet(
      actionRegistry: action, terminationRegistry: LocalTerminationRegistry(),
      commandRegistry: CommandRegistry())
    let scratch = RuntimeRegistrationSet.scratch(mirroringMembershipOf: target)
    let scratchAction = try #require(scratch.actionRegistry)
    let scratchTermination = try #require(scratch.terminationRegistry)
    let scratchCommands = try #require(scratch.commandRegistry)
    #expect(scratch.allRegistries.count == 3)
    #expect(scratchAction !== action)
    #expect(scratchTermination !== target.terminationRegistry)
    #expect(scratchCommands !== target.commandRegistry)
    #expect(scratch.targetIdentity != target.targetIdentity)
    let identity = testIdentity("SetA775")
    var dispatches: [String] = []
    action.register(identity: identity) {
      dispatches.append("live")
      return true
    }
    #expect(!scratchAction.hasHandler(identity: identity))
    scratchAction.register(identity: identity) {
      dispatches.append("scratch")
      return true
    }
    #expect(action.dispatch(identity: identity))
    #expect(scratchAction.dispatch(identity: identity))
    #expect(dispatches == ["live", "scratch"])
  }

  private func make<Content: View>(
    _ number: Int, @ViewBuilder content: @escaping () -> Content
  ) throws -> StressRuntimeHarness<Content> {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetAIdentityCurrency", "\(number)"),
      size: .init(width: 64, height: 14), content: content)
  }
}

private struct SetACurrencyDebugID: Hashable, Sendable, CustomDebugStringConvertible {
  let value: String
  var debugDescription: String { value }
}

private struct SetACurrencyCollidingID: Hashable, Sendable {
  let value: Int
  func hash(into hasher: inout Hasher) { hasher.combine(0) }
}

private struct SetACurrencyPair: Equatable {
  var x: Int
  var y: Int
}

private struct SetACurrencyEnvelope: Equatable {
  var pair: SetACurrencyPair
  var title: String
}

private final class SetACurrencyModel {
  var value: Int
  init(value: Int) { self.value = value }
}

private struct SetACurrencyReferenceEnvelope: Equatable {
  var model: SetACurrencyModel
  static func == (lhs: Self, rhs: Self) -> Bool { lhs.model === rhs.model }
}

@MainActor
private final class SetACurrencyBox<Value> {
  var value: Value
  var writes = 0
  init(_ value: Value) { self.value = value }
  var binding: Binding<Value> {
    Binding(
      get: { self.value },
      set: {
        self.value = $0
        self.writes += 1
      })
  }
}

@MainActor
private final class SetACurrencyTransactionProbe {
  var value = SetACurrencyPair(x: 0, y: 0)
  var requests: [AnimationRequest] = []
  var continuity: [Bool] = []
  var velocity: [Bool] = []
  var binding: Binding<SetACurrencyPair> {
    Binding(
      get: { self.value },
      set: {
        self.value = $0
        self.requests.append(AnimationContextStorage.currentRequest)
        self.continuity.append(AnimationContextStorage.currentIsContinuous)
        self.velocity.append(AnimationContextStorage.currentTracksVelocity)
      })
  }
}

@propertyWrapper
@MainActor
private struct SetACurrencyInnerCounter: DynamicProperty {
  @State private var value = 0
  init() {}
  var wrappedValue: Int {
    get { value }
    nonmutating set { value = newValue }
  }
  func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult { .unchanged }
}

@propertyWrapper
@MainActor
private struct SetACurrencyNestedCounter: DynamicProperty {
  private var inner = SetACurrencyInnerCounter()
  init() {}
  var wrappedValue: Int {
    get { inner.wrappedValue }
    nonmutating set { inner.wrappedValue = newValue }
  }
  func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult { .unchanged }
}

private struct SetACurrencyComposedHost: View {
  @SetACurrencyNestedCounter private var first: Int
  @SetACurrencyNestedCounter private var second: Int
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Increment first") { first += 1 }
      Button("Increment second") { second += 1 }
      Text("first=\(first) second=\(second)")
    }
  }
}

@MainActor
private final class SetACurrencyIntProbe { var values: [Int] = [] }

@propertyWrapper
@MainActor
private struct SetACurrencyPreparedValue: DynamicProperty {
  private var value = 0
  init() {}
  var wrappedValue: Int { value }
  mutating func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    value += 1
    return .changed
  }
}

private struct SetACurrencyPreparedHost: View {
  @SetACurrencyPreparedValue private var value: Int
  let probe: SetACurrencyIntProbe
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("prepared=\(value)")
      Button("Read prepared") { probe.values.append(value) }
    }
  }
}

private struct SetACurrencySharedCounter: View {
  @State private var count = 0
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Increment shared") { count += 1 }
      Text("count=\(count)")
    }
  }
}

@MainActor
private final class SetACurrencyRetiredProbe {
  var original: Binding<Int>?
  var current: Binding<Int>?
}

private struct SetACurrencyRetiredHost: View {
  @State private var shown = true
  let probe: SetACurrencyRetiredProbe
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle child") { shown.toggle() }
      if shown { SetACurrencyRetiredChild(probe: probe) }
    }
  }
}

private struct SetACurrencyRetiredChild: View {
  @State private var value = 0
  let probe: SetACurrencyRetiredProbe
  var body: some View {
    let _ = {
      probe.current = $value
      if probe.original == nil { probe.original = $value }
    }()
    VStack(alignment: .leading, spacing: 0) {
      Button("Increment live") { value += 1 }
      Text("live=\(value)")
    }
  }
}

private struct SetACurrencyRow: Identifiable, Equatable {
  var id: Int
  var name: String
}

@MainActor
private final class SetACurrencyRowsProbe<C: MutableCollection & RandomAccessCollection> {
  var collection: Binding<C>?
  var retained: Binding<C.Element>?
}

private struct SetACurrencySliceHost: View {
  @State private var rows = [
    SetACurrencyRow(id: -1, name: "padding"),
    SetACurrencyRow(id: 1, name: "A"), SetACurrencyRow(id: 2, name: "B"),
  ][1...]
  let probe: SetACurrencyRowsProbe<ArraySlice<SetACurrencyRow>>
  var body: some View {
    let _ = { probe.collection = $rows }()
    VStack(alignment: .leading, spacing: 0) {
      Button("Rebase slice") {
        let padding = [
          SetACurrencyRow(id: -2, name: "padding"), .init(id: -1, name: "padding"),
        ]
        rows = (padding + Array(rows))[2...]
      }
      Button("Edit retained") { probe.retained?.name.wrappedValue = "edited" }
      ForEach($rows) { row in
        let _ = remember(row)
        Text(row.wrappedValue.name)
      }
    }
  }
  private func remember(_ row: Binding<SetACurrencyRow>) {
    if row.wrappedValue.id == 2 && probe.retained == nil { probe.retained = row }
  }
}

private final class SetACurrencyIDBox {
  var value: Int
  init(_ value: Int) { self.value = value }
}

private struct SetACurrencyComputedRow {
  var source: SetACurrencyIDBox
  var name: String
  var id: Int { source.value }
}

private struct SetACurrencyComputedHost: View {
  @State private var rows = [
    SetACurrencyComputedRow(source: .init(0), name: "Other"),
    SetACurrencyComputedRow(source: .init(1), name: "Ada"),
  ]
  @State private var revision = 0
  let probe: SetACurrencyRowsProbe<[SetACurrencyComputedRow]>
  var body: some View {
    let _ = { probe.collection = $rows }()
    VStack(alignment: .leading, spacing: 0) {
      Button("Change computed IDs") {
        rows[0].source.value = 1
        revision += 1
      }
      Button("Edit computed") { probe.retained?.name.wrappedValue = "edited" }
      Text("revision=\(revision)")
      ForEach($rows, id: \.id) { row in
        let _ = remember(row)
        Text(row.wrappedValue.name)
      }
    }
  }
  private func remember(_ row: Binding<SetACurrencyComputedRow>) {
    if row.wrappedValue.name == "Ada" && probe.retained == nil { probe.retained = row }
  }
}

private struct SetACurrencyTransformingHost: View {
  @State private var rows = [
    SetACurrencyRow(id: 1, name: "A"), SetACurrencyRow(id: 2, name: "B"),
    SetACurrencyRow(id: 3, name: "C"),
  ]
  let probe: SetACurrencyRowsProbe<[SetACurrencyRow]>
  var body: some View {
    let source = Binding(get: { rows }, set: { rows = Array($0.reversed()) })
    let _ = { probe.collection = source }()
    VStack(alignment: .leading, spacing: 0) {
      Button("Edit retained A") {
        if let retained = probe.retained { retained.name.wrappedValue += "!" }
      }
      ForEach(source) { row in
        let _ = remember(row)
        Text(row.wrappedValue.name)
      }
    }
  }
  private func remember(_ row: Binding<SetACurrencyRow>) {
    if row.wrappedValue.id == 1 && probe.retained == nil { probe.retained = row }
  }
}

private struct SetACurrencyMissingOccurrenceHost: View {
  @State private var rows = [
    SetACurrencyRow(id: 1, name: "A"), SetACurrencyRow(id: 1, name: "B"),
    SetACurrencyRow(id: 2, name: "C"),
  ]
  let probe: SetACurrencyRowsProbe<[SetACurrencyRow]>
  var body: some View {
    let _ = { probe.collection = $rows }()
    VStack(alignment: .leading, spacing: 0) {
      Button("Remove second duplicate") { rows.removeAll { $0.name == "B" } }
      ForEach($rows) { row in
        let _ = remember(row)
        Text(row.wrappedValue.name)
      }
    }
  }
  private func remember(_ row: Binding<SetACurrencyRow>) {
    if row.wrappedValue.name == "B" && probe.retained == nil { probe.retained = row }
  }
}
