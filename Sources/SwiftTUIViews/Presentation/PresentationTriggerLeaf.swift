import SwiftTUICore

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
  /// The declaration's source identity (the resolved background's identity) —
  /// reported with every resolve so the frame head can compare observations
  /// against the portal registry's declared sources.
  let sourceIdentity: Identity
  /// Reads the presentation's activation state (`isPresented.wrappedValue`,
  /// `item.wrappedValue != nil`, tip eligibility + dismissal `@State`, …).
  /// Invoked only inside this leaf's resolve so every `@State`/binding read it
  /// performs is reader-attributed to the leaf.
  let isActive: @MainActor () -> Bool
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
    // of the background). Toggling the presentation state then dirties only
    // this leaf, leaving the disjoint-sibling background reusable.
    let active = isActive()
    // Reported on EVERY resolve (active or not): the frame head no longer
    // force-queues the portal root on invalidation frames, so an observed
    // activation change is what escalates the frame to a portal reconcile.
    context.presentationTriggerObserver?.record(
      sourceIdentity: sourceIdentity,
      isActive: active
    )
    if active {
      node.preferenceValues.merge(
        PresentationCoordinatorDeclarationPreferenceKey.self,
        value: makeDeclaration()
      )
    }
    return [node]
  }
}

/// Shared resolve path for the builtin presentation modifiers.
///
/// Resolves the background at a `base` child so a zero-size
/// ``PresentationTriggerLeaf`` sibling can own the activation read. A wrapper
/// pins `context.identity` and parents `[background, trigger]` as disjoint
/// siblings, so toggling the presentation state dirties only the trigger leaf
/// (reader-attributed) and spares the background.
///
/// `prepareBackground` runs on the resolved background (e.g. the palette sheet
/// absorbs and clears `PaletteCommandsPreferenceKey`). The `declaration` closure
/// builds the coordinator declaration lazily from the resolved background; it is
/// invoked only when the trigger leaf observes an active presentation,
/// preserving the "build the presentation item only while presented" laziness.
@MainActor
func resolvePresentationModifier<Base: View>(
  content: ModifierContentInputs<Base>,
  isPresented: Binding<Bool>,
  in context: ResolveContext,
  prepareBackground: (inout ResolvedNode) -> Void = { _ in },
  declaration:
    @escaping @MainActor (_ background: ResolvedNode) ->
    PresentationCoordinatorDeclarationPreferenceValue
) -> [ResolvedNode] {
  resolvePresentationModifier(
    content: content,
    isActive: { isPresented.wrappedValue },
    in: context,
    prepareBackground: prepareBackground,
    declaration: declaration
  )
}

/// Generalized core of ``resolvePresentationModifier(content:isPresented:in:prepareBackground:declaration:)``
/// for presentations whose activation state is not a plain `Binding<Bool>`
/// (item bindings, tip eligibility + dismissal `@State`). `isActive` is read
/// inside the trigger leaf's resolve so all of its `@State`/binding reads are
/// reader-attributed to the leaf.
@MainActor
func resolvePresentationModifier<Base: View>(
  content: ModifierContentInputs<Base>,
  isActive: @escaping @MainActor () -> Bool,
  in context: ResolveContext,
  prepareBackground: (inout ResolvedNode) -> Void = { _ in },
  declaration:
    @escaping @MainActor (_ background: ResolvedNode) ->
    PresentationCoordinatorDeclarationPreferenceValue
) -> [ResolvedNode] {
  var background = content.resolve(in: context.child(component: .named("base")))
  prepareBackground(&background)
  let resolvedBackground = background
  let trigger = PresentationTriggerLeaf(
    sourceIdentity: resolvedBackground.identity,
    isActive: isActive
  ) {
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
