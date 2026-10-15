import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct CollectionControlUpdateTests {
  @Test(
    "hidden collection controls reveal current geometry and actions before forward and reverse traversal",
    arguments: CollectionControlUpdateConsumer.allCases)
  func hiddenControlUpdates(consumer: CollectionControlUpdateConsumer) throws {
    let horizontal = consumer == .lazyHorizontal
    let ledger = CollectionControlUpdateLedger()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("CollectionControlUpdate", consumer.rawValue),
      size: CellSize(width: 64, height: 12)
    ) {
      CollectionControlUpdateFixture(consumer: consumer, ledger: ledger)
    }
    defer { harness.shutdown() }

    let originalIdentity = try harness.focusIdentity(forText: "T0")
    _ = try harness.focusText("T0")

    for generation in [1, 2] {
      _ = try harness.clickText("Away")
      try #require(harness.frame.contains("R100"), "\(harness.frame)")
      #expect(
        !harness.runLoop.latestSemanticSnapshot.focusRegions.contains {
          $0.identity == originalIdentity
        })
      #expect(
        !harness.runLoop.latestSemanticSnapshot.interactionRegions.contains {
          $0.identity == originalIdentity
        })

      _ = try harness.clickText(generation == 1 ? "Grow" : "Shrink")
      #expect(!harness.frame.contains("T\(generation)"))
      #expect(
        !harness.runLoop.latestSemanticSnapshot.focusRegions.contains {
          $0.identity == originalIdentity
        })

      _ = try harness.clickText("Reveal")
      let label = "T\(generation)"
      try #require(harness.frame.contains(label), "\(harness.frame)")
      #expect(!harness.frame.contains("T\(generation - 1)"))
      let targetIdentity = try harness.focusIdentity(forText: label)
      let neighborIdentity = try harness.focusIdentity(forText: "R002")
      #expect(targetIdentity == originalIdentity)
      let target = try #require(
        harness.runLoop.latestSemanticSnapshot.focusRegions.first {
          $0.identity == targetIdentity
        })
      let neighbor = try #require(
        harness.runLoop.latestSemanticSnapshot.focusRegions.first {
          $0.identity == neighborIdentity
        })
      let expectedWidth = horizontal ? (generation == 1 ? 16 : 8) : 12
      let expectedHeight = horizontal ? 2 : (generation == 1 ? 3 : 1)
      #expect(target.rect.size == CellSize(width: expectedWidth, height: expectedHeight))
      if horizontal {
        #expect(neighbor.rect.origin.x == target.rect.origin.x + expectedWidth)
        #expect(neighbor.rect.origin.y == target.rect.origin.y)
      } else {
        #expect(neighbor.rect.origin.y == target.rect.origin.y + expectedHeight)
        #expect(neighbor.rect.origin.x == target.rect.origin.x)
      }

      // Unrealized controls are not traversal targets. Both controls above have
      // first been revealed, so these keys exercise their live focus routes.
      if generation == 1 {
        _ = try harness.focusText(label)
        _ = try harness.pressKey(KeyPress(.tab))
        #expect(harness.runLoop.focusTracker.currentFocusIdentity == neighborIdentity)
        _ = try harness.pressKey(KeyPress(.tab, modifiers: .shift))
      } else {
        _ = try harness.focusText("R002")
        _ = try harness.pressKey(KeyPress(.tab, modifiers: .shift))
        #expect(harness.runLoop.focusTracker.currentFocusIdentity == targetIdentity)
        _ = try harness.pressKey(KeyPress(.tab))
        #expect(harness.runLoop.focusTracker.currentFocusIdentity == neighborIdentity)
        _ = try harness.pressKey(KeyPress(.tab, modifiers: .shift))
      }
      #expect(harness.runLoop.focusTracker.currentFocusIdentity == targetIdentity)
      #expect(harness.frame.contains(label))
      _ = try harness.pressKey(KeyPress(.return))
      let expectedActivations = generation == 1 ? ["target:1"] : ["target:1", "target:2"]
      #expect(ledger.activations == expectedActivations)
    }
  }
}

@MainActor
private final class CollectionControlUpdateLedger {
  var activations: [String] = []
}

@MainActor
private struct CollectionControlUpdateFixture {
  let consumer: CollectionControlUpdateConsumer
  let ledger: CollectionControlUpdateLedger
  @State private var generation = 0
}

extension CollectionControlUpdateFixture: View {
  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 2) {
          // Centering isolates hidden updates from scroll edge alignment.
          Button("Away") { proxy.scrollTo(100, anchor: .center) }
          Button("Grow") { generation = 1 }
          Button("Shrink") { generation = 2 }
          Button("Reveal") { proxy.scrollTo(1, anchor: .center) }
        }
        collection
          .scrollIndicators(.hidden)
          .frame(width: 48, height: 6, alignment: .topLeading)
      }
    }
    .buttonStyle(CollectionControlUpdateButtonStyle())
  }

  @ViewBuilder
  private var collection: some View {
    switch consumer {
    case .lazyVertical:
      ScrollView(.vertical) {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<160, id: \.self) { row in control(row) }
        }
      }
    case .lazyHorizontal:
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: 0) {
          ForEach(0..<160, id: \.self) { row in control(row) }
        }
      }
    case .indexedList:
      List(0..<160, id: \.self) { row in control(row) }
        .listStyle(CollectionControlUpdateListStyle())
    }
  }

  private func control(_ row: Int) -> some View {
    let horizontal = consumer == .lazyHorizontal
    let isTarget = row == 1
    let revision = generation
    let label = isTarget ? "T\(revision)" : "R" + String(("000" + String(row)).suffix(3))
    let payload = isTarget ? "target:\(revision)" : "neighbor:\(row)"
    let isExpanded = isTarget && revision == 1
    let width = horizontal ? (isExpanded ? 16 : 8) : 12
    let height = horizontal ? 2 : (isExpanded ? 3 : 1)
    return Button {
      ledger.activations.append(payload)
    } label: {
      Text(label).frame(width: width, height: height, alignment: .topLeading)
    }
    .id(row)
  }
}

// A label-only public style gives the geometry checks explicit authored sizes.
private struct CollectionControlUpdateButtonStyle {}

extension CollectionControlUpdateButtonStyle: ButtonStyle {
  @MainActor
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    configuration.label
  }
}

private struct CollectionControlUpdateListStyle {}

extension CollectionControlUpdateListStyle: ListStyle {
  @MainActor
  func resolvePresentation(for configuration: ListStyleConfiguration) -> ListStylePresentation {
    ListStylePresentation(
      contentInsets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
      showsRowSeparators: false,
      showsSectionSeparators: false)
  }
}

enum CollectionControlUpdateConsumer: String {
  case lazyVertical
  case lazyHorizontal
  case indexedList
}

extension CollectionControlUpdateConsumer: CaseIterable {}
extension CollectionControlUpdateConsumer: Sendable {}
