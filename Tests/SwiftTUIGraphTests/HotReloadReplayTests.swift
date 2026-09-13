import Testing

@testable import SwiftTUIGraph

private struct ReloadRecord: Codable, Equatable {
  var title: String
  var flags: [Bool?]
  var counts: [String: UInt64]
  var choice: Choice
  enum Choice: Codable, Equatable {
    case selection(Int, String)
    case none
  }
}

private final class ReloadModel: Codable {
  var count: Int
  init(count: Int) { self.count = count }
}

private struct ReentrantReloadValue: Codable {
  @MainActor static var onDecode: (() -> Void)?
  var count: Int
  init(count: Int) { self.count = count }
  init(from decoder: any Decoder) throws {
    MainActor.assumeIsolated { Self.onDecode?() }
    count = try decoder.singleValueContainer().decode(Int.self)
  }
  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(count)
  }
}

private struct NestedCoding: Codable, Equatable {
  var values: [Int]
  enum Key: String, CodingKey { case values, extra }
  init(values: [Int]) { self.values = values }
  init(from decoder: any Decoder) throws {
    let keyed = try decoder.container(keyedBy: Key.self)
    var nested = try keyed.nestedUnkeyedContainer(forKey: .values)
    var result: [Int] = []
    while !nested.isAtEnd { result.append(try nested.decode(Int.self)) }
    values = result
    _ = try keyed.superDecoder(forKey: .extra).singleValueContainer().decode(String.self)
  }
  func encode(to encoder: any Encoder) throws {
    var keyed = encoder.container(keyedBy: Key.self)
    var nested = keyed.nestedUnkeyedContainer(forKey: .values)
    for value in values { try nested.encode(value) }
    var extra = keyed.superEncoder(forKey: .extra).singleValueContainer()
    try extra.encode("base")
  }
}

private final class CyclicCoding: Encodable {
  func encode(to encoder: any Encoder) throws {
    var container = encoder.unkeyedContainer()
    try container.encode(self)
  }
}

private struct RecursiveSingleCoding: Codable {
  init() {}
  init(from decoder: any Decoder) throws {
    self = try decoder.singleValueContainer().decode(Self.self)
  }
  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(self)
  }
}

@Suite("Portable hot-reload coding")
struct SnapshotCodingTests {
  @Test func nestedValuesRoundTrip() throws {
    let record = ReloadRecord(
      title: "héllo\n世界", flags: [true, nil, false], counts: ["largest": .max],
      choice: .selection(.min, "row")
    )
    #expect(
      try SnapshotCoding.decode(ReloadRecord.self, from: SnapshotCoding.encode(record)) == record)
    let nested = NestedCoding(values: [.min, 0, .max])
    #expect(
      try SnapshotCoding.decode(NestedCoding.self, from: SnapshotCoding.encode(nested)) == nested)
  }

  @Test func primitiveBoundariesAndNil() throws {
    #expect(try SnapshotCoding.decode(Int128.self, from: SnapshotCoding.encode(Int128.min)) == .min)
    #expect(
      try SnapshotCoding.decode(UInt128.self, from: SnapshotCoding.encode(UInt128.max)) == .max)
    #expect(try SnapshotCoding.decode(Int64.self, from: SnapshotCoding.encode(Int64.min)) == .min)
    #expect(try SnapshotCoding.decode(UInt64.self, from: SnapshotCoding.encode(UInt64.max)) == .max)
    #expect(try SnapshotCoding.decode(UInt8.self, from: SnapshotCoding.encode(UInt8.max)) == .max)
    #expect(
      try SnapshotCoding.decode(
        Float.self, from: SnapshotCoding.encode(Float.leastNonzeroMagnitude))
        == Float.leastNonzeroMagnitude)
    for value in [Double.nan, .infinity, -.infinity, -0.0] {
      let encoded = try SnapshotCoding.encode(value)
      #expect(encoded == encoded)
      #expect(try SnapshotCoding.decode(Double.self, from: encoded).bitPattern == value.bitPattern)
    }
    let missing: Int? = nil
    #expect(try SnapshotCoding.encode(missing) == .null)
    #expect(try SnapshotCoding.decode(Int?.self, from: .null) == nil)
    #expect(throws: (any Error).self) { try SnapshotCoding.decode(Int8.self, from: .signed(128)) }
    #expect(throws: (any Error).self) { try SnapshotCoding.decode(UInt64.self, from: .signed(-1)) }
    #expect(throws: (any Error).self) { try SnapshotCoding.decode(Int.self, from: .string("1")) }
  }

  @Test func decodingFailureAndContainerBounds() throws {
    #expect(throws: (any Error).self) {
      try SnapshotCoding.decode(ReloadRecord.self, from: .object([:]))
    }
    #expect(throws: SnapshotCodingError.limitExceeded) {
      try SnapshotCoding.encode(Array(0..<20), limits: .init(maximumValues: 8))
    }
    #expect(throws: SnapshotCodingError.limitExceeded) {
      try SnapshotCoding.encode(CyclicCoding(), limits: .init(maximumDepth: 8))
    }
    #expect(throws: SnapshotCodingError.limitExceeded) {
      try SnapshotCoding.encode(RecursiveSingleCoding(), limits: .init(maximumDepth: 8))
    }
    #expect(throws: SnapshotCodingError.limitExceeded) {
      try SnapshotCoding.decode(
        RecursiveSingleCoding.self, from: .null, limits: .init(maximumDepth: 8))
    }
    #expect(throws: SnapshotCodingError.limitExceeded) {
      try SnapshotCoding.encode(["large": "payload"], limits: .init(maximumUTF8Bytes: 8))
    }
    #expect(throws: SnapshotCodingError.limitExceeded) {
      try SnapshotCoding.decode(
        String.self, from: .string("éé"), limits: .init(maximumUTF8Bytes: 3))
    }
    #expect(throws: SnapshotCodingError.limitExceeded) {
      try SnapshotCoding.decode(
        [Int].self, from: .array([.signed(1)]), limits: .init(maximumDepth: 0))
    }
  }
}

@MainActor
@Suite("Hot-reload state replay")
struct HotReloadReplayTests {
  @Test func declaredImageModuleAliasesReconstructReferencesWithoutRewritingUserKeys() throws {
    let type = String(reflecting: ReloadModel.self)
    let parts = type.split(separator: ".", maxSplits: 1)
    let encoded = try SnapshotCoding.encode(ReloadModel(count: 42))
    let address = HotReloadSlotAddress(owner: Identity(components: ["ID[Image.Type]"]), slot: slot(10))
    for permitsAlias in [false, true] {
      let graph = ViewGraph()
      try graph.installHotReloadReplay(
        .init(sourceRoot: source, entries: [
          .init(address: address, typeName: "Image." + parts[1], value: encoded)
        ]), at: destination,
        owners: [.init(identity: address.owner, slots: [slot(10): type])],
        typeAliases: permitsAlias ? ["Image": String(parts[0])] : [:])
      let restored: ReloadModel? = graph.restoredHotReloadValue(for: absolute(address.owner), slot: slot(10))
      #expect(restored?.count == (permitsAlias ? 42 : nil))
    }
    let aliases = ["Image": "Logical"]
    #expect(HotReloadTypeNames.canonical("Swift.Array<Image.Record>", aliases: aliases)
      == "Swift.Array<Logical.Record>")
    #expect(HotReloadTypeNames.canonical("OtherImage.Record", aliases: aliases) == "OtherImage.Record")
    #expect(HotReloadTypeNames.canonical("Container.Image.Record", aliases: aliases) == "Container.Image.Record")
    #expect(HotReloadTypeNames.canonical("Image", aliases: aliases) == "Image")
  }
  private let source = Identity(components: ["App", "Generation[0]"])
  private let destination = Identity(components: ["App", "Generation[1]"])
  private let owner = Identity(components: ["Root"])
  private func slot(_ ordinal: Int, path: [Int] = []) -> StateSlotIdentifier {
    .init(ordinal: ordinal, path: .init(fieldIndices: path))
  }
  private func entry(
    _ ordinal: Int, owner: Identity? = nil, value: Int = 41, path: [Int] = []
  ) -> HotReloadSnapshot.Entry {
    .init(
      address: .init(owner: owner ?? self.owner, slot: slot(ordinal, path: path)),
      typeName: String(reflecting: Int.self), value: .signed(Int64(value))
    )
  }
  private func schema(
    _ ordinals: [Int], owner: Identity? = nil, path: [Int] = []
  ) -> HotReloadOwnerSchema {
    .init(
      identity: owner ?? self.owner,
      slots: Dictionary(
        uniqueKeysWithValues: ordinals.map {
          (slot($0, path: path), String(reflecting: Int.self))
        }))
  }
  private func absolute(_ relative: Identity) -> Identity {
    Identity(components: destination.components + relative.components)
  }

  @Test func exactRebaseInitializesBeforeFirstReadWithoutAliasing() throws {
    let graph = ViewGraph()
    let old = graph.prepareDynamicPropertyUpdate(identity: source.child("Root"))
    withOwnedDormantStateSlot { old.setStateSlot(ordinal: 10, value: 42) }
    let snapshot = graph.captureHotReloadSnapshot(rootedAt: source)
    try graph.installHotReloadReplay(snapshot, at: destination, owners: [schema([10])])
    let new = graph.prepareDynamicPropertyUpdate(identity: destination.child("Root"))
    #expect(new.stateSlot(ordinal: 10, seed: 0) == 42)
    #expect(new.ownerLifetimeID != old.ownerLifetimeID)
    new.setStateSlot(ordinal: 10, value: 99)
    #expect(old.stateSlot(ordinal: 10, seed: 0) == 42)
    #expect(graph.finishHotReloadReplay().isEmpty)
  }

  @Test func shiftedOrdinalsReserveTheWholeGroup() {
    // The new first declaration now occupies the old second one's line.
    var replay = HotReloadReplay(
      snapshot: .init(sourceRoot: source, entries: [entry(10, value: 7), entry(20, value: 9)]),
      destinationRoot: destination, owners: [schema([20, 30])]
    )
    let first: Int? = replay.value(for: absolute(owner), slot: slot(20))
    let second: Int? = replay.value(for: absolute(owner), slot: slot(30))
    #expect(first == 7)
    #expect(second == 9)
    #expect(replay.finish().isEmpty)
  }

  @Test func countChangesRefuseRankAndNestedPathsStaySeparate() {
    var replay = HotReloadReplay(
      snapshot: .init(
        sourceRoot: source,
        entries: [
          entry(10, value: 3, path: [0]), entry(10, value: 8, path: [1]),
        ]),
      destinationRoot: destination,
      owners: [
        .init(
          identity: owner,
          slots: [
            slot(20, path: [0]): String(reflecting: Int.self),
            slot(30, path: [0]): String(reflecting: Int.self),
            slot(20, path: [1]): String(reflecting: Int.self),
          ])
      ]
    )
    let refused: Int? = replay.value(for: absolute(owner), slot: slot(20, path: [0]))
    let restored: Int? = replay.value(for: absolute(owner), slot: slot(20, path: [1]))
    #expect(refused == nil)
    #expect(restored == 8)
    #expect(replay.finish().count == 1)
  }

  @Test func uniqueWrapperInsertionAndRemoval() {
    let wrapped = Identity(components: ["Wrapper", "Root"])
    for (old, new) in [(owner, wrapped), (wrapped, owner)] {
      var replay = HotReloadReplay(
        snapshot: .init(sourceRoot: source, entries: [entry(10, owner: old)]),
        destinationRoot: destination, owners: [schema([10], owner: new)]
      )
      let restored: Int? = replay.value(for: absolute(new), slot: slot(10))
      #expect(restored == 41)
      #expect(replay.finish().isEmpty)
    }
  }

  @Test func ambiguityIsRefusedInBothDirections() {
    let a = Identity(components: ["A", "Root"])
    let b = Identity(components: ["B", "Root"])
    let inputs: [([HotReloadSnapshot.Entry], [HotReloadOwnerSchema])] = [
      ([entry(10)], [schema([10], owner: a), schema([10], owner: b)]),
      ([entry(10, owner: a), entry(10, owner: b)], [schema([10])]),
      ([entry(10)], [schema([10]), schema([10])]),
      ([entry(10), entry(10)], [schema([10])]),
    ]
    for (entries, schemas) in inputs {
      var replay = HotReloadReplay(
        snapshot: .init(sourceRoot: source, entries: entries),
        destinationRoot: destination, owners: schemas
      )
      #expect(replay.pending.isEmpty)
      #expect(replay.finish().count == entries.count)
    }
  }

  @Test func exactOwnersCannotDonateToWrappersOrEntitySiblings() {
    let a = Identity(components: ["ID[a]", "Root"])
    let b = Identity(components: ["ID[b]", "Root"])
    var replay = HotReloadReplay(
      snapshot: .init(sourceRoot: source, entries: [entry(10, owner: a, value: 5), entry(10)]),
      destinationRoot: destination,
      owners: [schema([10], owner: a), schema([10], owner: b), schema([10], owner: owner)]
    )
    let entity: Int? = replay.value(for: absolute(a), slot: slot(10))
    let fresh: Int? = replay.value(for: absolute(b), slot: slot(10))
    #expect(entity == 5)
    #expect(fresh == nil)
    #expect(replay.finish().count == 1)  // Root was deliberately never read.
  }

  @Test func valuesAreConsumedOnceAndFailuresKeepSeed() throws {
    let graph = ViewGraph()
    let snapshot = HotReloadSnapshot(
      sourceRoot: source,
      entries: [
        .init(
          address: .init(owner: owner, slot: slot(10)),
          typeName: String(reflecting: Int.self), value: .string("invalid"))
      ])
    try graph.installHotReloadReplay(snapshot, at: destination, owners: [schema([10])])
    let node = graph.prepareDynamicPropertyUpdate(identity: absolute(owner))
    #expect(node.stateSlot(ordinal: 10, seed: 12) == 12)
    #expect(node.stateSlot(ordinal: 10, seed: 0) == 12)
    let report = graph.finishHotReloadReplay()
    #expect(report.count == 1)
    #expect(report[0].reason.hasPrefix("Decode failed:"))
  }

  @Test func checkpointRollbackRestoresReplayClaims() throws {
    let graph = ViewGraph()
    try graph.installHotReloadReplay(
      .init(sourceRoot: source, entries: [entry(10)]), at: destination, owners: [schema([10])]
    )
    let checkpoint = graph.makeCheckpoint()
    let first = graph.prepareDynamicPropertyUpdate(identity: absolute(owner))
    #expect(first.stateSlot(ordinal: 10, seed: 0) == 41)
    _ = graph.restoreCheckpoint(checkpoint)
    #expect(graph.hotReloadReplay?.restoredCount == 0)
    let second = graph.prepareDynamicPropertyUpdate(identity: absolute(owner))
    #expect(second.ownerLifetimeID != first.ownerLifetimeID)
    #expect(second.stateSlot(ordinal: 10, seed: 0) == 41)
    #expect(graph.finishHotReloadReplay().isEmpty)
  }

  @Test func applicationDecoderCanInspectGraphWithoutOverlappingMutableAccess() throws {
    let graph = ViewGraph()
    let old = graph.prepareDynamicPropertyUpdate(identity: source.child("Root"))
    withOwnedDormantStateSlot {
      old.setStateSlot(ordinal: 10, value: ReentrantReloadValue(count: 19))
    }
    try graph.installHotReloadReplay(
      graph.captureHotReloadSnapshot(rootedAt: source), at: destination,
      owners: [
        .init(
          identity: owner,
          slots: [
            slot(10): String(reflecting: ReentrantReloadValue.self)
          ])
      ]
    )
    var observedClaim = false
    ReentrantReloadValue.onDecode = {
      observedClaim = graph.hotReloadReplay?.pending.isEmpty == true
      old.setStateSlot(ordinal: 10, value: ReentrantReloadValue(count: 20))
    }
    defer { ReentrantReloadValue.onDecode = nil }
    let new = graph.prepareDynamicPropertyUpdate(identity: absolute(owner))
    #expect(new.stateSlot(ordinal: 10, seed: ReentrantReloadValue(count: 0)).count == 19)
    #expect(observedClaim)
    #expect(graph.finishHotReloadReplay().isEmpty)
  }

  @Test func freshGraphReconstructsReferencesAndSnapshotReleasesOldObjects() throws {
    weak var released: ReloadModel?
    let snapshot: HotReloadSnapshot
    do {
      let graph = ViewGraph()
      let model = ReloadModel(count: 73)
      released = model
      let node = graph.prepareDynamicPropertyUpdate(identity: source.child("Root"))
      withOwnedDormantStateSlot { node.setStateSlot(ordinal: 10, value: model) }
      snapshot = graph.captureHotReloadSnapshot(rootedAt: source)
    }
    #expect(released == nil)
    let graph = ViewGraph()
    try graph.installHotReloadReplay(
      snapshot, at: destination,
      owners: [
        .init(identity: owner, slots: [slot(10): String(reflecting: ReloadModel.self)])
      ])
    let seed = ReloadModel(count: 0)
    let new = graph.prepareDynamicPropertyUpdate(identity: absolute(owner))
    let restored = new.stateSlot(ordinal: 10, seed: seed)
    #expect(restored !== seed)
    #expect(restored.count == 73)
    #expect(graph.finishHotReloadReplay().isEmpty)
  }

  @Test func unsupportedAndTransientSlotsAreReported() {
    let graph = ViewGraph()
    let node = graph.prepareDynamicPropertyUpdate(identity: source.child("Root"))
    withOwnedDormantStateSlot { node.setStateSlot(ordinal: 10, value: { 1 }) }
    node.setStateSlot(ordinal: -1, value: 99)
    let snapshot = graph.captureHotReloadSnapshot(rootedAt: source)
    #expect(snapshot.entries.count == 2)
    #expect(snapshot.entries.allSatisfy { $0.value == nil && $0.failure != nil })
    var replay = HotReloadReplay(snapshot: snapshot, destinationRoot: destination, owners: [])
    #expect(replay.finish().count == 2)
  }

  @Test func optionalNilIsAReplayValueAndWrongGraphsCannotConsumeIt() throws {
    let graph = ViewGraph()
    let old = graph.prepareDynamicPropertyUpdate(identity: source.child("Root"))
    withOwnedDormantStateSlot { old.setStateSlot(ordinal: 10, value: Optional<Int>.none) }
    try graph.installHotReloadReplay(
      graph.captureHotReloadSnapshot(rootedAt: source),
      at: destination,
      owners: [
        .init(
          identity: owner, slots: [slot(10): String(reflecting: Int?.self)]
        )
      ])
    let otherGraph = ViewGraph()
    let other = otherGraph.prepareDynamicPropertyUpdate(identity: absolute(owner))
    #expect(other.stateSlot(ordinal: 10, seed: Optional(8)) == 8)
    let new = graph.prepareDynamicPropertyUpdate(identity: absolute(owner))
    #expect(new.stateSlot(ordinal: 10, seed: Optional(8)) == nil)
    #expect(graph.finishHotReloadReplay().isEmpty)
  }

  @Test func rejectedOwnerSchemaNeverDonatesToANearbyOwner() {
    let nearby = Identity(components: ["Wrapper", "Root"])
    var replay = HotReloadReplay(
      snapshot: .init(sourceRoot: source, entries: [entry(10)]),
      destinationRoot: destination,
      owners: [
        .init(identity: owner, slots: [slot(10): String(reflecting: String.self)]),
        schema([10], owner: nearby),
      ]
    )
    let refused: Int? = replay.value(for: absolute(nearby), slot: slot(10))
    #expect(refused == nil)
    #expect(replay.finish().count == 1)
  }

  @Test func refusesExistingDestinationAndOverlappingGenerations() throws {
    let graph = ViewGraph()
    let snapshot = HotReloadSnapshot(sourceRoot: source, entries: [entry(10)])
    #expect(throws: (any Error).self) {
      try graph.installHotReloadReplay(snapshot, at: source, owners: [schema([10])])
    }
    _ = graph.prepareDynamicPropertyUpdate(identity: destination.child("Root"))
    #expect(throws: (any Error).self) {
      try graph.installHotReloadReplay(snapshot, at: destination, owners: [schema([10])])
    }
  }

  @Test func inactiveValuesRequireTheWholeExactDeclarationSetBeforeClaiming() throws {
    for changed in [false, true] {
      let graph = ViewGraph()
      var first = entry(10, value: 7)
      var second = entry(20, value: 9)
      first.isDormant = true
      second.isDormant = true
      try graph.installHotReloadReplay(
        .init(sourceRoot: source, entries: [first, second]),
        at: destination, owners: [])
      let identity = absolute(owner)
      let premature: Int? = graph.restoredHotReloadValue(for: identity, slot: slot(20))
      #expect(premature == nil)
      #expect(graph.needsDormantHotReloadSchema(for: identity))
      graph.validateDormantHotReloadSchema(
        for: identity,
        slots: schema(changed ? [20, 30] : [10, 20]).slots, ambiguous: false)
      let value: Int? = graph.restoredHotReloadValue(for: identity, slot: slot(20))
      #expect(value == (changed ? nil : 9))
      if changed { #expect(graph.finishHotReloadReplay().count == 2) }
    }
  }
}
