/// Indexed child access for data-backed lazy containers.
package protocol IndexedChildSource: Sendable {
  var count: Int { get }
  var identityRoot: Identity { get }
  var measurementSignature: String { get }
  var canRunOnWorker: Bool { get }
  var workerResolvedChildren: [ResolvedNode]? { get }

  func child(at index: Int) -> ResolvedNode
}

extension IndexedChildSource {
  package var canRunOnWorker: Bool { false }
  package var workerResolvedChildren: [ResolvedNode]? { nil }
}

package struct CustomLayoutFallbackSummary: Equatable, Sendable {
  package var count: Int
  package var firstIdentity: Identity?

  package init(
    count: Int = 0,
    firstIdentity: Identity? = nil
  ) {
    self.count = count
    self.firstIdentity = firstIdentity
  }

  package mutating func record(_ identity: Identity) {
    count += 1
    if firstIdentity == nil {
      firstIdentity = identity
    }
  }

  package mutating func merge(_ other: Self) {
    count += other.count
    if firstIdentity == nil {
      firstIdentity = other.firstIdentity
    }
  }
}

/// Sendable resolved-child snapshot for lazy indexed containers that have
/// already materialized their authored children on the main actor.
package struct IndexedChildSourceSnapshot: IndexedChildSource {
  package let identityRoot: Identity
  package let measurementSignature: String
  private let children: [ResolvedNode]

  package init(
    identityRoot: Identity,
    measurementSignature: String,
    children: [ResolvedNode]
  ) {
    self.identityRoot = identityRoot
    self.measurementSignature = measurementSignature
    self.children = children
  }

  package var count: Int {
    children.count
  }

  package var canRunOnWorker: Bool {
    true
  }

  package var workerResolvedChildren: [ResolvedNode]? {
    children
  }

  package func child(at index: Int) -> ResolvedNode {
    children[index]
  }
}

extension ResolvedNode {
  package var usesIndexedChildSource: Bool {
    indexedChildSource != nil
  }
}
