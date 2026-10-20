/// Value-only vocabulary shared by body diagnostics and host output adapters.
package struct BodyChangeRecord: Sendable, Equatable {
  package struct Cause: Sendable, Hashable {
    package var category: String
    package var precision: String
    package var property: String?

    package init(_ category: String, precision: String = "owner-only", property: String? = nil) {
      self.category = category
      self.precision = precision
      self.property = property
    }
  }

  package var typeName: String
  package var kind: String
  package var graph: UInt64
  package var owner: UInt64
  package var body: Int
  package var attempt: UInt64
  package var causes: [Cause]
  package var omitted: Int

  package init(
    typeName: String, kind: String, graph: UInt64 = 0, owner: UInt64 = 0,
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
