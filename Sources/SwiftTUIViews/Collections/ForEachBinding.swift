import SwiftTUICore

/// One row of a collection-binding `ForEach`: the element snapshot for
/// identity extraction plus the capture that lets the row's projected
/// binding find its element again after the collection mutates.
public struct ForEachBindingElement<Element, Index, ID: Hashable & Sendable> {
  package let element: Element
  package let index: Index
  package let elementID: ID
  package let occurrence: Int

  package init(element: Element, index: Index, elementID: ID, occurrence: Int) {
    self.element = element
    self.index = index
    self.elementID = elementID
    self.occurrence = occurrence
  }
}

extension ForEach {
  /// Creates repeated content from a binding to a mutable collection,
  /// handing each row a binding to its own element.
  ///
  /// Row bindings are ID-verified rather than index-captured: a write checks
  /// that the captured position still holds the captured identity, relocates
  /// by ID when the collection reordered, and — where SwiftUI writes through
  /// a stale index — drops a write whose element is gone entirely, reporting
  /// a `forEach.staleElementBindingWrite` runtime issue instead.
  @MainActor
  public init<C>(
    _ data: Binding<C>,
    @ViewBuilder content: @escaping @MainActor (Binding<C.Element>) -> Content
  )
  where
    C: MutableCollection & RandomAccessCollection,
    C.Element: Identifiable,
    ID == C.Element.ID,
    Data == [ForEachBindingElement<C.Element, C.Index, ID>]
  {
    self.init(data, id: \.id, content: content)
  }

  /// Creates repeated content from a binding to a mutable collection, keyed
  /// by the identity at `id`, handing each row a binding to its own element.
  @MainActor
  public init<C>(
    _ data: Binding<C>,
    id: KeyPath<C.Element, ID>,
    @ViewBuilder content: @escaping @MainActor (Binding<C.Element>) -> Content
  )
  where
    C: MutableCollection & RandomAccessCollection,
    Data == [ForEachBindingElement<C.Element, C.Index, ID>]
  {
    let snapshot = data.wrappedValue
    let ids = snapshot.map { $0[keyPath: id] }
    let occurrences = makeForEachOccurrences(ids: ids)
    var rows: [ForEachBindingElement<C.Element, C.Index, ID>] = []
    rows.reserveCapacity(ids.count)
    var offset = 0
    for index in snapshot.indices {
      rows.append(
        .init(
          element: snapshot[index],
          index: index,
          elementID: ids[offset],
          occurrence: occurrences[offset]
        )
      )
      offset += 1
    }
    self.init(rows, id: \.elementID) { row in
      content(projectedElementBinding(collection: data, id: id, row: row))
    }
  }
}

@MainActor
private func projectedElementBinding<C, ID: Hashable & Sendable>(
  collection: Binding<C>,
  id idKeyPath: KeyPath<C.Element, ID>,
  row: ForEachBindingElement<C.Element, C.Index, ID>
) -> Binding<C.Element>
where C: MutableCollection & RandomAccessCollection {
  let capturedIndex = row.index
  let elementID = row.elementID
  let occurrence = row.occurrence
  var projected = Binding<C.Element>(
    mainActorGet: {
      let snapshot = collection.wrappedValue
      guard
        let index = locateElement(
          in: snapshot,
          id: idKeyPath,
          capturedIndex: capturedIndex,
          elementID: elementID,
          occurrence: occurrence
        )
      else {
        fatalError(
          """
          A ForEach element binding for id \(elementID) was read after its \
          element left the collection. Row bindings are only valid while \
          their element is present — re-derive content from current data \
          instead of retaining a row binding across removal.
          """
        )
      }
      return snapshot[index]
    },
    set: { newValue in
      var snapshot = collection.wrappedValue
      guard
        let index = locateElement(
          in: snapshot,
          id: idKeyPath,
          capturedIndex: capturedIndex,
          elementID: elementID,
          occurrence: occurrence
        )
      else {
        ImperativeRuntimeIssueQueue.record(
          RuntimeIssue(
            severity: .warning,
            code: "forEach.staleElementBindingWrite",
            message:
              "A ForEach element binding for id \(elementID) was written after "
              + "its element left the collection; the write was dropped. "
              + "Mutate current data instead of retaining a row binding "
              + "across removal."
          )
        )
        return
      }
      snapshot[index] = newValue
      collection.wrappedValue = snapshot
    }
  )
  // Mirror the member projection: the collection binding's stored transaction
  // rides the element binding, and writes funnel through the collection
  // binding's setter either way.
  projected.transaction = collection.transaction
  return projected
}

private func locateElement<C, ID: Hashable & Sendable>(
  in collection: C,
  id idKeyPath: KeyPath<C.Element, ID>,
  capturedIndex: C.Index,
  elementID: ID,
  occurrence: Int
) -> C.Index?
where C: MutableCollection & RandomAccessCollection {
  if capturedIndex >= collection.startIndex,
    capturedIndex < collection.endIndex,
    collection[capturedIndex][keyPath: idKeyPath] == elementID
  {
    return capturedIndex
  }
  var seen = 0
  var index = collection.startIndex
  while index < collection.endIndex {
    if collection[index][keyPath: idKeyPath] == elementID {
      if seen == occurrence {
        return index
      }
      seen += 1
    }
    collection.formIndex(after: &index)
  }
  return nil
}
