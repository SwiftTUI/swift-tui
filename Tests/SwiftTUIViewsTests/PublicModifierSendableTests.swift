import Testing

@testable import SwiftTUIViews

// Compile-time guard for supplemental item #22: the value-type
// `PrimitiveViewModifier`s in the layout and metadata groups must remain
// `Sendable` so callers can compose modifiers across task/actor boundaries.
// `requireSendable` takes only the metatype, so dropping the conformance from
// any listed modifier fails this file's *compilation* — no instance needed.
//
// Modifier groups deliberately excluded (and why they are not yet here): the
// generic-over-`View`-content modifiers (overlay/background/presentation/sheet,
// etc.) would need a conditional `where Content: Sendable` the host `View`s do
// not satisfy; the lifecycle/preference modifiers store non-`@Sendable`
// closures. Those are the "reference escape" cases #22 sets aside.
private func requireSendable<T: Sendable>(_: T.Type) {}

@Suite("Public modifier Sendable baseline")
struct PublicModifierSendableTests {
  @Test("layout value modifiers are Sendable")
  func layoutModifiersAreSendable() {
    requireSendable(PaddingModifier.self)
    requireSendable(SafeAreaPaddingModifier.self)
    requireSendable(IgnoreSafeAreaModifier.self)
    requireSendable(BorderModifier.self)
    requireSendable(FrameModifier.self)
    requireSendable(OffsetModifier.self)
    requireSendable(PositionModifier.self)
    requireSendable(MatchedGeometryModifier.self)
    requireSendable(FlexibleFrameModifier.self)
  }

  @Test("metadata value modifiers are Sendable")
  func metadataModifiersAreSendable() {
    requireSendable(ExactIdentityModifier.self)
    requireSendable(LayoutMetadataModifier.self)
    requireSendable(HorizontalAlignmentGuideModifier.self)
    requireSendable(VerticalAlignmentGuideModifier.self)
    requireSendable(DrawMetadataModifier.self)
    requireSendable(DrawEffectModifier.self)
    requireSendable(SemanticMetadataModifier.self)
  }
}
