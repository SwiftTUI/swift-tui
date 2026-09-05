import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

struct ScrollLinkStyleReuseTests {
  @Test func typedEquality() {
    #expect(AnyScrollViewStyle.automatic.isEqualForReuse(to: AnyScrollViewStyle.automatic))
    #expect(!AnyScrollViewStyle.automatic.isEqualForReuse(to: AnyScrollViewStyle.minimal))
    #expect(
      AnyScrollViewStyle(ConsumerScrollViewStyle()).isEqualForReuse(
        to: AnyScrollViewStyle(ConsumerScrollViewStyle())))
    #expect(
      !AnyScrollViewStyle(ConsumerScrollViewStyle()).isEqualForReuse(
        to: AnyScrollViewStyle(ConsumerScrollViewStyle(reservesSpace: true))))
    #expect(
      !AnyScrollViewStyle(OpaqueScrollStyle()).isEqualForReuse(
        to: AnyScrollViewStyle(OpaqueScrollStyle())))
    #expect(AnyLinkStyle.automatic.isEqualForReuse(to: AnyLinkStyle.automatic))
    #expect(!AnyLinkStyle.automatic.isEqualForReuse(to: AnyLinkStyle.plain))
    #expect(
      AnyLinkStyle(ConsumerLinkStyle()).isEqualForReuse(
        to: AnyLinkStyle(ConsumerLinkStyle())))
    #expect(
      !AnyLinkStyle(ConsumerLinkStyle()).isEqualForReuse(
        to: AnyLinkStyle(ConsumerLinkStyle(underline: .hidden))))
    #expect(!AnyLinkStyle(OpaqueLinkStyle()).isEqualForReuse(to: AnyLinkStyle(OpaqueLinkStyle())))
  }
}

private struct OpaqueScrollStyle: ScrollViewStyle {
  let callback: @Sendable () -> Void = {}
  func resolvePresentation(for configuration: ScrollViewStyleConfiguration)
    -> ScrollViewStylePresentation
  {
    .init(snapshotLabel: "opaque")
  }
}

private struct OpaqueLinkStyle: LinkStyle {
  let callback: @Sendable () -> Void = {}
  func resolvePresentation(for configuration: LinkStyleConfiguration) -> LinkStylePresentation {
    .init()
  }
}
