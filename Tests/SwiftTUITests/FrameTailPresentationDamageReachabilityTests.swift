import SwiftTUICore
import Testing

@testable import SwiftTUIRuntime

/// The incremental raster path was unreachable in practice: every frame of
/// every real app barriered out of damage production with
/// `unresolvedInvalidatedIdentity`.
///
/// Two things were wrong. Both `placedPath` implementations climbed
/// `Identity.parent`, which is purely lexical — it drops the last path
/// component and terminates only at the *empty* identity — so on a real app,
/// whose placed tree is rooted at the window content (`App/<scene>`), the walk
/// ran off the top of the placed tree into ancestors that own no `PlacedNode`.
/// Every existing fixture rooted its placed tree at `testIdentity()`, the empty
/// identity whose `parent` is `nil`, so the walk terminated successfully and
/// the bug stayed invisible.
///
/// And once damage *was* produced, keying it on the subtree extents of
/// `directlyInvalidated` proved unsound: that set is the invalidation seed set,
/// not the set of identities whose painted output changed. Damage is now
/// derived by diffing the previous committed placed tree against this frame's,
/// so these fixtures use non-empty roots (the shape real apps produce) *and*
/// trees that actually differ.
@MainActor
@Suite("Frame tail presentation damage reachability")
struct FrameTailPresentationDamageReachabilityTests {
  @Test("a placed tree rooted below the identity root still resolves damage")
  func nonEmptyPlacedRootResolvesDamage() throws {
    // The real-app shape: the placed root is `App/scene`, so the lexical
    // ancestors `App` and `(root)` exist as identities but never as
    // `PlacedNode`s.
    let sceneIdentity = testIdentity("App", "scene")
    let layoutIdentity = testIdentity("App", "scene", "Layout[0]")
    let cleanIdentity = testIdentity("App", "scene", "Layout[0]", "VStack[0]")
    let dirtyIdentity = testIdentity("App", "scene", "Layout[0]", "VStack[3]")

    func tree(dirtyRow: Int) -> PlacedNode {
      PlacedNode(
        identity: sceneIdentity,
        kind: .root,
        bounds: .init(origin: .zero, size: .init(width: 20, height: 6)),
        children: [
          PlacedNode(
            identity: layoutIdentity,
            kind: .view("VStack"),
            bounds: .init(origin: .zero, size: .init(width: 20, height: 6)),
            children: [
              PlacedNode(
                identity: cleanIdentity,
                kind: .view("Text"),
                bounds: .init(origin: .zero, size: .init(width: 20, height: 1))
              ),
              PlacedNode(
                identity: dirtyIdentity,
                kind: .view("Text"),
                bounds: .init(
                  origin: .init(x: 0, y: dirtyRow),
                  size: .init(width: 20, height: 1)
                )
              ),
            ]
          )
        ]
      )
    }

    let previousPlaced = tree(dirtyRow: 3)
    let currentPlaced = tree(dirtyRow: 4)

    let plan = FrameTailPresentationDamageResolver.resolve(
      rootIdentity: sceneIdentity,
      placed: currentPlaced,
      draw: Self.drawTree(from: currentPlaced),
      retainedLayout: RetainedLayoutSession(
        previousFrameIndex: RetainedFrameIndex(
          frame: damageFrameArtifacts(placed: previousPlaced)
        ),
        invalidatedIdentities: [dirtyIdentity]
      ),
      previousDraw: Self.drawTree(from: previousPlaced),
      previousSurfaceTopology: SurfaceTopologySignature(placedRoot: previousPlaced)
    )

    #expect(plan.barriers.isEmpty)
    // The changed leaf moves from row 3 to row 4; each rect carries the
    // one-cell margin the half-block painters need (rows 2 and 5).
    #expect(plan.damage?.dirtyRows == [2, 3, 4, 5])
  }

  @Test("a placed child that skips a lexical level still resolves damage")
  func multiComponentPlacementJumpResolvesDamage() throws {
    // `Identity.explicitID(_:)` and indexed components make multi-component
    // jumps between placed levels plausible: here `App/scene/Group` is a real
    // identity level that never materializes as a `PlacedNode`, so the placed
    // child's identity extends its placed parent's by *two* components. A
    // lexical walk fails on the missing intermediate; a walk over recorded
    // placed-tree edges cannot.
    let sceneIdentity = testIdentity("App", "scene")
    let dirtyIdentity = testIdentity("App", "scene", "Group", "ID[\"row\"]")

    func tree(dirtyRow: Int) -> PlacedNode {
      PlacedNode(
        identity: sceneIdentity,
        kind: .root,
        bounds: .init(origin: .zero, size: .init(width: 20, height: 6)),
        children: [
          PlacedNode(
            identity: dirtyIdentity,
            kind: .view("Text"),
            bounds: .init(
              origin: .init(x: 0, y: dirtyRow),
              size: .init(width: 20, height: 1)
            )
          )
        ]
      )
    }

    let previousPlaced = tree(dirtyRow: 2)
    let currentPlaced = tree(dirtyRow: 3)

    let plan = FrameTailPresentationDamageResolver.resolve(
      rootIdentity: sceneIdentity,
      placed: currentPlaced,
      draw: Self.drawTree(from: currentPlaced),
      retainedLayout: RetainedLayoutSession(
        previousFrameIndex: RetainedFrameIndex(
          frame: damageFrameArtifacts(placed: previousPlaced)
        ),
        invalidatedIdentities: [dirtyIdentity]
      ),
      previousDraw: Self.drawTree(from: previousPlaced),
      previousSurfaceTopology: SurfaceTopologySignature(placedRoot: previousPlaced)
    )

    #expect(plan.barriers.isEmpty)
    #expect(plan.damage?.dirtyRows == [1, 2, 3, 4])
  }

  @Test("a changed node that was never invalidated is still damaged")
  func changedButUninvalidatedSiblingIsDamaged() throws {
    // The premise the seed-set model rested on — `directlyInvalidated` is the
    // complete set of identities whose painted output changed — is false.
    // Re-resolution routinely repaints a sibling that reads a derived value,
    // an environment write, or a preference; the seed names only the node whose
    // state changed. Here the *button* is invalidated and the *label* is what
    // repaints, which is the shape the DEBUG verify oracle caught in eleven
    // separate runtime scenarios.
    let sceneIdentity = testIdentity("App", "scene")
    let buttonIdentity = testIdentity("App", "scene", "VStack[0]")
    let labelIdentity = testIdentity("App", "scene", "VStack[1]")

    func tree(labelWidth: Int) -> PlacedNode {
      PlacedNode(
        identity: sceneIdentity,
        kind: .root,
        bounds: .init(origin: .zero, size: .init(width: 20, height: 2)),
        children: [
          PlacedNode(
            identity: buttonIdentity,
            kind: .view("Button"),
            bounds: .init(origin: .zero, size: .init(width: 20, height: 1))
          ),
          PlacedNode(
            identity: labelIdentity,
            kind: .view("Text"),
            bounds: .init(origin: .init(x: 0, y: 1), size: .init(width: labelWidth, height: 1))
          ),
        ]
      )
    }

    let previousPlaced = tree(labelWidth: 7)
    let currentPlaced = tree(labelWidth: 9)

    let plan = FrameTailPresentationDamageResolver.resolve(
      rootIdentity: sceneIdentity,
      placed: currentPlaced,
      draw: Self.drawTree(from: currentPlaced),
      retainedLayout: RetainedLayoutSession(
        previousFrameIndex: RetainedFrameIndex(
          frame: damageFrameArtifacts(placed: previousPlaced)
        ),
        // Deliberately NOT the label: only the button is a seed.
        invalidatedIdentities: [buttonIdentity]
      ),
      previousDraw: Self.drawTree(from: previousPlaced),
      previousSurfaceTopology: SurfaceTopologySignature(placedRoot: previousPlaced)
    )

    #expect(plan.barriers.isEmpty)
    // Row 1 is the changed label; rows 0 and 2 are its one-cell margin.
    #expect(plan.damage?.dirtyRows == [0, 1, 2])
  }

  @Test("a departed child's previous ink is damaged")
  func departedChildIsDamaged() throws {
    let sceneIdentity = testIdentity("App", "scene")
    let keptIdentity = testIdentity("App", "scene", "VStack[0]")
    let departedIdentity = testIdentity("App", "scene", "VStack[1]")

    func row(_ identity: Identity, _ y: Int) -> PlacedNode {
      PlacedNode(
        identity: identity,
        kind: .view("Text"),
        bounds: .init(origin: .init(x: 0, y: y), size: .init(width: 20, height: 1))
      )
    }
    func tree(children: [PlacedNode]) -> PlacedNode {
      PlacedNode(
        identity: sceneIdentity,
        kind: .root,
        bounds: .init(origin: .zero, size: .init(width: 20, height: 2)),
        children: children
      )
    }

    let previousPlaced = tree(children: [row(keptIdentity, 0), row(departedIdentity, 1)])
    let currentPlaced = tree(children: [row(keptIdentity, 0)])

    let plan = FrameTailPresentationDamageResolver.resolve(
      rootIdentity: sceneIdentity,
      placed: currentPlaced,
      draw: Self.drawTree(from: currentPlaced),
      retainedLayout: RetainedLayoutSession(
        previousFrameIndex: RetainedFrameIndex(
          frame: damageFrameArtifacts(placed: previousPlaced)
        ),
        invalidatedIdentities: [sceneIdentity.child("VStack[1]")]
      ),
      previousDraw: Self.drawTree(from: previousPlaced),
      previousSurfaceTopology: SurfaceTopologySignature(placedRoot: previousPlaced)
    )

    #expect(plan.barriers.isEmpty)
    #expect(plan.damage?.dirtyRows == [0, 1, 2])
  }

  @Test("a re-rooted placed tree barriers instead of comparing paths")
  func reRootedPlacedTreeBarriers() throws {
    // `SurfaceTopologyEntry` deliberately carries no `Identity`, so a placed
    // root swap can pass topology equality. Both placed paths terminate at
    // their own tree's root, so without this guard the two paths would be
    // rooted at different nodes and compared pairwise anyway.
    let previousSceneIdentity = testIdentity("App", "sceneA")
    let currentSceneIdentity = testIdentity("App", "sceneB")
    let dirtyIdentity = testIdentity("App", "Body")

    func tree(rootIdentity: Identity) -> PlacedNode {
      PlacedNode(
        identity: rootIdentity,
        kind: .root,
        bounds: .init(origin: .zero, size: .init(width: 20, height: 3)),
        children: [
          PlacedNode(
            identity: dirtyIdentity,
            kind: .view("Text"),
            bounds: .init(origin: .zero, size: .init(width: 20, height: 1))
          )
        ]
      )
    }

    let previousPlaced = tree(rootIdentity: previousSceneIdentity)
    let currentPlaced = tree(rootIdentity: currentSceneIdentity)

    let plan = FrameTailPresentationDamageResolver.resolve(
      rootIdentity: currentSceneIdentity,
      placed: currentPlaced,
      draw: Self.drawTree(from: currentPlaced),
      retainedLayout: RetainedLayoutSession(
        previousFrameIndex: RetainedFrameIndex(
          frame: damageFrameArtifacts(placed: previousPlaced)
        ),
        invalidatedIdentities: [dirtyIdentity]
      ),
      previousDraw: Self.drawTree(from: previousPlaced),
      previousSurfaceTopology: SurfaceTopologySignature(placedRoot: previousPlaced)
    )

    #expect(plan.damage == nil)
    #expect(plan.barriers == [.placedRootChanged])
  }

  @Test("a duplicated identity in the previous frame barriers")
  func duplicateIdentityInPreviousFrameBarriers() throws {
    // Both placed indexes collapse duplicate explicit ids last-writer-wins, so
    // a path crossing one can mix nodes from different siblings and
    // under-report damage — release-only corruption under `.trustSoundDamage`.
    let sceneIdentity = testIdentity("App", "scene")
    let dirtyIdentity = testIdentity("App", "scene", "ID[\"dup\"]")

    let placed = PlacedNode(
      identity: sceneIdentity,
      kind: .root,
      bounds: .init(origin: .zero, size: .init(width: 20, height: 3)),
      children: [
        PlacedNode(
          identity: dirtyIdentity,
          kind: .view("Text"),
          bounds: .init(origin: .zero, size: .init(width: 20, height: 1))
        )
      ]
    )
    // Two resolved siblings share one identity, which is exactly what a
    // non-unique `ForEach` id keypath or a reused `.id(_:)` produces.
    let resolved = ResolvedNode(
      identity: sceneIdentity,
      kind: .root,
      children: [
        ResolvedNode(identity: dirtyIdentity, kind: .view("Text")),
        ResolvedNode(identity: dirtyIdentity, kind: .view("Text")),
      ]
    )

    let plan = FrameTailPresentationDamageResolver.resolve(
      rootIdentity: sceneIdentity,
      placed: placed,
      draw: Self.drawTree(from: placed),
      retainedLayout: RetainedLayoutSession(
        previousFrameIndex: RetainedFrameIndex(
          frame: damageFrameArtifacts(placed: placed, resolved: resolved)
        ),
        invalidatedIdentities: [dirtyIdentity]
      ),
      previousDraw: Self.drawTree(from: placed),
      previousSurfaceTopology: SurfaceTopologySignature(placedRoot: placed)
    )

    #expect(plan.damage == nil)
    #expect(plan.barriers == [.duplicateInvalidatedIdentity])
  }

  @Test("a duplicated identity in the current placed tree barriers")
  func duplicateIdentityInCurrentPlacedTreeBarriers() throws {
    let sceneIdentity = testIdentity("App", "scene")
    let dirtyIdentity = testIdentity("App", "scene", "ID[\"dup\"]")

    func row(_ y: Int) -> PlacedNode {
      PlacedNode(
        identity: dirtyIdentity,
        kind: .view("Text"),
        bounds: .init(origin: .init(x: 0, y: y), size: .init(width: 20, height: 1))
      )
    }

    let previousPlaced = PlacedNode(
      identity: sceneIdentity,
      kind: .root,
      bounds: .init(origin: .zero, size: .init(width: 20, height: 3)),
      children: [row(0)]
    )
    let currentPlaced = PlacedNode(
      identity: sceneIdentity,
      kind: .root,
      bounds: .init(origin: .zero, size: .init(width: 20, height: 3)),
      children: [row(0), row(1)]
    )

    let plan = FrameTailPresentationDamageResolver.resolve(
      rootIdentity: sceneIdentity,
      placed: currentPlaced,
      draw: Self.drawTree(from: currentPlaced),
      retainedLayout: RetainedLayoutSession(
        previousFrameIndex: RetainedFrameIndex(
          frame: damageFrameArtifacts(placed: previousPlaced)
        ),
        invalidatedIdentities: [dirtyIdentity]
      ),
      previousDraw: Self.drawTree(from: previousPlaced),
      previousSurfaceTopology: SurfaceTopologySignature(placedRoot: previousPlaced)
    )

    #expect(plan.damage == nil)
    #expect(plan.barriers == [.duplicateInvalidatedIdentity])
  }

  @Test("an animation-interpolated frame barriers before any diff")
  func animationInterpolatedFrameBarriers() throws {
    let sceneIdentity = testIdentity("App", "scene")
    let dirtyIdentity = testIdentity("App", "scene", "Layout[0]")

    func tree(dirtyRow: Int) -> PlacedNode {
      PlacedNode(
        identity: sceneIdentity,
        kind: .root,
        bounds: .init(origin: .zero, size: .init(width: 20, height: 6)),
        children: [
          PlacedNode(
            identity: dirtyIdentity,
            kind: .view("Text"),
            bounds: .init(origin: .init(x: 0, y: dirtyRow), size: .init(width: 20, height: 1))
          )
        ]
      )
    }

    let previousPlaced = tree(dirtyRow: 1)
    let currentPlaced = tree(dirtyRow: 2)

    func plan(animationRedrawIdentities: Set<Identity>) -> FrameTailRasterReusePlan {
      FrameTailPresentationDamageResolver.resolve(
        rootIdentity: sceneIdentity,
        placed: currentPlaced,
        draw: Self.drawTree(from: currentPlaced),
        retainedLayout: RetainedLayoutSession(
          previousFrameIndex: RetainedFrameIndex(
            frame: damageFrameArtifacts(placed: previousPlaced)
          ),
          invalidatedIdentities: [dirtyIdentity]
        ),
        previousDraw: Self.drawTree(from: previousPlaced),
        previousSurfaceTopology: SurfaceTopologySignature(placedRoot: previousPlaced),
        animationRedrawIdentities: animationRedrawIdentities
      )
    }

    // The fixture is otherwise incremental-eligible, so this test reds if the
    // guard is removed rather than vacuously passing on an unrelated barrier.
    let control = plan(animationRedrawIdentities: [])
    #expect(control.barriers.isEmpty)
    #expect(control.damage != nil)

    let animated = plan(animationRedrawIdentities: [dirtyIdentity])
    #expect(animated.damage == nil)
    #expect(animated.barriers == [.animationInterpolationApplied])
  }

  @Test("an animation-overlay-decorated frame barriers before any diff")
  func animationOverlayDecoratedFrameBarriers() throws {
    let sceneIdentity = testIdentity("App", "scene")
    let dirtyIdentity = testIdentity("App", "scene", "Layout[0]")

    func tree(dirtyRow: Int) -> PlacedNode {
      PlacedNode(
        identity: sceneIdentity,
        kind: .root,
        bounds: .init(origin: .zero, size: .init(width: 20, height: 6)),
        children: [
          PlacedNode(
            identity: dirtyIdentity,
            kind: .view("Text"),
            bounds: .init(origin: .init(x: 0, y: dirtyRow), size: .init(width: 20, height: 1))
          )
        ]
      )
    }

    let previousPlaced = tree(dirtyRow: 1)
    let currentPlaced = tree(dirtyRow: 2)

    func plan(overlaySnapshot: PlacedAnimationOverlaySnapshot) -> FrameTailRasterReusePlan {
      FrameTailPresentationDamageResolver.resolve(
        rootIdentity: sceneIdentity,
        placed: currentPlaced,
        draw: Self.drawTree(from: currentPlaced),
        retainedLayout: RetainedLayoutSession(
          previousFrameIndex: RetainedFrameIndex(
            frame: damageFrameArtifacts(placed: previousPlaced)
          ),
          invalidatedIdentities: [dirtyIdentity]
        ),
        previousDraw: Self.drawTree(from: previousPlaced),
        previousSurfaceTopology: SurfaceTopologySignature(placedRoot: previousPlaced),
        animationOverlaySnapshot: overlaySnapshot
      )
    }

    let control = plan(overlaySnapshot: .init())
    #expect(control.barriers.isEmpty)
    #expect(control.damage != nil)

    let decorated = plan(
      overlaySnapshot: .init(
        insertionOffsets: [.init(identity: dirtyIdentity, dx: 0, dy: 1)]
      )
    )
    #expect(decorated.damage == nil)
    #expect(decorated.barriers == [.animationOverlayDecorated])

    // Co-present matched-geometry adoption is steady-state decoration, not an
    // animation sample: it does not barrier (plan 2026-08-25-003 A3). The
    // draw-tree diff sees an adopted node's rect move like any bounds change.
    let adopted = plan(
      overlaySnapshot: .init(
        adoptionOffsets: [.init(identity: dirtyIdentity, dx: 0, dy: 1)]
      )
    )
    #expect(adopted.barriers.isEmpty)
    #expect(adopted.damage != nil)
  }
}

// MARK: - Shared fixture support

extension FrameTailPresentationDamageReachabilityTests {
  fileprivate func damageFrameArtifacts(
    placed: PlacedNode,
    resolved: ResolvedNode? = nil
  ) -> FrameArtifacts {
    FrameArtifacts(
      resolvedTree: resolved ?? Self.resolvedTree(from: placed),
      measuredTree: Self.measuredTree(from: placed),
      placedTree: placed,
      semanticSnapshot: .init(),
      drawTree: Self.drawTree(from: placed),
      rasterSurface: .init(),
      presentationDamage: nil,
      drawnIdentities: [],
      commitPlan: .init()
    )
  }

  fileprivate static func resolvedTree(from node: PlacedNode) -> ResolvedNode {
    ResolvedNode(
      identity: node.identity,
      kind: node.kind,
      children: node.children.map(resolvedTree(from:))
    )
  }

  fileprivate static func measuredTree(from node: PlacedNode) -> MeasuredNode {
    MeasuredNode(
      identity: node.identity,
      proposal: .unspecified,
      measuredSize: .zero,
      childMeasurements: node.children.map(measuredTree(from:))
    )
  }

  fileprivate static func drawTree(from node: PlacedNode) -> DrawNode {
    DrawNode(
      identity: node.identity,
      bounds: node.bounds,
      children: node.children.map(drawTree(from:))
    )
  }
}
