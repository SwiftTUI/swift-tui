public import SwiftTUICore

/// A zero-size, layout-inert sibling leaf that is the **sole reader** of a
/// presentation's `isPresented` binding.
///
/// This is "Lever B" of the sheet-open re-architecture. The expensive part of
/// opening a sheet/palette is that toggling `isPresented` re-resolves the whole
/// *background*, even though the background does not change. That happens
/// because the presenting view (the `@State` slot owner) is an ancestor of the
/// background, so the standard modifier — which reads `isPresented` while the
/// background root is the current `ViewNode` — attributes the read to that
/// ancestor and dirties its entire subtree.
///
/// Reading `isPresented` *inside this leaf's own* `ViewNodeContext` instead
/// attributes the `@State` read to the leaf (under
/// ``ReaderAttributionConfiguration``). Because the leaf is resolved as a
/// disjoint sibling of the background — neither an ancestor nor a descendant of
/// it — toggling the binding dirties only the leaf, and the existing reuse
/// machinery spares the background (sheet open becomes O(overlay), not
/// O(background)). The leaf carries the presentation-coordinator declaration up
/// as a preference exactly as the background did before, so nothing downstream
/// of the portal changes.
struct PresentationTriggerLeaf: PrimitiveView, ResolvableView {
  let isPresented: Binding<Bool>
  let makeDeclaration: @MainActor () -> PresentationCoordinatorDeclarationPreferenceValue

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = ResolvedNode(
      identity: context.identity,
      kind: .view("__presentationTrigger"),
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      intrinsicSize: .zero
    )
    // The crux of Lever B: this read executes inside the trigger leaf's
    // ViewNodeContext, so reader-attributed `@State` tracking records the
    // dependency on THIS leaf rather than the binding's slot owner (an ancestor
    // of the background). Toggling `isPresented` then dirties only this leaf,
    // leaving the disjoint-sibling background reusable.
    if isPresented.wrappedValue {
      node.preferenceValues.merge(
        PresentationCoordinatorDeclarationPreferenceKey.self,
        value: makeDeclaration()
      )
    }
    return [node]
  }
}

/// Shared resolve path for the builtin presentation modifiers, gated on
/// reader-attribution.
///
/// - When ``ReaderAttributionConfiguration/isEnabled`` is **off** (default),
///   this is byte-identical to the pre-Lever-B behavior: resolve the background
///   at `context.identity`, read `isPresented` there, and merge the declaration
///   onto it.
/// - When **on**, resolve the background at a `base` child so a zero-size
///   ``PresentationTriggerLeaf`` sibling can own the `isPresented` read. A
///   wrapper pins `context.identity` and parents `[background, trigger]` as
///   disjoint siblings, so toggling `isPresented` spares the background.
///
/// `prepareBackground` runs on the resolved background in both paths (e.g. the
/// palette sheet absorbs and clears `PaletteCommandsPreferenceKey`). The
/// `declaration` closure builds the coordinator declaration lazily from the
/// resolved background; in the reader-attributed path it is invoked only when
/// the trigger leaf observes `isPresented == true`, preserving the original
/// "build the presentation item only while presented" laziness.
@MainActor
func resolvePresentationModifier<Base: View>(
  content: ModifierContentInputs<Base>,
  isPresented: Binding<Bool>,
  in context: ResolveContext,
  prepareBackground: (inout ResolvedNode) -> Void = { _ in },
  declaration: @escaping @MainActor (_ background: ResolvedNode) ->
    PresentationCoordinatorDeclarationPreferenceValue
) -> [ResolvedNode] {
  guard ReaderAttributionConfiguration.isEnabled else {
    var node = content.resolve(in: context)
    prepareBackground(&node)
    guard isPresented.wrappedValue else {
      return [node]
    }
    node.preferenceValues.merge(
      PresentationCoordinatorDeclarationPreferenceKey.self,
      value: declaration(node)
    )
    return [node]
  }

  var background = content.resolve(in: context.child(component: .named("base")))
  prepareBackground(&background)
  let resolvedBackground = background
  let trigger = PresentationTriggerLeaf(isPresented: isPresented) {
    declaration(resolvedBackground)
  }
  let triggerNode = resolveView(
    trigger,
    in: context.child(component: .named("__presentationTrigger"))
  )
  return [
    ResolvedNode(
      identity: context.identity,
      kind: .view("Presentation"),
      children: [background, triggerNode],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      layoutBehavior: .decoration(primaryIndex: 0, alignment: .topLeading)
    )
  ]
}
