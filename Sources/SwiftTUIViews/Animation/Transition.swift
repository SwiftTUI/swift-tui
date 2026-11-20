public import SwiftTUICore

/// A description of how a view changes while it appears and disappears.
///
/// A transition is a function from a phase to a view. Implement
/// ``body(content:phase:)`` to return `content` with the modifiers that the
/// phase calls for, and attach the transition with ``View/transition(_:)-(T)``:
///
/// ```swift
/// struct Dim: Transition {
///   func body(content: Content, phase: TransitionPhase) -> some View {
///     content.opacity(phase.isIdentity ? 1 : 0.3)
///   }
/// }
///
/// Text("Saved").transition(Dim())
/// ```
///
/// A transition is a value type: a struct or an enum. A conforming type is
/// `Sendable`, which a type that declares the conformance in its primary
/// declaration already is, because the protocol is isolated to the main
/// actor.
///
/// While the view is present it shows the body of the
/// ``TransitionPhase/identity`` phase. When the view is inserted inside an
/// animation it appears through the body of ``TransitionPhase/willAppear``
/// and moves to the identity body: the views on screen are those of the
/// identity body from the first frame, and every modifier value SwiftTUI can
/// interpolate (opacity, styles, padding, offset, position, frame, shape and
/// clip paths, stroke dash phase and trim) animates from the value the
/// `willAppear` body gives the same view. A value that cannot interpolate
/// shows its identity value at once. Keep the same views in every phase and
/// change their modifiers: a view that only the `willAppear` body has is
/// never shown, and SwiftTUI reports a runtime issue for it.
///
/// When the view is removed inside an animation it leaves through the body
/// of ``TransitionPhase/didDisappear``: the views drawn are those of that
/// body from the first frame of the removal, and every modifier value that
/// interpolates animates from the value on screen. A value that cannot
/// interpolate shows its `didDisappear` value at once.
///
/// A view or a view modifier in the body that conforms to `Animatable`
/// animates its `animatableData` in the same way: from the data the
/// `willAppear` body gives it on insertion, and to the data the
/// `didDisappear` body gives it on removal. Its body runs on every frame of
/// the transition with the interpolated data, so it can draw what no
/// modifier value interpolates to. ``AnyTransition/modifier(active:identity:)``
/// is the short form for one such modifier.
///
/// SwiftTUI ends the life of the view when its removal starts: that frame
/// cancels its tasks, runs `onDisappear` and drops its state, where SwiftUI
/// waits for the removal to end. The removal then draws the view as it was
/// last drawn, inside the `didDisappear` body. That body is drawn and not
/// mounted, so a view it adds shows its initial state and runs nothing. See
/// <doc:Divergences-And-Gaps> for the rules and the limits.
@MainActor
public protocol Transition: Sendable {
  /// The type of view that ``body(content:phase:)`` returns.
  associatedtype Body: View

  /// The stand-in for the view that the transition is applied to.
  typealias Content = TransitionContent<Self>

  /// Returns the view to show for `content` in `phase`.
  ///
  /// SwiftTUI calls this method with ``TransitionPhase/identity`` to build
  /// the views on screen. It calls it with ``TransitionPhase/willAppear``
  /// when an insertion starts, to read the modifier values of that phase, and
  /// with ``TransitionPhase/didDisappear`` when a removal starts, to build
  /// the views the removal draws. When the result holds a view or a modifier
  /// that conforms to `Animatable`, a removal calls it with `didDisappear`
  /// again on each frame it draws, to evaluate that view or modifier with
  /// the frame's data. The calls for `willAppear` and `didDisappear` have no
  /// view state: a `@State` property in a view the body adds reads its
  /// initial value there, and no lifecycle handler, task or action of the
  /// result ever runs.
  ///
  /// - Parameters:
  ///   - content: A stand-in for the view the transition is applied to. Place
  ///     it in the result as you would place any view.
  ///   - phase: The phase to describe.
  @ViewBuilder @MainActor
  func body(content: Content, phase: TransitionPhase) -> Body

  /// The properties of this transition type. The default has
  /// ``TransitionProperties/hasMotion`` set to `true`.
  @MainActor
  static var properties: TransitionProperties { get }

  /// Value-type conformance guard; never implement it. The unconstrained
  /// extension below witnesses it for every struct and enum, and the
  /// `Self: AnyObject` overload is unavailable, so a class conformance fails
  /// to compile (plan 2026-08-29-001).
  @_documentation(visibility: internal)
  static var _transitionValueTypeWitness: Void { get }
}

extension Transition {
  @_documentation(visibility: internal)
  public static var _transitionValueTypeWitness: Void { () }
}

extension Transition where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message:
      "SwiftTUI transitions must be value types (a struct or an enum); a class cannot conform to Transition"
  )
  public static var _transitionValueTypeWitness: Void { () }
}

extension Transition {
  /// The default properties: the transition has motion.
  public static var properties: TransitionProperties {
    TransitionProperties()
  }

  /// Returns the body of this transition for `content` in `phase`.
  ///
  /// Use this method inside the body of another transition to build on an
  /// existing one:
  ///
  /// ```swift
  /// func body(content: Content, phase: TransitionPhase) -> some View {
  ///   OpacityTransition().apply(content: content.padding(1), phase: phase)
  /// }
  /// ```
  ///
  /// A body can render the opacity of a built-in transition and its fixed
  /// offset. It cannot render a move relative to an edge or a scale, which
  /// act on the placed frame of the view: ``MoveTransition``,
  /// ``PushTransition``, ``SlideTransition`` and ``ScaleTransition`` report
  /// a runtime issue when they are applied this way outside the identity
  /// phase, and show the content without that effect. Use
  /// ``combined(with:)`` for those.
  public func apply<V: View>(content: V, phase: TransitionPhase) -> some View {
    TransitionBodyHost(
      transition: self,
      content: TransitionContentSource(
        ModifierContentInputs(base: content, authoringScope: makeCapturedSubviewScope())
      ),
      phase: phase
    )
  }

  /// Attaches an animation to this transition.
  ///
  /// The animation replaces the animation of the transaction for this
  /// transition, on insertion and on removal. It also plays when the state
  /// change has no animation. Pass `nil` to make the transition snap.
  /// `withAnimation(nil)` and reduced motion still disable the transition.
  ///
  /// If the transition already carries its own animation, that animation
  /// stays in effect.
  public func animation(_ animation: Animation?) -> some Transition {
    AnimatedTransition(base: self, animation: animation)
  }

  /// Combines this transition with another.
  ///
  /// The body of `other` wraps the body of this transition. The result has
  /// motion when either part has motion.
  public func combined<T: Transition>(with other: T) -> some Transition {
    CombinedTransition(first: self, second: other)
  }
}

/// The phase a transition body describes.
public enum TransitionPhase: Hashable, Sendable {
  /// The view is about to appear. An insertion animates from the modifier
  /// values of this phase to those of ``identity``.
  case willAppear
  /// The view is present.
  case identity
  /// The view has disappeared. A removal animates from the state on screen
  /// to this phase.
  case didDisappear

  /// Whether this phase is ``identity``.
  public var isIdentity: Bool {
    self == .identity
  }

  /// A number for the phase: `-1` for ``willAppear``, `0` for ``identity``
  /// and `1` for ``didDisappear``.
  public var value: Double {
    switch self {
    case .willAppear: -1
    case .identity: 0
    case .didDisappear: 1
    }
  }
}

/// The properties a ``Transition`` type declares about itself.
public struct TransitionProperties: Sendable {
  /// Whether the transition moves or resizes the view.
  ///
  /// It is `false` for ``OpacityTransition`` and ``IdentityTransition`` and
  /// `true` for the other built-in transitions. A combination has motion when
  /// any part has motion.
  ///
  /// SwiftTUI carries this value and does not act on it. Under
  /// `accessibilityReduceMotion` no transition plays, whatever the value is:
  /// the view appears and disappears at once.
  public var hasMotion: Bool

  /// Creates the properties of a transition.
  public init(hasMotion: Bool = true) {
    self.hasMotion = hasMotion
  }
}

extension View {
  /// Associates a transition with this view for insertion and removal.
  ///
  /// This overload accepts any ``Transition``, including the result of
  /// ``Transition/combined(with:)`` and ``Transition/animation(_:)``. It
  /// erases the value with ``AnyTransition/init(_:)``, so a built-in
  /// transition type behaves exactly as the matching ``AnyTransition`` value.
  public func transition<T: Transition>(_ transition: T) -> some View {
    self.transition(AnyTransition(transition))
  }
}

// MARK: - Built-in transitions as static members

extension Transition where Self == OpacityTransition {
  /// A transition that fades the view in and out.
  public static var opacity: OpacityTransition { Self() }
}

extension Transition where Self == IdentityTransition {
  /// A transition that changes nothing: the view appears and disappears at
  /// once.
  nonisolated public static var identity: IdentityTransition { Self() }
}

extension Transition where Self == SlideTransition {
  /// A transition that moves the view in from its leading edge and out
  /// toward its trailing edge.
  public static var slide: SlideTransition { Self() }
}

extension Transition where Self == ScaleTransition {
  /// A transition that scales the view from and to a nearly collapsed size
  /// around its center.
  public static var scale: ScaleTransition { Self(1e-5) }

  /// A transition that scales the view from and to `scale` around `anchor`.
  public static func scale(_ scale: Double, anchor: UnitPoint = .center) -> Self {
    Self(scale, anchor: anchor)
  }
}

extension Transition where Self == MoveTransition {
  /// A transition that moves the view in from `edge` and back out to it.
  public static func move(edge: Edge) -> Self {
    Self(edge: edge)
  }
}

extension Transition where Self == OffsetTransition {
  /// A transition that shifts the view by `offset` cells.
  public static func offset(_ offset: CellSize) -> Self {
    Self(offset)
  }

  /// A transition that shifts the view by `x` columns and `y` rows.
  public static func offset(x: Int = 0, y: Int = 0) -> Self {
    offset(CellSize(width: x, height: y))
  }
}

extension Transition where Self == PushTransition {
  /// A transition that fades and moves the view in from `edge`, and fades
  /// and moves it out toward the opposite edge.
  public static func push(from edge: Edge) -> Self {
    Self(edge: edge)
  }
}
