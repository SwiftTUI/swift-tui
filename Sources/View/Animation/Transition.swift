import Core

/// The phase a transition is in.
///
/// Matches SwiftUI iOS 17+ `TransitionPhase`.
public enum TransitionPhase: Hashable, Sendable {
  /// The view is being inserted — transition is about to play forward.
  case willAppear
  /// The view is fully present — no visual modifiers applied.
  case identity
  /// The view has been removed — transition is playing its exit phase.
  case didDisappear

  public var isIdentity: Bool { self == .identity }
}

/// Compile-time hints the runtime can use to decide whether a transition
/// needs special handling (e.g. non-semantic overlays).
public struct TransitionProperties: Sendable {
  public var hasMotion: Bool

  public init(hasMotion: Bool = true) {
    self.hasMotion = hasMotion
  }
}

/// A placeholder used by transition bodies to reference the content
/// being transitioned.
///
/// In SwiftUI this is a fully-capable View; here it is a shim that lets
/// authored transitions describe their effects in terms of a neutral
/// placeholder.  The runtime resolves the authored effects by probing
/// the body with each phase in turn and flattening the output.
public struct TransitionContent<T: Transition>: Sendable {
  public init() {}
}

/// Modern SwiftUI-style transition protocol.
///
/// Adopt this protocol to author custom transitions.  The `body`
/// method receives a phase-aware content placeholder and returns a view
/// whose effects will be applied to the real content for the duration
/// of the transition.
///
/// - Note: The current runtime palette is limited to opacity and offset
///   effects (see ``TransitionModifiers``).  Other modifiers applied
///   inside `body` are silently ignored until the palette is expanded.
///
/// Marked `@MainActor` for parity with `View` — user-authored
/// transitions almost always compose main-actor-isolated view types
/// like `.opacity(_:)` and `.offset(x:y:)`, so a nonisolated protocol
/// would force every conformance to split across isolation boundaries.
@MainActor
public protocol Transition: Sendable {
  associatedtype Body: View

  @ViewBuilder @MainActor
  func body(
    content: TransitionContent<Self>,
    phase: TransitionPhase
  ) -> Body

  static var properties: TransitionProperties { get }
}

extension Transition {
  public static var properties: TransitionProperties {
    TransitionProperties(hasMotion: true)
  }
}
