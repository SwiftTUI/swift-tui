#if PUBLIC_SEMANTIC_ORACLE
  import SwiftUI
#else
  import SwiftTUIViews
#endif

// This exact source is compiled by both adapters. Only the import changes.
@MainActor
final class PublicSemanticRecorder {
  static let fixtures = [
    "state-batching", "equal-value-write", "binding-projection",
    "explicit-identity-reset", "anyview-same-type", "anyview-type-change",
  ]
  var events: [String] = []
  var actions: [String: () -> Void] = [:]
  var count = -1
  var pair = "unobserved"
}

private struct PublicSemanticPair: Equatable {
  var count = 0
  var sibling = 7
}

@MainActor
struct PublicSemanticFixture: View {
  let name: String
  let recorder: PublicSemanticRecorder
  @State private var revision = 0

  var body: some View {
    VStack {
      if name == "explicit-identity-reset" {
        PublicSemanticLeaf(recorder: recorder, tag: "A", revision: revision).id(revision)
      } else if name == "anyview-same-type" || name == "anyview-type-change" {
        erasedLeaf
      } else {
        PublicSemanticLeaf(recorder: recorder, tag: "A", revision: revision)
      }
    }
    .onAppear {
      recorder.actions["replace"] = { revision += 1 }
    }
  }

  // AnyView policy: this fixture intentionally compares type erasure at one
  // stable structural position. Branching outside the eraser would test a
  // conditional-content identity change instead.
  private var erasedLeaf: AnyView {
    if name == "anyview-type-change", revision > 0 {
      return AnyView(PublicSemanticAlternate(recorder: recorder, revision: revision))
    }
    return AnyView(PublicSemanticLeaf(recorder: recorder, tag: "A", revision: revision))
  }
}

@MainActor
private struct PublicSemanticAlternate: View {
  let recorder: PublicSemanticRecorder
  let revision: Int

  var body: some View {
    PublicSemanticLeaf(recorder: recorder, tag: "B", revision: revision)
  }
}

@MainActor
private struct PublicSemanticLeaf: View {
  let recorder: PublicSemanticRecorder
  let tag: String
  let revision: Int
  @State private var count = 0
  @State private var pair = PublicSemanticPair()

  var body: some View {
    Text("\(tag) count \(count) pair \(pair.count):\(pair.sibling) revision \(revision)")
      .onAppear {
        recorder.count = count
        recorder.pair = "\(pair.count):\(pair.sibling)"
        recorder.events.append("appear:\(tag):\(count)")
        recorder.actions["batch"] = {
          count = 1
          count = 2
        }
        recorder.actions["equal"] = { count = 0 }
        recorder.actions["increment"] = { count += 1 }
        recorder.actions["project"] = { $pair.count.wrappedValue = 3 }
      }
      .onChange(of: count) { _, next in
        recorder.count = next
        recorder.events.append("count:\(next)")
      }
      .onChange(of: pair) { _, next in
        recorder.pair = "\(next.count):\(next.sibling)"
        recorder.events.append("pair:\(next.count):\(next.sibling)")
      }
      .onChange(of: revision) { _, _ in
        recorder.count = count
        recorder.events.append("retained:\(tag):\(count)")
      }
      .onDisappear {
        recorder.events.append("disappear:\(tag)")
      }
  }
}
