import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct ForEachBindingRuntimeTests {
  @Test("retained duplicate bindings edit the right displayed row after input mutates state")
  func retainedRowsThroughInput() throws {
    let capture = RowCapture()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DuplicateRowInput"), size: .init(width: 44, height: 12)
    ) {
      DuplicateRowsHost(capture: capture)
    }
    defer { harness.shutdown() }

    #expect(harness.frame.contains("Brian"))
    _ = try harness.clickText("Insert before rows")
    #expect(harness.frame.contains("Inserted"))
    _ = try harness.clickText("Edit retained second")
    #expect(
      capture.collection?.wrappedValue.map(\.name) == [
        "Inserted", "Other", "Ada", "Edited", "Cora",
      ])
    #expect(harness.frame.contains("Ada"))
    #expect(harness.frame.contains("Edited"))
    #expect(!harness.frame.contains("Brian"))

    _ = try harness.clickText("Remove third occurrence")
    #expect(!harness.frame.contains("Cora"))
    _ = try harness.clickText("Write retained third")
    #expect(capture.collection?.wrappedValue.map(\.name) == ["Inserted", "Other", "Ada", "Edited"])
    #expect(harness.frame.contains("Edited"))
    #expect(!harness.frame.contains("Ghost"))
  }
}

private struct Person: Identifiable, Equatable {
  var id: Int
  var name: String
}

@MainActor
private final class RowCapture {
  var collection: Binding<[Person]>?
  var second: Binding<Person>?
  var third: Binding<Person>?
}

private struct DuplicateRowsHost: View {
  @State private var people = [
    Person(id: 0, name: "Other"), Person(id: 1, name: "Ada"),
    Person(id: 1, name: "Brian"), Person(id: 1, name: "Cora"),
  ]
  let capture: RowCapture

  var body: some View {
    let _ = { capture.collection = $people }()
    VStack(alignment: .leading, spacing: 0) {
      Button("Insert before rows") { people.insert(Person(id: 2, name: "Inserted"), at: 0) }
      Button("Edit retained second") { capture.second?.name.wrappedValue = "Edited" }
      Button("Remove third occurrence") { people.removeLast() }
      Button("Write retained third") { capture.third?.wrappedValue = Person(id: 1, name: "Ghost") }
      ForEach($people) { person in
        let _ = remember(person)
        Text(person.wrappedValue.name)
      }
    }
  }

  private func remember(_ person: Binding<Person>) {
    if person.wrappedValue.name == "Brian", capture.second == nil {
      capture.second = person
    }
    if person.wrappedValue.name == "Cora", capture.third == nil {
      capture.third = person
    }
  }
}
