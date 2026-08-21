package import SwiftTUIGraph

// The capture-bind pass (plan 2026-08-20-001 Stage 2).
//
// A sibling of the dynamic-property update pass that runs inside
// `resolveView`'s fresh-evaluation closure, after `beginEvaluation` has
// produced the graph node and immediately before the body evaluates: it
// writes each `@State` (and future `CaptureBindableDynamicProperty`) field's
// owner into the exact container copy body evaluation consumes, so closures
// the body creates carry their state owner instead of re-deriving it from
// ambient dispatch scope at fire time.
//
// The pass is deliberately independent of the update pass: certification,
// the `ForwardedDynamicPropertyPreparationScope` handoff, and third-party
// `DynamicProperty.update` semantics are untouched. Binding is idempotent —
// every fresh evaluation overwrites — and reuse serves never run it (no body
// runs on a serve; previously registered closures keep their captures, and
// reuse preserves the owner's node).

/// One field's bind operation, bound once per container type: either writes
/// the capture into a `CaptureBindableDynamicProperty` field, or recurses
/// into a nested `DynamicProperty` container with a path-qualified binding.
///
/// `@unsafe` because applying the binder to a raw base pointer is the unsafe
/// act; every application site spells `unsafe`.
@unsafe package struct DynamicPropertyCaptureFieldBinder {
  package let apply:
    @MainActor (UnsafeMutableRawPointer, StateCaptureBinding, _ sharedMutableContainer: Bool)
      -> Void

  package init(
    apply:
      @escaping @MainActor (
        UnsafeMutableRawPointer, StateCaptureBinding, _ sharedMutableContainer: Bool
      ) -> Void
  ) {
    unsafe self.apply = apply
  }
}

/// How the bind pass reaches one container type's bindable fields.
@unsafe package enum DynamicPropertyCaptureBindPlan {
  /// Nothing to bind — the pass returns the value untouched.
  case none
  /// Struct container: bind through a private mutable copy's field offsets.
  case structFields([DynamicPropertyCaptureFieldBinder])
  /// Native class container: bind in place through the instance's field
  /// offsets. Shared memory — binders run with the conflict-demotion guard.
  case classFields([DynamicPropertyCaptureFieldBinder])
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
    let isStruct = kind == RuntimeFieldReflection.structureKind
    // Kind 0 is a native Swift class (the runtime's MetadataKind.Class);
    // foreign/ObjC class kinds stay out — their field offsets are not
    // guaranteed by the Swift runtime's reflection entry points.
    let isNativeClass = kind == 0
    guard isStruct || isNativeClass else {
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
    return unsafe isStruct ? .structFields(binders) : .classFields(binders)
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

/// Binds a `ResolvableView` container's fields against its own node's
/// dynamic-property authoring scope — the same owner selection the update
/// pass uses ahead of the reuse door. Called from `resolveView`'s fresh
/// evaluation, where `graphNode` is this evaluation's node.
@MainActor
package func bindingDynamicPropertyCaptures<V>(
  _ view: V,
  in context: ResolveContext,
  graphNode: SwiftTUICore.ViewNode?,
  authoringContextOverride: AuthoringContext?
) -> V {
  guard StateCaptureBindingConfiguration.isEnabled else {
    return view
  }
  return boundCopy(view) {
    let scope =
      authoringContextOverride.map { rebasedAuthoringContext($0, viewNode: graphNode) }
      ?? dynamicPropertyAuthoringContext(
        for: context,
        current: currentAuthoringContext(),
        viewNode: graphNode
      )
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

/// Plan-dispatched core: struct containers bind a private copy; native class
/// containers bind in place through the shared instance (with the
/// conflict-demotion guard). Everything else — existential containers,
/// foreign classes, enum shapes — returns unchanged and counts
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
      case .classFields: StateCaptureBindTraceProbe.onVisit?(concreteType, "class")
      }
    }
  #endif
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
        sharedMutableContainer: false
      )
    }
    StateCaptureCensus.record(.bindBound)
    return copy
  case .classFields(let binders):
    guard let binding = makeBinding() else {
      StateCaptureCensus.record(.bindNoOwner)
      return view
    }
    let object = view as AnyObject
    let base = unsafe Unmanaged.passUnretained(object).toOpaque()
    unsafe applyCaptureBinders(
      binders,
      atBase: base,
      binding: binding,
      sharedMutableContainer: true
    )
    StateCaptureCensus.record(.bindBound)
    return view
  }
}

@MainActor
private func applyCaptureBinders(
  _ binders: [DynamicPropertyCaptureFieldBinder],
  atBase base: UnsafeMutableRawPointer,
  binding: StateCaptureBinding,
  sharedMutableContainer: Bool
) {
  // Index loop on purpose: `for unsafe x in` is mangled by swift-format
  // (see the env-cleanup 2026-08-10 lesson), so spell the unsafe access per
  // element instead.
  for index in 0..<(unsafe binders.count) {
    unsafe binders[index].apply(base, binding, sharedMutableContainer)
  }
}

/// Recurses into one nested container value in place. Struct-typed nested
/// containers continue at the field's memory; class-typed nested containers
/// re-enter through the reference with shared-container semantics.
@MainActor
private func bindNestedCaptures<T>(
  at pointer: UnsafeMutablePointer<T>,
  binding: StateCaptureBinding
) {
  let plan = unsafe DynamicPropertyCaptureBindPlanCache.plan(for: T.self)
  switch unsafe plan {
  case .none:
    return
  case .structFields(let binders):
    unsafe applyCaptureBinders(
      binders,
      atBase: UnsafeMutableRawPointer(pointer),
      binding: binding,
      sharedMutableContainer: false
    )
  case .classFields(let binders):
    let object = unsafe pointer.pointee as AnyObject
    let base = unsafe Unmanaged.passUnretained(object).toOpaque()
    unsafe applyCaptureBinders(
      binders,
      atBase: base,
      binding: binding,
      sharedMutableContainer: true
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
    unsafe DynamicPropertyCaptureFieldBinder { base, binding, sharedMutableContainer in
      unsafe (base + offset).assumingMemoryBound(to: T.self).pointee.bindCapture(
        binding,
        sharedMutableContainer: sharedMutableContainer
      )
    }
  }
}

extension CaptureBinderFieldShim: CaptureRecursableFieldBinding where T: DynamicProperty {
  static func nestedCaptureBinder(atOffset offset: Int, index: Int)
    -> DynamicPropertyCaptureFieldBinder
  {
    unsafe DynamicPropertyCaptureFieldBinder { base, binding, _ in
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
