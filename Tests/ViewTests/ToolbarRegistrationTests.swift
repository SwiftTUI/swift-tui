import Testing

@testable import Core
@testable import View

@MainActor
@Suite
struct ToolbarRegistrationTests {
  // MARK: - Single-item registration

  @Test("single free-form toolbar item surfaces in the preference value")
  func singleFreeFormItemSurfacesInPreference() {
    let context = makeContext("SingleItem")
    // An inner toolbar modifier that publishes via preferences, then
    // an outer reader that only inspects the resolved node. Since
    // the outermost modifier composes a VStack, we deliberately hoist
    // the toolbar modifier under a no-op outer modifier that sets
    // `isInsideToolbarHost = true` on children so the inner modifier
    // publishes-only and the preference value is visible on the
    // resolved node.
    let node =
      Text("Body")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Text("Save")
        }
      }
      .insideToolbarHost()
      .resolve(in: context)

    let records = node.preferenceValues[ToolbarItemsPreferenceKey.self].records
    #expect(records.count == 1)
    #expect(records[0].placement == .primaryAction)
    #expect(records[0].commandID == nil)
  }

  @Test("multiple items in one toolbar block appear in declaration order")
  func multipleItemsInDeclarationOrder() {
    let context = makeContext("MultipleItems")
    let node =
      Text("Body")
      .toolbar {
        ToolbarItem(placement: .status) { Text("Status") }
        ToolbarItem(placement: .secondaryAction) { Text("Secondary") }
        ToolbarItem(placement: .primaryAction) { Text("Primary") }
      }
      .insideToolbarHost()
      .resolve(in: context)

    let records = node.preferenceValues[ToolbarItemsPreferenceKey.self].records
    #expect(records.count == 3)
    #expect(records[0].placement == .status)
    #expect(records[1].placement == .secondaryAction)
    #expect(records[2].placement == .primaryAction)
  }

  @Test("nested .toolbar blocks flatten into one preference value, innermost first")
  func nestedToolbarsFlatten() {
    let context = makeContext("Nested")
    let node =
      Text("Body")
      .toolbar {
        ToolbarItem(placement: .status) { Text("Inner") }
      }
      .toolbar {
        ToolbarItem(placement: .primaryAction) { Text("Outer") }
      }
      .insideToolbarHost()
      .resolve(in: context)

    // Innermost-first matches ``CommandPreferenceKey`` and the help
    // strip's dedup convention (see
    // ``HelpStripDedupTests/dedupAppliedToResolvedTree``).
    let records = node.preferenceValues[ToolbarItemsPreferenceKey.self].records
    #expect(records.count == 2)
    if case .item = records[0].shape, case .item = records[1].shape {
      #expect(records[0].placement == .status)
      #expect(records[1].placement == .primaryAction)
    } else {
      Issue.record("Expected item shapes, got \(records.map(\.shape))")
    }
  }

  @Test("command-bound item stores the commandID in the record")
  func commandBoundItemStoresCommandID() {
    let context = makeContext("CommandBound")
    let node =
      Text("Body")
      .command(
        id: "save",
        title: "Save",
        key: .ctrl("s")
      ) {}
      .toolbar {
        ToolbarItem(.primaryAction, command: "save")
      }
      .insideToolbarHost()
      .resolve(in: context)

    let records = node.preferenceValues[ToolbarItemsPreferenceKey.self].records
    #expect(records.count == 1)
    #expect(records[0].commandID == "save")
    #expect(records[0].placement == .primaryAction)

    // The underlying command registration is on the same resolved
    // tree (written by `.command`) so a composition layer that reads
    // both keys can match them up.
    let commands = node.preferenceValues[CommandPreferenceKey.self].registrations
    #expect(commands.map(\.command.id).contains("save"))
  }

  @Test("command-bound item with unresolved id is still captured in the record")
  func unresolvedCommandIDIsCapturedInRecord() {
    // v1: the record is *kept* even for unresolved ids — the host
    // layer is responsible for silently omitting the render. This
    // gives Stage 5 space to change the policy (warn-at-debug,
    // surface an inline marker, etc.) without re-plumbing the
    // preference key.
    let context = makeContext("UnresolvedCommand")
    let node =
      Text("Body")
      .toolbar {
        ToolbarItem(.primaryAction, command: "does-not-exist")
      }
      .insideToolbarHost()
      .resolve(in: context)

    let records = node.preferenceValues[ToolbarItemsPreferenceKey.self].records
    #expect(records.count == 1)
    #expect(records[0].commandID == "does-not-exist")

    // No command registration exists for this id, so the
    // composition-time render step must omit it. That behavior is
    // pinned by ``ToolbarHostIntegrationTests`` in the TerminalUI
    // tests.
    let commands = node.preferenceValues[CommandPreferenceKey.self].registrations
    #expect(!commands.map(\.command.id).contains("does-not-exist"))
  }

  @Test("spacer entries reach the preference value as spacer records")
  func spacerEntriesReachPreferenceValue() {
    let context = makeContext("Spacer")
    let node =
      Text("Body")
      .toolbar {
        ToolbarItem(placement: .status) { Text("Left") }
        ToolbarSpacer(.flexible, placement: .secondaryAction)
        ToolbarItem(placement: .primaryAction) { Text("Right") }
      }
      .insideToolbarHost()
      .resolve(in: context)

    let records = node.preferenceValues[ToolbarItemsPreferenceKey.self].records
    #expect(records.count == 3)
    if case .spacer = records[1].shape {
      // ok
    } else {
      Issue.record("Expected middle entry to be a spacer, got \(records[1].shape)")
    }
  }
}

// MARK: - Helpers

@MainActor
private func makeContext(_ suffix: String) -> ResolveContext {
  var context = ResolveContext(
    identity: testIdentity("ToolbarRegistrationTests", suffix),
    applyEnvironmentValues: true
  )
  context.hotkeyRegistry = HotkeyRegistry()
  return context
}

/// A thin modifier used by these tests to flip the
/// ``EnvironmentValues/isInsideToolbarHost`` flag so an inner
/// `.toolbar { }` modifier publishes its records through the
/// preference channel without composing its own VStack. The flag
/// corresponds to the runtime wiring used by an outer composer
/// (`.toolbar { }` or `.help()`) in the real rendering pipeline.
extension View {
  fileprivate func insideToolbarHost() -> some View {
    InsideToolbarHostModifier(content: self)
  }
}

private struct InsideToolbarHostModifier<Content: View>: View, ResolvableView {
  var content: Content

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let innerContext = context.settingEnvironment(
      \.isInsideToolbarHost,
      to: true
    )
    return [content.resolve(in: innerContext)]
  }
}
