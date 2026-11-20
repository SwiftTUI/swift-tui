// Overload selection for `View.transition(_:)` (STUI-1543). This file must
// typecheck CLEAN against the built modules;
// `Scripts/check_transition_overloads.sh` fails the lane if it does not.
//
// `View` has two `transition(_:)` methods: one takes an `AnyTransition`, the
// other any `Transition`. Both return an opaque view, and the two opaque
// types differ, so a result's type names the overload that produced it.
// `expectSameOverload` compiles only when its two arguments have one type.
// Every result is bound with `let` first, so the call is resolved with no
// contextual type before it is compared.
//
// - A reference built from a value whose type is `AnyTransition` can only
//   come from the `AnyTransition` overload. Every spelling that existed
//   before the generic overload is compared with it, so each of them still
//   selects the overload it selected before.
// - A reference built from a value of a concrete transition type can only
//   come from the generic overload. Each new spelling is compared with the
//   reference of its own transition type.
//
// It is a downstream consumer's file: it imports the public product only.

import SwiftTUIViews

struct Custom: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View { content }
}

struct Indent: ViewModifier {
  var amount: Int
  func body(content: Content) -> some View { content.padding(.leading, amount) }
}

@MainActor func expectSameOverload<T>(_ lhs: T, _ rhs: T) {}

@MainActor
func existingSpellings(flag: Bool, optional: AnyTransition?) {
  let view = Text("x")
  let stored: AnyTransition = .move(edge: .bottom)
  let viaAnyTransition = view.transition(stored)

  // The built-in statics.
  let a1 = view.transition(.opacity)
  expectSameOverload(a1, viaAnyTransition)
  let a2 = view.transition(.identity)
  expectSameOverload(a2, viaAnyTransition)
  let a3 = view.transition(.slide)
  expectSameOverload(a3, viaAnyTransition)
  let a4 = view.transition(.scale)
  expectSameOverload(a4, viaAnyTransition)
  let a5 = view.transition(.move(edge: .top))
  expectSameOverload(a5, viaAnyTransition)
  let a6 = view.transition(.move(edge: .leading))
  expectSameOverload(a6, viaAnyTransition)
  let a7 = view.transition(.scale(scale: 0.5))
  expectSameOverload(a7, viaAnyTransition)
  let a8 = view.transition(.scale(scale: 0.5, anchor: .center))
  expectSameOverload(a8, viaAnyTransition)
  let a9 = view.transition(.scale(scale: 1e300))
  expectSameOverload(a9, viaAnyTransition)
  let a10 = view.transition(.offset(x: 12))
  expectSameOverload(a10, viaAnyTransition)
  let a11 = view.transition(.offset(y: 3))
  expectSameOverload(a11, viaAnyTransition)
  let a12 = view.transition(.offset(x: 1, y: 2))
  expectSameOverload(a12, viaAnyTransition)
  let a13 = view.transition(.offset())
  expectSameOverload(a13, viaAnyTransition)
  let a14 = view.transition(.push(from: .leading))
  expectSameOverload(a14, viaAnyTransition)

  // Combinators and chains.
  let b1 = view.transition(.opacity.combined(with: .slide))
  expectSameOverload(b1, viaAnyTransition)
  let b2 = view.transition(.opacity.combined(with: .offset(x: 8)))
  expectSameOverload(b2, viaAnyTransition)
  let b3 = view.transition(.opacity.combined(with: .scale))
  expectSameOverload(b3, viaAnyTransition)
  let b4 = view.transition(.move(edge: .leading).combined(with: .opacity))
  expectSameOverload(b4, viaAnyTransition)
  let b5 = view.transition(.asymmetric(insertion: .opacity, removal: .slide))
  expectSameOverload(b5, viaAnyTransition)
  let b6 = view.transition(
    .asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .scale))
  expectSameOverload(b6, viaAnyTransition)
  let b7 = view.transition(
    .asymmetric(
      insertion: .move(edge: .trailing).combined(with: .opacity),
      removal: .scale.combined(with: .opacity)))
  expectSameOverload(b7, viaAnyTransition)
  let b8 = view.transition(
    .asymmetric(
      insertion: .asymmetric(insertion: .opacity, removal: .identity),
      removal: .push(from: .top)))
  expectSameOverload(b8, viaAnyTransition)

  // Ternaries, explicit types and stored values.
  let c1 = view.transition(flag ? .opacity : .slide)
  expectSameOverload(c1, viaAnyTransition)
  let c2 = view.transition(flag ? .move(edge: .top) : .move(edge: .bottom))
  expectSameOverload(c2, viaAnyTransition)
  let c3 = view.transition(flag ? AnyTransition.scale : AnyTransition.offset(x: 4))
  expectSameOverload(c3, viaAnyTransition)
  let c4 = view.transition(AnyTransition.opacity)
  expectSameOverload(c4, viaAnyTransition)
  let c5 = view.transition(
    AnyTransition.asymmetric(insertion: .move(edge: .leading), removal: .opacity))
  expectSameOverload(c5, viaAnyTransition)
  let c6 = view.transition(AnyTransition.move(edge: .leading).combined(with: .move(edge: .top)))
  expectSameOverload(c6, viaAnyTransition)
  let c7 = view.transition(AnyTransition.offset(x: 2, y: 1).combined(with: .identity))
  expectSameOverload(c7, viaAnyTransition)
  let c8 = view.transition(optional ?? .opacity)
  expectSameOverload(c8, viaAnyTransition)

  // A modifier chain around the call does not change the selection.
  let d1 = view.padding(1).transition(.identity).padding(1)
  let d1Reference = view.padding(1).transition(stored).padding(1)
  expectSameOverload(d1, d1Reference)
  let d2 = Button("b") {}.transition(.opacity)
  let d2Reference = Button("b") {}.transition(stored)
  expectSameOverload(d2, d2Reference)
  let d3 = view.id("wrapped").transition(.opacity)
  let d3Reference = view.id("wrapped").transition(stored)
  expectSameOverload(d3, d3Reference)

  // An unapplied reference is not ambiguous: the generic overload has nothing
  // to fix its parameter from.
  let unapplied = view.transition
  let e1 = unapplied(.opacity)
  expectSameOverload(e1, viaAnyTransition)
  let e2 = unapplied(stored)
  expectSameOverload(e2, viaAnyTransition)

  // The additions to `AnyTransition` stay on the `AnyTransition` overload.
  let f1 = view.transition(AnyTransition(Custom()))
  expectSameOverload(f1, viaAnyTransition)
  let f2 = view.transition(.opacity.animation(nil))
  expectSameOverload(f2, viaAnyTransition)
  let f3 = view.transition(.modifier(active: Indent(amount: 2), identity: Indent(amount: 0)))
  expectSameOverload(f3, viaAnyTransition)
}

@MainActor
func newSpellings() {
  let view = Text("x")

  // A value of a concrete transition type can only select the generic
  // overload. The static members select it with the same transition type.
  let custom = view.transition(Custom())
  let custom2 = view.transition(Custom())
  expectSameOverload(custom, custom2)

  let viaOpacityType = view.transition(OpacityTransition())
  let opacity: OpacityTransition = .opacity
  let g1 = view.transition(opacity)
  expectSameOverload(g1, viaOpacityType)

  let viaScaleType = view.transition(ScaleTransition(0.5))
  let g2 = view.transition(.scale(0.5))
  expectSameOverload(g2, viaScaleType)
  let g3 = view.transition(.scale(0.5, anchor: .center))
  expectSameOverload(g3, viaScaleType)

  let viaOffsetType = view.transition(OffsetTransition(CellSize(width: 1, height: 0)))
  let g4 = view.transition(.offset(CellSize(width: 1, height: 0)))
  expectSameOverload(g4, viaOffsetType)

  let viaAsymmetricType = view.transition(
    AsymmetricTransition(insertion: OpacityTransition(), removal: Custom()))
  let g5 = view.transition(AsymmetricTransition(insertion: .opacity, removal: Custom()))
  expectSameOverload(g5, viaAsymmetricType)

  // Results of `combined(with:)` and `animation(_:)` are transitions, not
  // `AnyTransition` values, so only the generic overload accepts them.
  _ = view.transition(Custom().combined(with: .opacity))
  _ = view.transition(Custom().animation(nil))
  _ = view.transition(OpacityTransition().combined(with: MoveTransition(edge: .top)))
  _ = view.transition(MoveTransition(edge: .top))
  _ = view.transition(PushTransition(edge: .top))
  _ = view.transition(SlideTransition())
  _ = view.transition(IdentityTransition())
}
