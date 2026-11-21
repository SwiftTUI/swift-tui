import SwiftTUICore

// A transition with a body, applied to a view that emits several views.
//
// SwiftUI applies a transition to each view its content emits: on a `Group`
// of two views, on the rows of a `ForEach`, or on a view whose body has
// several roots, each view has the transition, and the body is evaluated once
// for each. A body takes one view as its `content`, behind one boundary
// (`TransitionContent`), so that is the only shape it can be evaluated for.
//
// So the transition is not evaluated where it is written when its content is
// several views. It travels down in the resolve context
// (`ResolveContext.elementTransition`), through the views that only arrange
// other views, and the first view on each path that is one view takes it:
// that view resolves as if `.transition(_:)` had been written on it. Every
// view of the content then has a transition of its own, with its own graph
// node, registration, boundary and phases, which is the case the animation
// engine already inserts and removes. Nothing is shared between the views.
//
// Whether a view emits several views is read from its type, not from what it
// resolves to: the body has to be chosen before the content resolves, and
// resolving the content twice would mount it twice.

/// A view type that only arranges other views, so that what it emits is what
/// they emit. A transition on its way down passes through a view of such a
/// type to the views it arranges.
package protocol SeveralViewsStructure {
  /// Whether a value of this type can emit more than one view.
  @MainActor static var emitsSeveralViews: Bool { get }
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
/// A view with a modifier on it that has no body is one view here, whatever
/// it wraps, and so is an `AnyView`: such a modifier can resolve views of
/// its own, which the transition is not for, and an erased view has no type
/// to read. A modifier with a body is read through its body like any view.
@MainActor
package func viewEmitsSeveralViews<V: View>(_ type: V.Type) -> Bool {
  if let structure = type as? any SeveralViewsStructure.Type {
    // A type can reach itself through its body: a view that shows another
    // of its own type in one branch of an `if`. That path adds no view to
    // what the other paths emit.
    let key = ObjectIdentifier(type)
    guard SeveralViewsTypeWalk.entered.insert(key).inserted else { return false }
    defer { SeveralViewsTypeWalk.entered.remove(key) }
    return structure.emitsSeveralViews
  }
  if V.Body.self == Never.self {
    return false
  }
  let key = ObjectIdentifier(type)
  guard SeveralViewsTypeWalk.entered.insert(key).inserted else { return false }
  defer { SeveralViewsTypeWalk.entered.remove(key) }
  return viewEmitsSeveralViews(V.Body.self)
}

/// The types ``viewEmitsSeveralViews(_:)`` is in the middle of reading.
@MainActor
private enum SeveralViewsTypeWalk {
  static var entered: Set<ObjectIdentifier> = []
}

/// A transition on its way down to each view of several.
package final class ElementTransition: Sendable {
  package let transition: AnyTransition
  /// Names this passage of the transition. Each resolve of the modifier it
  /// was written on starts a new one.
  package let serial: UInt64

  @MainActor
  package init(_ transition: AnyTransition) {
    self.transition = transition
    Self.lastSerial &+= 1
    serial = Self.lastSerial
  }

  @MainActor private static var lastSerial: UInt64 = 0
}

/// Reuse currency for a transition on its way down.
///
/// The transition in the resolve context is an input to the resolve of every
/// view it passes through, and it is not part of the graph's reuse key. A
/// view it passes through can be one the graph would serve from an earlier
/// resolve: a view with a body of several roots and plain values for
/// fields. Mirroring the passage into the environment snapshot denies that
/// reuse whenever the transition was resolved again, was removed, or is
/// new, so each view below takes the transition as it is now. The view that
/// takes the transition clears the mirror with it, so the content behind it
/// is reused as it is without one.
private struct ElementTransitionPassageEnvironmentKey: EnvironmentKey, FrameworkEnvironmentKey {
  static var defaultValue: UInt64? { nil }
}

extension EnvironmentValues {
  package var elementTransitionPassageForReuse: UInt64? {
    get { self[ElementTransitionPassageEnvironmentKey.self] }
    set { self[ElementTransitionPassageEnvironmentKey.self] = newValue }
  }
}

extension ResolveContext {
  /// This context with `transition` on its way to each view below.
  @MainActor
  package func distributing(_ transition: AnyTransition) -> ResolveContext {
    let passage = ElementTransition(transition)
    var context = settingEnvironment(\.elementTransitionPassageForReuse, to: passage.serial)
    context.elementTransition = passage
    return context
  }
}

/// The view that takes a transition travelling down in `context`, or `nil`
/// when there is none or `view` passes it on to the views it arranges.
///
/// The result resolves in the returned context, which no longer carries the
/// transition: it is for `view`, not for the views inside it.
@MainActor
func takingElementTransition<V: View>(
  _ view: V,
  in context: ResolveContext
) -> (view: ModifiedContent<V, TransitionRegistrationModifier>, context: ResolveContext)? {
  guard let pending = context.elementTransition else {
    return nil
  }
  // A view that arranges other views passes the transition on, whether it
  // arranges one or several: a `Group` around one view, a branch of an `if`.
  // A view with a body takes it unless the body is several views.
  if V.self is any SeveralViewsStructure.Type {
    return nil
  }
  if V.Body.self != Never.self, viewEmitsSeveralViews(V.Body.self) {
    return nil
  }
  var elementContext = context.settingEnvironment(\.elementTransitionPassageForReuse, to: nil)
  elementContext.elementTransition = nil
  return (
    view.modifier(TransitionRegistrationModifier(transition: pending.transition)), elementContext
  )
}
