import SwiftTUICore

extension View {
  /// Drives modifiers applied to this view with a value interpolated along
  /// keyframes, once per `trigger` change.
  ///
  /// The modifier form of ``KeyframeAnimator``: `content` receives a
  /// ``PlaceholderContentView`` standing in for this view plus the current
  /// keyframe value.
  ///
  /// ```swift
  /// Text("★")
  ///   .keyframeAnimator(initialValue: 0.0, trigger: taps) { star, y in
  ///     star.offset(x: 0, y: Int(y.rounded()))
  ///   } keyframes: { _ in
  ///     CubicKeyframe(-3, duration: .milliseconds(400))
  ///     SpringKeyframe(0, spring: .bouncy)
  ///   }
  /// ```
  public func keyframeAnimator<Value: Sendable, KeyframePath: Keyframes, Content: View>(
    initialValue: Value,
    trigger: some Equatable,
    @ViewBuilder content: @escaping @MainActor (PlaceholderContentView<Self>, Value) -> Content,
    @KeyframesBuilder<Value> keyframes: @escaping @MainActor (Value) -> KeyframePath
  ) -> some View where KeyframePath.Value == Value {
    KeyframeAnimator(
      initialValue: initialValue,
      trigger: trigger,
      content: { value in content(PlaceholderContentView(self), value) },
      keyframes: keyframes
    )
  }

  /// Drives modifiers applied to this view with a value interpolated along
  /// keyframes, starting on appearance and looping when `repeating`.
  ///
  /// The modifier form of ``KeyframeAnimator``'s repeating mode.
  public func keyframeAnimator<Value: Sendable, KeyframePath: Keyframes, Content: View>(
    initialValue: Value,
    repeating: Bool = true,
    @ViewBuilder content: @escaping @MainActor (PlaceholderContentView<Self>, Value) -> Content,
    @KeyframesBuilder<Value> keyframes: @escaping @MainActor (Value) -> KeyframePath
  ) -> some View where KeyframePath.Value == Value {
    KeyframeAnimator(
      initialValue: initialValue,
      repeating: repeating,
      content: { value in content(PlaceholderContentView(self), value) },
      keyframes: keyframes
    )
  }

  /// Cycles modifiers applied to this view through `phases` once per
  /// `trigger` change; the modifier form of ``PhaseAnimator``'s trigger mode.
  public func phaseAnimator<Phase: Equatable & Sendable, Content: View>(
    _ phases: [Phase],
    trigger: some Hashable & Sendable,
    @ViewBuilder content: @escaping @MainActor (PlaceholderContentView<Self>, Phase) -> Content,
    animation: @escaping @Sendable (Phase) -> Animation? = { _ in .default }
  ) -> some View {
    PhaseAnimator(
      phases,
      trigger: trigger,
      content: { phase in content(PlaceholderContentView(self), phase) },
      animation: animation
    )
  }

  /// Cycles modifiers applied to this view through `phases` continuously;
  /// the modifier form of ``PhaseAnimator``'s loop mode.
  public func phaseAnimator<Phase: Equatable & Sendable, Content: View>(
    _ phases: [Phase],
    @ViewBuilder content: @escaping @MainActor (PlaceholderContentView<Self>, Phase) -> Content,
    animation: @escaping @Sendable (Phase) -> Animation? = { _ in .default }
  ) -> some View {
    PhaseAnimator(
      phases,
      content: { phase in content(PlaceholderContentView(self), phase) },
      animation: animation
    )
  }
}
