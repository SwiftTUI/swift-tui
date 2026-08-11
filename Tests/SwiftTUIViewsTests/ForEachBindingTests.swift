import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

private struct Person: Identifiable, Equatable {
  var id: String
  var name: String
}

@MainActor
private final class PeopleStore {
  var people: [Person]
  var collectionWrites = 0

  init(_ people: [Person]) {
    self.people = people
  }

  func binding() -> Binding<[Person]> {
    Binding(
      get: { self.people },
      set: {
        self.people = $0
        self.collectionWrites += 1
      }
    )
  }
}

@MainActor
private final class RowCapture {
  var rows: [String: Binding<Person>] = [:]
}

private struct CapturingRow: View {
  let person: Binding<Person>

  @MainActor
  init(person: Binding<Person>, capture: RowCapture) {
    self.person = person
    capture.rows[person.wrappedValue.id] = person
  }

  var body: some View {
    Text(person.wrappedValue.name)
  }
}

@MainActor
@Suite
struct ForEachBindingTests {
  private func resolveRows(
    _ store: PeopleStore,
    capture: RowCapture,
    identity: Identity
  ) {
    let view = ForEach(store.binding()) { person in
      CapturingRow(person: person, capture: capture)
    }
    _ = Resolver().resolve(
      view,
      in: .init(identity: identity, environmentValues: .init(), applyEnvironmentValues: true)
    )
  }

  @Test("rows receive element bindings that read the live source")
  func rowsReceiveElementBindings() {
    let store = PeopleStore([
      Person(id: "a", name: "Ada"),
      Person(id: "b", name: "Brian"),
    ])
    let capture = RowCapture()
    resolveRows(store, capture: capture, identity: testIdentity("BindingRows"))

    #expect(capture.rows.count == 2)
    #expect(capture.rows["a"]?.wrappedValue.name == "Ada")

    store.people[0].name = "Ada L."
    #expect(capture.rows["a"]?.wrappedValue.name == "Ada L.")
  }

  @Test("an element write mutates the source through the collection binding")
  func elementWriteMutatesSource() {
    let store = PeopleStore([
      Person(id: "a", name: "Ada"),
      Person(id: "b", name: "Brian"),
    ])
    let capture = RowCapture()
    resolveRows(store, capture: capture, identity: testIdentity("BindingWrite"))

    capture.rows["b"]?.wrappedValue = Person(id: "b", name: "Bryan")
    #expect(store.people[1].name == "Bryan")
    #expect(store.people[0].name == "Ada")
    #expect(store.collectionWrites == 1)
  }

  @Test("member projection through a row binding writes the one field back")
  func memberProjectionWritesThroughRowBinding() {
    let store = PeopleStore([Person(id: "a", name: "Ada")])
    let capture = RowCapture()
    resolveRows(store, capture: capture, identity: testIdentity("BindingMember"))

    let name = capture.rows["a"]!.name
    name.wrappedValue = "Ada Lovelace"
    #expect(store.people[0] == Person(id: "a", name: "Ada Lovelace"))
  }

  @Test("a write through a pre-reorder row binding relocates by ID")
  func reorderedWriteRelocatesByID() {
    let store = PeopleStore([
      Person(id: "a", name: "Ada"),
      Person(id: "b", name: "Brian"),
    ])
    let capture = RowCapture()
    resolveRows(store, capture: capture, identity: testIdentity("BindingReorder"))

    store.people.swapAt(0, 1)
    capture.rows["a"]?.wrappedValue = Person(id: "a", name: "Ada L.")
    #expect(store.people == [
      Person(id: "b", name: "Brian"),
      Person(id: "a", name: "Ada L."),
    ])
  }

  @Test("a write after the element left the collection is dropped and reported")
  func removedElementWriteIsDroppedAndReported() {
    _ = ImperativeRuntimeIssueQueue.drain()
    let store = PeopleStore([
      Person(id: "a", name: "Ada"),
      Person(id: "b", name: "Brian"),
    ])
    let capture = RowCapture()
    resolveRows(store, capture: capture, identity: testIdentity("BindingRemoval"))

    store.people.removeAll { $0.id == "a" }
    capture.rows["a"]?.wrappedValue = Person(id: "a", name: "Ghost")

    #expect(store.people == [Person(id: "b", name: "Brian")])
    #expect(store.collectionWrites == 0)
    #expect(
      ImperativeRuntimeIssueQueue.pending.contains {
        $0.code == "forEach.staleElementBindingWrite"
      }
    )
    _ = ImperativeRuntimeIssueQueue.drain()
  }

  @Test("duplicate-ID rows write back to their own occurrence after relocation")
  func duplicateIDsWriteToTheMatchingOccurrence() {
    let store = PeopleStore([
      Person(id: "dup", name: "First"),
      Person(id: "x", name: "Other"),
      Person(id: "dup", name: "Second"),
    ])
    let capture = RowCapture()
    var secondDuplicate: Binding<Person>?
    let view = ForEach(store.binding(), id: \.id) { person in
      CapturingRow(person: person, capture: capture)
      let _ = {
        if person.wrappedValue.name == "Second" {
          secondDuplicate = person
        }
      }()
    }
    _ = Resolver().resolve(
      view,
      in: .init(
        identity: testIdentity("BindingDuplicates"),
        environmentValues: .init(),
        applyEnvironmentValues: true
      )
    )

    // Move the second duplicate off its captured index; the occurrence-aware
    // scan must still address it, not the first duplicate.
    store.people = [
      Person(id: "dup", name: "First"),
      Person(id: "dup", name: "Second"),
      Person(id: "x", name: "Other"),
    ]
    secondDuplicate?.wrappedValue = Person(id: "dup", name: "Second Edited")
    #expect(store.people[1].name == "Second Edited")
    #expect(store.people[0].name == "First")
  }

  @Test("the annotated destructuring spelling stays compilable")
  func annotatedDestructuringSpellingCompiles() {
    // Swift drops the contextual @MainActor from a property-wrapper closure
    // parameter, so SwiftUI's bare `{ $person in }` cannot compile against
    // the isolated builder closure; `@MainActor $person in` is the supported
    // destructuring spelling (the plain `person in` parameter is already the
    // binding and needs no sugar).
    let store = PeopleStore([Person(id: "a", name: "Ada")])
    let capture = RowCapture()
    let view = ForEach(store.binding()) { @MainActor $person in
      CapturingRow(person: $person, capture: capture)
    }
    _ = Resolver().resolve(
      view,
      in: .init(
        identity: testIdentity("BindingSugar"),
        environmentValues: .init(),
        applyEnvironmentValues: true
      )
    )
    #expect(capture.rows["a"]?.wrappedValue.name == "Ada")
  }
}
