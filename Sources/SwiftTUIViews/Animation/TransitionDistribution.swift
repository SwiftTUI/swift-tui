import SwiftTUICore

// A modifier that preserves its content's declared views travels down the
// resolve context until it reaches each single view. Resolving the modifier
// there gives every element the identity, graph node and replay producer
// it would have if the modifier were written directly on that element.
// Shape comes from the type so the content is mounted exactly once.

/// A view type that only arranges other views, so that what it emits is what
/// they emit. A transition on its way down passes through a view of such a
/// type to the views it arranges.
package protocol SeveralViewsStructure {
  /// Whether a value of this type can emit more than one view.
  @MainActor static var emitsSeveralViews: Bool { get }
  @MainActor static var passesElementModifiers: Bool { get }
}

extension SeveralViewsStructure {
  package static var passesElementModifiers: Bool { true }
}

extension EmptyView: SeveralViewsStructure {
  // It emits nothing, so a transition that reaches it is for no view. A
  // body evaluated around it would draw the views the body adds, with no
  // content.
  package static var emitsSeveralViews: Bool { false }
}

extension TupleView: SeveralViewsStructure {
  package static var emitsSeveralViews: Bool { true }
}

extension ForEach: SeveralViewsStructure {
  package static var emitsSeveralViews: Bool { true }
}

extension VariadicView: SeveralViewsStructure {
  // The views of a `for` loop in a builder.
  package static var emitsSeveralViews: Bool { true }
}

extension Group: SeveralViewsStructure {
  package static var emitsSeveralViews: Bool { viewEmitsSeveralViews(Content.self) }
}

extension ConditionalContent: SeveralViewsStructure {
  package static var emitsSeveralViews: Bool {
    viewEmitsSeveralViews(TrueContent.self) || viewEmitsSeveralViews(FalseContent.self)
  }
}

/// Whether a view of type `V` can emit more than one view: a `TupleView`, a
/// `ForEach` or the views of a loop, a `Group` or a conditional around one,
/// or a view whose body is one of those.
///
/// Per-element modifiers preserve their content's cardinality. Other
/// primitive modifiers can introduce views of their own. An erased view
/// has no type to read.
@MainActor
package func viewEmitsSeveralViews<V: View>(_ type: V.Type) -> Bool {
  let key = ObjectIdentifier(type)
  if let cached = SeveralViewsTypeWalk.cache[key] { return cached }
  let outermost = SeveralViewsTypeWalk.entered.isEmpty
  guard SeveralViewsTypeWalk.entered.insert(key).inserted else { return false }
  defer { SeveralViewsTypeWalk.entered.remove(key) }
  let result: Bool
  if let structure = type as? any SeveralViewsStructure.Type {
    result = structure.emitsSeveralViews
  } else {
    result = V.Body.self != Never.self && viewEmitsSeveralViews(V.Body.self)
  }
  if outermost { SeveralViewsTypeWalk.cache[key] = result }
  return result
}

/// The types ``viewEmitsSeveralViews(_:)`` is in the middle of reading.
@MainActor
private enum SeveralViewsTypeWalk {
  static var entered: Set<ObjectIdentifier> = []
  static var cache: [ObjectIdentifier: Bool] = [:]
}

/// Primitive modifiers whose application preserves the number of declared views.
package protocol PerElementViewModifier: IterativePrimitiveViewModifier, Sendable {
  var distributesOverElements: Bool { get }
}

extension PerElementViewModifier {
  package var distributesOverElements: Bool { true }
}

extension PaddingModifier: PerElementViewModifier {}
extension FrameModifier: PerElementViewModifier {}
extension FlexibleFrameModifier: PerElementViewModifier {}
extension OffsetModifier: PerElementViewModifier {}
extension DrawMetadataModifier: PerElementViewModifier {}
extension TransitionRegistrationModifier: PerElementViewModifier {
  // Built-in transitions register every emitted identity directly.
  package var distributesOverElements: Bool { transition.bodyBox != nil }
}

extension ModifiedContent: SeveralViewsStructure
where Content: View, Modifier: PerElementViewModifier {
  package static var emitsSeveralViews: Bool { viewEmitsSeveralViews(Content.self) }
  package static var passesElementModifiers: Bool { emitsSeveralViews }
}

/// One modifier on its way to the leaves, followed by the modifiers written
/// outside it. Its serial makes the passage an input to graph reuse.
package final class ElementModifierPassage: Sendable {
  package let modifier: any PerElementViewModifier
  package let outer: ElementModifierPassage?
  package let serial: UInt64

  @MainActor
  package init(_ modifier: any PerElementViewModifier, outer: ElementModifierPassage?) {
    self.modifier = modifier
    self.outer = outer
    Self.lastSerial &+= 1
    serial = Self.lastSerial
  }

  @MainActor private static var lastSerial: UInt64 = 0
}

private struct ElementModifierPassageEnvironmentKey: EnvironmentKey, FrameworkEnvironmentKey {
  static var defaultValue: UInt64? { nil }
}

extension EnvironmentValues {
  fileprivate var elementModifierPassageForReuse: UInt64? {
    get { self[ElementModifierPassageEnvironmentKey.self] }
    set { self[ElementModifierPassageEnvironmentKey.self] = newValue }
  }
}

extension ResolveContext {
  @MainActor
  fileprivate func carrying(_ passage: ElementModifierPassage?) -> ResolveContext {
    var context = settingEnvironment(\.elementModifierPassageForReuse, to: passage?.serial)
    context.elementModifier = passage
    return context
  }
}

extension PerElementViewModifier {
  @MainActor
  func distribute<Base: View>(_ content: ModifierContentInputs<Base>, in context: ResolveContext)
    -> ResolveWork<[ResolvedNode]>
  {
    let passage = ElementModifierPassage(self, outer: context.elementModifier)
    return content.resolveDeclaredElementsWork(in: context.carrying(passage)).map { elements in
      // Always keep the structural group. Crossing between one and two
      // elements must not transfer the modifier's graph node to a survivor.
      var views = elements
      assignEntityIdentityOccurrences(to: &views)
      return [
        ResolvedNode(
          identity: context.identity, kind: .view(.group),
          typeDiscriminator: ObjectIdentifier(SynthesizedGroupWrapperMarker.self),
          children: views, environmentSnapshot: context.environment,
          transactionSnapshot: context.transaction)
      ]
    }
  }

  @MainActor
  func resolveElement<V: View>(
    _ view: V, in context: ResolveContext, authoringContextOverride: AuthoringContext?,
    rebuilding: ViewEvaluationProducer<V>?
  ) -> ResolveWork<ResolvedNode> {
    resolveViewWork(
      view.modifier(self), in: context,
      authoringContextOverride: authoringContextOverride,
      rebuilding: rebuilding.map { producer in
        ViewEvaluationProducer(
          entityIdentity: producer.entityIdentity, structuralPath: producer.structuralPath,
          declaredChildReplayBoundary: producer.declaredChildReplayBoundary,
          makeView: { producer.makeView($0).modifier(self) })
      })
  }

  @MainActor
  func resolveElementList<V: View>(_ view: V, in context: ResolveContext) -> ResolveWork<
    [ResolvedNode]
  > {
    resolveViewElementsWork(view.modifier(self), in: context)
  }
}

@MainActor
func takingElementModifier<V: View>(
  _ type: V.Type, in context: ResolveContext
) -> (modifier: any PerElementViewModifier, context: ResolveContext)? {
  guard let passage = context.elementModifier else { return nil }
  if let structure = type as? any SeveralViewsStructure.Type {
    if structure.passesElementModifiers { return nil }
  } else if V.Body.self != Never.self, viewEmitsSeveralViews(V.Body.self) {
    return nil
  }
  return (passage.modifier, context.carrying(passage.outer))
}
