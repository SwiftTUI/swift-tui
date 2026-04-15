import Testing

@testable import Core
@testable import View

@MainActor
@Suite
struct HelpStripDedupTests {
  // MARK: - Pure dedup function

  @Test("a single command is preserved unchanged")
  func singleCommandPreserved() {
    let registrations = [
      makeRegistration(id: "save", title: "Save", key: .ctrl("s"))
    ]
    let deduped = helpStripDedupedRegistrations(
      viewLevel: registrations,
      sceneLevel: []
    )
    #expect(deduped.count == 1)
    #expect(deduped[0].command.id == "save")
    #expect(deduped[0].command.title == "Save")
  }

  @Test("keyless commands are filtered out of the strip")
  func keylessCommandsFiltered() {
    let registrations = [
      makeRegistration(id: "unbound", title: "No Key", key: nil),
      makeRegistration(id: "save", title: "Save", key: .ctrl("s")),
    ]
    let deduped = helpStripDedupedRegistrations(
      viewLevel: registrations,
      sceneLevel: []
    )
    #expect(deduped.count == 1)
    #expect(deduped[0].command.id == "save")
  }

  @Test("two distinct ids sharing the same key are both kept")
  func distinctIDsSameKeyBothKept() {
    let registrations = [
      makeRegistration(id: "a", title: "A", key: .ctrl("x")),
      makeRegistration(id: "b", title: "B", key: .ctrl("x")),
    ]
    let deduped = helpStripDedupedRegistrations(
      viewLevel: registrations,
      sceneLevel: []
    )
    #expect(deduped.count == 2)
    #expect(deduped.map(\.command.id) == ["a", "b"])
  }

  @Test("duplicate ids within view-level resolve innermost-wins (first)")
  func duplicateIDsInViewLevelKeepInnermost() {
    // Reflects the order produced by view-level `.command` nesting:
    // the innermost modifier resolves first and thus appears earlier
    // in the flat reduction.
    let registrations = [
      makeRegistration(id: "quit", title: "Close Document", key: .ctrl("q")),
      makeRegistration(id: "quit", title: "Quit", key: .ctrl("q")),
    ]
    let deduped = helpStripDedupedRegistrations(
      viewLevel: registrations,
      sceneLevel: []
    )
    #expect(deduped.count == 1)
    #expect(deduped[0].command.title == "Close Document")
  }

  @Test("view-level commands override same-id scene-level commands")
  func viewLevelOverridesSceneLevel() {
    // View-level (innermost) wins over scene-level (outermost).
    let viewLevel = [
      makeRegistration(id: "quit", title: "Close Document", key: .ctrl("q"))
    ]
    let sceneLevel = [
      makeRegistration(id: "quit", title: "Quit", key: .ctrl("q"))
    ]
    let deduped = helpStripDedupedRegistrations(
      viewLevel: viewLevel,
      sceneLevel: sceneLevel
    )
    #expect(deduped.count == 1)
    #expect(deduped[0].command.title == "Close Document")
  }

  @Test("scene-level commands not shadowed by view-level are still kept")
  func nonShadowedSceneLevelKept() {
    let viewLevel = [
      makeRegistration(id: "save", title: "Save", key: .ctrl("s"))
    ]
    let sceneLevel = [
      makeRegistration(id: "quit", title: "Quit", key: .ctrl("q"))
    ]
    let deduped = helpStripDedupedRegistrations(
      viewLevel: viewLevel,
      sceneLevel: sceneLevel
    )
    #expect(deduped.count == 2)
    #expect(deduped.map(\.command.id) == ["save", "quit"])
  }

  @Test("keyless override does not shadow a keyed parent entry")
  func keylessOverrideDoesNotShadow() {
    // If the innermost command is keyless, it's filtered BEFORE
    // dedup runs — so a keyed outer entry with the same id should
    // still surface in the strip.
    let registrations = [
      makeRegistration(id: "save", title: "Save (no key)", key: nil),
      makeRegistration(id: "save", title: "Save", key: .ctrl("s")),
    ]
    let deduped = helpStripDedupedRegistrations(
      viewLevel: registrations,
      sceneLevel: []
    )
    #expect(deduped.count == 1)
    #expect(deduped[0].command.title == "Save")
    #expect(deduped[0].command.key == .ctrl("s"))
  }

  // MARK: - End-to-end via resolution

  @Test("innermost-wins dedup applied to actual resolved preference values")
  func dedupAppliedToResolvedTree() {
    var context = ResolveContext(
      identity: testIdentity("HelpStripDedupTests", "Resolved"),
      applyEnvironmentValues: true
    )
    context.hotkeyRegistry = HotkeyRegistry()

    // Two `.command(id: "quit", ...)` calls nested: the innermost one
    // ("Close Document") is applied first (closer to Text), the outer
    // one ("Quit") is applied on top. The reduced preference value at
    // the top of the chain should list them in [inner, outer] order.
    let node =
      Text("Body")
      .command(
        id: "quit",
        title: "Close Document",
        key: .ctrl("q")
      ) {}
      .command(
        id: "quit",
        title: "Quit",
        key: .ctrl("q")
      ) {}
      .resolve(in: context)

    let registrations = node.preferenceValues[CommandPreferenceKey.self].registrations
    #expect(registrations.count == 2)
    #expect(registrations[0].command.title == "Close Document")
    #expect(registrations[1].command.title == "Quit")

    let deduped = helpStripDedupedRegistrations(
      viewLevel: registrations,
      sceneLevel: []
    )
    #expect(deduped.count == 1)
    #expect(deduped[0].command.title == "Close Document")
  }
}

// MARK: - Helpers

@MainActor
private func makeRegistration(
  id: String,
  title: String,
  key: KeyPress?,
  group: String? = nil
) -> CommandRegistration {
  CommandRegistration(
    command: Command(
      id: id,
      title: title,
      key: key,
      group: group
    ),
    action: nil
  )
}
