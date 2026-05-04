/// Identifies the high-level role of a node in the resolved tree.
package enum NodeKind: Equatable, Sendable {
  case root
  case scene(String)
  case view(String)
}
