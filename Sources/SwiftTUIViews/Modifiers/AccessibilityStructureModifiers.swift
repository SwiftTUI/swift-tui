public import SwiftTUICore

extension View {
  /// Groups related semantic content without changing its visual layout.
  public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> some View {
    modifier(AccessibilityStructureModifier(children: children, priority: nil))
  }

  /// Orders peers within the same accessibility container, highest priority first.
  public func accessibilitySortPriority(_ priority: Double) -> some View {
    modifier(AccessibilityStructureModifier(children: nil, priority: priority))
  }

  /// Replaces this view's accessibility output with unpainted authored views.
  /// Bind representation controls to the same application state as the visual control.
  public func accessibilityRepresentation<Representation: View>(
    @ViewBuilder representation: () -> Representation
  ) -> some View {
    modifier(
      AccessibilityRepresentationModifier(
        representation: representation(), scope: makeCapturedSubviewScope(),
        replacesElement: true))
  }

  /// Replaces semantic descendants while retaining this view's own name and role.
  public func accessibilityChildren<Children: View>(
    @ViewBuilder children: () -> Children
  ) -> some View {
    modifier(
      AccessibilityRepresentationModifier(
        representation: children(), scope: makeCapturedSubviewScope(),
        replacesElement: false))
  }
}

private struct AccessibilityStructureModifier: IterativePrimitiveViewModifier {
  let children: AccessibilityChildBehavior?
  let priority: Double?

  func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>, in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    content.resolveWork(in: context).map { completed in
      var node = completed
      var structure = node.semanticMetadata.accessibilityStructure ?? .init()
      if let children { structure.children = children }
      if let priority, priority.isFinite { structure.sortPriority = priority }
      node.semanticMetadata.accessibilityStructure = structure
      return [node]
    }
  }
}

private struct AccessibilityRepresentationModifier<Representation: View>:
  IterativePrimitiveViewModifier
{
  let representation: Representation
  let scope: CapturedSubviewScope
  let replacesElement: Bool

  func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>, in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    content.resolveWork(in: context.child(component: .named("visual"))).flatMap { completed in
      let virtualContext = context.child(component: .named("accessibility"))
      return withAuthoringContext(scope.authoringContext) {
        resolveViewWork(representation, in: virtualContext)
      }.map { representationNode in
        var visual = completed
        var virtual = markingVirtualAccessibility(representationNode)
        if replacesElement {
          visual.semanticMetadata.accessibilityHidden = true
        } else {
          var structure = visual.semanticMetadata.accessibilityStructure ?? .init()
          structure.children = .ignore
          structure.keepsVirtualChildren = true
          visual.semanticMetadata.accessibilityStructure = structure
          visual.semanticMetadata.accessibilityVisualContent = nil
          visual.semanticMetadata.accessibilityRole =
            visual.semanticMetadata.accessibilityRole ?? .group
          virtual.semanticMetadata.isAccessibilityContent = true
          virtual.semanticMetadata.accessibilityStructure?.parent = visual.identity
        }
        return [
          ResolvedNode(
            identity: context.identity, kind: .view("AccessibilityRepresentation"),
            children: [visual, virtual], environmentSnapshot: context.environment,
            transactionSnapshot: context.transaction,
            layoutBehavior: .decoration(primaryIndex: 0, alignment: .topLeading),
            semanticMetadata: .init())
        ]
      }
    }
  }
}

/// Mark every resolved node so retained children preserve the presentation boundary.
private func markingVirtualAccessibility(_ root: ResolvedNode) -> ResolvedNode {
  var steps: [(ResolvedNode, Bool)] = [(root, false)]
  var completed: [ResolvedNode] = []
  while let (source, assembling) = steps.popLast() {
    if !assembling {
      steps.append((source, true))
      for child in source.children.reversed() { steps.append((child, false)) }
    } else {
      var node = source
      var structure = node.semanticMetadata.accessibilityStructure ?? .init()
      structure.isVirtual = true
      node.semanticMetadata.accessibilityStructure = structure
      let count = source.children.count
      if count > 0 {
        node.children = Array(completed.suffix(count))
        completed.removeLast(count)
      }
      completed.append(node)
    }
  }
  return completed.removeLast()
}
