import SwiftTUITestSupport
import Testing

@testable import SwiftTUIViews

@MainActor
@Suite
struct NavigationDestinationDeclarationIdentityTests {
  @Test(
    "replacing an active declaration at a stable source starts fresh state",
    arguments: [false, true])
  func sameFrameReplacement(usesItem: Bool) throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DestinationDeclarationReplacement"),
      size: .init(width: 50, height: 10)
    ) {
      ReplacementFixture(usesItem: usesItem)
    }
    defer { harness.shutdown() }

    for second in [true, false, true, false] {
      let incremented = try harness.clickText("Increment")
      #expect(incremented.contains("local 1"))
      let replaced = try harness.clickText("Replace destination")
      #expect(replaced.contains("destination \(second ? "B" : "A") local 0"))
      #expect(!replaced.contains("local 1"))
    }
  }
}

private struct ReplacementItem: Identifiable, Sendable {
  let id = "same-item"
}

@MainActor
private struct ReplacementFixture: View {
  let usesItem: Bool
  @State private var usesSecond = false
  @State private var firstPresented = true
  @State private var secondPresented = true
  @State private var firstItem: ReplacementItem? = .init()
  @State private var secondItem: ReplacementItem? = .init()

  private var source: some View {
    Text("Source").id("stable-source")
  }

  private var destination: some View {
    ReplacementDestination(label: usesSecond ? "B" : "A") { usesSecond.toggle() }
  }

  var body: some View {
    NavigationStack {
      if usesItem {
        if usesSecond {
          source.navigationDestination(item: $secondItem) { _ in destination }
        } else {
          source.navigationDestination(item: $firstItem) { _ in destination }
        }
      } else {
        if usesSecond {
          source.navigationDestination(isPresented: $secondPresented) { destination }
        } else {
          source.navigationDestination(isPresented: $firstPresented) { destination }
        }
      }
    }
  }
}

@MainActor
private struct ReplacementDestination: View {
  let label: String
  let replace: @MainActor () -> Void
  @State private var local = 0

  var body: some View {
    VStack {
      Text("destination \(label) local \(local)")
      Button("Increment") { local += 1 }
      Button("Replace destination", action: replace)
    }
  }
}
