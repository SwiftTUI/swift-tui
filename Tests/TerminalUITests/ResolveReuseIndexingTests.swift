import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@Suite
struct ResolveReuseIndexingTests {
  @Test("retained resolve frame indexes resolved subtrees by identity")
  func retainedResolveFrameIndexesResolvedSubtreesByIdentity() {
    let rootIdentity = testIdentity("Root")
    let nestedIdentity = testIdentity("Root", "VStack[1]")
    let nestedLeafIdentity = testIdentity("Root", "VStack[1]", "VStack[1]")

    let resolvedTree = VStack(alignment: .leading, spacing: 1) {
      Text("Stable")
      VStack(alignment: .leading, spacing: 0) {
        Text("Nested")
        Text("Leaf")
      }
    }
    .resolve(in: .init(identity: rootIdentity))

    let retainedFrame = RetainedResolveFrame(resolvedTree: resolvedTree)

    #expect(
      retainedFrame.resolvedTreeIndex.resolvedNode(for: nestedIdentity)?.kind
        == .view("VStack")
    )

    let subtreeIdentities = Array(
      retainedFrame.resolvedTreeIndex.subtreeIdentities(for: nestedIdentity) ?? []
    )
    #expect(subtreeIdentities.first == nestedIdentity)
    #expect(subtreeIdentities.contains(nestedLeafIdentity))
    #expect(
      retainedFrame.resolvedTreeIndex.contains(
        nestedLeafIdentity,
        inSubtreeOf: nestedIdentity
      )
    )
    #expect(
      !retainedFrame.resolvedTreeIndex.contains(
        testIdentity("Root", "VStack[0]"),
        inSubtreeOf: nestedIdentity
      )
    )
  }

  @Test("resolve reuse replays handlers for indexed subtrees")
  func resolveReuseReplaysHandlersForIndexedSubtrees() {
    final class CounterBox {
      var value = 0
    }

    let box = CounterBox()
    let actionRegistry = LocalActionRegistry()
    let keyRegistry = LocalKeyHandlerRegistry()
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let targetIdentity = testIdentity("Root", "VStack[0]", "HStack[0]", "CountStepper")

    func makeRoot(secondLine: String) -> some View {
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 1) {
          Stepper(
            "Count",
            value: Binding(
              get: { box.value },
              set: { box.value = $0 }
            ),
            in: 0...3
          )
          .id(targetIdentity)
        }
        Text(secondLine)
      }
    }

    var environmentValues = EnvironmentValues()
    environmentValues.parallelFocusedIdentity = targetIdentity

    _ = renderer.render(
      makeRoot(secondLine: "World"),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localActionRegistry: actionRegistry,
        localKeyHandlerRegistry: keyRegistry,
        applyEnvironmentValues: true
      )
    )

    actionRegistry.reset()
    keyRegistry.reset()

    let updated = renderer.render(
      makeRoot(secondLine: "Planet!"),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        invalidatedIdentities: [testIdentity("Root", "VStack[1]")],
        localActionRegistry: actionRegistry,
        localKeyHandlerRegistry: keyRegistry,
        applyEnvironmentValues: true
      )
    )

    #expect(updated.diagnostics.resolvedNodesReused > 0)
    #expect(actionRegistry.dispatch(identity: targetIdentity))
    #expect(box.value == 1)
    #expect(keyRegistry.dispatch(identity: targetIdentity, event: .arrowRight))
    #expect(box.value == 2)
  }
}
