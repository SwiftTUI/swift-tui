// The negative half of the `View.transition(_:)` overload fixture
// (STUI-1543). This file MUST fail to compile, and only on the lines marked
// `expect-error`: `Scripts/check_transition_overloads.sh` requires an error on
// each marked line and none anywhere else.
//
// `accepted.swift` proves each spelling selects one overload by comparing
// result types. That proof holds only if the two overloads really have
// different result types and `expectSameOverload` really rejects a mismatch.
// Each marked line pairs a result of one overload with a result of the
// other. If one of them ever compiled, the positive fixture would no longer
// discriminate, and this lane would fail instead of passing silently.

import SwiftTUIViews

struct Custom: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View { content }
}

@MainActor func expectSameOverload<T>(_ lhs: T, _ rhs: T) {}

@MainActor
func overloadsAreDistinguishable() {
  let view = Text("x")
  let stored: AnyTransition = .opacity
  let viaAnyTransition = view.transition(stored)
  let viaOpacityType = view.transition(OpacityTransition())
  let viaScaleType = view.transition(ScaleTransition(0.5))
  let viaCustomType = view.transition(Custom())

  // The two overloads have different result types.
  expectSameOverload(viaAnyTransition, viaOpacityType)  // expect-error
  expectSameOverload(viaAnyTransition, viaCustomType)  // expect-error

  // `.transition(.opacity)` is the `AnyTransition` overload, not the generic
  // one with `OpacityTransition`.
  let implicitOpacity = view.transition(.opacity)
  expectSameOverload(implicitOpacity, viaOpacityType)  // expect-error

  // `.transition(.scale)` is the `AnyTransition` overload too.
  let implicitScale = view.transition(.scale)
  expectSameOverload(implicitScale, viaScaleType)  // expect-error

  // `.transition(.scale(0.5))` is the generic overload, not the
  // `AnyTransition` one.
  let unlabelledScale = view.transition(.scale(0.5))
  expectSameOverload(unlabelledScale, viaAnyTransition)  // expect-error

  // An erased custom transition and the same transition passed directly go
  // through different overloads.
  let erasedCustom = view.transition(AnyTransition(Custom()))
  expectSameOverload(erasedCustom, viaCustomType)  // expect-error
}
