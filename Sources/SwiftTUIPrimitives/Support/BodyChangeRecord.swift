/// Value-only vocabulary shared by body diagnostics and host output adapters.
package struct BodyChangeRecord: Sendable, Equatable {
  package enum Kind: String, Hashable, Sendable { case view, modifier }
  package enum Precision: String, Hashable, Sendable {
    case exact, unavailable
    case ownerOnly = "owner-only"
  }
  package enum Category: String, Hashable, Sendable {
    case identity
    case provenanceUnavailable = "provenance-unavailable"
    case state
    case environment
    case observation
    case explicit
    case ancestor
    case input
    case dynamicProperty = "dynamic-property"
    case inputUnverified = "input-unverified"
    case contextUnavailable = "context-unavailable"
  }

  package struct Cause: Sendable, Hashable {
    package var category: Category
    package var precision: Precision
    package var property: String?

    package init(_ category: Category, precision: Precision = .ownerOnly, property: String? = nil) {
      self.category = category
      self.precision = precision
      self.property = property
    }
  }

  package var typeName: String
  package var kind: Kind
  package var graph: UInt64
  package var owner: UInt64
  package var body: Int
  package var attempt: UInt64
  package var causes: [Cause]
  package var omitted: Int

  package init(
    typeName: String, kind: Kind, graph: UInt64 = 0, owner: UInt64 = 0,
    body: Int = 0, attempt: UInt64 = 0, causes: [Cause], omitted: Int = 0
  ) {
    self.typeName = typeName
    self.kind = kind
    self.graph = graph
    self.owner = owner
    self.body = body
    self.attempt = attempt
    self.causes = causes
    self.omitted = omitted
  }
}

extension BodyChangeRecord {
  /// Swift's reflected private type contexts can embed an address. Preserve
  /// the qualified declaration name without publishing that runtime address.
  package static func name(of type: Any.Type) -> String {
    var name = String(reflecting: type)
    while let start = name.firstRange(of: "(unknown context at $"),
      let end = name[start.upperBound...].firstIndex(of: ")")
    {
      name.replaceSubrange(start.lowerBound...end, with: "(private)")
    }
    return name
  }
}
