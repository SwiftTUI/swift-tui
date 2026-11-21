// What a node is to the container that lays it out.
//
// A container reads a few things from its direct children: a layout
// priority, a spacing preference, alignment guides, layout values, and
// whether a child is a `Spacer`. The body of a transition puts a boundary
// node around each view of its content, so that a modifier of the body lands
// on the boundary and not on the view (`TransitionContent`). The boundary is
// then the container's child, and it stands for the view behind it: the
// container reads the view's role through it.
//
// The role is read when the tree is laid out, never copied onto the boundary
// when it is resolved. A view can change what it declares in an evaluation
// of its own, which does not resolve the boundary again.
//
// Layout asks these of every child of every stack, in trees that have no
// transition at all, so a node that is not a boundary must cost one test
// and then be read exactly as before: no copy of the node or its metadata,
// and no accessor that yields. They are in the module of the layout engine
// so that they are inlined there.

extension ResolvedNode {
  /// Whether this node is the boundary a transition body put around the
  /// view it is for.
  ///
  /// The kind is tested first: it is stored in the node, and it rules out
  /// nearly every node without a look at its children.
  @inline(__always)
  package var isTransitionContentBoundary: Bool {
    guard case .view(.transitionContent) = kind else { return false }
    return typeDiscriminator != nil && _storedChildren.count == 1
  }

  /// The view behind this boundary: the first node below it that is not a
  /// boundary itself. A combination of two custom transitions puts one
  /// boundary inside the other. Only for a boundary.
  package var viewBehindBoundary: ResolvedNode {
    var node = _storedChildren[0]
    while node.isTransitionContentBoundary {
      node = node._storedChildren[0]
    }
    return node
  }

  /// The layout metadata of the view behind this boundary, with what the
  /// transition body stamped on the boundaries on the way merged over it,
  /// innermost first. Only for a boundary.
  package var layoutMetadataThroughBoundary: LayoutMetadata {
    var stamps = [layoutMetadata]
    var node = _storedChildren[0]
    while node.isTransitionContentBoundary {
      stamps.append(node.layoutMetadata)
      node = node._storedChildren[0]
    }
    var metadata = node.layoutMetadata
    for stamp in stamps.reversed() {
      metadata = metadata.merging(stamp)
    }
    return metadata
  }

  /// Calls `body` with what this node declares to the container that lays
  /// it out: its own layout metadata, or for a boundary that of the view
  /// behind it.
  @inline(__always)
  package func withContainerLayoutMetadata<Result>(
    _ body: (LayoutMetadata) -> Result
  ) -> Result {
    if isTransitionContentBoundary {
      return body(layoutMetadataThroughBoundary)
    }
    return body(layoutMetadata)
  }

  /// Calls `body` with the node whose kind decides what this node is to the
  /// container that lays it out: the node itself, or the view behind a
  /// boundary.
  @inline(__always)
  package func withLayoutRoleNode<Result>(
    _ body: (ResolvedNode) -> Result
  ) -> Result {
    if isTransitionContentBoundary {
      return body(viewBehindBoundary)
    }
    return body(self)
  }
}
