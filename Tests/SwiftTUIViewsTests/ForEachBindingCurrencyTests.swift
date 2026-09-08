import Synchronization
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct ForEachBindingCurrencyTests {
  private let seed = [
    Record(id: 0, name: "Other"), Record(id: 1, name: "Ada"),
    Record(id: 1, name: "Brian"), Record(id: 1, name: "Cora"),
  ]

  @Test("state-backed duplicate bindings relocate for every mutation shape", arguments: 0..<5)
  func stateMutations(change: Int) throws {
    let state = State(wrappedValue: seed)
    let rows = captureRows(state.projectedValue, id: \.id)
    switch change {
    case 0: state.wrappedValue.insert(Record(id: 2, name: "New"), at: 0)
    case 1: state.wrappedValue.removeFirst()
    case 2: state.wrappedValue.insert(Record(id: 1, name: "New duplicate"), at: 0)
    case 3: state.wrappedValue[0] = Record(id: 1, name: "Replacement")
    default: state.wrappedValue = [seed[1], seed[2], seed[3], seed[0]]
    }
    let index = try #require(
      state.wrappedValue.indices.filter { state.wrappedValue[$0].id == 1 }.dropFirst().first)
    #expect(rows[2].wrappedValue == state.wrappedValue[index])
    let before = state.wrappedValue
    rows[2].name.wrappedValue = "Edited"
    #expect(state.wrappedValue[index].name == "Edited")
    for other in before.indices where other != index {
      #expect(state.wrappedValue[other] == before[other])
    }
  }

  @Test(
    "a previously unique ID gains an earlier duplicate at unchanged count",
    arguments: [false, true])
  func introducedDuplicate(stateBacked: Bool) {
    let state = State(wrappedValue: [seed[0], seed[1]])
    let base = state.projectedValue
    // The arbitrary closure can also carry source identity; that is not a
    // promise that external mutation is versioned.
    let binding =
      stateBacked
      ? base
      : Binding(get: { state.wrappedValue }, set: { state.wrappedValue = $0 })
        .withBindingSource("same-source")
    let rows = captureRows(binding, id: \.id)
    state.wrappedValue[0] = Record(id: 1, name: "New first")
    #expect(rows[1].wrappedValue.name == "New first")
    rows[1].name.wrappedValue = "Edited first"
    #expect(state.wrappedValue.map(\.name) == ["Edited first", "Ada"])
  }

  @Test("checkpoint restore and a new branch invalidate the previous occurrence index")
  func checkpointBranches() throws {
    let graph = ViewGraph()
    let capture = StateRowsCapture()
    let host = StateRowsHost(seed: seed, capture: capture)
    resolve(host, in: graph)
    let binding = try #require(capture.collection)
    let second = capture.rows[2]
    let third = capture.rows[3]
    let checkpoint = graph.makeCheckpoint()
    let originalIdentity = try #require(binding.valueIdentity?())

    binding.wrappedValue.removeFirst()
    #expect(second.wrappedValue.name == "Brian")
    let discardedIdentity = try #require(binding.valueIdentity?())
    #expect(discardedIdentity !== originalIdentity)

    _ = graph.restoreCheckpoint(checkpoint)
    #expect(binding.wrappedValue == seed)
    #expect(binding.valueIdentity?() === originalIdentity)
    binding.wrappedValue.removeLast()
    #expect(binding.valueIdentity?() !== discardedIdentity)
    #expect(second.wrappedValue.name == "Brian")
    second.name.wrappedValue = "Edited"
    #expect(binding.wrappedValue.map(\.name) == ["Other", "Ada", "Edited"])

    _ = ImperativeRuntimeIssueQueue.drain()
    third.wrappedValue = Record(id: 1, name: "Ghost")
    #expect(binding.wrappedValue.map(\.name) == ["Other", "Ada", "Edited"])
    #expect(
      ImperativeRuntimeIssueQueue.drain().contains { $0.code == "forEach.staleElementBindingWrite" }
    )
  }

  @Test("bindings retain current occurrence lookup after their graph disappears")
  func retiredStorage() throws {
    let capture = StateRowsCapture()
    let host = StateRowsHost(seed: seed, capture: capture)
    do {
      let graph = ViewGraph()
      resolve(host, in: graph)
      capture.collection?.wrappedValue.removeFirst()
      #expect(capture.rows[2].wrappedValue.name == "Brian")
    }
    let binding = try #require(capture.collection)
    // Keep the source box alive just as an app-held view value does.
    withExtendedLifetime(host) {
      binding.wrappedValue.insert(Record(id: 2, name: "New"), at: 0)
      #expect(capture.rows[2].wrappedValue.name == "Brian")
      capture.rows[2].name.wrappedValue = "Edited"
      #expect(binding.wrappedValue.map(\.name) == ["New", "Ada", "Edited", "Cora"])
    }
  }

  @Test("stored member and optional projections preserve value currency")
  func valueProjections() throws {
    let state = State(wrappedValue: Envelope(records: seed))
    let member = state.projectedValue.records
    let optional = Binding<[Record]?>(member)
    let unwrapped = try #require(Binding<[Record]>(optional))
    let copy = Binding(projectedValue: unwrapped.animation(.linear(duration: .seconds(1))))
    #expect(copy.valueIdentity?() === state.projectedValue.valueIdentity?())
    let rows = captureRows(copy, id: \.id)
    state.wrappedValue.records.removeFirst()
    rows[2].name.wrappedValue = "Edited"
    #expect(state.wrappedValue.records.map(\.name) == ["Ada", "Edited", "Cora"])
    #expect(rows[2].transaction.animation == copy.transaction.animation)
  }

  @Test("source setters can replace IDs and reorder data after a row write")
  func transformingSetter() {
    let state = State(wrappedValue: seed)
    let binding = Binding(
      get: { state.wrappedValue },
      set: {
        state.wrappedValue = $0.reversed()
      })
    let rows = captureRows(binding, id: \.id)
    rows[2].wrappedValue = Record(id: 2, name: "Changed ID")
    #expect(rows[1].wrappedValue.name == "Cora")
    #expect(rows[2].wrappedValue.name == "Ada")
    rows[2].name.wrappedValue = "Edited"
    #expect(state.wrappedValue.map(\.name) == ["Other", "Edited", "Changed ID", "Cora"])
  }

  @Test("array slices use their current nonzero indices")
  func sliceIndices() {
    let state = State(wrappedValue: seed[1...])
    let rows = captureRows(state.projectedValue, id: \.id)
    state.wrappedValue = [Record(id: 9, name: "Padding"), seed[0], seed[1], seed[2], seed[3]][2...]
    #expect(rows[1].wrappedValue.name == "Brian")
    rows[1].name.wrappedValue = "Edited"
    #expect(state.wrappedValue.startIndex == 2)
    #expect(state.wrappedValue.map(\.name) == ["Ada", "Edited", "Cora"])
  }

  @Test(
    "reference IDs and computed IDs observe mutation outside a state store",
    arguments: [false, true])
  func externallyMutableIDs(computed: Bool) {
    let first = IDBox(0)
    if computed {
      let state = State(wrappedValue: [
        ComputedRecord(box: first, name: "Other"), ComputedRecord(box: IDBox(1), name: "Ada"),
      ])
      let rows = captureRows(state.projectedValue, id: \.id)
      first.value = 1
      #expect(rows[1].wrappedValue.name == "Other")
      rows[1].wrappedValue = ComputedRecord(box: IDBox(1), name: "Edited")
      #expect(state.wrappedValue.map(\.name) == ["Edited", "Ada"])
    } else {
      let state = State(wrappedValue: [
        ReferenceRecord(id: 0, name: "Other"), ReferenceRecord(id: 1, name: "Ada"),
      ])
      let rows = captureRows(state.projectedValue, id: \.id)
      state.wrappedValue[0].id = 1
      #expect(rows[1].wrappedValue.name == "Other")
      rows[1].wrappedValue = ReferenceRecord(id: 1, name: "Edited")
      #expect(state.wrappedValue.map(\.name) == ["Edited", "Ada"])
    }
  }

  @Test("reference-backed custom collections cannot reuse a state value's index")
  func customCollection() {
    let storage = RecordStorage(seed)
    let state = State(wrappedValue: ReferenceCollection(storage: storage))
    let rows = captureRows(state.projectedValue, id: \.id)
    storage.records.removeFirst()
    #expect(rows[2].wrappedValue.name == "Brian")
    rows[2].name.wrappedValue = "Edited"
    #expect(storage.records.map(\.name) == ["Ada", "Edited", "Cora"])
  }

  @Test("computed collection members do not inherit a parent's value token")
  func computedMember() {
    let storage = RecordStorage(seed)
    let state = State(wrappedValue: ReferenceEnvelope(storage: storage))
    let binding = state.projectedValue.records
    #expect(binding.valueIdentity == nil)
    let rows = captureRows(binding, id: \.id)
    storage.records.removeFirst()
    #expect(rows[2].wrappedValue.name == "Brian")
  }

  @Test("full-list state binding reads use linear identity work", arguments: 0..<4)
  func linearReads(mode: Int) throws {
    let duplicates = mode % 2 == 1
    let count = 512
    let initial = (0..<count).map {
      CountedRecord(id: CountedID(value: duplicates ? $0 % 8 : $0), value: $0)
    }
    let state = State(wrappedValue: initial)
    let graph = ViewGraph()
    let capture = Capture<CountedRecord>()
    let binding: Binding<[CountedRecord]>
    let rows: [Binding<CountedRecord>]
    if mode >= 2 {
      graph.beginFrame()
      var context = ResolveContext(
        identity: testIdentity("CountedState"), environmentValues: .init(),
        applyEnvironmentValues: true)
      context.viewGraph = graph
      _ = Resolver().resolve(CountedRowsHost(seed: initial, capture: capture), in: context)
      binding = try #require(capture.collection)
      rows = capture.rows
    } else {
      binding = state.projectedValue
      rows = captureRows(binding, id: \.id)
    }
    #expect(MemoryLayout<CountedRecord>.offset(of: \.id) != nil)
    CountedID.work.withLock { $0 = 0 }
    for _ in 0..<4 {
      #expect(rows.map { $0.wrappedValue.value } == Array(0..<count))
    }
    #expect(CountedID.work.withLock { $0 } < 40 * count)

    binding.wrappedValue.insert(CountedRecord(id: CountedID(value: -1), value: -1), at: 0)
    CountedID.work.withLock { $0 = 0 }
    // The first access rebuilds once; the remaining accesses share its index.
    for _ in 0..<4 {
      #expect(rows.map { $0.wrappedValue.value } == Array(0..<count))
    }
    #expect(CountedID.work.withLock { $0 } < 60 * count)
    withExtendedLifetime(graph) {}
  }

  @Test("contiguous arrays relocate duplicate occurrences")
  func contiguousArray() {
    let state = State(wrappedValue: ContiguousArray(seed))
    let rows = captureRows(state.projectedValue, id: \.id)
    state.wrappedValue.removeFirst()
    rows[2].name.wrappedValue = "Edited"
    #expect(state.wrappedValue.map(\.name) == ["Ada", "Edited", "Cora"])
  }

  @Test("reading a missing duplicate occurrence traps")
  func missingOccurrenceReadTraps() async {
    await #expect(processExitsWith: .failure) {
      await MainActor.run {
        let suite = ForEachBindingCurrencyTests()
        let state = State(wrappedValue: suite.seed)
        let rows = suite.captureRows(state.projectedValue, id: \.id)
        state.wrappedValue.removeLast()
        _ = rows[3].wrappedValue
      }
    }
  }

  private func captureRows<C, ID>(_ binding: Binding<C>, id: KeyPath<C.Element, ID>) -> [Binding<
    C.Element
  >]
  where C: MutableCollection & RandomAccessCollection, ID: Hashable & Sendable {
    let capture = Capture<C.Element>()
    _ = Resolver().resolve(
      ForEach(binding, id: id) { row in
        let _ = capture.rows.append(row)
        Text("row")
      },
      in: .init(
        identity: testIdentity("CurrencyRows"), environmentValues: .init(),
        applyEnvironmentValues: true)
    )
    return capture.rows
  }

  private func resolve(_ host: StateRowsHost, in graph: ViewGraph) {
    graph.beginFrame()
    var context = ResolveContext(
      identity: testIdentity("CurrencyState"), environmentValues: .init(),
      applyEnvironmentValues: true)
    context.viewGraph = graph
    _ = Resolver().resolve(host, in: context)
  }
}

private struct Record: Identifiable, Equatable {
  var id: Int
  var name: String
}

private struct Envelope {
  var records: [Record]
}

@MainActor
private final class Capture<Element> {
  var rows: [Binding<Element>] = []
  var collection: Binding<[Element]>?
}

@MainActor
private final class StateRowsCapture {
  var collection: Binding<[Record]>?
  var rows: [Binding<Record>] = []
}

private struct StateRowsHost: View {
  @State private var records: [Record]
  let capture: StateRowsCapture

  init(seed: [Record], capture: StateRowsCapture) {
    _records = State(wrappedValue: seed)
    self.capture = capture
  }

  var body: some View {
    let _ = { capture.collection = $records }()
    ForEach($records) { row in
      let _ = capture.rows.append(row)
      Text(row.wrappedValue.name)
    }
  }
}

private final class IDBox {
  var value: Int
  init(_ value: Int) { self.value = value }
}

private struct ComputedRecord {
  var box: IDBox
  var name: String
  var id: Int { box.value }
}

private final class ReferenceRecord {
  var id: Int
  var name: String
  init(id: Int, name: String) {
    self.id = id
    self.name = name
  }
}

private final class RecordStorage {
  var records: [Record]
  init(_ records: [Record]) { self.records = records }
}

private struct ReferenceEnvelope {
  var storage: RecordStorage
  var records: [Record] {
    get { storage.records }
    set { storage.records = newValue }
  }
}

private struct ReferenceCollection: MutableCollection, RandomAccessCollection {
  let storage: RecordStorage
  var startIndex: Int { storage.records.startIndex }
  var endIndex: Int { storage.records.endIndex }
  func index(after i: Int) -> Int { i + 1 }
  func index(before i: Int) -> Int { i - 1 }
  subscript(i: Int) -> Record {
    get { storage.records[i] }
    set { storage.records[i] = newValue }
  }
}

private struct CountedRecord {
  var id: CountedID
  var value: Int
}

private struct CountedRowsHost: View {
  @State private var records: [CountedRecord]
  let capture: Capture<CountedRecord>

  init(seed: [CountedRecord], capture: Capture<CountedRecord>) {
    _records = State(wrappedValue: seed)
    self.capture = capture
  }

  var body: some View {
    let _ = { capture.collection = $records }()
    ForEach($records, id: \.id) { row in
      let _ = capture.rows.append(row)
      Text("\(row.wrappedValue.value)")
    }
  }
}

private struct CountedID: Hashable, Sendable {
  static let work = Mutex(0)
  let value: Int
  func hash(into hasher: inout Hasher) {
    Self.work.withLock { $0 += 1 }
    hasher.combine(value)
  }
  static func == (lhs: Self, rhs: Self) -> Bool {
    Self.work.withLock { $0 += 1 }
    return lhs.value == rhs.value
  }
}
