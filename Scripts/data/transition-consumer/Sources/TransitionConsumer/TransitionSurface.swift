public import SwiftTUIViews

// Every public symbol of the `Transition` surface, used from outside the
// framework with the `SwiftTUIViews` product alone (STUI-1543).

// MARK: - Declaring transitions

/// A transition a library exports: its own stored configuration, its own
/// body, and the default properties.
public struct Veil: Transition {
  public var strength: Double

  public init(strength: Double = 0.4) {
    self.strength = strength
  }

  public func body(content: Content, phase: TransitionPhase) -> some View {
    content.opacity(phase.isIdentity ? 1 : strength)
  }
}

/// The example in the "Write Your Own Transition" section of the
/// `Animating-Views` article, compiled here so the article stays true.
struct Spotlight: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .padding(.horizontal, 1)
      .background(phase.isIdentity ? Color.blue : Color.gray)
      .opacity(phase.isIdentity ? 1 : 0)
  }
}

/// A transition that declares it has no motion and reads every phase value.
struct Marker: Transition {
  static let properties = TransitionProperties(hasMotion: false)

  func body(content: Content, phase: TransitionPhase) -> some View {
    HStack(spacing: 0) {
      content
      switch phase {
      case .willAppear: Text("+")
      case .identity: Text(" ")
      case .didDisappear: Text("-")
      }
    }
  }
}

/// A transition that builds on built-in transitions with `apply`.
struct Framed: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    OpacityTransition().apply(
      content: MoveTransition(edge: .leading).apply(content: content.padding(1), phase: phase),
      phase: phase
    )
  }
}

/// A generic transition: the carrier type is spelled through `Content`.
struct Wrapping<Inner: Transition>: Transition {
  var inner: Inner

  func body(content: Content, phase: TransitionPhase) -> some View {
    inner.apply(content: content, phase: phase)
  }
}

/// An enum transition.
enum Fixed: Transition {
  case dim

  func body(content: Content, phase: TransitionPhase) -> TransitionContent<Fixed> {
    content
  }
}

/// A modifier for `AnyTransition.modifier(active:identity:)`.
struct Inset: ViewModifier {
  var amount: Int

  func body(content: Content) -> some View {
    content.padding(.leading, amount)
  }
}

// MARK: - Using every new symbol

@MainActor
func phases() -> [Double] {
  let all: [TransitionPhase] = [.willAppear, .identity, .didDisappear]
  let identityCount = all.filter(\.isIdentity).count
  let distinct = Set(all).count
  return all.map(\.value) + [Double(identityCount), Double(distinct)]
}

@MainActor
func properties() -> [Bool] {
  var custom = TransitionProperties()
  custom.hasMotion = false
  return [
    custom.hasMotion,
    TransitionProperties(hasMotion: true).hasMotion,
    Veil.properties.hasMotion,
    Marker.properties.hasMotion,
    OpacityTransition.properties.hasMotion,
    IdentityTransition.properties.hasMotion,
    MoveTransition.properties.hasMotion,
    OffsetTransition.properties.hasMotion,
    PushTransition.properties.hasMotion,
    ScaleTransition.properties.hasMotion,
    SlideTransition.properties.hasMotion,
    AsymmetricTransition<OpacityTransition, MoveTransition>.properties.hasMotion,
  ]
}

/// The concrete types, their initializers and their stored properties.
@MainActor
func concreteTypes() {
  _ = OpacityTransition()
  _ = IdentityTransition()
  _ = SlideTransition()

  var move = MoveTransition(edge: .top)
  move.edge = .bottom

  var offset = OffsetTransition(CellSize(width: 2, height: 1))
  offset.offset = CellSize(width: 0, height: 3)

  var push = PushTransition(edge: .leading)
  push.edge = .trailing

  var scale = ScaleTransition(0.5)
  scale.scale = 0.25
  scale.anchor = .bottomTrailing
  _ = ScaleTransition(0.5, anchor: .top)

  var pair = AsymmetricTransition(insertion: move, removal: OpacityTransition())
  pair.insertion = MoveTransition(edge: .leading)
  pair.removal = OpacityTransition()
  _ = (move, offset, push, scale, pair)
}

/// The static members, through a generic parameter as a call site sees them.
@MainActor
func staticMembers() -> [AnyTransition] {
  func erase<T: Transition>(_ transition: T) -> AnyTransition { AnyTransition(transition) }
  return [
    erase(.opacity),
    erase(.identity),
    erase(.slide),
    erase(.scale),
    erase(.scale(0.5)),
    erase(.scale(0.5, anchor: .topLeading)),
    erase(.move(edge: .trailing)),
    erase(.offset(CellSize(width: 4, height: 0))),
    erase(.offset(x: 4)),
    erase(.offset(x: 1, y: -1)),
    erase(.push(from: .bottom)),
  ]
}

/// Combination, attached animation, erasure and the `AnyTransition` additions.
@MainActor
func combinators() -> [AnyTransition] {
  let combined = Veil().combined(with: .opacity).combined(with: Marker())
  let animated = Veil(strength: 0.2).animation(.linear(duration: .milliseconds(400)))
  let snapping = Framed().animation(nil)
  let modifier = AnyTransition.modifier(active: Inset(amount: 2), identity: Inset(amount: 0))
  return [
    AnyTransition(combined),
    AnyTransition(animated),
    AnyTransition(snapping),
    AnyTransition(Wrapping(inner: Fixed.dim)),
    AnyTransition(AsymmetricTransition(insertion: Veil(), removal: SlideTransition())),
    modifier,
    modifier.animation(.default),
    AnyTransition.opacity.animation(nil),
    AnyTransition.asymmetric(insertion: AnyTransition(Veil()), removal: .opacity),
    AnyTransition(Veil()).combined(with: .move(edge: .top)),
  ]
}

/// Both `View.transition` overloads, in a view a library would ship.
public struct TransitionShowcase: View {
  public var isShown: Bool

  public init(isShown: Bool) {
    self.isShown = isShown
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if isShown {
        Text("custom").transition(Veil())
        Text("Saved!").transition(Spotlight())
        Text("Saved!").transition(.opacity.animation(.linear(duration: .milliseconds(400))))
        Text("combined").transition(Veil().combined(with: .move(edge: .leading)))
        Text("animated").transition(Marker().animation(.default))
        Text("built-in type").transition(OpacityTransition())
        Text("scale").transition(.scale(0.5, anchor: .center))
        Text("asymmetric").transition(
          AsymmetricTransition(insertion: Framed(), removal: PushTransition(edge: .top)))
        Text("erased").transition(AnyTransition(Fixed.dim))
        Text("modifier").transition(
          .modifier(active: Inset(amount: 2), identity: Inset(amount: 0)))
        Text("existing").transition(.opacity)
        Text("existing combined").transition(.opacity.combined(with: .slide))
      }
    }
  }
}

/// `apply` with content that is not a transition's own content.
@MainActor
func applied() -> some View {
  Veil().apply(content: Text("applied"), phase: .willAppear)
}

/// A transition value is `Sendable`, so it can cross isolation.
func send<T: Transition>(_ transition: T) -> any Sendable {
  transition
}
