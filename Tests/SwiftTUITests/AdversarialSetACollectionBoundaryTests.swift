@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized, FailOnSoundnessViolationGrowth(), .timeLimit(.minutes(1)))
struct AdversarialSetACollectionBoundaryTests {
  @Test func setA501InitialCollectionFocusDoesNotInventAnOptionalSelection() throws {
    // Hypothesis: automatic row focus writes the first tag into an intentionally empty selection.
    var selected: Int?
    var writes = 0
    let h = try make("501") {
      List(
        [1, 2], id: \.self,
        selection: Binding(
          get: { selected },
          set: {
            selected = $0
            writes += 1
          })
      ) { Text("Optional row \($0)") }
    }
    defer { h.shutdown() }
    try h.focusText("Optional row 1")
    #expect(selected == nil && writes == 0)
    try h.clickText("Optional row 2")
    #expect(selected == 2 && writes == 1)
  }

  @Test func setA502MultipleSelectionSeparatesArrowCursorFromMembership() throws {
    // Hypothesis: keyboard cursor movement applies single-selection policy to a set-valued list.
    var selected: Set<Int> = [1]
    let h = try make("502") {
      List(
        [1, 2, 3], id: \.self,
        selection: Binding(get: { selected }, set: { selected = $0 })
      ) {
        Text("Multiple row \($0)")
      }
    }
    defer { h.shutdown() }
    try h.focusText("Multiple row 1")
    try h.pressKey(.init(.arrowDown))
    #expect(
      h.runLoop.focusTracker.currentFocusIdentity
        == (try h.focusIdentity(forText: "Multiple row 2")))
    #expect(selected == [1])
    try h.pressKey(.init(.space))
    #expect(selected == [1, 2])
    try h.pressKey(.init(.space))
    #expect(selected == [1])
  }

  @Test func setA503NestedRowButtonConsumesItsInputBeforeCollectionSelection() throws {
    // Hypothesis: descendant control activation falls through to the enclosing row selection action.
    var selected: Int? = 1
    var actions: [Int] = []
    let h = try make("503") {
      List(
        [1, 2], id: \.self,
        selection: Binding(get: { selected }, set: { selected = $0 })
      ) { id in
        HStack {
          Text("Row background \(id)")
          Button("Inspect record \(id)") { actions.append(id) }
        }
      }
    }
    defer { h.shutdown() }
    try h.clickText("Inspect record 2")
    #expect(actions == [2])
    #expect(selected == 1)
    try h.focusText("Inspect record 2")
    try h.pressKey(.init(.return))
    #expect(actions == [2, 2])
    #expect(selected == 1)
  }

  @Test func setA504AmbiguousRowTagsCannotBecomeNavigationCandidates() throws {
    // Hypothesis: a row with two authored tags silently selects one instead of remaining unselectable.
    var selected = 1
    let h = try make("504") {
      List(selection: Binding(get: { selected }, set: { selected = $0 })) {
        Text("Valid first").tag(1)
        HStack {
          Text("Ambiguous left").tag(2)
          Text("Ambiguous right").tag(3)
        }
        Text("Valid last").tag(4)
      }
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("Ambiguous left") && h.frame.contains("Ambiguous right"))
    try h.focusText("Valid first")
    try h.pressKey(.init(.arrowDown))
    #expect(selected == 4)
    try h.clickText("Ambiguous left")
    #expect(selected == 4)
  }

  @Test func setA505RejectedSelectionWritesDoNotPublishOptimisticMembership() throws {
    // Hypothesis: assistive row selection paints a proposed value after its binding rejects the write.
    var attempts: [Int?] = []
    let h = try make("505") {
      List(
        [1, 2], id: \.self,
        selection: Binding<Int?>(get: { 1 }, set: { attempts.append($0) })
      ) {
        Text("Rejected row \($0)")
      }
    }
    defer { h.shutdown() }
    try send(.activate, to: "Select row 2", in: h)
    #expect(attempts == [2])
    #expect(try node("Select row 1", in: h).control?.value == .boolean(true))
    #expect(try node("Select row 2", in: h).control?.value == .boolean(false))
  }

  @Test func setA506ActivatingCurrentRowDoesNotRewriteTheSelectionBinding() throws {
    // Hypothesis: Return conflates activation with a redundant write of the already-selected tag.
    var selected = 2
    var writes = 0
    var activations: [Int] = []
    let h = try make("506") {
      List(
        selection: Binding(
          get: { selected },
          set: {
            selected = $0
            writes += 1
          }), onActivate: { activations.append($0) }
      ) {
        Text("Activate first").tag(1)
        Text("Activate second").tag(2)
      }
    }
    defer { h.shutdown() }
    try h.focusText("Activate second")
    try h.pressKey(.init(.return))
    #expect(activations == [2])
    #expect(selected == 2 && writes == 0)
  }

  @Test func setA507WheelScrollingCannotChangeTheCollectionSelection() throws {
    // Hypothesis: viewport advancement leaks its anchor row into the application's selection binding.
    var selected: Int? = 0
    var writes = 0
    let h = try make("507", height: 8) {
      List(
        0..<200, id: \.self,
        selection: Binding(
          get: { selected },
          set: {
            selected = $0
            writes += 1
          })
      ) { Text("Wheel record \($0)") }
    }
    defer { h.shutdown() }
    let before = h.frame
    let point = try #require(h.point(forText: "Wheel record 0"))
    try h.scrollPointer(at: point, deltaY: 8)
    try #require(h.frame != before, "\(h.frame)")
    #expect(selected == 0 && writes == 0)
  }

  @Test func setA508TableAutomaticWidthsKeepTheirHighWaterAcrossViewportChanges() throws {
    // Hypothesis: recycling a wide row forgets discovered auto-column width despite stable source IDs.
    let h = try make("508", height: 8) {
      Table(0..<200, id: \.self, columns: [.init("Value"), .init("Suffix", width: 8)]) { id in
        Text(id == 199 ? "ABCDEFGHIJKLMNOPQRSTUVWX" : "x")
        Text("MARK")
      }
    }
    defer { h.shutdown() }
    let narrow = try #require(h.point(forText: "MARK")).x
    try send(.custom("Last item"), to: "Review items", in: h)
    try #require(h.frame.contains("ABCDEFGHIJKLMNOPQRSTUVWX"), "\(h.frame)")
    let wide = try #require(h.point(forText: "MARK")).x
    #expect(wide > narrow)
    try send(.custom("First item"), to: "Review items", in: h)
    try #require(!h.frame.contains("ABCDEFGHIJKLMNOPQRSTUVWX"))
    #expect(try #require(h.point(forText: "MARK")).x == wide, "\(h.frame)")
  }

  @Test func setA509AuthoredMultilineTableCellsOverrideTheDefaultLineLimit() throws {
    // Hypothesis: the hosted cell wrapper overwrites an authored line limit with the table default.
    let h = try make("509") {
      Table([0, 1], id: \.self, columns: [.init("Value", width: 10)]) { id in
        if id == 0 {
          Text("top\nmiddle\nbottom").lineLimit(2)
        } else {
          Text("following")
        }
      }
    }
    defer { h.shutdown() }
    let middle = try #require(h.point(forText: "middle"), "\(h.frame)")
    let following = try #require(h.point(forText: "following"), "\(h.frame)")
    #expect(following.y > middle.y)
    #expect(!h.frame.contains("bottom"), "\(h.frame)")
  }

  @Test func setA510LiveTableColumnAlignmentReplacesRetainedCellGeometry() throws {
    // Hypothesis: stable row membership reuses a cell frame with an obsolete column alignment.
    var trailing = false
    let h = try make("510") {
      Table(
        [1], id: \.self,
        columns: [.init("Value", width: 12, alignment: trailing ? .trailing : .leading)]
      ) { _ in
        Text("x")
      }
    }
    defer { h.shutdown() }
    let before = try #require(h.point(forText: "x"))
    trailing = true
    try h.renderAfterExternalMutation()
    let after = try #require(h.point(forText: "x"))
    #expect(after.x == before.x + 11 && after.y == before.y, "\(h.frame)")
  }

  @Test func setA511TableColumnSemanticRolesFollowLiveAuthoredMetadata() throws {
    // Hypothesis: unchanged column titles retain stale sort direction and row-header attribution.
    var changed = false
    let h = try make("511") {
      Table(
        [1], id: \.self,
        columns: [
          .init("Name", width: 10, sort: changed ? .descending : .ascending, isRowHeader: !changed),
          .init("Code", width: 10, isRowHeader: changed),
        ]
      ) { _ in
        Text("Ada")
        Text("A1")
      }
    }
    defer { h.shutdown() }
    try #require(try node("Name", role: .columnHeader, in: h).properties?.sort == .ascending)
    changed = true
    try h.renderAfterExternalMutation()
    #expect(try node("Name", role: .columnHeader, in: h).properties?.sort == .descending)
    let rowHeaders = nodes(in: h).filter { $0.role == .rowHeader }
    #expect(rowHeaders.count == 1)
    #expect(rowHeaders.first?.properties?.columnIndex == 2)
  }

  @Test func setA512FreshTableButtonsKeepTheirPublishedActivationHandlers() throws {
    // Hypothesis: table cell presentation wrappers retire a freshly resolved button's action owner.
    let showsTemporary = true
    var events: [String] = []
    do {
      var controlEvents: [String] = []
      let control = try make("512-control") {
        HStack {
          Button("Retained cell") { controlEvents.append("retained") }
          if showsTemporary { Button("Temporary cell") { controlEvents.append("temporary") } }
        }
      }
      defer { control.shutdown() }
      let target = try node("Temporary cell", role: .button, in: control)
      let identity = try #require(target.actionIdentity)
      try #require(control.runLoop.localActionRegistry.hasActivationHandler(identity: identity))
      try send(.activate, to: "Temporary cell", role: .button, in: control)
      try #require(controlEvents == ["temporary"])
    }
    let h = try make("512") {
      Table(columns: [.init("Keep", width: 20), .init("Remove", width: 20)]) {
        TableRow {
          Button("Retained cell") { events.append("retained") }
          if showsTemporary { Button("Temporary cell") { events.append("temporary") } }
        }
      }
    }
    defer { h.shutdown() }
    // A structural table cell can carry the same accessible name as its authored button.
    let initial = try node("Temporary cell", role: .button, in: h)
    try #require(initial.control?.actions.contains(.activate) == true)
    let initialTarget = try #require(initial.actionTarget)
    let initialIdentity = try #require(initial.actionIdentity)
    let registered = h.runLoop.localActionRegistry.hasActivationHandler(identity: initialIdentity)
    let registrations = h.runLoop.localActionRegistry.snapshot()
    let registrationPaths = registrations.keys.map(\.path).sorted().prefix(8)
    let initialResult = h.runLoop.handleAccessibilityAction(
      .init(target: initialTarget, action: .activate))
    try h.render()
    withKnownIssue("STUI-993: eager Table presentation loses the published button registration") {
      #expect(
        initialResult == .accepted && events == ["temporary"],
        "Initial button result=\(initialResult), events=\(events), identity=\(initialIdentity.path), activationRegistered=\(registered), registryCount=\(registrations.count), registryPrefix=\(registrationPaths)"
      )
    }
  }

  @Test func setA513OutlineCollapseUsesTheFullAncestralPath() throws {
    // Hypothesis: equal child IDs beneath different parents share a disclosure-state entry.
    let records = [
      SetACollectionNode(
        1, "Left root", children: [.init(7, "Shared left", children: [.init(8, "Left leaf")])]),
      SetACollectionNode(
        2, "Right root", children: [.init(7, "Shared right", children: [.init(9, "Right leaf")])]),
    ]
    let h = try make("513") {
      OutlineGroup(records, children: \.children) { Text($0.name) }
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("Left leaf") && h.frame.contains("Right leaf"))
    try send(.activate, to: "Collapse item 1 at level 2", in: h)
    #expect(!h.frame.contains("Left leaf"), "\(h.frame)")
    #expect(h.frame.contains("Right leaf"), "\(h.frame)")
    try send(.activate, to: "Expand item 1 at level 2", in: h)
    #expect(h.frame.contains("Left leaf") && h.frame.contains("Right leaf"), "\(h.frame)")
  }

  @Test func setA514OutlineBranchToLeafRetiresTheDisclosureRoute() throws {
    // Hypothesis: stable node identity keeps a disclosure button after its last child disappears.
    var records = [SetACollectionNode(1, "Changing branch", children: [.init(2, "Departing leaf")])]
    let h = try make("514") {
      OutlineGroup(records, children: \.children) { Text($0.name) }
    }
    defer { h.shutdown() }
    let retired = try #require(try node("Collapse item 1 at level 1", in: h).actionTarget)
    records[0].children = []
    try h.renderAfterExternalMutation()
    #expect(h.frame.contains("Changing branch") && !h.frame.contains("Departing leaf"))
    #expect(
      !nodes(in: h).contains {
        $0.label == "Collapse item 1 at level 1" || $0.label == "Expand item 1 at level 1"
      })
    #expect(
      h.runLoop.handleAccessibilityAction(.init(target: retired, action: .activate)) == .staleTarget
    )
  }

  @Test func setA515OutlineDisclosureStateOutlivesItsRealizedRowWindow() throws {
    // Hypothesis: offscreen row retirement owns and erases the outline's collapsed-path state.
    let records = (0..<100).map {
      SetACollectionNode($0, "Parent \($0)", children: [.init(1000 + $0, "Leaf \($0)")])
    }
    let h = try make("515", height: 8) {
      List { OutlineGroup(records, children: \.children) { Text($0.name) } }
    }
    defer { h.shutdown() }
    try send(.activate, to: "Collapse item 1 at level 1", in: h)
    try #require(!h.frame.contains("Leaf 0"))
    try send(.custom("Last item"), to: "Review items", in: h)
    try #require(h.frame.contains("Leaf 99"), "\(h.frame)")
    try send(.custom("First item"), to: "Review items", in: h)
    #expect(nodes(in: h).contains { $0.label == "Expand item 1 at level 1" })
    #expect(!h.frame.contains("Leaf 0"), "\(h.frame)")
    try send(.activate, to: "Expand item 1 at level 1", in: h)
    #expect(h.frame.contains("Leaf 0"), "\(h.frame)")
  }

  @Test func setA516DirectHierarchicalListPublishesExactlyOneEffectiveRowTag() throws {
    // Hypothesis: the List adapter and OutlineGroup each tag a row, making valid automatic selection ambiguous.
    let records = [SetACollectionNode(1, "Tagged parent", children: [.init(2, "Tagged child")])]
    var selected = 1
    let h = try make("516") {
      List(
        records, selection: Binding(get: { selected }, set: { selected = $0 }), children: \.children
      ) {
        Text($0.name)
      }
    }
    defer { h.shutdown() }
    try send(.activate, to: "Select row 2", in: h)
    #expect(selected == 2)
    #expect(try node("Select row 2", in: h).control?.value == .boolean(true))
  }

  @Test func setA517ReparentedOutlineNodesPublishCurrentHierarchyOrdinals() throws {
    // Hypothesis: a moved data node keeps level and sibling metadata from its former ancestral path.
    let moving = SetACollectionNode(3, "Moving record")
    var records = [
      SetACollectionNode(1, "First root", children: [moving]), .init(2, "Second root"),
    ]
    let h = try make("517") {
      List { OutlineGroup(records, children: \.children) { Text($0.name) } }
    }
    defer { h.shutdown() }
    let before = try item(containing: "Moving record", in: h)
    try #require(before.properties?.level == 2 && before.properties?.positionInSet == 1)
    records = [.init(1, "First root"), .init(2, "Second root"), moving]
    try h.renderAfterExternalMutation()
    let after = try item(containing: "Moving record", in: h)
    #expect(after.properties?.level == 1)
    #expect(after.properties?.positionInSet == 3 && after.properties?.setSize == 3)
  }

  @Test func setA518DisabledDisclosureCannotWriteItsExpansionBinding() throws {
    // Hypothesis: a disabled disclosure retains a semantic activation path that bypasses enabled policy.
    var expanded = false
    var enabled = false
    var writes = 0
    let h = try make("518") {
      DisclosureGroup(
        "Guarded disclosure",
        isExpanded: Binding(
          get: { expanded },
          set: {
            expanded = $0
            writes += 1
          })
      ) { Text("Guarded contents") }.disabled(!enabled)
    }
    defer { h.shutdown() }
    let disabled = try #require(try node("Guarded disclosure", in: h).actionTarget)
    #expect(
      h.runLoop.handleAccessibilityAction(.init(target: disabled, action: .activate)) == .disabled)
    try h.render()
    #expect(!expanded && writes == 0 && !h.frame.contains("Guarded contents"))
    enabled = true
    try h.renderAfterExternalMutation()
    try send(.activate, to: "Guarded disclosure", in: h)
    #expect(expanded && writes == 1 && h.frame.contains("Guarded contents"))
  }

  @Test func setA519IdempotentDisclosureSetValueDoesNotRepeatBindingEffects() throws {
    // Hypothesis: semantic setValue is implemented as activation and rewrites an unchanged expansion.
    var expanded = true
    var writes = 0
    let h = try make("519") {
      DisclosureGroup(
        "Explicit disclosure",
        isExpanded: Binding(
          get: { expanded },
          set: {
            expanded = $0
            writes += 1
          })
      ) { Text("Explicit contents") }
    }
    defer { h.shutdown() }
    try send(.setValue(.boolean(true)), to: "Explicit disclosure", in: h)
    #expect(expanded && writes == 0)
    try send(.setValue(.boolean(false)), to: "Explicit disclosure", in: h)
    try #require(!expanded && writes == 1)
    try send(.setValue(.boolean(false)), to: "Explicit disclosure", in: h)
    #expect(!expanded && writes == 1)
  }

  @Test func setA520EmptyLazyFragmentsDoNotConsumeInterChildSpacing() throws {
    // Hypothesis: logical ForEach entries that resolve empty still contribute lazy-stack spacing.
    let h = try make("520") {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          Text("HEAD")
          ForEach(0..<5, id: \.self) { id in
            if id == 2 { Text("MIDDLE") }
          }
          Text("TAIL")
        }
      }
    }
    defer { h.shutdown() }
    let head = try #require(h.point(forText: "HEAD"))
    let middle = try #require(h.point(forText: "MIDDLE"))
    let tail = try #require(h.point(forText: "TAIL"))
    #expect(middle.y - head.y == 3 && tail.y - middle.y == 3, "\(h.frame)")
  }

  @Test func setA521OffscreenLazyRowsDoNotPublishAppearanceBeforeRealization() async throws {
    // Hypothesis: enumerating lazy source membership runs lifecycle callbacks for unmounted rows.
    let probe = SetACollectionLifecycleProbe()
    let h = try make("521", height: 10) { SetALazyAppearanceFixture(probe: probe) }
    defer { h.shutdown() }
    await probe.appearancesChanged.wait(until: { probe.appeared.contains(0) })
    try Task.checkCancellation()
    #expect(!probe.appeared.contains(499))
    try h.clickText("Reveal last lifecycle")
    await probe.appearancesChanged.wait(until: { probe.appeared.contains(499) })
    try Task.checkCancellation()
    #expect(h.frame.contains("Lifecycle row 499"), "\(h.frame)")
    #expect(probe.appeared.count < 100)
  }

  @Test func setA522HorizontalLazyScrollTargetRetainsTheCorrectActionOwner() throws {
    // Hypothesis: horizontal composed-source target lookup lands on a neighboring row's action route.
    let probe = SetACollectionLifecycleProbe()
    let h = try make("522", width: 50, height: 8) { SetAHorizontalCollectionFixture(probe: probe) }
    defer { h.shutdown() }
    try #require(!h.frame.contains("Entry 499"))
    try h.clickText("Reveal last action")
    try #require(h.frame.contains("Entry 499"), "\(h.frame)")
    try h.clickText("Entry 499")
    #expect(probe.actions == [499])
  }

  @Test func setA523EmptySectionChromeCannotBecomeLogicalListRows() throws {
    // Hypothesis: empty section headers and footers enter the selectable row ordinal space.
    var populated = false
    let h = try make("523") {
      List(selection: Binding<Int>.constant(2)) {
        Section {
          if populated { Text("Inserted section record").tag(1) }
        } header: {
          Text("First header")
        } footer: {
          Text("First footer")
        }
        Section("Second header") { Text("Existing section record").tag(2) }
      }
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("First header") && h.frame.contains("First footer"))
    let initial = nodes(in: h).filter { $0.role == .custom("listitem") }
    try #require(initial.count == 1)
    #expect(
      initial.first?.properties?.positionInSet == 1 && initial.first?.properties?.setSize == 1)
    populated = true
    try h.renderAfterExternalMutation()
    let populatedItems = nodes(in: h).filter { $0.role == .custom("listitem") }
    #expect(populatedItems.count == 2)
    #expect(populatedItems.map { $0.properties?.positionInSet } == [1, 2])
    #expect(populatedItems.allSatisfy { $0.properties?.setSize == 2 })
    #expect(
      populatedItems.map { $0.properties?.description } == [
        "First header, item 1 of 1", "Second header, item 1 of 1",
      ])
    #expect(try node("Select row 2", in: h).control?.value == .boolean(true))
  }

  @Test func setA524CollectionReviewBookmarksRoundTripWithoutSelectionWrites() throws {
    // Hypothesis: returning to an assistive review bookmark changes selection or loses the return leg.
    var selected: Int?
    var writes = 0
    let h = try make("524", height: 8) {
      List(
        0..<1000, id: \.self,
        selection: Binding(
          get: { selected },
          set: {
            selected = $0
            writes += 1
          })
      ) { Text("Reviewed record \($0)") }
    }
    defer { h.shutdown() }
    try send(.setValue(.number(900)), to: "Review items", in: h)
    try send(.setValue(.number(45)), to: "Review items", in: h)
    try send(.custom("Return to previous item"), to: "Review items", in: h)
    #expect(try node("Review items", in: h).control?.value == .number(900))
    #expect(h.frame.contains("Reviewed record 899"), "\(h.frame)")
    try send(.custom("Return to previous item"), to: "Review items", in: h)
    #expect(try node("Review items", in: h).control?.value == .number(45))
    #expect(h.frame.contains("Reviewed record 44"), "\(h.frame)")
    #expect(selected == nil && writes == 0)
  }

  @Test func setA525FractionalReviewOrdinalsCannotMutateTheCurrentBookmark() throws {
    // Hypothesis: a fractional host ordinal is truncated to an index before validation and mutates review.
    let h = try make("525", height: 8) {
      List(0..<100, id: \.self) { Text("Ordinal record \($0)") }
    }
    defer { h.shutdown() }
    try send(.setValue(.number(50)), to: "Review items", in: h)
    let before = h.frame
    let target = try #require(try node("Review items", in: h).actionTarget)
    #expect(
      h.runLoop.handleAccessibilityAction(.init(target: target, action: .setValue(.number(50.5))))
        == .invalidValue)
    try h.render()
    #expect(try node("Review items", in: h).control?.value == .number(50))
    #expect(h.frame == before)
    try send(.custom("Return to previous item"), to: "Review items", in: h)
    #expect(try node("Review items", in: h).control?.value == .number(1))
  }

  private func make<V: View>(
    _ id: String, width: Int = 80, height: Int = 20,
    @ViewBuilder content: @escaping () -> V
  ) throws -> StressRuntimeHarness<V> {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetACollectionBoundary", id),
      size: .init(width: width, height: height), content: content)
  }

  private func nodes<V: View>(in h: StressRuntimeHarness<V>) -> [AccessibilityNode] {
    h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes
  }

  private func node<V: View>(
    _ label: String, role: AccessibilityRole? = nil,
    in h: StressRuntimeHarness<V>
  ) throws -> AccessibilityNode {
    try #require(
      nodes(in: h).first { $0.label == label && (role == nil || $0.role == role) },
      "Missing semantic node \(label); frame:\n\(h.frame)")
  }

  private func item<V: View>(containing text: String, in h: StressRuntimeHarness<V>) throws
    -> AccessibilityNode
  {
    let snapshot = nodes(in: h)
    var current = snapshot.first { $0.label?.contains(text) == true }
    var result: AccessibilityNode?
    for _ in 0..<snapshot.count {
      guard let candidate = current else { break }
      if candidate.role == .custom("listitem") {
        result = candidate
        break
      }
      current = candidate.parentIdentity.flatMap { parent in
        snapshot.first { $0.identity == parent }
      }
    }
    return try #require(
      result,
      "Missing list item \(text); nodes=\(snapshot.map { $0.label }); frame:\n\(h.frame)")
  }

  private func send<V: View>(
    _ action: AccessibilityAction, to label: String, role: AccessibilityRole? = nil,
    in h: StressRuntimeHarness<V>
  ) throws {
    let target = try #require(try node(label, role: role, in: h).actionTarget)
    #expect(h.runLoop.handleAccessibilityAction(.init(target: target, action: action)) == .accepted)
    try h.render()
  }
}

private struct SetACollectionNode: Identifiable {
  let id: Int
  let name: String
  var children: [SetACollectionNode]

  init(_ id: Int, _ name: String, children: [SetACollectionNode] = []) {
    self.id = id
    self.name = name
    self.children = children
  }
}

@MainActor
private final class SetACollectionLifecycleProbe {
  let appearancesChanged = MainActorConditionSignal()
  var appeared: Set<Int> = [] { didSet { appearancesChanged.notify() } }
  var actions: [Int] = []
}

@MainActor
private struct SetALazyAppearanceFixture: View {
  let probe: SetACollectionLifecycleProbe
  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        Button("Reveal last lifecycle") { proxy.scrollTo(499, anchor: .top) }
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<500, id: \.self) { id in
              Text("Lifecycle row \(id)").onAppear { probe.appeared.insert(id) }
            }
          }
        }
      }
    }
  }
}

@MainActor
private struct SetAHorizontalCollectionFixture: View {
  let probe: SetACollectionLifecycleProbe
  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        Button("Reveal last action") { proxy.scrollTo(499, anchor: .leading) }
        ScrollView(.horizontal) {
          LazyHStack(spacing: 1) {
            Text("Prefix")
            ForEach(0..<500, id: \.self) { id in
              Button("Entry \(id)") { probe.actions.append(id) }.frame(width: 14)
            }
          }
        }
      }
    }
  }
}
