import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
struct PortalStyleReuseTests {
  @Test func promptEquality() {
    #expect(AnyPromptStyle.automatic.isEqualForReuse(to: AnyPromptStyle.automatic))
    #expect(
      AnyPromptStyle(ConsumerPromptStyle(inset: 1)).isEqualForReuse(
        to: AnyPromptStyle(ConsumerPromptStyle(inset: 1))))
    #expect(
      !AnyPromptStyle(ConsumerPromptStyle(inset: 1)).isEqualForReuse(
        to: AnyPromptStyle(ConsumerPromptStyle(inset: 2))))
    #expect(
      !AnyPromptStyle.automatic.isEqualForReuse(
        to: AnyPromptStyle(ConsumerPromptStyle(inset: 1))))
    #expect(
      !AnyPromptStyle(OpaquePortalStyle()).isEqualForReuse(
        to: AnyPromptStyle(OpaquePortalStyle())))
  }

  @Test func fullScreenCoverEquality() {
    #expect(
      AnyFullScreenCoverStyle.automatic.isEqualForReuse(to: AnyFullScreenCoverStyle.automatic))
    #expect(
      AnyFullScreenCoverStyle(ConsumerFullScreenCoverStyle(inset: 1)).isEqualForReuse(
        to: AnyFullScreenCoverStyle(ConsumerFullScreenCoverStyle(inset: 1))))
    #expect(
      !AnyFullScreenCoverStyle(ConsumerFullScreenCoverStyle(inset: 1)).isEqualForReuse(
        to: AnyFullScreenCoverStyle(ConsumerFullScreenCoverStyle(inset: 2))))
    #expect(
      !AnyFullScreenCoverStyle.automatic.isEqualForReuse(
        to: AnyFullScreenCoverStyle(ConsumerFullScreenCoverStyle(inset: 1))))
    #expect(
      !AnyFullScreenCoverStyle(OpaquePortalStyle()).isEqualForReuse(
        to: AnyFullScreenCoverStyle(OpaquePortalStyle())))
  }

  @Test func popoverEquality() {
    #expect(AnyPopoverStyle.automatic.isEqualForReuse(to: AnyPopoverStyle.automatic))
    #expect(
      AnyPopoverStyle(ConsumerPopoverStyle(inset: 1)).isEqualForReuse(
        to: AnyPopoverStyle(ConsumerPopoverStyle(inset: 1))))
    #expect(
      !AnyPopoverStyle(ConsumerPopoverStyle(inset: 1)).isEqualForReuse(
        to: AnyPopoverStyle(ConsumerPopoverStyle(inset: 2))))
    #expect(
      !AnyPopoverStyle.automatic.isEqualForReuse(
        to: AnyPopoverStyle(ConsumerPopoverStyle(inset: 1))))
    #expect(
      !AnyPopoverStyle(OpaquePortalStyle()).isEqualForReuse(
        to: AnyPopoverStyle(OpaquePortalStyle())))
  }

}

private struct OpaquePortalStyle: PromptStyle, FullScreenCoverStyle, PopoverStyle {
  let callback: @Sendable () -> Void = {}
  var snapshotLabel: String { "opaque" }
  func resolvePresentation(for configuration: PromptStyleConfiguration)
    -> PromptSurfaceStylePresentation
  {
    configuration.defaultPresentation
  }
  func resolvePresentation(for configuration: FullScreenCoverStyleConfiguration)
    -> FullScreenSurfaceStylePresentation
  {
    configuration.defaultPresentation
  }
  func resolvePresentation(for configuration: PopoverStyleConfiguration)
    -> AnchoredSurfaceStylePresentation
  {
    configuration.defaultPresentation
  }
}
