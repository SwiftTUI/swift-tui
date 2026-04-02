import Testing

@testable import Core
@testable import TerminalUI
@testable import View

private enum StringListPreferenceKey: PreferenceKey {
  static let defaultValue: [String] = []

  static func reduce(
    value: inout [String],
    nextValue: () -> [String]
  ) {
    value.append(contentsOf: nextValue())
  }
}

private enum OptionalStringPreferenceKey: PreferenceKey {
  static let defaultValue: String? = nil

  static func reduce(
    value: inout String?,
    nextValue: () -> String?
  ) {
    value = nextValue() ?? value
  }
}

@Suite
struct PreferenceSurfaceTests {
  @Test("preferences reduce in view-tree order across sibling subtrees")
  @MainActor
  func preferencesReduceInViewTreeOrderAcrossSiblingSubtrees() {
    let resolved = Resolver().resolve(
      VStack(alignment: .leading, spacing: 1) {
        Text("First")
          .preference(key: StringListPreferenceKey.self, value: ["first"])
        Group {
          Text("Second")
            .preference(key: StringListPreferenceKey.self, value: ["second"])
          Text("Third")
            .preference(key: StringListPreferenceKey.self, value: ["third"])
        }
      },
      in: .init(identity: testIdentity("Root"))
    )

    #expect(
      resolved.preferenceValues[StringListPreferenceKey.self] == [
        "first",
        "second",
        "third",
      ]
    )
  }

  @Test("preference modifier order stays faithful for writes and transforms")
  @MainActor
  func preferenceModifierOrderStaysFaithful() {
    let writeThenTransform = Resolver().resolve(
      Text("Probe")
        .preference(key: StringListPreferenceKey.self, value: ["write"])
        .transformPreference(StringListPreferenceKey.self) { value in
          value.append("transform")
        },
      in: .init(identity: testIdentity("WriteThenTransform"))
    )

    let transformThenWrite = Resolver().resolve(
      Text("Probe")
        .transformPreference(StringListPreferenceKey.self) { value in
          value.append("transform")
        }
        .preference(key: StringListPreferenceKey.self, value: ["write"]),
      in: .init(identity: testIdentity("TransformThenWrite"))
    )

    #expect(
      writeThenTransform.preferenceValues[StringListPreferenceKey.self] == [
        "write",
        "transform",
      ]
    )
    #expect(
      transformThenWrite.preferenceValues[StringListPreferenceKey.self] == [
        "transform",
        "write",
      ]
    )
  }

  @Test("overlayPreferenceValue reads the base subtree value and combines overlay preferences")
  @MainActor
  func overlayPreferenceValueReadsBaseSubtreeAndCombinesOverlayPreferences() throws {
    let resolved = Resolver().resolve(
      Text("Base")
        .preference(key: StringListPreferenceKey.self, value: ["base"])
        .overlayPreferenceValue(StringListPreferenceKey.self) { values in
          Text(values.joined(separator: "+"))
            .preference(key: StringListPreferenceKey.self, value: ["overlay"])
        },
      in: .init(identity: testIdentity("OverlayPreferenceRoot"))
    )

    #expect(resolved.kind == .view("Overlay"))
    #expect(resolved.children.count == 2)
    #expect(
      resolved.preferenceValues[StringListPreferenceKey.self] == [
        "base",
        "overlay",
      ]
    )
    #expect(try textPayload(of: resolved.children[1]) == "base")
  }

  @Test(
    "backgroundPreferenceValue reads the base subtree value and keeps both preference sources visible"
  )
  @MainActor
  func backgroundPreferenceValueReadsBaseSubtreeAndKeepsCombinedPreferences() throws {
    let resolved = Resolver().resolve(
      Text("Base")
        .preference(key: StringListPreferenceKey.self, value: ["base"])
        .backgroundPreferenceValue(StringListPreferenceKey.self) { values in
          Text(values.joined(separator: "+"))
            .preference(key: StringListPreferenceKey.self, value: ["background"])
        },
      in: .init(identity: testIdentity("BackgroundPreferenceRoot"))
    )

    #expect(resolved.kind == .view("Background"))
    #expect(resolved.children.count == 2)
    #expect(
      resolved.preferenceValues[StringListPreferenceKey.self] == [
        "background",
        "base",
      ]
    )
    #expect(try textPayload(of: resolved.children[0]) == "base")
  }

  @Test("onPreferenceChange fires on non-default initial values and subsequent changes only")
  @MainActor
  func onPreferenceChangeFiresOnNonDefaultInitialValuesAndSubsequentChangesOnly() {
    final class Recorder: @unchecked Sendable {
      var values: [String?] = []
    }

    let recorder = Recorder()
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let registry = LocalPreferenceObservationRegistry()
    var previousSnapshots: [PreferenceObservationRegistrationSnapshot] = []

    func render(_ value: String?) {
      registry.reset()
      var context = ResolveContext(identity: testIdentity("Root"))
      context.localPreferenceObservationRegistry = registry

      _ = renderer.render(
        Text("Observed")
          .preference(key: OptionalStringPreferenceKey.self, value: value)
          .onPreferenceChange(OptionalStringPreferenceKey.self) { nextValue in
            recorder.values.append(nextValue)
          },
        context: context
      )

      _ = registry.applyChanges(since: previousSnapshots)
      previousSnapshots = registry.snapshot()
    }

    render(nil)
    render("first")
    render("first")
    render("second")

    #expect(
      recorder.values == [
        "first",
        "second",
      ]
    )
  }

  @Test("resolve reuse replays stable preference observers for reused subtrees")
  @MainActor
  func resolveReuseReplaysStablePreferenceObserversForReusedSubtrees() {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let registry = LocalPreferenceObservationRegistry()

    func makeRoot(secondLine: String) -> some View {
      VStack(alignment: .leading, spacing: 1) {
        Text("Stable")
          .id(testIdentity("StablePreferenceObserver"))
          .preference(key: OptionalStringPreferenceKey.self, value: "stable")
          .onPreferenceChange(OptionalStringPreferenceKey.self) { _ in }
        Text(secondLine)
      }
    }

    var initialContext = ResolveContext(identity: testIdentity("Root"))
    initialContext.localPreferenceObservationRegistry = registry
    _ = renderer.render(
      makeRoot(secondLine: "World"),
      context: initialContext
    )

    registry.reset()

    var updatedContext = ResolveContext(
      identity: testIdentity("Root"),
      invalidatedIdentities: [testIdentity("Root", "VStack[1]")]
    )
    updatedContext.localPreferenceObservationRegistry = registry
    _ = renderer.render(
      makeRoot(secondLine: "Planet"),
      context: updatedContext
    )

    #expect(
      registry.snapshot().contains { snapshot in
        snapshot.identity == testIdentity("StablePreferenceObserver")
      }
    )
  }
}

@MainActor
private func textPayload(
  of node: ResolvedNode
) throws -> String {
  guard case .text(let value) = node.drawPayload else {
    throw PreferenceSurfaceTestError.expectedTextPayload
  }
  return value
}

private enum PreferenceSurfaceTestError: Error {
  case expectedTextPayload
}
