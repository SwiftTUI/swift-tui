import Foundation
import Testing

@testable import Core
@testable import SwiftTUI
@testable import View

@MainActor
@Suite
struct ContentShapeTests {
  @Test(".contentShape overrides the hit-test rect")
  func contentShapeOverrides() throws {
    let root = Identity(components: [IdentityComponent(rawValue: "root")])
    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 20, height: 3)

    let shapeRect = CellRect(
      origin: .zero,
      size: CellSize(width: 10, height: 3)
    )

    // Same pattern as GestureViewModifierTests: construct registries,
    // attach to ResolveContext, render.
    let pointerRegistry = LocalPointerHandlerRegistry()
    let gestureRegistry = LocalGestureRegistry()
    let gestureStateRegistry = LocalGestureStateRegistry()

    var ctx = ResolveContext(
      identity: root,
      environmentValues: env
    )
    ctx.localPointerHandlerRegistry = pointerRegistry
    ctx.localGestureRegistry = gestureRegistry
    ctx.localGestureStateRegistry = gestureStateRegistry

    let artifacts = DefaultRenderer().render(
      Text("X")
        .contentShape(shapeRect)
        .gesture(TapGesture().onEnded {}),
      context: ctx,
      proposal: .init(width: 20, height: 3)
    )
    let region = try #require(artifacts.semanticSnapshot.interactionRegions.first)
    #expect(region.rect.size.width == 10)
    #expect(region.rect.size.height == 3)
  }

  @Test("rect-based contentShape is interpreted in node-local coordinates")
  func contentShapeRectIsNodeLocal() throws {
    // Regression: this test reproduces the bug that caused the gallery
    // Physics ball gesture to misfire. A rect-based `contentShape`
    // supplied at local origin (0, 0) used to anchor at absolute
    // (0, 0), which is silently wrong unless the modified view sits at
    // the screen origin. After fixing
    // `transformedExplicitInteractionRect` to translate by
    // `semanticBounds(for:)`, the rect's origin equals the modified
    // view's placed origin.
    let root = Identity(components: [IdentityComponent(rawValue: "root")])
    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 20, height: 6)

    let pointerRegistry = LocalPointerHandlerRegistry()
    let gestureRegistry = LocalGestureRegistry()
    let gestureStateRegistry = LocalGestureStateRegistry()

    var ctx = ResolveContext(
      identity: root,
      environmentValues: env
    )
    ctx.localPointerHandlerRegistry = pointerRegistry
    ctx.localGestureRegistry = gestureRegistry
    ctx.localGestureStateRegistry = gestureStateRegistry

    // Wrap the modified Text in a 5×2 leading inset so the contentShape
    // target is placed at absolute (5, 2) — _not_ at (0, 0) where the
    // bug used to hide.
    let shapeRect = CellRect(
      origin: .zero,
      size: CellSize(width: 3, height: 1)
    )
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Spacer().frame(height: 2)
        HStack(spacing: 0) {
          Spacer().frame(width: 5)
          Text("X")
            .contentShape(shapeRect)
            .gesture(TapGesture().onEnded {})
        }
      },
      context: ctx,
      proposal: .init(width: 20, height: 6)
    )

    let region = try #require(artifacts.semanticSnapshot.interactionRegions.first)
    #expect(region.rect.origin.x == 5)
    #expect(region.rect.origin.y == 2)
    #expect(region.rect.size.width == 3)
    #expect(region.rect.size.height == 1)
  }

  @Test("rect and path content-shape overloads agree on placement")
  func contentShapeRectPathParity() throws {
    // Lock the two `contentShape` overloads into the same coordinate
    // space so they can't drift apart again.
    let root = Identity(components: [IdentityComponent(rawValue: "root")])
    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 20, height: 6)

    let pointerRegistry = LocalPointerHandlerRegistry()
    let gestureRegistry = LocalGestureRegistry()
    let gestureStateRegistry = LocalGestureStateRegistry()

    var ctx = ResolveContext(
      identity: root,
      environmentValues: env
    )
    ctx.localPointerHandlerRegistry = pointerRegistry
    ctx.localGestureRegistry = gestureRegistry
    ctx.localGestureStateRegistry = gestureStateRegistry

    let rect = CellRect(
      origin: .zero,
      size: CellSize(width: 4, height: 2)
    )
    var path = Path()
    path.move(to: Point(x: 0, y: 0))
    path.addLine(to: Point(x: 4, y: 0))
    path.addLine(to: Point(x: 4, y: 2))
    path.addLine(to: Point(x: 0, y: 2))
    path.close()

    func render<V: View>(_ view: V) -> InteractionRegion {
      let artifacts = DefaultRenderer().render(
        VStack(alignment: .leading, spacing: 0) {
          Spacer().frame(height: 1)
          HStack(spacing: 0) {
            Spacer().frame(width: 3)
            view
          }
        },
        context: ctx,
        proposal: .init(width: 20, height: 6)
      )
      return artifacts.semanticSnapshot.interactionRegions.first!
    }

    let rectRegion = render(
      Text("XXXX").contentShape(rect).gesture(TapGesture().onEnded {})
    )
    let pathRegion = render(
      Text("XXXX").contentShape(path).gesture(TapGesture().onEnded {})
    )

    #expect(rectRegion.rect == pathRegion.rect)
  }

  @Test("content-shape nil falls back to the default interaction rect")
  func contentShapeNilRestoresDefault() throws {
    let root = Identity(components: [IdentityComponent(rawValue: "root")])
    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 20, height: 3)

    let pointerRegistry = LocalPointerHandlerRegistry()
    let gestureRegistry = LocalGestureRegistry()
    let gestureStateRegistry = LocalGestureStateRegistry()

    var ctx = ResolveContext(
      identity: root,
      environmentValues: env
    )
    ctx.localPointerHandlerRegistry = pointerRegistry
    ctx.localGestureRegistry = gestureRegistry
    ctx.localGestureStateRegistry = gestureStateRegistry

    let artifacts = DefaultRenderer().render(
      Text("X")
        .contentShape(nil)
        .gesture(TapGesture().onEnded {}),
      context: ctx,
      proposal: .init(width: 20, height: 3)
    )
    let region = try #require(artifacts.semanticSnapshot.interactionRegions.first)
    // Default shape — should match the text's natural bounds (width 1 for "X").
    #expect(region.rect.size.width >= 1)
  }

  @Test("continuous content-shape path filters pointer hit testing")
  func contentShapePathFiltersHitTesting() throws {
    let root = Identity(components: [IdentityComponent(rawValue: "root")])
    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 20, height: 6)

    let pointerRegistry = LocalPointerHandlerRegistry()
    let gestureRegistry = LocalGestureRegistry()
    let gestureStateRegistry = LocalGestureStateRegistry()

    var ctx = ResolveContext(
      identity: root,
      environmentValues: env
    )
    ctx.localPointerHandlerRegistry = pointerRegistry
    ctx.localGestureRegistry = gestureRegistry
    ctx.localGestureStateRegistry = gestureStateRegistry

    var path = Path()
    path.move(to: Point(x: 0, y: 0))
    path.addLine(to: Point(x: 4, y: 0))
    path.addLine(to: Point(x: 0, y: 4))
    path.close()

    let artifacts = DefaultRenderer().render(
      Text("XXXX")
        .contentShape(path)
        .gesture(TapGesture().onEnded {}),
      context: ctx,
      proposal: .init(width: 20, height: 6)
    )
    let region = try #require(artifacts.semanticSnapshot.interactionRegions.first)

    #expect(
      region.contains(
        .subCell(
          location: Point(x: 1, y: 1),
          source: .nativePixels,
          metrics: CellPixelMetrics(width: 8, height: 16, source: .reported)
        )
      )
    )
    #expect(
      !region.contains(
        .subCell(
          location: Point(x: 3.5, y: 3.5),
          source: .nativePixels,
          metrics: CellPixelMetrics(width: 8, height: 16, source: .reported)
        )
      )
    )
  }
}
