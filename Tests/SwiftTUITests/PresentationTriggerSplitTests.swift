import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Validates "Lever B" of the sheet-open re-architecture: the
/// ``PresentationTriggerLeaf`` split. A presentation modifier resolves its
/// background at a `base` child and emits the `isPresented` read from a zero-size
/// sibling trigger leaf, so the background is a disjoint sibling of the trigger
/// (neither ancestor nor descendant) and can be reused when `isPresented`
/// toggles (reader-attributed `@State` invalidation, now unconditional).
@MainActor
struct PresentationTriggerSplitTests {
  @Test("the trigger leaf is a disjoint sibling of the background")
  func triggerLeafIsDisjointSiblingOfBackground() throws {
    do {
      let renderer = DefaultRenderer()
      let artifacts = renderer.render(
        sheetTriggerRoot(isPresented: true),
        context: .init(identity: testIdentity("Root")),
        proposal: triggerProposal
      )

      let backgroundIdentity = try #require(
        artifacts.resolvedTree.descendant(withText: "Base probe")?.identity
      )
      let triggerIdentity = try #require(
        artifacts.resolvedTree.firstNode(ofKind: .view("__presentationTrigger"))?.identity
      )

      // The crux invariant: trigger and background are siblings, so toggling the
      // trigger never blocks the background from reuse (and vice versa).
      #expect(triggerIdentity != backgroundIdentity)
      #expect(!triggerIdentity.isDescendant(of: backgroundIdentity))
      #expect(!backgroundIdentity.isDescendant(of: triggerIdentity))

      // The overlay still reaches the portal through the new structure.
      #expect(artifacts.resolvedTree.descendant(withText: "Sheet body") != nil)
    }
  }

  @Test("reader-attributed: the background identity is stable across open/close")
  func backgroundIdentityStableAcrossToggle() throws {
    do {
      let renderer = DefaultRenderer()
      let rootIdentity = testIdentity("Root")

      @MainActor
      func backgroundIdentity(isPresented: Bool) throws -> Identity {
        let artifacts = renderer.render(
          sheetTriggerRoot(isPresented: isPresented),
          context: .init(identity: rootIdentity),
          proposal: triggerProposal
        )
        return try #require(
          artifacts.resolvedTree.descendant(withText: "Base probe")?.identity
        )
      }

      let initialIdentity = try backgroundIdentity(isPresented: false)
      let shownIdentity = try backgroundIdentity(isPresented: true)
      let dismissedIdentity = try backgroundIdentity(isPresented: false)

      // A *consistent* path-shift (the background lives at `.../base` whether or
      // not the sheet is open) preserves identity continuity; an inconsistent
      // one would flip the identity across the open boundary.
      #expect(shownIdentity == initialIdentity)
      #expect(dismissedIdentity == initialIdentity)
    }
  }

  @Test("reader-attributed: invalidating only the trigger leaf spares the background")
  func invalidatingTriggerSparesBackground() throws {
    do {
      let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
      let rootIdentity = testIdentity("ReuseRoot")

      // Frame 1 (closed): commit the background + trigger so a later toggle can
      // reuse the disjoint background.
      let closed = renderer.render(
        reuseProbe(isPresented: false),
        context: .init(identity: rootIdentity),
        proposal: triggerProposal
      )
      let triggerIdentity = try #require(
        closed.resolvedTree.firstNode(ofKind: .view("__presentationTrigger"))?.identity
      )

      // Frame 2 (open) with ONLY the trigger invalidated — exactly the set
      // reader-attribution produces, since the trigger is the sole reader of
      // `isPresented`. The disjoint background subtree must be reused.
      let opened = renderer.render(
        reuseProbe(isPresented: true),
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: [triggerIdentity]
        ),
        proposal: triggerProposal
      )
      #expect(opened.diagnostics.work.resolvedNodesReused > 0)
      let rendered = opened.rasterSurface.lines.joined(separator: "\n")
      #expect(rendered.contains("BG row 0"))
      #expect(opened.resolvedTree.descendant(withText: "Sheet body") != nil)
    }
  }

  @Test("invalidating the owner re-resolves the background (the cost Lever B avoids)")
  func invalidatingOwnerReResolvesBackground() throws {
    do {
      let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
      let rootIdentity = testIdentity("ReuseRoot")

      _ = renderer.render(
        reuseProbe(isPresented: false),
        context: .init(identity: rootIdentity),
        proposal: triggerProposal
      )
      // Owner-anchored invalidation dirties the root, an ancestor of the
      // background — so the background cannot be reused. This is the cost Lever B
      // removes by moving the `isPresented` read to the sibling trigger leaf.
      let opened = renderer.render(
        reuseProbe(isPresented: true),
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: [rootIdentity]
        ),
        proposal: triggerProposal
      )
      #expect(opened.diagnostics.work.resolvedNodesReused == 0)
    }
  }

  // MARK: - Popover trigger split (the same Lever B pattern, popover modifiers)

  @Test("popover: the trigger leaf is a disjoint sibling of the background")
  func popoverTriggerLeafIsDisjointSiblingOfBackground() throws {
    do {
      let renderer = DefaultRenderer()
      let artifacts = renderer.render(
        popoverTriggerRoot(isPresented: true),
        context: .init(identity: testIdentity("Root")),
        proposal: triggerProposal
      )

      let backgroundIdentity = try #require(
        artifacts.resolvedTree.descendant(withText: "Base probe")?.identity
      )
      let triggerIdentity = try #require(
        artifacts.resolvedTree.firstNode(ofKind: .view("__presentationTrigger"))?.identity
      )

      #expect(triggerIdentity != backgroundIdentity)
      #expect(!triggerIdentity.isDescendant(of: backgroundIdentity))
      #expect(!backgroundIdentity.isDescendant(of: triggerIdentity))
      #expect(artifacts.resolvedTree.descendant(withText: "Popover body") != nil)
    }
  }

  @Test("popover: invalidating only the trigger leaf spares the background")
  func popoverInvalidatingTriggerSparesBackground() throws {
    do {
      let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
      let rootIdentity = testIdentity("PopoverReuseRoot")

      let closed = renderer.render(
        popoverReuseProbe(isPresented: false),
        context: .init(identity: rootIdentity),
        proposal: triggerProposal
      )
      let triggerIdentity = try #require(
        closed.resolvedTree.firstNode(ofKind: .view("__presentationTrigger"))?.identity
      )

      let opened = renderer.render(
        popoverReuseProbe(isPresented: true),
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: [triggerIdentity]
        ),
        proposal: triggerProposal
      )
      #expect(opened.diagnostics.work.resolvedNodesReused > 0)
      let rendered = opened.rasterSurface.lines.joined(separator: "\n")
      #expect(rendered.contains("BG row 0"))
      #expect(opened.resolvedTree.descendant(withText: "Popover body") != nil)
    }
  }

  @Test("item popover: the trigger leaf owns the item read and the overlay presents")
  func itemPopoverTriggerLeafPresentsOverlay() throws {
    do {
      let renderer = DefaultRenderer()
      let artifacts = renderer.render(
        itemPopoverTriggerRoot(item: PopoverProbeItem(id: "alpha")),
        context: .init(identity: testIdentity("Root")),
        proposal: triggerProposal
      )

      #expect(
        artifacts.resolvedTree.firstNode(ofKind: .view("__presentationTrigger")) != nil
      )
      #expect(artifacts.resolvedTree.descendant(withText: "Item alpha") != nil)

      let dismissed = renderer.render(
        itemPopoverTriggerRoot(item: nil),
        context: .init(identity: testIdentity("Root")),
        proposal: triggerProposal
      )
      #expect(dismissed.resolvedTree.descendant(withText: "Item alpha") == nil)
    }
  }
}

private let triggerProposal = ProposedSize(width: .finite(40), height: .finite(10))

@MainActor
private func sheetTriggerRoot(
  isPresented: Bool
) -> some View {
  Text("Base probe")
    .sheet(
      "Inspector",
      isPresented: .constant(isPresented)
    ) {
      Text("Sheet body")
    }
    .frame(width: 40, height: 10, alignment: .topLeading)
}

@MainActor
private func reuseProbe(
  isPresented: Bool
) -> some View {
  VStack(alignment: .leading, spacing: 0) {
    ForEach(Array(0..<6), id: \.self) { row in
      Text("BG row \(row)")
    }
  }
  .sheet(
    "Inspector",
    isPresented: .constant(isPresented)
  ) {
    Text("Sheet body")
  }
  .frame(width: 40, height: 10, alignment: .topLeading)
}

@MainActor
private func popoverTriggerRoot(
  isPresented: Bool
) -> some View {
  Text("Base probe")
    .popover(isPresented: .constant(isPresented)) {
      Text("Popover body")
    }
    .frame(width: 40, height: 10, alignment: .topLeading)
}

private struct PopoverProbeItem: Identifiable, Sendable {
  let id: String
}

@MainActor
private func itemPopoverTriggerRoot(
  item: PopoverProbeItem?
) -> some View {
  Text("Base probe")
    .popover(item: .constant(item)) { item in
      Text("Item \(item.id)")
    }
    .frame(width: 40, height: 10, alignment: .topLeading)
}

@MainActor
private func popoverReuseProbe(
  isPresented: Bool
) -> some View {
  VStack(alignment: .leading, spacing: 0) {
    ForEach(Array(0..<6), id: \.self) { row in
      Text("BG row \(row)")
    }
  }
  .popover(isPresented: .constant(isPresented)) {
    Text("Popover body")
  }
  .frame(width: 40, height: 10, alignment: .topLeading)
}

extension ResolvedNode {
  fileprivate func descendant(
    withText text: String
  ) -> ResolvedNode? {
    if case .text(let value) = drawPayload, value == text {
      return self
    }
    for child in children {
      if let match = child.descendant(withText: text) {
        return match
      }
    }
    return nil
  }

  fileprivate func firstNode(
    ofKind kind: NodeKind
  ) -> ResolvedNode? {
    if self.kind == kind {
      return self
    }
    for child in children {
      if let match = child.firstNode(ofKind: kind) {
        return match
      }
    }
    return nil
  }
}
