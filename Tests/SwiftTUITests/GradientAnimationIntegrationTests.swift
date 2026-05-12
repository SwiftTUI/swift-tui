import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// End-to-end integration coverage for gradient animation through
/// the `AnimationController` value-interpolation path.  These tests
/// pin the migration's whole-stack contract: a `LinearGradient`'s
/// start and end points (and a `TileStyle` whose foreground is a
/// gradient) must interpolate halfway through an animation halfway
/// through its duration.  Pre-Phase-3 the controller treated
/// gradients as opaque values and snapped between phases; with
/// Phase 2's `Animatable` conformance plus Phase 3's `AnyAnimatable`
/// dispatch the interior interpolates continuously and these
/// assertions hold.
@MainActor
@Suite("Gradient animation end-to-end through AnimationController")
struct GradientAnimationIntegrationTests {

  @Test("LinearGradient direction animates through withAnimation")
  func linearGradientDirectionAnimates() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    _ = controller.register(animation)

    let leafIdentity = Identity(components: [.named("gradient-leaf")])

    // Frame 1: gradient going top-leading to bottom-trailing.
    var frame1Metadata = DrawMetadata()
    frame1Metadata.baseStyle.foregroundStyle = .linearGradient(
      LinearGradient(
        colors: [.red, .blue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    )
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Gradient"),
      drawMetadata: frame1Metadata
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    // Frame 2: gradient rotated 90° (top-trailing to bottom-leading)
    // under an explicit linear animation request.
    var frame2Metadata = DrawMetadata()
    frame2Metadata.baseStyle.foregroundStyle = .linearGradient(
      LinearGradient(
        colors: [.red, .blue],
        startPoint: .topTrailing,
        endPoint: .bottomLeading
      )
    )
    var frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Gradient"),
      drawMetadata: frame2Metadata
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    // Halfway through the animation.
    let halfway = t0.advanced(by: .milliseconds(100))
    _ = controller.applyInterpolations(to: &frame2, at: halfway)

    // Extract the interpolated gradient and assert the start point
    // is halfway between (0,0) and (1,0) — the midpoint of the top
    // edge — and the end point is halfway between (1,1) and (0,1) —
    // the midpoint of the bottom edge.  The whole gradient is
    // rotating around the square's center, so at t=0.5 it points
    // straight down.
    guard
      let style = frame2.drawMetadata.baseStyle.foregroundStyle,
      case .linearGradient(let interpolated) = style
    else {
      Issue.record("expected interpolated linear gradient")
      return
    }
    #expect(abs(interpolated.startPoint.x - 0.5) < 0.05)
    #expect(abs(interpolated.startPoint.y - 0) < 0.05)
    #expect(abs(interpolated.endPoint.x - 0.5) < 0.05)
    #expect(abs(interpolated.endPoint.y - 1) < 0.05)
  }

  @Test("TileStyle gradient foreground animates end-to-end")
  func tileStyleGradientForegroundAnimates() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    _ = controller.register(animation)

    let leafIdentity = Identity(components: [.named("pattern-leaf")])

    var frame1Metadata = DrawMetadata()
    frame1Metadata.baseStyle.foregroundStyle = .tileStyle(
      TileStyle(
        .lightShade,
        foreground: LinearGradient(
          colors: [.red, .blue],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
    )
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Pattern"),
      drawMetadata: frame1Metadata
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    var frame2Metadata = DrawMetadata()
    frame2Metadata.baseStyle.foregroundStyle = .tileStyle(
      TileStyle(
        .lightShade,
        foreground: LinearGradient(
          colors: [.red, .blue],
          startPoint: .topTrailing,
          endPoint: .bottomLeading
        )
      )
    )
    var frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Pattern"),
      drawMetadata: frame2Metadata
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    let halfway = t0.advanced(by: .milliseconds(100))
    _ = controller.applyInterpolations(to: &frame2, at: halfway)

    guard
      let style = frame2.drawMetadata.baseStyle.foregroundStyle,
      case .tileStyle(let tile) = style,
      case .linearGradient(let gradient) = tile.foreground.style
    else {
      Issue.record("expected interpolated tile style with gradient foreground")
      return
    }
    // Same midpoint test as the LinearGradient case: at t=0.5 the
    // gradient's start point should sit on the top edge midpoint.
    #expect(abs(gradient.startPoint.x - 0.5) < 0.05)
    #expect(abs(gradient.startPoint.y - 0) < 0.05)
    #expect(abs(gradient.endPoint.x - 0.5) < 0.05)
    #expect(abs(gradient.endPoint.y - 1) < 0.05)
  }

  // MARK: - Shape.fill path (drawPayload.shape.operation)
  //
  // The two tests above pin the `.foregroundStyle(_:)` modifier path
  // (which writes to `drawMetadata.baseStyle.foregroundStyle`).  The
  // tests below pin the `Shape.fill(_:)` / `.stroke(_:)` path, which
  // writes to `drawPayload.shape.operation.fill.style` — a completely
  // different storage location.  Both slots must animate through the
  // same `AnyAnimatable` interpolation pipeline; the Phase 5 migration
  // originally shipped with the shape-payload extraction missing, so
  // `Rectangle().fill(LinearGradient(...))` in the gallery demos
  // snapped instead of rotating.  These regression tests pin the
  // shape-payload path end-to-end.

  @Test("Shape fill LinearGradient animates through drawPayload path")
  func shapeFillLinearGradientAnimates() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    _ = controller.register(animation)

    let leafIdentity = Identity(components: [.named("shape-fill-leaf")])

    // Frame 1: Rectangle().fill(LinearGradient(.topLeading → .bottomTrailing)).
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Rectangle"),
      drawPayload: .shape(
        ShapePayload(
          geometry: .rectangle,
          insetAmount: 0,
          operation: .fill(
            style: .linearGradient(
              LinearGradient(
                colors: [.red, .blue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            ),
            mode: .full
          )
        )
      )
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    // Frame 2: gradient rotated 90° under an explicit animation request.
    var frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Rectangle"),
      drawPayload: .shape(
        ShapePayload(
          geometry: .rectangle,
          insetAmount: 0,
          operation: .fill(
            style: .linearGradient(
              LinearGradient(
                colors: [.red, .blue],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
              )
            ),
            mode: .full
          )
        )
      )
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    let halfway = t0.advanced(by: .milliseconds(100))
    _ = controller.applyInterpolations(to: &frame2, at: halfway)

    // Unwrap the interpolated shape payload's fill style.
    guard case .shape(let shapePayload) = frame2.drawPayload,
      case .fill(let interpolatedStyle, _) = shapePayload.operation,
      let style = interpolatedStyle,
      case .linearGradient(let gradient) = style
    else {
      Issue.record(
        "expected interpolated linear gradient inside drawPayload.shape.operation.fill"
      )
      return
    }
    // Same midpoint assertion as the .foregroundStyle path.  Without
    // Phase 5's shape-payload extraction bug fix, the `applyValue`
    // writeback would leave the shape payload at frame 1's start/end
    // points and this test would read back (0, 0) / (1, 1) instead.
    #expect(abs(gradient.startPoint.x - 0.5) < 0.05)
    #expect(abs(gradient.startPoint.y - 0) < 0.05)
    #expect(abs(gradient.endPoint.x - 0.5) < 0.05)
    #expect(abs(gradient.endPoint.y - 1) < 0.05)
  }

  @Test("Shape fill TileStyle gradient foreground animates through drawPayload path")
  func shapeFillTileStyleGradientForegroundAnimates() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    _ = controller.register(animation)

    let leafIdentity = Identity(components: [.named("shape-fill-pattern-leaf")])

    // Frame 1: Rectangle().fill(TileStyle(foreground: linear gradient)).
    // This matches the BordersAndShapesCurvedShapesSection PhaseAnimator
    // demo's exact shape.
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Rectangle"),
      drawPayload: .shape(
        ShapePayload(
          geometry: .rectangle,
          insetAmount: 0,
          operation: .fill(
            style: .tileStyle(
              TileStyle(
                .init(glyph: "/"),
                foreground: LinearGradient(
                  colors: [.white, .red],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                )
              )
            ),
            mode: .full
          )
        )
      )
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    var frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Rectangle"),
      drawPayload: .shape(
        ShapePayload(
          geometry: .rectangle,
          insetAmount: 0,
          operation: .fill(
            style: .tileStyle(
              TileStyle(
                .init(glyph: "/"),
                foreground: LinearGradient(
                  colors: [.white, .red],
                  startPoint: .topTrailing,
                  endPoint: .bottomLeading
                )
              )
            ),
            mode: .full
          )
        )
      )
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    let halfway = t0.advanced(by: .milliseconds(100))
    _ = controller.applyInterpolations(to: &frame2, at: halfway)

    guard case .shape(let shapePayload) = frame2.drawPayload,
      case .fill(let interpolatedStyle, _) = shapePayload.operation,
      let style = interpolatedStyle,
      case .tileStyle(let tile) = style,
      case .linearGradient(let gradient) = tile.foreground.style
    else {
      Issue.record(
        "expected interpolated TileStyle with gradient foreground inside drawPayload.shape.operation.fill"
      )
      return
    }
    #expect(abs(gradient.startPoint.x - 0.5) < 0.05)
    #expect(abs(gradient.startPoint.y - 0) < 0.05)
    #expect(abs(gradient.endPoint.x - 0.5) < 0.05)
    #expect(abs(gradient.endPoint.y - 1) < 0.05)
    // Pattern must survive interpolation.
    #expect(tile.pattern.character(atX: 0, y: 0) == "/")
  }
}
