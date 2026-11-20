import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph
@testable import SwiftTUIViews

/// The value half of the `Transition` surface (STUI-1543): phases, erasure
/// into `AnyTransition`, the animation override and `hasMotion`.
@MainActor
@Suite("Transition erasure")
struct TransitionErasureTests {
  @Test("TransitionPhase has SwiftUI's values")
  func phaseValues() {
    #expect(TransitionPhase.willAppear.value == -1)
    #expect(TransitionPhase.identity.value == 0)
    #expect(TransitionPhase.didDisappear.value == 1)
    #expect(TransitionPhase.identity.isIdentity)
    #expect(!TransitionPhase.willAppear.isIdentity)
    #expect(!TransitionPhase.didDisappear.isIdentity)
  }

  @Test("a built-in type erases to the effect values of its AnyTransition static")
  func builtInsEraseToTheirStatics() {
    Self.expectSameEffects(AnyTransition(OpacityTransition()), .opacity)
    Self.expectSameEffects(AnyTransition(IdentityTransition()), .identity)
    Self.expectSameEffects(AnyTransition(SlideTransition()), .slide)
    Self.expectSameEffects(AnyTransition(MoveTransition(edge: .top)), .move(edge: .top))
    Self.expectSameEffects(
      AnyTransition(OffsetTransition(CellSize(width: 3, height: -2))), .offset(x: 3, y: -2))
    Self.expectSameEffects(
      AnyTransition(PushTransition(edge: .trailing)), .push(from: .trailing))
    Self.expectSameEffects(
      AnyTransition(ScaleTransition(0.25, anchor: .bottomTrailing)),
      .scale(scale: 0.25, anchor: .bottomTrailing))
    Self.expectSameEffects(AnyTransition(ScaleTransition(0.5)), .scale(scale: 0.5))
  }

  @Test("the static members build the same values as the initializers")
  func staticMembersEraseToTheirStatics() {
    Self.expectSameEffects(Self.erase(.opacity), .opacity)
    Self.expectSameEffects(Self.erase(.identity), .identity)
    Self.expectSameEffects(Self.erase(.slide), .slide)
    Self.expectSameEffects(Self.erase(.scale), .scale)
    Self.expectSameEffects(
      Self.erase(.scale(0.25, anchor: .top)), .scale(scale: 0.25, anchor: .top))
    Self.expectSameEffects(Self.erase(.move(edge: .bottom)), .move(edge: .bottom))
    Self.expectSameEffects(
      Self.erase(.offset(CellSize(width: 4, height: 1))), .offset(x: 4, y: 1))
    Self.expectSameEffects(Self.erase(.offset(x: 4)), .offset(x: 4))
    Self.expectSameEffects(Self.erase(.offset(y: -3)), .offset(y: -3))
    Self.expectSameEffects(Self.erase(.push(from: .leading)), .push(from: .leading))
  }

  @Test("combinations, asymmetric pairs and animated wrappers erase part by part")
  func wrappersEraseRecursively() {
    Self.expectSameEffects(
      AnyTransition(OpacityTransition().combined(with: MoveTransition(edge: .top))),
      AnyTransition.opacity.combined(with: .move(edge: .top)))
    Self.expectSameEffects(
      AnyTransition(
        OpacityTransition().combined(with: ScaleTransition(0.5)).combined(with: .offset(x: 2))),
      AnyTransition.opacity.combined(with: .scale(scale: 0.5)).combined(with: .offset(x: 2)))
    Self.expectSameEffects(
      AnyTransition(
        AsymmetricTransition(
          insertion: MoveTransition(edge: .leading), removal: OpacityTransition())),
      .asymmetric(insertion: .move(edge: .leading), removal: .opacity))
    Self.expectSameEffects(
      AnyTransition(
        AsymmetricTransition(
          insertion: AsymmetricTransition(
            insertion: OpacityTransition(), removal: SlideTransition()),
          removal: PushTransition(edge: .top).combined(with: .scale))),
      .asymmetric(
        insertion: .asymmetric(insertion: .opacity, removal: .slide),
        removal: AnyTransition.push(from: .top).combined(with: .scale)))

    let animation = Animation.linear(duration: .milliseconds(400))
    let animated = AnyTransition(OpacityTransition().animation(animation))
    #expect(animated.insertionModifiers() == AnyTransition.opacity.insertionModifiers())
    #expect(animated.removalModifiers() == AnyTransition.opacity.removalModifiers())
    #expect(animated.bodyBox == nil)
    #expect(animated.insertionAnimation == .explicit(animation))
    #expect(animated.removalAnimation == .explicit(animation))

    let snapping = AnyTransition(MoveTransition(edge: .top).animation(nil))
    #expect(snapping.insertionAnimation == .explicit(nil))
    #expect(snapping.removalAnimation == .explicit(nil))
  }

  @Test("a custom transition becomes a body box and keeps the effects of its built-in parts")
  func customTransitionsBecomeBodyBoxes() {
    let custom = AnyTransition(Bracket())
    #expect(custom.bodyBox != nil)
    #expect(custom.insertionModifiers() == .identity)
    #expect(custom.removalModifiers() == .identity)
    #expect(custom.insertionAnimation == .inherit)
    #expect(custom.removalAnimation == .inherit)

    let mixed = AnyTransition(Bracket().combined(with: .opacity))
    #expect(mixed.bodyBox != nil)
    #expect(mixed.insertionModifiers() == AnyTransition.opacity.insertionModifiers())
    #expect(mixed.removalModifiers() == AnyTransition.opacity.removalModifiers())

    let asymmetric = AnyTransition(
      AsymmetricTransition(insertion: Bracket(), removal: OpacityTransition()))
    #expect(asymmetric.bodyBox != nil)
    #expect(asymmetric.insertionModifiers() == .identity)
    #expect(asymmetric.removalModifiers() == AnyTransition.opacity.removalModifiers())

    let modifier = AnyTransition.modifier(active: Indent(amount: 2), identity: Indent(amount: 0))
    #expect(modifier.bodyBox != nil)
    #expect(modifier.insertionModifiers() == .identity)
  }

  @Test("AnyTransition combinators carry body boxes and animations through")
  func combinatorsCarryTheNewFields() {
    let fast = Animation.linear(duration: .milliseconds(100))
    let slow = Animation.linear(duration: .milliseconds(900))

    let body = AnyTransition(Bracket())
    #expect(AnyTransition.opacity.combined(with: body).bodyBox != nil)
    #expect(body.combined(with: .opacity).bodyBox != nil)
    #expect(AnyTransition.asymmetric(insertion: body, removal: .opacity).bodyBox != nil)
    #expect(AnyTransition.asymmetric(insertion: .opacity, removal: body).bodyBox != nil)
    #expect(AnyTransition.asymmetric(insertion: .opacity, removal: .slide).bodyBox == nil)
    #expect(AnyTransition.opacity.combined(with: .slide).bodyBox == nil)

    // An asymmetric pair takes each direction's animation from its own side.
    let pair = AnyTransition.asymmetric(
      insertion: AnyTransition.opacity.animation(fast),
      removal: AnyTransition.opacity.animation(slow))
    #expect(pair.insertionAnimation == .explicit(fast))
    #expect(pair.removalAnimation == .explicit(slow))
    let half = AnyTransition.asymmetric(
      insertion: AnyTransition.opacity.animation(nil), removal: .opacity)
    #expect(half.insertionAnimation == .explicit(nil))
    #expect(half.removalAnimation == .inherit)

    // In a combination the first part that carries an animation decides.
    #expect(
      AnyTransition.opacity.animation(fast).combined(with: AnyTransition.slide.animation(slow))
        .insertionAnimation == .explicit(fast))
    #expect(
      AnyTransition.opacity.combined(with: AnyTransition.slide.animation(slow)).removalAnimation
        == .explicit(slow))
    #expect(AnyTransition.opacity.combined(with: .slide).insertionAnimation == .inherit)

    // The animation attached first stays in effect.
    #expect(
      AnyTransition.opacity.animation(fast).animation(slow).insertionAnimation
        == .explicit(fast))
    #expect(
      AnyTransition.opacity.animation(nil).animation(slow).removalAnimation == .explicit(nil))
  }

  @Test("hasMotion is false for opacity and identity and true for the other built-ins")
  func builtInMotion() {
    #expect(!OpacityTransition.properties.hasMotion)
    #expect(!IdentityTransition.properties.hasMotion)
    #expect(MoveTransition.properties.hasMotion)
    #expect(OffsetTransition.properties.hasMotion)
    #expect(PushTransition.properties.hasMotion)
    #expect(ScaleTransition.properties.hasMotion)
    #expect(SlideTransition.properties.hasMotion)
    #expect(Bracket.properties.hasMotion)
    #expect(!Still.properties.hasMotion)
    #expect(TransitionProperties().hasMotion)
    #expect(!TransitionProperties(hasMotion: false).hasMotion)

    #expect(!AnyTransition.opacity.hasMotion)
    #expect(!AnyTransition.identity.hasMotion)
    #expect(AnyTransition.slide.hasMotion)
    #expect(AnyTransition.scale.hasMotion)
    #expect(AnyTransition.scale(scale: 0.5).hasMotion)
    #expect(AnyTransition.move(edge: .top).hasMotion)
    #expect(AnyTransition.offset(x: 1).hasMotion)
    #expect(AnyTransition.offset().hasMotion)
    #expect(AnyTransition.push(from: .top).hasMotion)

    #expect(!AnyTransition(OpacityTransition()).hasMotion)
    #expect(!AnyTransition(IdentityTransition()).hasMotion)
    #expect(AnyTransition(MoveTransition(edge: .top)).hasMotion)
    #expect(AnyTransition(OffsetTransition(.zero)).hasMotion)
    #expect(AnyTransition(PushTransition(edge: .top)).hasMotion)
    #expect(AnyTransition(ScaleTransition(1)).hasMotion)
    #expect(AnyTransition(SlideTransition()).hasMotion)
    #expect(AnyTransition(Bracket()).hasMotion)
    #expect(!AnyTransition(Still()).hasMotion)
    #expect(
      AnyTransition.modifier(active: Indent(amount: 2), identity: Indent(amount: 0)).hasMotion)
  }

  @Test("hasMotion is the OR of the parts of a combination or an asymmetric pair")
  func motionCombines() {
    #expect(!Self.motion(of: OpacityTransition().combined(with: .opacity)))
    #expect(Self.motion(of: OpacityTransition().combined(with: .move(edge: .top))))
    #expect(Self.motion(of: MoveTransition(edge: .top).combined(with: .opacity)))
    #expect(!Self.motion(of: Still().combined(with: .opacity)))
    #expect(Self.motion(of: Still().combined(with: Bracket())))
    #expect(
      !Self.motion(
        of: AsymmetricTransition(insertion: OpacityTransition(), removal: OpacityTransition())))
    #expect(
      Self.motion(
        of: AsymmetricTransition(
          insertion: OpacityTransition(), removal: MoveTransition(edge: .top))))
    #expect(
      Self.motion(
        of: AsymmetricTransition(
          insertion: MoveTransition(edge: .top), removal: OpacityTransition())))
    #expect(!Self.motion(of: OpacityTransition().animation(.default)))
    #expect(Self.motion(of: MoveTransition(edge: .top).animation(.default)))
    #expect(!Self.motion(of: Still().animation(nil)))

    #expect(!AnyTransition.opacity.combined(with: .opacity).hasMotion)
    #expect(AnyTransition.opacity.combined(with: .scale).hasMotion)
    #expect(AnyTransition.opacity.combined(with: AnyTransition(Bracket())).hasMotion)
    #expect(!AnyTransition.opacity.combined(with: AnyTransition(Still())).hasMotion)
    #expect(!AnyTransition.asymmetric(insertion: .opacity, removal: .identity).hasMotion)
    #expect(AnyTransition.asymmetric(insertion: .opacity, removal: .slide).hasMotion)
    #expect(
      AnyTransition.asymmetric(insertion: AnyTransition(Bracket()), removal: .opacity).hasMotion)
    #expect(!AnyTransition.opacity.animation(.default).hasMotion)
    #expect(AnyTransition.slide.animation(nil).hasMotion)
  }

  @Test("the effect channel's identity phase holds the identity value of each channel in use")
  func identityPhaseEffects() {
    #expect(AnyTransition.opacity.effectModifiers(for: .willAppear).opacity == 0)
    #expect(AnyTransition.opacity.effectModifiers(for: .didDisappear).opacity == 0)
    #expect(
      AnyTransition.opacity.effectModifiers(for: .identity) == TransitionModifiers(opacity: 1))
    #expect(AnyTransition.identity.effectModifiers(for: .identity) == .identity)
    #expect(AnyTransition.slide.effectModifiers(for: .identity) == .identity)
    #expect(AnyTransition.slide.effectModifiers(for: .willAppear).moveEdge == .leading)
    #expect(AnyTransition.slide.effectModifiers(for: .didDisappear).moveEdge == .trailing)
    #expect(
      AnyTransition.push(from: .top).effectModifiers(for: .identity)
        == TransitionModifiers(opacity: 1))
    #expect(
      AnyTransition.offset(x: 3).effectModifiers(for: .identity)
        == TransitionModifiers(offsetX: 0, offsetY: 0))
    #expect(
      AnyTransition.scale(scale: 0.5, anchor: .top).effectModifiers(for: .identity)
        == TransitionModifiers(scale: TransitionScaleEffect(scale: 1, anchor: .top)))
  }

  @Test("a body box resolves any phase, in any context, around a stand-in for the content")
  func bodyBoxResolvesAPhaseAroundAStandIn() throws {
    let box = try #require(AnyTransition(Still()).bodyBox)
    // No view graph: nothing here has state storage, lifecycle or handlers.
    let context = ResolveContext(identity: testIdentity("TransitionScratch"))
    #expect(context.viewGraph == nil)
    let standIn = TransitionContentSource { contentContext in
      .value(
        ResolvedNode(
          identity: contentContext.identity,
          kind: .view(.spacer),
          intrinsicSize: CellSize(width: 4, height: 1)
        )
      )
    }
    for (phase, opacity) in [
      (TransitionPhase.willAppear, 0.5), (.identity, 1.0), (.didDisappear, 0.5),
    ] {
      let nodes = box.resolveElementsWork(content: standIn, phase: phase, in: context).run()
      #expect(nodes.count == 1)
      let boundary = try #require(nodes.first)
      // The phase's modifier lands on the boundary, at the context's own
      // identity, and the stand-in is its single child.
      #expect(boundary.kind == .view(.transitionContent))
      #expect(boundary.identity == context.identity)
      #expect(boundary.drawMetadata.baseStyle.explicitOpacity == opacity)
      #expect(boundary.children.count == 1)
      #expect(boundary.children.first?.kind == .view(.spacer))
      #expect(boundary.children.first?.identity == context.identity.child(.named("content")))
      #expect(boundary.children.first?.intrinsicSize == CellSize(width: 4, height: 1))
    }
  }

  @Test("nested body boxes put the stand-in behind the innermost boundary")
  func nestedBodyBoxesKeepTheStandInInnermost() throws {
    let box = try #require(AnyTransition(Still().combined(with: Still())).bodyBox)
    let context = ResolveContext(identity: testIdentity("TransitionScratchNested"))
    let standIn = TransitionContentSource { contentContext in
      .value(ResolvedNode(identity: contentContext.identity, kind: .view(.spacer)))
    }
    let nodes = box.resolveElementsWork(content: standIn, phase: .didDisappear, in: context).run()
    let outer = try #require(nodes.first)
    #expect(nodes.count == 1)
    #expect(outer.kind == .view(.transitionContent))
    #expect(outer.identity == context.identity)
    #expect(outer.drawMetadata.baseStyle.explicitOpacity == 0.5)
    // The outer body's content is the inner body, whose content is the
    // stand-in. Both bodies saw the same phase.
    let inner = try #require(outer.children.first)
    #expect(outer.children.count == 1)
    #expect(inner.kind == .view(.transitionContent))
    #expect(inner.identity == context.identity.child(.named("content")))
    #expect(inner.drawMetadata.baseStyle.explicitOpacity == 0.5)
    #expect(inner.children.count == 1)
    #expect(inner.children.first?.kind == .view(.spacer))
    #expect(
      inner.children.first?.identity
        == context.identity.child(.named("content")).child(.named("content")))
  }

  @Test("an inheriting AnyTransition stays small")
  func anyTransitionStaysSmall() {
    // Two effect closures, the motion closure, the optional body box and two
    // one-word animation overrides.
    #expect(MemoryLayout<TransitionAnimationOverride>.size <= MemoryLayout<Int>.size)
    #expect(MemoryLayout<AnyTransition>.size <= 112)
  }

  private static func expectSameEffects(
    _ erased: AnyTransition,
    _ expected: AnyTransition,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(
      erased.insertionModifiers() == expected.insertionModifiers(),
      sourceLocation: sourceLocation)
    #expect(
      erased.removalModifiers() == expected.removalModifiers(), sourceLocation: sourceLocation)
    #expect(erased.bodyBox == nil, sourceLocation: sourceLocation)
    #expect(erased.insertionAnimation == .inherit, sourceLocation: sourceLocation)
    #expect(erased.removalAnimation == .inherit, sourceLocation: sourceLocation)
    #expect(erased.hasMotion == expected.hasMotion, sourceLocation: sourceLocation)
  }

  private static func erase<T: Transition>(_ transition: T) -> AnyTransition {
    AnyTransition(transition)
  }

  /// Checks the type's own `properties` and its erased form together.
  private static func motion<T: Transition>(of transition: T) -> Bool {
    let erased = AnyTransition(transition).hasMotion
    #expect(erased == T.properties.hasMotion)
    return erased
  }
}

private struct Bracket: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    HStack(spacing: 0) {
      Text(phase.isIdentity ? "[" : "<")
      content
      Text(phase.isIdentity ? "]" : ">")
    }
  }
}

private struct Still: Transition {
  static let properties = TransitionProperties(hasMotion: false)

  func body(content: Content, phase: TransitionPhase) -> some View {
    content.opacity(phase.isIdentity ? 1 : 0.5)
  }
}

private struct Indent: ViewModifier {
  var amount: Int

  func body(content: Content) -> some View {
    content.padding(.leading, amount)
  }
}
