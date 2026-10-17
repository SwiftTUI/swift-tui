// Adversarial set B, pass 4: hot reload (301–310).
//
// Compiled hot reload captures every initialized state slot into a detached
// Codable archive, rehearses the replacement root until its declared schema
// converges, and replays values by owner identity, slot ordinal and reflected
// type name. These probes sit on the seams of that contract: module aliasing
// of reflected names that are not dotted, the coder's undocumented size
// bounds, the declaration-rank fallback under a reorder, focus rebase without
// a stateful owner, dormant tab entries under a wrapper edit, a grown
// declaration set, the loader's sequence and spool validation, the cost of a
// rehearsal, and the coder's container conventions against Foundation.
import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: hot reload", .serialized)
struct AdversarialSetBHotReloadTests {
  // A module alias rewrites every occurrence of the image module in a
  // reflected type name, including the `(extension in Module):` context.
  @Test func setB301ExtensionContextModuleNamesCanonicalize() throws {
    let hostName = String(reflecting: Int.SetBReloadExtensionPayload.self)
    try #require(hostName.contains("extension in SwiftTUITests"), "\(hostName)")
    let imageName = hostName.replacingOccurrences(of: "SwiftTUITests", with: "SetBImage")
    let aliases = ["SetBImage": "SwiftTUITests"]
    #expect(
      HotReloadTypeNames.canonical("SetBImage.Model", aliases: aliases) == "SwiftTUITests.Model")
    #expect(
      HotReloadTypeNames.canonical("Swift.Array<SetBImage.Model>", aliases: aliases)
        == "Swift.Array<SwiftTUITests.Model>")
    let slot = setBSlot(10)
    let encoded = try SnapshotCoding.encode(Int.SetBReloadExtensionPayload(value: 9))
    var replay = HotReloadReplay(
      snapshot: .init(
        sourceRoot: setBSourceRoot,
        entries: [
          .init(address: .init(owner: setBOwner, slot: slot), typeName: imageName, value: encoded)
        ]),
      destinationRoot: setBDestinationRoot,
      owners: [.init(identity: setBOwner, slots: [slot: hostName])], typeAliases: aliases)
    let restored: Int.SetBReloadExtensionPayload? = replay.value(
      for: setBAbsolute(setBOwner), slot: slot)
    do {
      #expect(HotReloadTypeNames.canonical(imageName, aliases: aliases) == hostName, "\(imageName)")
      #expect(restored?.value == 9, "\(replay.diagnostics)")
    }
  }

  // Ordinary large state is captured for replay: a 70,000-element array and a
  // string just over 4 MiB are neither non-Codable, transient, ambiguous nor
  // schema changes.
  @Test func setB302LargeArchivesAreCapturedForReplay() throws {
    let graph = ViewGraph()
    let node = graph.prepareDynamicPropertyUpdate(identity: setBSourceRoot.child("Root"))
    withOwnedDormantStateSlot {
      node.setStateSlot(ordinal: 10, value: Array(0..<70_000))
      node.setStateSlot(ordinal: 11, value: String(repeating: "a", count: 4_194_305))
    }
    let snapshot = graph.captureHotReloadSnapshot(rootedAt: setBSourceRoot)
    let entries = Dictionary(
      uniqueKeysWithValues: snapshot.entries.map { ($0.address.slot.ordinal, $0) })
    let array = try #require(entries[10])
    let text = try #require(entries[11])
    do {
      #expect(array.value != nil && array.failure == nil, "\(array.failure ?? "no failure")")
      #expect(text.value != nil && text.failure == nil, "\(text.failure ?? "no failure")")
      let restoredArray: [Int] = try HotReloadReplay.decode(array)
      let restoredText: String = try HotReloadReplay.decode(text)
      #expect(restoredArray == Array(0..<70_000))
      #expect(restoredText.utf8.count == 4_194_305)
    }
    #expect(throws: Never.self) { _ = try SnapshotCoding.encode(Array(0..<65_535)) }
    #expect(throws: SnapshotCodingError.limitExceeded) {
      _ = try SnapshotCoding.encode(Array(0..<65_536))
    }
    #expect(throws: Never.self) {
      _ = try SnapshotCoding.encode(String(repeating: "a", count: 4_194_304))
    }
    #expect(throws: SnapshotCodingError.limitExceeded) {
      _ = try SnapshotCoding.encode(String(repeating: "a", count: 4_194_305))
    }
  }

  // The declaration-rank fallback restores two declarations shifted by an edit
  // above them, and does not exchange their values when the two declarations
  // are reordered.
  @Test func setB303RankFallbackSurvivesShiftsButSwapsReorderedDeclarations() throws {
    let probe = SetBReloadProbe()
    let h = try SetBReloadHarness("Rank") { SetBPairRoot(probe: probe, aLine: 1000, bLine: 1001) }
    defer { h.shutdown() }
    probe.set?(5, 7)
    try h.drain()
    try #require(h.frame.contains("a=5 b=7"), "\(h.frame)")
    try h.reload { SetBPairRoot(probe: probe, aLine: 1002, bLine: 1003) }
    #expect(h.frame.contains("a=5 b=7"), "\(h.frame) \(h.session.lastReport)")
    #expect(h.session.lastReport.isEmpty, "\(h.session.lastReport)")
    try h.reload { SetBPairRoot(probe: probe, aLine: 1003, bLine: 1002) }
    do {
      #expect(
        h.frame.contains("a=5 b=7") && h.session.lastReport.isEmpty,
        "\(h.frame) \(h.session.lastReport)")
    }
  }

  // Focus survives a one-wrapper edit whether or not a stateful owner encloses
  // the focused control: the rebased identity differs from the old one by the
  // inserted wrapper component only.
  @Test func setB304FocusFollowsAUniqueWrapperEditLikeStateDoes() throws {
    let stateless = try SetBReloadHarness("FocusStateless") { SetBFocusButtons(version: "one") }
    defer { stateless.shutdown() }
    let oldStateless = try setBFocusOffFirstRegion(stateless)
    try stateless.reload { SetBFocusButtons(version: "two").padding(1) }
    #expect(stateless.frame.contains("two"), "\(stateless.frame)")
    let statelessRoot = try #require(stateless.session.generationRoot)
    let newStateless = stateless.loop.focusTracker.currentFocusIdentity.flatMap {
      HotReloadReplay.relative($0, to: statelessRoot)
    }
    do {
      #expect(
        newStateless.map { setBDiffersByOneComponent(oldStateless, $0) } == true,
        "\(oldStateless) -> \(String(describing: newStateless))")
    }

    let stateful = try SetBReloadHarness("FocusStateful") { SetBFocusCounter(version: "one") }
    defer { stateful.shutdown() }
    let oldStateful = try setBFocusOffFirstRegion(stateful)
    try stateful.reload { SetBFocusCounter(version: "two").padding(1) }
    #expect(stateful.frame.contains("two count=0"), "\(stateful.frame)")
    let statefulRoot = try #require(stateful.session.generationRoot)
    let newStateful = stateful.loop.focusTracker.currentFocusIdentity.flatMap {
      HotReloadReplay.relative($0, to: statefulRoot)
    }
    #expect(
      newStateful.map { setBDiffersByOneComponent(oldStateful, $0) } == true,
      "\(oldStateful) -> \(String(describing: newStateful)) \(stateful.session.lastReport)")
  }

  // An inactive tab's archived value replays after a wrapper edit inside that
  // tab, or the drop is reported for that slot; the active tab's exact owner
  // replays either way.
  @Test func setB305InactiveTabStateSurvivesAWrapperEditInsideTheTab() throws {
    let probe = SetBReloadProbe()
    let h = try SetBReloadHarness("TabWrapper") { SetBTabRootPlain(probe: probe) }
    defer { h.shutdown() }
    probe.increment["A"]?()
    try h.drain()
    try #require(h.frame.contains("A count=1"), "\(h.frame)")
    probe.select?(1)
    try h.drain()
    try #require(h.frame.contains("B count=0"), "\(h.frame)")
    probe.increment["B"]?()
    probe.increment["B"]?()
    try h.drain()
    try #require(h.frame.contains("B count=2"), "\(h.frame)")
    probe.select?(0)
    try h.drain()
    try #require(h.frame.contains("A count=1"), "\(h.frame)")
    try h.reload { SetBTabRootWrappedB(probe: probe) }
    #expect(h.frame.contains("A count=1"), "\(h.frame) \(h.session.lastReport)")
    probe.select?(1)
    try h.drain()
    let bOrdinal = StateSlotOrdinals.authored(line: 1022, column: 1)
    let reported = h.session.lastReport.contains { $0.address.slot.ordinal == bOrdinal }
    do {
      #expect(h.frame.contains("B count=2") || reported, "\(h.frame) \(h.session.lastReport)")
    }
  }

  // Adding a second @State below an existing one keeps the existing slot,
  // whose ordinal and type still match exactly; the new slot takes its seed.
  @Test func setB306AddingADeclarationKeepsTheExistingSlot() throws {
    let slot = setBSlot(10)
    let intName = String(reflecting: Int.self)
    var replay = HotReloadReplay(
      snapshot: .init(
        sourceRoot: setBSourceRoot,
        entries: [
          .init(address: .init(owner: setBOwner, slot: slot), typeName: intName, value: .signed(41))
        ]),
      destinationRoot: setBDestinationRoot,
      owners: [.init(identity: setBOwner, slots: [slot: intName, setBSlot(20): intName])])
    let restored: Int? = replay.value(for: setBAbsolute(setBOwner), slot: slot)
    do {
      #expect(restored == 41, "\(replay.diagnostics)")
    }

    let probe = SetBReloadProbe()
    let h = try SetBReloadHarness("Grow") { SetBOneSlotRoot(probe: probe) }
    defer { h.shutdown() }
    for _ in 0..<3 {
      probe.increment["count"]?()
    }
    try h.drain()
    try #require(h.frame.contains("count=3"), "\(h.frame)")
    try h.reload { SetBTwoSlotRoot(probe: probe) }
    #expect(h.frame.contains("extra=0"), "\(h.frame)")
    let countOrdinal = StateSlotOrdinals.authored(line: 1010, column: 1)
    #expect(
      !h.session.lastReport.contains { $0.address.slot.ordinal == countOrdinal },
      "the surviving declaration is preserved: \(h.session.lastReport)")
    do {
      #expect(h.frame.contains("count=3"), "\(h.frame) \(h.session.lastReport)")
    }
  }

  #if DEBUG && (os(macOS) || os(Linux))
    // An image that cannot be loaded is refused before counting toward the
    // image cap, both files are removed, and its sequence number is consumed.
    @Test func setB307UnloadableImagesDoNotCountButConsumeTheirSequence() throws {
      let spool = try SetBSpool()
      defer { spool.clean() }
      let loader = try HotReloadLoader(spoolPath: spool.root.path, expectedToolchain: 12345)
      try spool.writeImage(1, bytes: [1, 2, 3])
      try spool.publish(1)
      #expect(throws: HotReloadLoadError.self) { try loader.loadPending() }
      #expect(loader.loadedImageCount == 0)
      #expect(!spool.exists(HotReloadLoader.imageName(1)))
      #expect(!spool.exists("pending"))
      try spool.writeImage(1, bytes: [1, 2, 3])
      try spool.publish(1)
      #expect(throws: HotReloadLoadError.self) { try loader.loadPending() }
      #expect(spool.exists(HotReloadLoader.imageName(1)), "a stale manifest leaves its image")
      #expect(!spool.exists("pending"))
      try spool.publish(2)
      do {
        _ = try loader.loadPending()
        Issue.record("a missing image loaded")
      } catch {
        #expect(String(describing: error).contains("Cannot open reload image"), "\(error)")
      }
      #expect(loader.loadedImageCount == 0)
      #expect(try loader.loadPending() == nil)
    }

    // The spool must be a direct same-user 0700 directory in a host that
    // exports the contract scalars; a malformed manifest is an error that is
    // consumed without advancing the sequence.
    @Test func setB308SpoolAndManifestValidationEdges() throws {
      let spool = try SetBSpool()
      defer { spool.clean() }
      let link = spool.root.deletingLastPathComponent()
        .appendingPathComponent("setb-hot-reload-link-" + UUID().uuidString)
      try FileManager.default.createSymbolicLink(at: link, withDestinationURL: spool.root)
      defer { try? FileManager.default.removeItem(at: link) }
      #expect(throws: HotReloadLoadError.self) {
        _ = try HotReloadLoader(spoolPath: link.path, expectedToolchain: 12345)
      }
      #expect(throws: HotReloadLoadError.self) {
        _ = try HotReloadLoader(spoolPath: "setb-relative-spool", expectedToolchain: 12345)
      }
      #expect(throws: HotReloadLoadError.self) {
        _ = try HotReloadLoader(spoolPath: spool.root.path)
      }
      let loader = try HotReloadLoader(spoolPath: spool.root.path, expectedToolchain: 12345)
      #expect(try loader.loadPending() == nil)
      #expect(FileManager.default.createFile(atPath: spool.path("pending"), contents: Data()))
      #expect(throws: HotReloadLoadError.self) { try loader.loadPending() }
      #expect(!spool.exists("pending"), "an empty manifest is consumed")
      #expect(try loader.loadPending() == nil)
      try spool.publish(1, mode: 0o664)
      #expect(throws: HotReloadLoadError.self) { try loader.loadPending() }
      try spool.publish(0)
      #expect(throws: HotReloadLoadError.self) { try loader.loadPending() }
      try spool.publish(1, manifest: "SwiftTUIReload1\n1\n\(HotReloadLoader.imageName(1))\n\n")
      #expect(throws: HotReloadLoadError.self) { try loader.loadPending() }
      try spool.publish(1)
      do {
        _ = try loader.loadPending()
        Issue.record("sequence 1 should still be fresh")
      } catch {
        #expect(String(describing: error).contains("Cannot open reload image"), "\(error)")
      }
      #expect(loader.loadedImageCount == 0)
    }
  #endif

  // A reload rehearses a stateful root twice and a stateless root once, and
  // decodes a replayed value once during rehearsal and once at commit.
  @Test func setB309RehearsalEvaluatesTheRootFactoryTwiceAndDecodesOnce() throws {
    SetBCountingPayload.decodes = 0
    let probe = SetBReloadProbe()
    let h = try SetBReloadHarness("Cost") { SetBCostRoot(probe: probe.noteFactory()) }
    defer { h.shutdown() }
    probe.setPayload?(5)
    try h.drain()
    try #require(h.frame.contains("value=5"), "\(h.frame)")
    try #require(SetBCountingPayload.decodes == 0)
    let factoryBefore = probe.factory
    try h.loop.replaceHotReloadGeneration(
      HotReloadGeneration { SetBCostRoot(probe: probe.noteFactory()) })
    #expect(
      probe.factory - factoryBefore == 2, "rehearsal passes: \(probe.factory - factoryBefore)")
    #expect(SetBCountingPayload.decodes == 1, "\(SetBCountingPayload.decodes)")
    #expect(h.session.awaitingCommit)
    try h.drain()
    #expect(h.frame.contains("value=5"), "\(h.frame) \(h.session.lastReport)")
    #expect(SetBCountingPayload.decodes == 2, "\(SetBCountingPayload.decodes)")
    #expect(probe.factory - factoryBefore == 3, "\(probe.factory - factoryBefore)")
    #expect(!h.session.awaitingCommit)
    #expect(h.session.lastReport.isEmpty, "\(h.session.lastReport)")

    let stateless = SetBReloadProbe()
    let s = try SetBReloadHarness("CostStateless") {
      SetBStaticRoot(probe: stateless.noteFactory(), version: "one")
    }
    defer { s.shutdown() }
    let staticBefore = stateless.factory
    try s.loop.replaceHotReloadGeneration(
      HotReloadGeneration { SetBStaticRoot(probe: stateless.noteFactory(), version: "two") })
    #expect(stateless.factory - staticBefore == 1, "\(stateless.factory - staticBefore)")
    try s.drain()
    #expect(s.frame.contains("two"), "\(s.frame)")
    #expect(stateless.factory - staticBefore == 2, "\(stateless.factory - staticBefore)")
  }

  // The snapshot coder follows the Codable container conventions Foundation's
  // JSONEncoder implements, including last-write-wins for a repeated key.
  @Test func setB310SnapshotCoderFollowsCodableContainerConventions() throws {
    let intKeyed: [Int: String] = [3: "c", -1: "m"]
    let encodedIntKeyed = try SnapshotCoding.encode(intKeyed)
    #expect(
      encodedIntKeyed == .object(["3": .string("c"), "-1": .string("m")]), "\(encodedIntKeyed)")
    #expect(try SnapshotCoding.decode([Int: String].self, from: encodedIntKeyed) == intKeyed)
    let narrowKeyed: [Int8: Int] = [1: 10, 2: 20]
    #expect(
      try SnapshotCoding.decode([Int8: Int].self, from: SnapshotCoding.encode(narrowKeyed))
        == narrowKeyed)
    let set: Set<Int> = [5, 1, 9]
    #expect(try SnapshotCoding.decode(Set<Int>.self, from: SnapshotCoding.encode(set)) == set)
    let cluster = "👩‍👩‍👧"
    #expect(
      try SnapshotCoding.decode(String.self, from: SnapshotCoding.encode(cluster)) == cluster)
    let awkwardKeys = ["a/b": 1, "nul\0key": 2, "": 3]
    #expect(
      try SnapshotCoding.decode([String: Int].self, from: SnapshotCoding.encode(awkwardKeys))
        == awkwardKeys)
    let nested: Int?? = .some(.none)
    #expect(try SnapshotCoding.encode(nested) == .null)
    #expect(try SnapshotCoding.decode(Int??.self, from: .null) == nil)
    #expect(try SnapshotCoding.encode(SetBEmptyRecord()) == .object([:]))
    #expect(
      try SnapshotCoding.decode(SetBEmptyRecord.self, from: .object([:])) == SetBEmptyRecord())
    #expect(throws: SnapshotCodingError.missingValue) {
      _ = try SnapshotCoding.encode(SetBSilentRecord())
    }
    #expect(throws: Never.self) { _ = try JSONEncoder().encode(SetBDuplicateKeyRecord()) }
    do {
      let encoded = try SnapshotCoding.encode(SetBDuplicateKeyRecord())
      #expect(encoded == .object(["value": .signed(2)]), "\(encoded)")
    }
  }
}

private let setBSourceRoot = Identity(components: ["App", "Generation[0]"])
private let setBDestinationRoot = Identity(components: ["App", "Generation[1]"])
private let setBOwner = Identity(components: ["Root"])

private func setBSlot(_ ordinal: Int) -> StateSlotIdentifier {
  StateSlotIdentifier(ordinal: ordinal)
}

private func setBAbsolute(_ relative: Identity) -> Identity {
  Identity(components: setBDestinationRoot.components + relative.components)
}

private func setBDiffersByOneComponent(_ shorter: Identity, _ longer: Identity) -> Bool {
  let short = shorter.components
  let long = longer.components
  guard long.count == short.count + 1 else { return false }
  return long.indices.contains { index in
    Array(long[..<index]) + Array(long[(index + 1)...]) == short
  }
}

@MainActor
private func setBFocusOffFirstRegion(_ h: SetBReloadHarness) throws -> Identity {
  for _ in 0..<3 {
    let tracker = h.loop.focusTracker
    if let focused = tracker.currentFocusIdentity,
      focused != tracker.focusRegions.first?.identity
    {
      break
    }
    _ = h.loop.handle(.input(.key(KeyPress(.tab))))
    try h.drain()
  }
  let tracker = h.loop.focusTracker
  let focused = try #require(tracker.currentFocusIdentity)
  try #require(
    focused != tracker.focusRegions.first?.identity, "focus stayed on the first region")
  let root = try #require(h.session.generationRoot)
  return try #require(HotReloadReplay.relative(focused, to: root))
}

@MainActor
private final class SetBReloadHarness {
  let session: HotReloadSession
  let surface = RecordingPresentationSurface(surfaceSize: .init(width: 40, height: 10))
  let loop: SwiftTUIRuntime.RunLoop<Int, HotReloadHost>
  var frames = 0

  init<Content: View>(
    _ name: String, @ViewBuilder content: @escaping @MainActor () -> Content
  ) throws {
    let session = HotReloadSession(content: HotReloadGeneration(content: content))
    self.session = session
    let identity = testIdentity("SetBHotReload", name)
    loop = SwiftTUIRuntime.RunLoop(
      rootIdentity: identity, presentationSurface: surface,
      terminalInputReader: InjectedTerminalInputReader(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [identity]),
      focusTracker: FocusTracker(invalidationIdentities: [identity]),
      proposal: .init(width: 40, height: 10)
    ) { _, _ in HotReloadHost(session: session) }
    loop.installHotReloadSession(session)
    loop.scheduler.requestInvalidation(of: [identity])
    try drain()
  }

  var frame: String { surface.frames.last ?? "" }

  func drain() throws {
    try loop.renderPendingFrames(renderedFrames: &frames)
  }

  func reload<Content: View>(@ViewBuilder content: @escaping @MainActor () -> Content) throws {
    try loop.replaceHotReloadGeneration(HotReloadGeneration(content: content))
    try drain()
  }

  func shutdown() {
    loop.lifecycleCoordinator.shutdown()
  }
}

@MainActor
private final class SetBReloadProbe {
  var factory = 0
  var set: ((Int, Int) -> Void)?
  var increment: [String: () -> Void] = [:]
  var select: ((Int) -> Void)?
  var setPayload: ((Int) -> Void)?

  func noteFactory() -> SetBReloadProbe {
    factory += 1
    return self
  }
}

extension Int {
  struct SetBReloadExtensionPayload: Codable, Equatable {
    var value: Int
  }
}

private struct SetBCountingPayload: Codable, Equatable {
  @MainActor static var decodes = 0
  var value: Int

  init(value: Int) {
    self.value = value
  }

  init(from decoder: any Decoder) throws {
    MainActor.assumeIsolated { Self.decodes += 1 }
    value = try decoder.singleValueContainer().decode(Int.self)
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }
}

private struct SetBEmptyRecord: Codable, Equatable {}

private struct SetBSilentRecord: Encodable {
  func encode(to encoder: any Encoder) throws {}
}

private struct SetBDuplicateKeyRecord: Encodable {
  enum Key: String, CodingKey {
    case value
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Key.self)
    try container.encode(1, forKey: .value)
    try container.encode(2, forKey: .value)
  }
}

@MainActor
private struct SetBPairRoot: View {
  let probe: SetBReloadProbe
  @State private var a: Int
  @State private var b: Int

  init(probe: SetBReloadProbe, aLine: UInt, bLine: UInt) {
    self.probe = probe
    _a = State(wrappedValue: 0, dormantPolicy: .owned, line: aLine, column: 1)
    _b = State(wrappedValue: 0, dormantPolicy: .owned, line: bLine, column: 1)
  }

  var body: some View {
    probe.set = {
      a = $0
      b = $1
    }
    return Text("a=\(a) b=\(b)")
  }
}

@MainActor
private struct SetBFocusButtons: View {
  let version: String

  var body: some View {
    VStack(alignment: .leading) {
      Button("First") {}
      Button("Second") {}
      Button("Third") {}
      Text(version)
    }
  }
}

@MainActor
private struct SetBFocusCounter: View {
  let version: String
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading) {
      Button("First") { count += 1 }
      Button("Second") { count += 1 }
      Button("Third") { count += 1 }
      Text("\(version) count=\(count)")
    }
  }
}

@MainActor
private struct SetBTabCounter: View {
  let label: String
  let probe: SetBReloadProbe
  @State private var count: Int

  init(label: String, probe: SetBReloadProbe, line: UInt) {
    self.label = label
    self.probe = probe
    _count = State(wrappedValue: 0, dormantPolicy: .owned, line: line, column: 1)
  }

  var body: some View {
    probe.increment[label] = { count += 1 }
    return Text("\(label) count=\(count)")
  }
}

@MainActor
private struct SetBTabRootPlain: View {
  let probe: SetBReloadProbe
  @State private var selection: Int

  init(probe: SetBReloadProbe) {
    self.probe = probe
    _selection = State(wrappedValue: 0, dormantPolicy: .owned, line: 1020, column: 1)
  }

  var body: some View {
    probe.select = { selection = $0 }
    return TabView(selection: $selection) {
      Tab("A", value: 0) { SetBTabCounter(label: "A", probe: probe, line: 1021) }
      Tab("B", value: 1) { SetBTabCounter(label: "B", probe: probe, line: 1022) }
    }
  }
}

@MainActor
private struct SetBTabRootWrappedB: View {
  let probe: SetBReloadProbe
  @State private var selection: Int

  init(probe: SetBReloadProbe) {
    self.probe = probe
    _selection = State(wrappedValue: 0, dormantPolicy: .owned, line: 1020, column: 1)
  }

  var body: some View {
    probe.select = { selection = $0 }
    return TabView(selection: $selection) {
      Tab("A", value: 0) { SetBTabCounter(label: "A", probe: probe, line: 1021) }
      Tab("B", value: 1) { SetBTabCounter(label: "B", probe: probe, line: 1022).padding(1) }
    }
  }
}

@MainActor
private struct SetBOneSlotRoot: View {
  let probe: SetBReloadProbe
  @State private var count: Int

  init(probe: SetBReloadProbe) {
    self.probe = probe
    _count = State(wrappedValue: 0, dormantPolicy: .owned, line: 1010, column: 1)
  }

  var body: some View {
    probe.increment["count"] = { count += 1 }
    return Text("count=\(count)")
  }
}

@MainActor
private struct SetBTwoSlotRoot: View {
  let probe: SetBReloadProbe
  @State private var count: Int
  @State private var extra: Int

  init(probe: SetBReloadProbe) {
    self.probe = probe
    _count = State(wrappedValue: 0, dormantPolicy: .owned, line: 1010, column: 1)
    _extra = State(wrappedValue: 0, dormantPolicy: .owned, line: 1011, column: 1)
  }

  var body: some View {
    probe.increment["count"] = { count += 1 }
    return Text("count=\(count) extra=\(extra)")
  }
}

@MainActor
private struct SetBCostRoot: View {
  let probe: SetBReloadProbe
  @State private var payload = SetBCountingPayload(value: 1)

  var body: some View {
    probe.setPayload = { payload = SetBCountingPayload(value: $0) }
    return Text("value=\(payload.value)")
  }
}

@MainActor
private struct SetBStaticRoot: View {
  let probe: SetBReloadProbe
  let version: String

  var body: some View {
    Text(version)
  }
}

#if DEBUG && (os(macOS) || os(Linux))
  @MainActor
  private final class SetBSpool {
    let root: URL

    init() throws {
      root = FileManager.default.temporaryDirectory
        .appendingPathComponent("setb-hot-reload-" + UUID().uuidString)
      try FileManager.default.createDirectory(
        at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }

    func clean() {
      try? FileManager.default.removeItem(at: root)
    }

    func path(_ name: String) -> String {
      root.appendingPathComponent(name).path
    }

    func exists(_ name: String) -> Bool {
      FileManager.default.fileExists(atPath: path(name))
    }

    func writeImage(_ sequence: UInt64, bytes: [UInt8]) throws {
      let url = root.appendingPathComponent(HotReloadLoader.imageName(sequence))
      try Data(bytes).write(to: url)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func publish(_ sequence: UInt64, manifest: String? = nil, mode: Int = 0o600) throws {
      let text =
        manifest ?? "SwiftTUIReload1\n\(sequence)\n\(HotReloadLoader.imageName(sequence))\n"
      let url = root.appendingPathComponent("pending")
      try text.write(to: url, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }
  }
#endif
