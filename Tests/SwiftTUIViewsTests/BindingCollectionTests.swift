import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

private struct Entry: Identifiable, Equatable {
  var id: String
  var name: String
}

@MainActor
private final class EntryStore {
  var entries: [Entry]

  init(_ entries: [Entry]) {
    self.entries = entries
  }

  func binding() -> Binding<[Entry]> {
    Binding(
      get: { self.entries },
      set: { self.entries = $0 }
    )
  }
}

@MainActor
@Suite
struct BindingCollectionTests {
  @Test("a collection binding iterates as element bindings over live values")
  func collectionBindingIteratesElementBindings() {
    let store = EntryStore([
      Entry(id: "a", name: "Ada"),
      Entry(id: "b", name: "Brian"),
    ])

    var names: [String] = []
    for entry in store.binding() {
      names.append(entry.wrappedValue.name)
    }
    #expect(names == ["Ada", "Brian"])
    #expect(store.binding().count == 2)
    #expect(!store.binding().isEmpty)
  }

  @Test("a positional element binding writes through to the source")
  func positionalWriteMutatesSource() {
    let store = EntryStore([
      Entry(id: "a", name: "Ada"),
      Entry(id: "b", name: "Brian"),
    ])
    let items = store.binding()

    let first = items[items.startIndex]
    first.wrappedValue = Entry(id: "a", name: "Ada Lovelace")
    #expect(store.entries[0].name == "Ada Lovelace")

    first.name.wrappedValue = "Ada L."
    #expect(store.entries[0].name == "Ada L.")
  }

  @Test("positional bindings are index-denominated, unlike ForEach rows")
  func positionalBindingsAreIndexDenominated() {
    // The recorded contract: the Collection subscript keeps SwiftUI's exact
    // positional semantics — a retained element binding addresses whatever
    // occupies that position later. The ForEach binding rows are the
    // identity-safe tier.
    let store = EntryStore([
      Entry(id: "a", name: "Ada"),
      Entry(id: "b", name: "Brian"),
    ])
    let items = store.binding()
    let first = items[items.startIndex]

    store.entries.removeFirst()
    #expect(first.wrappedValue == Entry(id: "b", name: "Brian"))

    first.wrappedValue = Entry(id: "b", name: "Bryan")
    #expect(store.entries == [Entry(id: "b", name: "Bryan")])
  }
}
