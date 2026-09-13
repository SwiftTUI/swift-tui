import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct NestedMatchedGeometryTests {
  private func leaf(
    _ name: String, x: Int, key: String? = nil, source: Bool = true,
    children: [PlacedNode] = []
  ) -> PlacedNode {
    PlacedNode(
      identity: testIdentity(name),
      bounds: .init(origin: .init(x: x, y: 0), size: .init(width: 2, height: 1)),
      children: children,
      matchedGeometry: key.map { .init(key: .init(id: $0), isSource: source) })
  }

  private func placed(_ name: String, in tree: PlacedNode) throws -> PlacedNode {
    try #require(AnimationTreeQueries.findPlacedSubtree(in: tree, identity: testIdentity(name)))
  }

  @Test("a nested adoptee reaches its own source after its ancestor adopts")
  func nestedAdoptee() throws {
    let original = leaf(
      "root", x: 0,
      children: [
        leaf("outerSource", x: 10, key: "outer"),
        leaf("innerSource", x: 30, key: "inner"),
        leaf(
          "outer", x: 0, key: "outer", source: false,
          children: [
            leaf("inner", x: 2, key: "inner", source: false)
          ]),
      ])
    let controller = AnimationController()
    var result = original
    controller.applyPlacedOverlays(to: &result, at: .now())
    #expect(try placed("outer", in: result).bounds.origin.x == 10)
    #expect(try placed("inner", in: result).bounds.origin.x == 30)
    #expect(try placed("inner", in: original).bounds.origin.x == 2)
  }

  @Test("a source nested inside an adopted ancestor supplies its displayed position")
  func nestedSource() throws {
    let original = leaf(
      "root", x: 0,
      children: [
        leaf("outerSource", x: 10, key: "outer"),
        leaf(
          "outer", x: 0, key: "outer", source: false,
          children: [
            leaf("innerSource", x: 2, key: "inner")
          ]),
        leaf("inner", x: 30, key: "inner", source: false),
      ])
    let controller = AnimationController()
    controller.capturePlacedTree(original)
    var result = original
    controller.applyPlacedOverlays(to: &result, at: .now())
    #expect(try placed("innerSource", in: result).bounds.origin.x == 12)
    #expect(try placed("inner", in: result).bounds.origin.x == 12)
    #expect(
      controller.debugStateSnapshot().previousMatchedGeometryBounds[.init(id: "inner")]?.origin.x
        == 12)
  }

  @Test("nested insertion offsets compose and an absorbed identity applies only once")
  func nestedOffsets() throws {
    let original = leaf(
      "outer", x: 0,
      children: [
        leaf("outer", x: 0, children: [leaf("inner", x: 2)])
      ])
    let offsets = [
      testIdentity("outer"): PlacedAnimationOverlayOffset(
        identity: testIdentity("outer"), dx: 10, dy: 0),
      testIdentity("inner"): PlacedAnimationOverlayOffset(
        identity: testIdentity("inner"), dx: 4, dy: 0),
    ]
    let result = translatePlacedNodesByIdentity(tree: original, offsets: offsets)
    #expect(result.bounds.origin.x == 10)
    #expect(result.children[0].bounds.origin.x == 10)
    #expect(try placed("inner", in: result).bounds.origin.x == 16)
  }

  @Test("an adoptee follows a source's animated ancestor")
  func sourceAncestorMotion() throws {
    let original = leaf(
      "root", x: 0,
      children: [
        leaf("moving", x: 0, children: [leaf("source", x: 2, key: "pair")]),
        leaf("adoptee", x: 30, key: "pair", source: false),
      ])
    let live = PlacedAnimationOverlayOffset(identity: testIdentity("moving"), dx: 10, dy: 0)
    let adoption = PlacedAnimationOverlaySampling.sampleAdoption(
      tree: original, liveOffsets: [live])
    var result = original
    applyPlacedAnimationOverlaySnapshot(
      .init(insertionOffsets: [live], adoptionOffsets: adoption), to: &result)
    #expect(try placed("source", in: result).bounds.origin.x == 12)
    #expect(try placed("adoptee", in: result).bounds.origin.x == 12)
  }

  @Test("a descendant frozen without its ancestor retains the full adoption displacement")
  func frozenDescendant() throws {
    let original = leaf("outer", x: 0, children: [leaf("child", x: 2)])
    let offsets = NestedMatchedGeometryPlacement.absoluteOffsets(
      in: original,
      applying: [.init(identity: testIdentity("outer"), dx: 10, dy: 3)])
    let frozen = translatePlacedNodesByIdentity(
      tree: original.children[0], offsets: offsets, offsetsAreAbsolute: true)
    #expect(frozen.bounds.origin == .init(x: 12, y: 3))
    let whole = translatePlacedNodesByIdentity(
      tree: original, offsets: offsets, offsetsAreAbsolute: true)
    #expect(whole.children[0].bounds == frozen.bounds)
  }

  @Test(
    "nested matched interpolation reaches each absolute target without adding its ancestor twice")
  func nestedMatchedInterpolation() throws {
    let original = leaf("outer", x: 0, children: [leaf("inner", x: 2)])
    let offsets: [PlacedAnimationOverlayOffset] = [
      .init(identity: testIdentity("outer"), dx: 10, dy: 0),
      .init(identity: testIdentity("inner"), dx: 28, dy: 0),
    ]
    var result = original
    applyPlacedAnimationOverlaySnapshot(.init(matchedGeometryOffsets: offsets), to: &result)
    #expect(result.bounds.origin.x == 10)
    #expect(result.children[0].bounds.origin.x == 30)
    let local = NestedMatchedGeometryPlacement.localOffsets(in: original, absolute: offsets)
    let localResult = translatePlacedNodesByIdentity(
      tree: original, offsets: Dictionary(uniqueKeysWithValues: local.map { ($0.identity, $0) }))
    #expect(localResult.children[0].bounds == result.children[0].bounds)
  }

  @Test("a nested node without an independent source inherits its ancestor's adoption")
  func missingNestedSource() throws {
    let original = leaf(
      "root", x: 0,
      children: [
        leaf("source", x: 10, key: "outer"),
        leaf(
          "outer", x: 0, key: "outer", source: false,
          children: [
            leaf("inner", x: 2, key: "unpaired", source: false)
          ]),
      ])
    var result = original
    AnimationController().applyPlacedOverlays(to: &result, at: .now())
    #expect(try placed("inner", in: result).bounds.origin.x == 12)
  }

  @Test("a source inside its own adoptee does not create a recursive moving target")
  func cyclicAdoption() throws {
    let original = leaf(
      "outer", x: 0, key: "cycle", source: false,
      children: [
        leaf("innerSource", x: 2, key: "cycle")
      ])
    var result = original
    AnimationController().applyPlacedOverlays(to: &result, at: .now())
    #expect(result.bounds == original.bounds)
    #expect(result.children[0].bounds == original.children[0].bounds)
  }

  @Test("nested adoption resizes and clips at the independent target")
  func nestedSize() throws {
    var innerSource = leaf("innerSource", x: 30, key: "inner")
    innerSource.bounds.size.width = 4
    let original = leaf(
      "root", x: 0,
      children: [
        leaf("outerSource", x: 10, key: "outer"), innerSource,
        leaf(
          "outer", x: 0, key: "outer", source: false,
          children: [
            leaf("inner", x: 2, key: "inner", source: false)
          ]),
      ])
    var result = original
    AnimationController().applyPlacedOverlays(to: &result, at: .now())
    let inner = try placed("inner", in: result)
    #expect(inner.bounds == innerSource.bounds)
    #expect(inner.drawMetadata.clipsToBounds)
    #expect(inner.clipBounds == innerSource.bounds)
    #expect(try placed("inner", in: original).bounds.size.width == 2)
  }
}
