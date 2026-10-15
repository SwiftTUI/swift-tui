import SwiftTUITestSupport
import Testing

@testable import SwiftTUIViews

@MainActor
@Suite
struct NavigationDestinationDeclarationIdentityTests {
  @Test(
    "declarations inside pushed surfaces keep state across source reorder",
    arguments: [false, true])
  func nestedSourceReorder(usesPath: Bool) throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("NestedDeclarationReorder"), size: .init(width: 50, height: 10)
    ) {
      NestedDeclarationRoot(usesPath: usesPath)
    }
    defer { harness.shutdown() }
    _ = try harness.clickText("Push nested")
    for count in 1...4 {
      _ = try harness.clickText("Increment")
      let frame = try harness.clickText("Replace destination")
      #expect(frame.contains("local \(count)"))
    }
  }

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

@MainActor
private struct NestedDeclarationRoot: View {
  let usesPath: Bool
  @State private var path = [1]
  @State private var presented = true
  var body: some View {
    if usesPath {
      NavigationStack(path: $path) {
        Text("Root").navigationDestination(for: Int.self) { _ in NestedDeclarationSource() }
      }
    } else {
      NavigationStack {
        Text("Root").navigationDestination(isPresented: $presented) { NestedDeclarationSource() }
      }
    }
  }
}

@MainActor
private struct NestedDeclarationSource: View {
  @State private var presented = false
  @State private var reversed = false
  var body: some View {
    VStack {
      if reversed {
        Text("Peer")
        source
      } else {
        source
        Text("Peer")
      }
    }
  }
  private var source: some View {
    Button("Push nested") { presented = true }
      .id("nested-source")
      .navigationDestination(isPresented: $presented) {
        ReplacementDestination(label: "nested") { reversed.toggle() }
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
