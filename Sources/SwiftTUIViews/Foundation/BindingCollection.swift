/// `Binding` projects a mutable collection as a collection of element
/// bindings, matching SwiftUI's conditional conformances.
///
/// The conformances are `@MainActor`-isolated — `wrappedValue` access is
/// main-actor-gated here, so positional reads and writes are too; body code
/// and every framework closure that could iterate a binding already run on
/// the main actor.
///
/// Positional element bindings are index-denominated, SwiftUI's exact
/// semantics including its sharp edge: a retained element binding addresses
/// whatever occupies that position later. The collection-binding `ForEach`
/// initializers remain the identity-safe idiom — their row bindings relocate
/// by ID and drop writes whose element is gone.
extension Binding: @MainActor Sequence where Value: MutableCollection {
  public typealias Element = Binding<Value.Element>
  public typealias Iterator = IndexingIterator<Binding<Value>>
}

extension Binding: @MainActor Collection where Value: MutableCollection {
  public typealias Index = Value.Index
  public typealias Indices = Value.Indices

  @MainActor
  public var startIndex: Value.Index {
    wrappedValue.startIndex
  }

  @MainActor
  public var endIndex: Value.Index {
    wrappedValue.endIndex
  }

  @MainActor
  public var indices: Value.Indices {
    wrappedValue.indices
  }

  @MainActor
  public func index(after position: Value.Index) -> Value.Index {
    wrappedValue.index(after: position)
  }

  @MainActor
  public subscript(position: Value.Index) -> Binding<Value.Element> {
    var projected = Binding<Value.Element>(
      mainActorGet: { wrappedValue[position] },
      set: { wrappedValue[position] = $0 }
    )
    // Mirror the member projection: the stored transaction rides the element
    // binding, and writes funnel through this binding's setter either way.
    projected.transaction = transaction
    return projected
  }
}

extension Binding: @MainActor BidirectionalCollection
where Value: MutableCollection & BidirectionalCollection {
  @MainActor
  public func index(before position: Value.Index) -> Value.Index {
    wrappedValue.index(before: position)
  }
}

extension Binding: @MainActor RandomAccessCollection
where Value: MutableCollection & RandomAccessCollection {}
