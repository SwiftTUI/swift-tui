@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized, FailOnSoundnessViolationGrowth(), .timeLimit(.minutes(1)))
struct AdversarialSetAHotReloadBoundaryTests {
  @Test func setA651ANonNilProbeDoesNotConsumeTheUnkeyedSnapshotElement() throws {
    // Hypothesis: decodeNil advances an unkeyed cursor even when the next value is non-nil.
    let result = try SnapshotCoding.decode(
      SetAReloadNilCursor.self, from: .array([.signed(7), .null, .signed(9)]))
    #expect(result.values == [7, 9])
    #expect(result.indices == [0, 1, 2, 3])
  }

  @Test func setA652ARejectedUnkeyedDecodeCanBeRetriedAtTheSameIndex() throws {
    // Hypothesis: a failed typed decode consumes its element and makes a valid fallback read the next value.
    let result = try SnapshotCoding.decode(
      SetAReloadRetryCursor.self, from: .array([.string("fallback"), .signed(8)]))
    #expect(result.text == "fallback" && result.tail == 8)
    #expect(result.failedIndex == 0)
  }

  @Test func setA653EmptyContainersAndExplicitNullMembersRemainDistinct() throws {
    // Hypothesis: freezing empty containers collapses them to null or drops an explicitly nil dictionary member.
    let original = SetAReloadEmptyValues(list: [], map: [:], nullable: ["present": nil])
    let encoded = try SnapshotCoding.encode(original)
    #expect(
      encoded
        == .object([
          "list": .array([]), "map": .object([:]),
          "nullable": .object(["present": .null]),
        ]))
    #expect(try SnapshotCoding.decode(SetAReloadEmptyValues.self, from: encoded) == original)
  }

  @Test func setA654DefaultSuperclassContainersDoNotOverwriteSubclassFields() throws {
    // Hypothesis: unkeyed and keyed superclass encoders share the child's storage instead of the reserved super child.
    let source = SetAReloadDerived(base: 17, name: "derived")
    let encoded = try SnapshotCoding.encode(source)
    #expect(
      encoded == .object(["name": .string("derived"), "super": .object(["base": .signed(17)])]))
    let restored = try SnapshotCoding.decode(SetAReloadDerived.self, from: encoded)
    #expect(restored.base == 17 && restored.name == "derived")
  }

  @Test func setA655NestedDecodeFailuresIdentifyTheExactKeyAndArrayIndex() throws {
    // Hypothesis: child decoder erasure drops the array index or enclosing key from restoration diagnostics.
    let value = SnapshotValue.object(["records": .array([.object(["amount": .string("wrong")])])])
    do {
      _ = try SnapshotCoding.decode(SetAReloadEnvelope.self, from: value)
      Issue.record("Expected a typed restoration failure")
    } catch DecodingError.typeMismatch(_, let context) {
      #expect(context.codingPath.map(\.stringValue) == ["records", "Index 0", "amount"])
      #expect(context.codingPath.dropFirst().first?.intValue == 0)
    }
  }

  @Test func setA656SnapshotValueBudgetsIncludeTheRootExactlyOnce() throws {
    // Hypothesis: encoder and decoder disagree at the exact root-plus-children value budget.
    let source = [1, 2, 3]
    let limit = SnapshotCodingLimits(maximumValues: 4)
    let encoded = try SnapshotCoding.encode(source, limits: limit)
    #expect(try SnapshotCoding.decode([Int].self, from: encoded, limits: limit) == source)
    #expect(throws: SnapshotCodingError.limitExceeded) {
      try SnapshotCoding.encode(source, limits: .init(maximumValues: 3))
    }
    #expect(throws: SnapshotCodingError.limitExceeded) {
      try SnapshotCoding.decode([Int].self, from: encoded, limits: .init(maximumValues: 3))
    }
  }

  @Test func setA657UTF8BudgetsCountAuthoredKeysButNotSyntheticArrayIndices() throws {
    // Hypothesis: coding-path labels spend payload bytes, or non-ASCII object keys bypass the byte budget.
    let source = ["é": "界"]
    let limit = SnapshotCodingLimits(maximumUTF8Bytes: 5)
    let encoded = try SnapshotCoding.encode(source, limits: limit)
    #expect(
      try SnapshotCoding.decode([String: String].self, from: encoded, limits: limit) == source)
    #expect(throws: SnapshotCodingError.limitExceeded) {
      try SnapshotCoding.encode(source, limits: .init(maximumUTF8Bytes: 4))
    }
    #expect(throws: SnapshotCodingError.limitExceeded) {
      try SnapshotCoding.decode(
        [String: String].self, from: encoded, limits: .init(maximumUTF8Bytes: 4))
    }
    #expect(
      try SnapshotCoding.encode([1, 2], limits: .init(maximumUTF8Bytes: 0))
        == .array([.signed(1), .signed(2)]))
  }

  @Test func setA658StructuredDictionaryKeysRoundTripWithoutStringCoercion() throws {
    // Hypothesis: the portable snapshot assumes every Dictionary is a string-keyed object and loses structured keys.
    let source: [SetAReloadDictionaryKey: [Int?]] = [
      .init(group: "same", ordinal: 1): [nil, 3],
      .init(group: "same", ordinal: 2): [],
    ]
    let encoded = try SnapshotCoding.encode(source)
    let restored = try SnapshotCoding.decode([SetAReloadDictionaryKey: [Int?]].self, from: encoded)
    #expect(restored == source)
  }

  @Test func setA659ATypeMismatchRejectsTheWholeOrdinalRankGroupOnly() {
    // Hypothesis: rank migration restores a compatible trailing slot after an earlier type change shifted its meaning.
    let owner = Identity(components: ["Owner"])
    var replay = replay(
      entries: [entry(owner, 10, 1), entry(owner, 20, 2), entry(owner, 10, 3, path: [1])],
      owners: [
        .init(
          identity: owner,
          slots: [
            slot(30): "Swift.String", slot(40): "Swift.Int", slot(20, path: [1]): "Swift.Int",
          ])
      ])
    let rejected: Int? = replay.value(for: absolute(owner), slot: slot(40))
    let independent: Int? = replay.value(for: absolute(owner), slot: slot(20, path: [1]))
    #expect(rejected == nil && independent == 3)
    #expect(replay.restoredCount == 1 && replay.finish().count == 2)
  }

  @Test func setA660SyntheticSlotsCannotMigrateByDeclarationRank() {
    // Hypothesis: negative runtime slot ordinals are shifted by rank as if they were authored source positions.
    let owner = Identity(components: ["Owner"])
    var replay = replay(entries: [entry(owner, -10, 7)], owners: [schema(owner, [-20])])
    let value: Int? = replay.value(for: absolute(owner), slot: slot(-20))
    #expect(value == nil && replay.restoredCount == 0)
    #expect(replay.finish().count == 1)
    var exact = self.replay(entries: [entry(owner, -10, 7)], owners: [schema(owner, [-10])])
    let unchanged: Int? = exact.value(for: absolute(owner), slot: slot(-10))
    #expect(unchanged == 7)
  }

  @Test func setA661AnIndexedSiblingCannotBeErasedAsAWrapperEdit() {
    // Hypothesis: conservative wrapper matching erases an indexed component and donates a sibling's state to its parent.
    let source = Identity(components: ["Row[0]", "Counter"])
    let target = Identity(components: ["Counter"])
    var replay = replay(entries: [entry(source, 10, 5)], owners: [schema(target, [10])])
    let value: Int? = replay.value(for: absolute(target), slot: slot(10))
    #expect(value == nil && replay.ownerMatches.isEmpty)
    #expect(replay.finish().count == 1)
  }

  @Test func setA662DescendantFocusRebasingUsesItsMostSpecificMatchedOwner() {
    // Hypothesis: focus rebasing stops at an unchanged ancestor and misses a wrapper inserted inside that owner.
    let parent = Identity(components: ["Outer"])
    let child = parent.child("Inner")
    let wrapped = parent.child("Wrapper").child("Inner")
    let replay = replay(
      entries: [entry(parent, 10, 1), entry(child, 10, 2)],
      owners: [schema(parent, [10]), schema(wrapped, [10])])
    let oldFocus = Identity(components: sourceRoot.components + child.components + ["Button"])
    #expect(replay.rebasedIdentity(oldFocus, from: sourceRoot) == absolute(wrapped.child("Button")))
    #expect(
      replay.rebasedIdentity(
        Identity(components: ["Generation-old-sibling", "Button"]), from: sourceRoot) == nil)
  }

  @Test func setA663FinishingActiveReplayKeepsDormantClaimsWithoutDuplicatingDiagnostics() {
    // Hypothesis: finish(keepingDormant:) retires unread inactive values or repeatedly reports an already retired active slot.
    let active = Identity(components: ["Active"])
    let asleep = Identity(components: ["Asleep"])
    var dormant = entry(asleep, 10, 8)
    dormant.isDormant = true
    var replay = replay(entries: [entry(active, 10, 3), dormant], owners: [schema(active, [10])])
    let first = replay.finish(keepingDormant: true)
    #expect(first.count == 1 && first.first?.address.owner == active)
    #expect(replay.pending.count == 1 && replay.pending.values.first?.isDormant == true)
    #expect(replay.finish(keepingDormant: true) == first)
    #expect(replay.finish().count == 2 && replay.pending.isEmpty)
  }

  @Test func setA664ModuleAliasesDoNotRewriteNestedNominalTypeNames() {
    // Hypothesis: alias replacement treats every qualified token as a module and changes a nested type's schema.
    let aliases = ["ImageA": "App", "ImageB": "App", "Nested": "Wrong"]
    #expect(
      HotReloadTypeNames.canonical("ImageA.Outer.Nested<ImageB.Value>", aliases: aliases)
        == "App.Outer.Nested<App.Value>")
    #expect(
      HotReloadTypeNames.canonical("Other.ImageA.Value", aliases: aliases) == "Other.ImageA.Value")
    #expect(HotReloadTypeNames.canonical("ImageAB.Value", aliases: aliases) == "ImageAB.Value")
  }

  @Test func setA665AnUntouchedDormantClaimSurvivesASecondGenerationSnapshot() throws {
    // Hypothesis: a new snapshot includes live nodes but omits deferred values from a still-inactive prior generation.
    let owner = Identity(components: ["Dormant"])
    var dormant = entry(owner, 10, 42)
    dormant.isDormant = true
    let graph = ViewGraph()
    try graph.installHotReloadReplay(
      .init(sourceRoot: sourceRoot, entries: [dormant]),
      at: destinationRoot, owners: [])
    #expect(graph.finishHotReloadReplay(keepingDormant: true).isEmpty)
    let recaptured = graph.captureHotReloadSnapshot(rootedAt: destinationRoot)
    try #require(recaptured.entries.count == 1)
    let next = Identity(components: ["Generation-third"])
    let replacement = ViewGraph()
    try replacement.installHotReloadReplay(recaptured, at: next, owners: [])
    let absolute = Identity(components: next.components + owner.components)
    replacement.validateDormantHotReloadSchema(
      for: absolute, slots: schema(owner, [10]).slots, ambiguous: false)
    let value: Int? = replacement.restoredHotReloadValue(for: absolute, slot: slot(10))
    #expect(value == 42 && replacement.finishHotReloadReplay().isEmpty)
  }

  @Test func setA666SnapshotRootFilteringUsesIdentityComponentsRatherThanTextPrefixes() {
    // Hypothesis: snapshot traversal captures a sibling generation whose string path merely starts with the requested root.
    let graph = ViewGraph()
    let included = graph.prepareDynamicPropertyUpdate(identity: sourceRoot.child("Owner"))
    let excluded = graph.prepareDynamicPropertyUpdate(
      identity: Identity(components: ["Generation-old-sibling", "Owner"]))
    withOwnedDormantStateSlot {
      included.setStateSlot(ordinal: 10, value: 4)
      excluded.setStateSlot(ordinal: 10, value: 99)
    }
    let snapshot = graph.captureHotReloadSnapshot(rootedAt: sourceRoot)
    #expect(snapshot.entries.count == 1)
    #expect(snapshot.entries.first?.value == .signed(4))
    #expect(snapshot.entries.first?.address.owner == Identity(components: ["Owner"]))
  }

  @Test func setA667ASecondSwapCannotReplaceAnUncommittedGeneration() throws {
    // Hypothesis: a second install snapshots a half-installed generation and loses the last committed state.
    let h = try SetAReloadHarness(667) { SetAReloadCounter(version: "one") }
    defer { h.shutdown() }
    try h.press(.return)
    try #require(h.text.contains("one=1"))
    try h.loop.replaceHotReloadGeneration(HotReloadGeneration { SetAReloadCounter(version: "two") })
    #expect(h.session.awaitingCommit && h.session.generation == 1)
    #expect(throws: HotReloadSwapError.swapInProgress) {
      try h.loop.replaceHotReloadGeneration(
        HotReloadGeneration { SetAReloadCounter(version: "rejected") })
    }
    try h.drain()
    #expect(h.text.contains("two=1") && !h.session.awaitingCommit)
    try h.reload { SetAReloadCounter(version: "three") }
    #expect(h.text.contains("three=1") && h.session.generation == 2)
  }

  @Test func setA668FailedSchemaRehearsalLeavesTheOldInputHandlerUsable() throws {
    // Hypothesis: a failed rehearsal installs new content or retires the old generation before convergence is known.
    let h = try SetAReloadHarness(668) { SetAReloadCounter(version: "old") }
    defer { h.shutdown() }
    try h.press(.return)
    let root = h.session.generationRoot
    #expect(throws: HotReloadSwapError.schemaDidNotConverge) {
      try h.session.replace(
        with: HotReloadGeneration { SetAReloadCounter(version: "new") },
        proposal: h.loop.proposal(), maximumAttempts: 1)
    }
    #expect(
      h.session.generation == 0 && h.session.generationRoot == root && !h.session.awaitingCommit)
    try h.press(.return)
    #expect(h.text.contains("old=2"))
    try h.reload { SetAReloadCounter(version: "new") }
    #expect(h.text.contains("new=2"))
  }

  @Test func setA669AStatelessSwapConvergesWithinOneAttemptButNeedsARealCommit() throws {
    // Hypothesis: empty schemas can never converge, or an early finish falsely acknowledges an unrendered replacement.
    let h = try SetAReloadHarness(669) { Text("old stateless") }
    defer { h.shutdown() }
    try h.session.replace(
      with: HotReloadGeneration { Text("new stateless") },
      proposal: h.loop.proposal(), maximumAttempts: 1)
    h.session.finishCommittedReplay()
    #expect(h.session.awaitingCommit && h.text.contains("old stateless"))
    try h.drain()
    #expect(!h.session.awaitingCommit && h.text.contains("new stateless"))
  }

  @Test func setA670ReloadingOneSessionCannotConsumeAnotherSessionsState() throws {
    // Hypothesis: replay or schema capture uses shared session storage and restores another live host's similarly shaped counter.
    let left = try SetAReloadHarness(670) { SetAReloadCounter(version: "left") }
    let right = try SetAReloadHarness(1670) { SetAReloadCounter(version: "right") }
    defer {
      left.shutdown()
      right.shutdown()
    }
    try left.press(.return)
    try right.press(.return)
    try right.press(.return)
    try left.reload { SetAReloadCounter(version: "left-new") }
    #expect(left.text.contains("left-new=1") && right.text.contains("right=2"))
    try right.reload { SetAReloadCounter(version: "right-new") }
    #expect(right.text.contains("right-new=2") && left.text.contains("left-new=1"))
  }

  @Test func setA671ReloadedReferenceStateIsDetachedFromTheRetiredObject() throws {
    // Hypothesis: successful replay carries an old Codable object reference instead of reconstructing an isolated generation value.
    let probe = SetAReloadObjectProbe()
    let h = try SetAReloadHarness(671) { SetAReloadObjectRoot(probe: probe) }
    defer { h.shutdown() }
    try h.press(.return)
    let old = try #require(probe.value)
    try #require(old.count == 1)
    try h.reload { SetAReloadObjectRoot(probe: probe) }
    let current = try #require(probe.value)
    #expect(current !== old && current.count == 1)
    old.count = 90
    try h.press(.return)
    #expect(current.count == 2 && h.text.contains("object=2"))
    #expect(old.count == 90)
  }

  @Test func setA672ADecodeFailureFallsBackOnlyItsOwnSlot() throws {
    // Hypothesis: a valid schema with one application-decoder rejection resets compatible neighboring state or reuses undecoded bytes.
    let h = try SetAReloadHarness(672) { SetAReloadRejectingRoot() }
    defer { h.shutdown() }
    try h.press(.return)
    try #require(h.text.contains("payload=9,count=7"))
    try h.reload { SetAReloadRejectingRoot() }
    #expect(h.text.contains("payload=0,count=7"))
    #expect(h.session.lastReport.filter { $0.reason.hasPrefix("Decode failed:") }.count == 1)
  }

  @Test func setA673UnsupportedStateReportsItsLossWithoutBlockingSupportedNeighbors() throws {
    // Hypothesis: a non-Codable authored slot prevents its whole owner's otherwise valid Codable state from replaying.
    let h = try SetAReloadHarness(673) { SetAReloadUnsupportedRoot() }
    defer { h.shutdown() }
    try h.press(.return)
    try #require(h.text.contains("ephemeral=9,count=7"))
    try h.reload { SetAReloadUnsupportedRoot() }
    #expect(h.text.contains("ephemeral=0,count=7"))
    #expect(h.session.lastReport.filter { $0.reason.contains("notCodable") }.count == 1)
  }

  @Test func setA674RestoredBranchStateRehearsesChildSchemasWithoutPublishingAppearances() throws {
    // Hypothesis: schema convergence stops before restored state reveals a stateful child, or publishes rehearsal lifecycle effects.
    let probe = SetAReloadAppearProbe()
    let h = try SetAReloadHarness(674) { SetAReloadBranchRoot(probe: probe) }
    defer { h.shutdown() }
    try h.press(.return)
    try h.press(.tab)
    try h.press(.return)
    try #require(h.text.contains("child=1"))
    let before = probe.events.count
    try h.loop.replaceHotReloadGeneration(
      HotReloadGeneration { SetAReloadBranchRoot(probe: probe) })
    #expect(probe.events.count == before)
    try h.drain()
    #expect(h.text.contains("child=1"))
    #expect(Array(probe.events.dropFirst(before)) == ["child appeared=1"])
    #expect(h.session.lastReport.isEmpty)
  }

  @Test func setA675RemovingTheFocusedReloadOwnerClearsThePendingFocusRequest() throws {
    // Hypothesis: a rebased focus request for a removed control blocks focus convergence or leaves input on the retired generation.
    let probe = SetAReloadAppearProbe()
    let h = try SetAReloadHarness(675) { SetAReloadFocusRoot(showsSecond: true, probe: probe) }
    defer { h.shutdown() }
    try h.press(.tab)
    try h.press(.return)
    try #require(probe.events == ["second"])
    let retired = h.loop.focusTracker.currentFocusIdentity
    try h.reload { SetAReloadFocusRoot(showsSecond: false, probe: probe) }
    #expect(h.session.pendingFocus == nil)
    #expect(
      h.loop.focusTracker.currentFocusIdentity != nil
        && h.loop.focusTracker.currentFocusIdentity != retired)
    try h.press(.return)
    #expect(probe.events == ["second", "first"])
  }

  private var sourceRoot: Identity { .init(components: ["Generation-old"]) }
  private var destinationRoot: Identity { .init(components: ["Generation-new"]) }
  private func absolute(_ owner: Identity) -> Identity {
    .init(components: destinationRoot.components + owner.components)
  }
  private func slot(_ ordinal: Int, path: [Int] = []) -> StateSlotIdentifier {
    .init(ordinal: ordinal, path: .init(fieldIndices: path))
  }
  private func entry(_ owner: Identity, _ ordinal: Int, _ value: Int, path: [Int] = [])
    -> HotReloadSnapshot.Entry
  {
    .init(
      address: .init(owner: owner, slot: slot(ordinal, path: path)),
      typeName: String(reflecting: Int.self), value: .signed(Int64(value)))
  }
  private func schema(_ owner: Identity, _ ordinals: [Int]) -> HotReloadOwnerSchema {
    .init(
      identity: owner,
      slots: Dictionary(
        uniqueKeysWithValues: ordinals.map { (slot($0), String(reflecting: Int.self)) }))
  }
  private func replay(entries: [HotReloadSnapshot.Entry], owners: [HotReloadOwnerSchema])
    -> HotReloadReplay
  {
    .init(
      snapshot: .init(sourceRoot: sourceRoot, entries: entries), destinationRoot: destinationRoot,
      owners: owners)
  }
}

private struct SetAReloadNilCursor: Decodable {
  let values: [Int]
  let indices: [Int]
  init(from decoder: any Decoder) throws {
    var container = try decoder.unkeyedContainer()
    var indices = [container.currentIndex]
    guard try !container.decodeNil() else { throw SnapshotCodingError.missingValue }
    let first = try container.decode(Int.self)
    indices.append(container.currentIndex)
    guard try container.decodeNil() else { throw SnapshotCodingError.missingValue }
    indices.append(container.currentIndex)
    let last = try container.decode(Int.self)
    indices.append(container.currentIndex)
    values = [first, last]
    self.indices = indices
  }
}

private struct SetAReloadRetryCursor: Decodable {
  let text: String
  let tail: Int
  let failedIndex: Int
  init(from decoder: any Decoder) throws {
    var container = try decoder.unkeyedContainer()
    do {
      _ = try container.decode(Int.self)
      throw SnapshotCodingError.incompatibleContainer
    } catch DecodingError.typeMismatch {
      failedIndex = container.currentIndex
    }
    text = try container.decode(String.self)
    tail = try container.decode(Int.self)
  }
}

private struct SetAReloadEmptyValues: Codable, Equatable {
  var list: [Int]
  var map: [String: Int]
  var nullable: [String: Int?]
}

private class SetAReloadBase: Codable {
  let base: Int
  init(base: Int) { self.base = base }
  private enum Key: String, CodingKey { case base }
  required init(from decoder: any Decoder) throws {
    base = try decoder.container(keyedBy: Key.self).decode(Int.self, forKey: .base)
  }
  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Key.self)
    try container.encode(base, forKey: .base)
  }
}

private final class SetAReloadDerived: SetAReloadBase {
  let name: String
  init(base: Int, name: String) {
    self.name = name
    super.init(base: base)
  }
  private enum Key: String, CodingKey { case name }
  required init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: Key.self)
    name = try container.decode(String.self, forKey: .name)
    try super.init(from: container.superDecoder())
  }
  override func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Key.self)
    try container.encode(name, forKey: .name)
    try super.encode(to: container.superEncoder())
  }
}

private struct SetAReloadEnvelope: Decodable {
  struct Item: Decodable { var amount: Int }
  var records: [Item]
}

private struct SetAReloadDictionaryKey: Codable, Hashable {
  var group: String
  var ordinal: Int
}

@MainActor
private final class SetAReloadHarness {
  let session: HotReloadSession
  let surface = RecordingPresentationSurface(surfaceSize: .init(width: 50, height: 8))
  let loop: RunLoop<Int, HotReloadHost>
  private var frames = 0

  init<Content: View>(_ number: Int, @ViewBuilder content: @escaping @MainActor () -> Content)
    throws
  {
    let session = HotReloadSession(content: HotReloadGeneration(content: content))
    self.session = session
    let root = testIdentity("SetAHotReload", "\(number)")
    let scheduler = FrameScheduler(mergePressurePacingEnabled: false)
    loop = RunLoop(
      rootIdentity: root, presentationSurface: surface,
      terminalInputReader: InjectedTerminalInputReader(), scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root]),
      runtimeConfiguration: .init(motion: .reduced),
      viewBuilder: .init { _ in HotReloadHost(session: session) })
    loop.stateContainer.invalidator = scheduler
    loop.installFocusTrackerInvalidator()
    loop.installHotReloadSession(session)
    scheduler.requestInvalidation(of: [root])
    try drain()
    loop.renderer.enableSelectiveEvaluation()
  }
  var text: String { surface.frames.last ?? "" }
  func drain() throws { try loop.renderPendingFrames(renderedFrames: &frames) }
  func press(_ key: KeyEvent) throws {
    #expect(loop.handle(.input(.key(KeyPress(key)))) == nil)
    try drain()
  }
  func reload<Content: View>(@ViewBuilder content: @escaping @MainActor () -> Content) throws {
    try loop.replaceHotReloadGeneration(HotReloadGeneration(content: content))
    try drain()
  }
  func shutdown() { loop.lifecycleCoordinator.shutdown() }
}

private struct SetAReloadCounter: View {
  let version: String
  @State private var count = 0
  var body: some View {
    Button("\(version)=\(count)") { count += 1 }
  }
}

private final class SetAReloadObject: Codable {
  var count: Int
  init(count: Int) { self.count = count }
}

@MainActor
private final class SetAReloadObjectProbe { var value: SetAReloadObject? }

private struct SetAReloadObjectRoot: View {
  let probe: SetAReloadObjectProbe
  @State private var model = SetAReloadObject(count: 0)
  @State private var revision = 0
  var body: some View {
    Button("object=\(model.count),revision=\(revision)") {
      model.count += 1
      revision += 1
    }.onAppear { probe.value = model }
  }
}

private struct SetAReloadRejectingValue: Codable {
  var value: Int
  init(value: Int) { self.value = value }
  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    value = try container.decode(Int.self)
    if value > 0 {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Rejected saved value")
    }
  }
  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }
}

private struct SetAReloadRejectingRoot: View {
  @State private var payload = SetAReloadRejectingValue(value: 0)
  @State private var count = 0
  var body: some View {
    Button("payload=\(payload.value),count=\(count)") {
      payload = .init(value: 9)
      count = 7
    }
  }
}

private struct SetAReloadEphemeralValue { var value: Int }
private struct SetAReloadUnsupportedRoot: View {
  @State private var payload = SetAReloadEphemeralValue(value: 0)
  @State private var count = 0
  var body: some View {
    Button("ephemeral=\(payload.value),count=\(count)") {
      payload = .init(value: 9)
      count = 7
    }
  }
}

@MainActor
private final class SetAReloadAppearProbe { var events: [String] = [] }

private struct SetAReloadBranchRoot: View {
  let probe: SetAReloadAppearProbe
  @State private var revealed = false
  var body: some View {
    VStack {
      Button("Reveal child") { revealed = true }
      if revealed { SetAReloadBranchChild(probe: probe) }
    }
  }
}

private struct SetAReloadBranchChild: View {
  let probe: SetAReloadAppearProbe
  @State private var count = 0
  var body: some View {
    Button("child=\(count)") { count += 1 }
      .onAppear { probe.events.append("child appeared=\(count)") }
  }
}

private struct SetAReloadFocusRoot: View {
  let showsSecond: Bool
  let probe: SetAReloadAppearProbe
  var body: some View {
    VStack {
      Button("First reload action") { probe.events.append("first") }
      if showsSecond { Button("Second reload action") { probe.events.append("second") } }
    }
  }
}
