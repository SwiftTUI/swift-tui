import SwiftTUIGraph

// The capture-bind pass (plan 2026-08-20-001 Stages 2–3).
//
// A sibling of the dynamic-property update pass that runs immediately before
// user-authored code evaluates, at three seams: `resolveViewElements`'
// resolvable branch (every `ResolvableView` evaluation), its plain-body tail
// (every `body` evaluation, transparent forwarding containers included), and
// the forwarding seams where a composed `ViewModifier` or style struct runs
// its body (`bindingForwardedDynamicPropertyCaptures`). It writes each
// `@State` (and future `CaptureBindableDynamicProperty`) field's owner into
// the exact container copy that code consumes, so closures it creates carry
// their state owner instead of re-deriving it from ambient dispatch scope at
// fire time.
//
// The pass is deliberately independent of the update pass: certification,
// the `ForwardedDynamicPropertyPreparationScope` handoff, and third-party
// `DynamicProperty.update` semantics are untouched. Binding is idempotent —
// every fresh evaluation overwrites — and reuse serves never run it (no body
// runs on a serve; previously registered closures keep their captures, and
// reuse preserves the owner's node).
//
// The overwrite is unconditional because authored containers are value types
// (plan 2026-08-29-001): the pass writes through a copy private to one mount
// and one evaluation, so no two mounts can reach the same wrapper slot. That
// invariant is what removed the shared-container tier this pass used to carry.

/// One field's bind operation, bound once per container type: either writes
/// the capture into a `CaptureBindableDynamicProperty` field, or recurses
/// into a nested `DynamicProperty` container with a path-qualified binding.
///
/// `@unsafe` because applying the binder to a raw base pointer is the unsafe
/// act; every application site spells `unsafe`.
@unsafe package struct DynamicPropertyCaptureFieldBinder {
  /// The stored-field index this binder writes, mirrored from the update
  /// pass's field discovery so an `AdditionalDynamicPropertyUpdating`
  /// container can exclude fields it forwards itself (those bind as their
  /// own root at the forwarding seam, with root-relative paths — binding
  /// them here under an appended path would name a different slot than the
  /// forwarded update claims).
  package let index: Int
  package let apply: @MainActor (UnsafeMutableRawPointer, StateCaptureBinding) -> Void

  package init(
    index: Int,
    apply: @escaping @MainActor (UnsafeMutableRawPointer, StateCaptureBinding) -> Void
  ) {
    unsafe self.index = index
    unsafe self.apply = apply
  }
}

/// How the bind pass reaches one container type's bindable fields.
///
/// Two tiers only: authored containers are value types (plan 2026-08-29-001),
/// so a bindable container is always a struct whose private copy the pass
/// owns. Enum and existential shapes fall to `.none`.
@unsafe package enum DynamicPropertyCaptureBindPlan {
  /// Nothing to bind — the pass returns the value untouched.
  case none
  /// Struct container: bind through a private mutable copy's field offsets.
  case structFields([DynamicPropertyCaptureFieldBinder])
}

/// Reflect-once-per-type cache of ``DynamicPropertyCaptureBindPlan``s.
/// Independent of `DynamicPropertyDescriptorCache` so the update pass's plan
/// shapes and cache lifecycle stay untouched.
@MainActor
package enum DynamicPropertyCaptureBindPlanCache {
  private static var plansByType: [ObjectIdentifier: DynamicPropertyCaptureBindPlan] =
    unsafe [:]

  package static func plan(for type: Any.Type) -> DynamicPropertyCaptureBindPlan {
    let key = ObjectIdentifier(type)
    if let cached = unsafe plansByType[key] {
      return unsafe cached
    }
    let built = unsafe buildPlan(for: type)
    unsafe plansByType[key] = built
    return unsafe built
  }

  package static func resetForTesting() {
    unsafe plansByType.removeAll(keepingCapacity: false)
  }

  private static func buildPlan(for type: Any.Type) -> DynamicPropertyCaptureBindPlan {
    let kind = RuntimeFieldReflection.metadataKind(of: type)
    if ValueTypeAuthoringInvariant.isClassKind(kind) {
      // Unreachable from Swift source: every authoring protocol a container
      // can reach this builder through rejects class conformers at compile
      // time. See ValueTypeAuthoringInvariant.
      ValueTypeAuthoringInvariant.rejectClassContainer(type)
    }
    guard kind == RuntimeFieldReflection.structureKind else {
      return unsafe .none
    }
    var binders: [DynamicPropertyCaptureFieldBinder] = unsafe []
    let fieldCount = RuntimeFieldReflection.fieldCount(of: type)
    for index in 0..<fieldCount {
      let info = RuntimeFieldReflection.fieldInfo(of: type, at: index)
      guard info.isStrong else {
        continue
      }
      let shim = openedBinderShim(boundTo: info.fieldType)
      if let bindable = shim as? any CaptureBindableFieldBinding.Type {
        unsafe binders.append(
          unsafe bindable.captureBinder(atOffset: info.offset, index: index)
        )
      } else if let recursable = shim as? any CaptureRecursableFieldBinding.Type {
        unsafe binders.append(
          unsafe recursable.nestedCaptureBinder(atOffset: info.offset, index: index)
        )
      }
    }
    guard unsafe !binders.isEmpty else {
      return unsafe .none
    }
    return unsafe .structFields(binders)
  }

  /// Rebinds the shim's generic parameter to `fieldType` so the conditional
  /// conformances (`where T: CaptureBindableDynamicProperty`, `where
  /// T: DynamicProperty`) can be tested at runtime.
  private static func openedBinderShim(boundTo fieldType: Any.Type) -> Any.Type {
    func open<F>(_ concrete: F.Type) -> Any.Type {
      CaptureBinderFieldShim<F>.self
    }
    return _openExistential(fieldType, do: open)
  }
}

#if DEBUG
  /// Test-only observation of the bind pass: fires once per visited container
  /// with its plan tier. Production behavior is unchanged.
  @MainActor
  package enum StateCaptureBindTraceProbe {
    package static var onVisit: ((_ containerType: Any.Type, _ tier: String) -> Void)?
  }
#endif

/// Binds a `ResolvableView` container's fields immediately before its
/// `resolveElements` runs — at `resolveViewElements`' resolvable branch, the
/// one seam every resolvable evaluation funnels through: `resolveView`'s
/// fresh path, `ScopedBuilder`'s transparent resolvable-output closure, a
/// body result that is itself a resolvable container, and conditional-branch
/// content all route here. Owner selection is exactly
/// `dynamicPropertyAuthoringContext(for:current:viewNode:)` — the same
/// function `withDynamicPropertyUpdateScope` applies inside every
/// resolvable's `resolveElements` — so the capture and the update pass's box
/// binding can never disagree: a same-node ambient scope (a rebased style
/// override, a body-result container sharing its author's node) keeps that
/// scope's owner, and any other shape resolves to the currently evaluating
/// node's own scope.
@MainActor
package func bindingResolvableDynamicPropertyCaptures<V>(
  _ view: V,
  in context: ResolveContext
) -> V {
  guard StateCaptureBindingConfiguration.isEnabled else {
    return view
  }
  return boundCopy(view) {
    let scope = dynamicPropertyAuthoringContext(
      for: context,
      current: currentAuthoringContext(),
      viewNode: ViewNodeContext.current
    )
    return rootCaptureBinding(for: scope)
  }
}

/// Binds a transparently forwarded payload as its own root container under
/// the current ambient scope — the exact mirror of
/// `runForwardedDynamicPropertyUpdates`, which updates such payloads with
/// root-relative paths under the scope active at the forwarding seam. Used
/// for a composed `ViewModifier` value before its `body(content:)` runs and
/// for a style struct before its `makeBody(configuration:)` runs; both are
/// evaluated under an installed ambient scope, so a nil ambient here means
/// no owner is nameable and the value stays unbound (counted).
@MainActor
package func bindingForwardedDynamicPropertyCaptures<V>(_ value: V) -> V {
  guard StateCaptureBindingConfiguration.isEnabled else {
    return value
  }
  return boundCopy(value) {
    guard let scope = currentAuthoringContext() else {
      return nil
    }
    return rootCaptureBinding(for: scope)
  }
}

/// Binds a plain-body view immediately before its body evaluates — the one
/// seam every body evaluation funnels through (`resolveViewElements` forms
/// the `{ view.body }` closure here), including transparent forwarding
/// containers such as `ScopedBuilder` that never give their wrapped value a
/// `resolveView` of its own. Owner selection mirrors `View.resolveBody`'s
/// ambient-wins rule exactly: an installed ambient scope names the owner the
/// body's wrappers will bind, and only its absence falls back to a scope for
/// the currently evaluating node.
@MainActor
package func bindingBodyDynamicPropertyCaptures<V: View>(
  _ view: V,
  in context: ResolveContext
) -> V {
  guard StateCaptureBindingConfiguration.isEnabled else {
    return view
  }
  return boundCopy(view) {
    let scope =
      currentAuthoringContext()
      ?? makeAuthoringContext(
        for: context,
        viewNode: ViewNodeContext.current
      )
    return rootCaptureBinding(for: scope)
  }
}

/// Capture and box binding must name the same owner, or capture-served reads
/// would route past the slot resolve-time writes land in — so the binding is
/// derived from the exact authoring scope the caller's wrappers bind under.
/// The refresh identity is the scope's authored view identity (the owner
/// node's), not the local resolve identity, so a capture bound through a
/// reinstalled ambient scope refreshes toward its true author.
@MainActor
private func rootCaptureBinding(for scope: AuthoringContext) -> StateCaptureBinding? {
  guard let owner = stateStorageOwner(for: scope) else {
    return nil
  }
  return StateCaptureBinding(
    owner: owner,
    identity: scope.viewIdentity,
    graphScope: graphScopeID(for: scope) ?? owner.graphScope,
    path: .root
  )
}

/// Plan-dispatched core: a struct container binds a private copy — the only
/// bindable tier, because authored containers are value types. Everything
/// else (existential containers, enum shapes) returns unchanged and counts
/// `state.captureBind.skippedTier`.
@MainActor
private func boundCopy<V>(
  _ view: V,
  makeBinding: () -> StateCaptureBinding?
) -> V {
  let concreteType = type(of: view)
  let plan = unsafe DynamicPropertyCaptureBindPlanCache.plan(for: concreteType)
  #if DEBUG
    if StateCaptureBindTraceProbe.onVisit != nil {
      switch unsafe plan {
      case .none: StateCaptureBindTraceProbe.onVisit?(concreteType, "none")
      case .structFields: StateCaptureBindTraceProbe.onVisit?(concreteType, "struct")
      }
    }
  #endif
  // A transparent container that forwards fields itself (ScopedBuilder's
  // output, ModifiedContent's content/modifier) excludes them here exactly
  // as the update pass does: those values bind as their own root at their
  // forwarding seam.
  let traversalOwner = view as? any AdditionalDynamicPropertyUpdating
  switch unsafe plan {
  case .none:
    return view
  case .structFields(let binders):
    guard V.self == concreteType else {
      // An existential `V` boxes a differently-typed value; a pointer to it
      // would address the box, not the value the plan's offsets describe.
      StateCaptureCensus.record(.bindSkippedTier)
      return view
    }
    guard let binding = makeBinding() else {
      StateCaptureCensus.record(.bindNoOwner)
      return view
    }
    var copy = view
    unsafe withUnsafeMutablePointer(to: &copy) { base in
      unsafe applyCaptureBinders(
        binders,
        atBase: UnsafeMutableRawPointer(base),
        binding: binding,
        excludingFieldsOwnedBy: traversalOwner
      )
    }
    StateCaptureCensus.record(.bindBound)
    return copy
  }
}

@MainActor
private func applyCaptureBinders(
  _ binders: [DynamicPropertyCaptureFieldBinder],
  atBase base: UnsafeMutableRawPointer,
  binding: StateCaptureBinding,
  excludingFieldsOwnedBy owner: (any AdditionalDynamicPropertyUpdating)? = nil
) {
  // Index loop on purpose: `for unsafe x in` is mangled by swift-format
  // (see the env-cleanup 2026-08-10 lesson), so spell the unsafe access per
  // element instead.
  for index in 0..<(unsafe binders.count) {
    if owner?.ownsDynamicPropertyTraversal(ofStoredFieldAt: unsafe binders[index].index)
      == true
    {
      continue
    }
    unsafe binders[index].apply(base, binding)
  }
}

/// Recurses into one nested container value in place, at the field's memory.
/// A nested container is a `DynamicProperty`, so it too is a value type.
@MainActor
private func bindNestedCaptures<T>(
  at pointer: UnsafeMutablePointer<T>,
  binding: StateCaptureBinding
) {
  let plan = unsafe DynamicPropertyCaptureBindPlanCache.plan(for: T.self)
  let traversalOwner = unsafe pointer.pointee as? any AdditionalDynamicPropertyUpdating
  switch unsafe plan {
  case .none:
    return
  case .structFields(let binders):
    unsafe applyCaptureBinders(
      binders,
      atBase: UnsafeMutableRawPointer(pointer),
      binding: binding,
      excludingFieldsOwnedBy: traversalOwner
    )
  }
}

/// Conditional-conformance shims: `CaptureBinderFieldShim<F>` conforms to the
/// bindable protocol only when `F: CaptureBindableDynamicProperty` and to the
/// recursable protocol only when `F: DynamicProperty`, so `as? any ...Type`
/// casts are the runtime conformance tests — and inside a conformance, `T`
/// is bound with its constraint so the pointer access is statically typed.
/// The plan builder tests bindable first; a bindable wrapper handles itself
/// and is never recursed into.
private protocol CaptureBindableFieldBinding {
  @MainActor static func captureBinder(atOffset offset: Int, index: Int)
    -> DynamicPropertyCaptureFieldBinder
}

private protocol CaptureRecursableFieldBinding {
  @MainActor static func nestedCaptureBinder(atOffset offset: Int, index: Int)
    -> DynamicPropertyCaptureFieldBinder
}

private enum CaptureBinderFieldShim<T> {}

extension CaptureBinderFieldShim: CaptureBindableFieldBinding
where T: CaptureBindableDynamicProperty {
  static func captureBinder(atOffset offset: Int, index: Int)
    -> DynamicPropertyCaptureFieldBinder
  {
    unsafe DynamicPropertyCaptureFieldBinder(index: index) { base, binding in
      unsafe (base + offset).assumingMemoryBound(to: T.self).pointee.bindCapture(binding)
    }
  }
}

extension CaptureBinderFieldShim: CaptureRecursableFieldBinding where T: DynamicProperty {
  static func nestedCaptureBinder(atOffset offset: Int, index: Int)
    -> DynamicPropertyCaptureFieldBinder
  {
    unsafe DynamicPropertyCaptureFieldBinder(index: index) { base, binding in
      // A nested wrapper's own fields bind under the container's field path —
      // the same qualification `updateDynamicProperty` gives the nested
      // update walk — so composed-wrapper instances keep distinct slots.
      let nested = StateCaptureBinding(
        owner: binding.owner,
        identity: binding.identity,
        graphScope: binding.graphScope,
        path: binding.path.appending(index)
      )
      unsafe bindNestedCaptures(
        at: (base + offset).assumingMemoryBound(to: T.self),
        binding: nested
      )
    }
  }
}
