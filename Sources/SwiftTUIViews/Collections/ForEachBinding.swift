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
  /// Row bindings address the current occurrence of an ID, counting duplicates
  /// from zero in collection order. Reads and writes relocate after mutations;
  /// a write whose occurrence is gone is dropped and reports a
  /// `forEach.staleElementBindingWrite` runtime issue. A missing read traps.
  ///
  /// State-backed arrays with stored POD or String IDs share an index per stored value, so
  /// reading all rows takes linear lookup work. Sources without value currency
  /// (including arbitrary getter/setter bindings), custom collections and
  /// computed IDs require a current-data scan for each access.
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
    let lookup = ForEachBindingLookup(collection: data, snapshot: snapshot, ids: ids, id: id)
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
      content(projectedElementBinding(collection: data, lookup: lookup, row: row))
    }
  }
}

@MainActor
private func projectedElementBinding<C, ID: Hashable & Sendable>(
  collection: Binding<C>,
  lookup: ForEachBindingLookup<C, ID>,
  row: ForEachBindingElement<C.Element, C.Index, ID>
) -> Binding<C.Element>
where C: MutableCollection & RandomAccessCollection {
  let elementID = row.elementID
  let occurrence = row.occurrence
  var projected = Binding<C.Element>(
    mainActorGet: {
      let snapshot = collection.wrappedValue
      guard
        let index = lookup.locateElement(
          in: snapshot,
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
        let index = lookup.locateElement(
          in: snapshot,
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
  projected.valueIdentity = lookup.valueIdentity
  return projected
}

// These standard collections guarantee that membership and indices cannot
// change without replacing the value. A custom struct can wrap reference
// storage, so merely checking that C is not a class would be unsound.
private protocol ForEachBindingValueCollection {}
extension Array: ForEachBindingValueCollection {}
extension ArraySlice: ForEachBindingValueCollection {}
extension ContiguousArray: ForEachBindingValueCollection {}

@MainActor
private final class ForEachBindingLookup<C, ID: Hashable & Sendable>
where C: MutableCollection & RandomAccessCollection {
  let valueIdentity: (@MainActor @Sendable () -> StateValueIdentity?)?
  private let id: KeyPath<C.Element, ID>
  private var indexedValueIdentity: StateValueIdentity?
  private var indicesByID: [ID: [C.Index]] = [:]

  init(collection: Binding<C>, snapshot: C, ids: [ID], id: KeyPath<C.Element, ID>) {
    self.id = id
    // Stored IDs may themselves contain mutable references, including through
    // a value wrapper. Admit reference-free storage and String's known value
    // semantics; arbitrary non-POD Hashable values need a current-data scan.
    // Hashable implementations must still derive equality from the ID value.
    if C.self is any ForEachBindingValueCollection.Type,
      !(C.Element.self is AnyObject.Type),
      _isPOD(ID.self) || ID.self == String.self,
      MemoryLayout<C.Element>.offset(of: id) != nil
    {
      valueIdentity = collection.valueIdentity
    } else {
      valueIdentity = nil
    }
    if let identity = valueIdentity?() {
      rebuild(in: snapshot, ids: ids, identity: identity)
    }
  }

  func locateElement(in collection: C, elementID: ID, occurrence: Int) -> C.Index? {
    if let identity = valueIdentity?() {
      if indexedValueIdentity !== identity {
        rebuild(in: collection, ids: collection.map { $0[keyPath: id] }, identity: identity)
      }
      guard let indices = indicesByID[elementID], occurrence < indices.count else {
        return nil
      }
      return indices[occurrence]
    }

    // No producer guarantee means no reusable index, even if count and the
    // captured position's ID still match. Equal-count replacement can insert
    // an earlier duplicate while leaving both of those checks unchanged.
    indexedValueIdentity = nil
    indicesByID.removeAll(keepingCapacity: false)
    var seen = 0
    for index in collection.indices {
      if collection[index][keyPath: id] == elementID {
        if seen == occurrence {
          return index
        }
        seen += 1
      }
    }
    return nil
  }

  private func rebuild(in collection: C, ids: [ID], identity: StateValueIdentity) {
    indicesByID.removeAll(keepingCapacity: true)
    indicesByID.reserveCapacity(ids.count)
    for (index, elementID) in zip(collection.indices, ids) {
      indicesByID[elementID, default: []].append(index)
    }
    indexedValueIdentity = identity
  }
}
