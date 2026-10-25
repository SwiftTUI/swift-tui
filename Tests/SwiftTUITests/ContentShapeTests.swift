import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct ContentShapeTests {
  @Test(
    "invalid path bounds cannot trap semantic extraction",
    arguments: [Double.nan, .infinity, 1e200])
  func invalidPathBounds(value: Double) {
    let path = Path([.move(to: .init(x: value, y: 0)), .line(to: .init(x: 10, y: 10))])
    let frame = DefaultRenderer().render(
      Button("Target") {}.contentShape(path), proposal: .init(width: 20, height: 4))
    #expect(
      !frame.semanticSnapshot.interactionRegions.contains {
        $0.contains(.cellFallback(.init(x: 2, y: 0)))
      })
  }

  @Test("enclosing paths and rects intersect across identity and layout wrappers")
  func enclosingShapesIntersect() throws {
    var triangle = Path()
    triangle.move(to: .init(x: 0, y: 0))
    triangle.addLine(to: .init(x: 6, y: 0))
    triangle.addLine(to: .init(x: 0, y: 6))
    triangle.close()
    let artifacts = DefaultRenderer().render(
      VStack {
        Button("Target") {}
          .contentShape(CellRect(origin: .zero, size: .init(width: 12, height: 6)))
          .frame(width: 12, height: 6, alignment: .topLeading).id("re-rooted-child")
      }
      .frame(width: 6, height: 6, alignment: .topLeading)
      .contentShape(triangle)
      .padding(1)
      .contentShape(CellRect(origin: .zero, size: .init(width: 5, height: 8))),
      proposal: .init(width: 20, height: 10))
    let regions = artifacts.semanticSnapshot.interactionRegions
    try #require(!regions.isEmpty)
    let metrics = CellPixelMetrics(width: 8, height: 16, source: .reported)
    func contains(_ x: Double, _ y: Double) -> Bool {
      regions.contains {
        $0.contains(
          .subCell(
            location: .init(x: x, y: y), source: .nativePixels, metrics: metrics))
      }
    }
    #expect(contains(2, 2))
    #expect(!contains(4, 5))  // inside both bounding boxes, outside the triangle
    #expect(!contains(5.5, 1.2))  // inside the triangle, outside the outer rectangle
    #expect(
      artifacts.semanticSnapshot.focusRegions.contains {
        $0.identity.path.contains("re-rooted-child")
      })
  }

  @Test("disjoint ancestor content shapes remain empty")
  func disjointShapesDoNotResetClipping() {
    let artifacts = DefaultRenderer().render(
      VStack {
        Button("Target") {}.contentShape(
          CellRect(origin: .init(x: 10, y: 0), size: .init(width: 5, height: 2)))
      }
      .contentShape(CellRect(origin: .zero, size: .init(width: 5, height: 2))),
      proposal: .init(width: 20, height: 4))
    #expect(artifacts.semanticSnapshot.interactionRegions.isEmpty)
    #expect(!artifacts.semanticSnapshot.focusRegions.isEmpty)
  }

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

    let rectArtifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Spacer().frame(height: 1)
        HStack(spacing: 0) {
          Spacer().frame(width: 3)
          Text("XXXX")
            .contentShape(rect)
            .gesture(TapGesture().onEnded {})
        }
      },
      context: ctx,
      proposal: .init(width: 20, height: 6)
    )
    let pathArtifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Spacer().frame(height: 1)
        HStack(spacing: 0) {
          Spacer().frame(width: 3)
          Text("XXXX")
            .contentShape(path)
            .gesture(TapGesture().onEnded {})
        }
      },
      context: ctx,
      proposal: .init(width: 20, height: 6)
    )

    let rectRegion = rectArtifacts.semanticSnapshot.interactionRegions.first!
    let pathRegion = pathArtifacts.semanticSnapshot.interactionRegions.first!

    #expect(rectRegion.rect == pathRegion.rect)
  }

  @Test("STUI-1208: a content shape from a trimmed path follows the outline its fill paints")
  func trimmedContentShapeFollowsPaintedOutline() throws {
    let root = Identity(components: [IdentityComponent(rawValue: "trimmed-content-shape")])
    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 10, height: 10)
    var ctx = ResolveContext(identity: root, environmentValues: env)
    ctx.localPointerHandlerRegistry = LocalPointerHandlerRegistry()
    ctx.localGestureRegistry = LocalGestureRegistry()
    ctx.localGestureStateRegistry = LocalGestureStateRegistry()

    let rect = Rect(origin: .zero, size: .init(width: 10, height: 10))
    let painted = ShapeGeometry.trimmed(.rectangle, from: 0, to: 0.25).path(
      in: rect,
      trimAspectRatio: RectangleStrokeTrack.snappedAspectRatio(
        CellPixelMetrics.estimated.aspectRatio))
    let artifacts = DefaultRenderer().render(
      Rectangle().trim(from: 0, to: 0.25).fill()
        .contentShape(Rectangle().trim(from: 0, to: 0.25).path(in: rect))
        .gesture(TapGesture().onEnded {}),
      context: ctx,
      proposal: .init(width: 10, height: 10)
    )
    let region = try #require(artifacts.semanticSnapshot.interactionRegions.first)
    let metrics = CellPixelMetrics(width: 8, height: 16, source: .reported)
    func hits(_ point: Point) -> Bool {
      region.contains(.subCell(location: point, source: .nativePixels, metrics: metrics))
    }
    var disagreements: [CellPoint] = []
    for y in 0..<10 {
      for x in 0..<10 {
        let center = Point(x: Double(x) + 0.5, y: Double(y) + 0.5)
        if hits(center) != painted.contains(center) {
          disagreements.append(CellPoint(x: x, y: y))
        }
      }
    }
    #expect(disagreements.isEmpty, "cells where hit testing and paint disagree: \(disagreements)")
    #expect(!hits(Point(x: 2.5, y: 8.5)))
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
