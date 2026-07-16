import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Typed navigation paths", .serialized)
struct TypedNavigationPathTests {
  @Test("a deep-linked typed path renders its last value")
  func deepLinkedPathRendersLastValue() {
    let model = TypedNavigationPathModel(path: [.detail(1), .detail(2)])

    let artifacts = DefaultRenderer().render(
      typedNavigationStack(model: model),
      context: .init(identity: testIdentity("TypedPathDeepLink")),
      proposal: .init(width: 40, height: 8)
    )
    let frame = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(frame.contains("detail 2"))
    #expect(!frame.contains("detail 1"))
    #expect(!frame.contains("typed root"))
  }

  @Test("Escape removes one typed path value at a time")
  func escapeRemovesOnePathValueAtATime() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("TypedPathEscape"),
      size: .init(width: 44, height: 10)
    ) {
      TypedNavigationEscapeFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.frame.contains("detail 2"))

    var frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("detail 1"))

    frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("typed root"))
  }

  @Test("path mutation is the push and pop-to-root command")
  func pathMutationPushesAndPopsToRoot() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("TypedPathMutation"),
      size: .init(width: 44, height: 10)
    ) {
      TypedNavigationMutationFixture()
    }
    defer { harness.shutdown() }

    var frame = try harness.clickText("Push detail 1")
    #expect(frame.contains("detail 1"))

    frame = try harness.clickText("Push detail 2")
    #expect(frame.contains("detail 2"))

    frame = try harness.clickText("Pop to root")
    #expect(frame.contains("typed root"))
  }

  @Test("a typed destination keeps local state through unrelated source updates")
  func typedDestinationKeepsLocalState() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("TypedPathState"),
      size: .init(width: 48, height: 10)
    ) {
      TypedNavigationStateFixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Increment route local")
    let frame = try harness.clickText("Refresh route source")

    #expect(frame.contains("route local 1 refresh 1"))
  }

  @Test("a missing typed destination reports an actionable runtime issue")
  func missingDestinationReportsRuntimeIssue() {
    let model = TypedNavigationPathModel(path: [.detail(1)])
    let artifacts = DefaultRenderer().render(
      NavigationStack(path: typedNavigationBinding(model)) {
        Text("typed root")
      },
      context: .init(identity: testIdentity("TypedPathMissingDestination")),
      proposal: .init(width: 40, height: 8)
    )

    #expect(
      artifacts.diagnostics.runtime.issues.contains {
        $0.code == "navigation.missingValueDestination"
      }
    )
  }

  @Test("simultaneous binding destinations reset losers and report the conflict")
  func simultaneousBindingDestinationsResetLosers() {
    let model = BindingDestinationConflictModel()
    let artifacts = DefaultRenderer().render(
      NavigationStack {
        Text("root")
          .navigationDestination(isPresented: model.firstBinding) {
            Text("first")
          }
          .navigationDestination(isPresented: model.secondBinding) {
            Text("second")
          }
      },
      context: .init(identity: testIdentity("NavigationBindingConflict")),
      proposal: .init(width: 40, height: 8)
    )

    #expect(!model.first)
    #expect(model.second)
    #expect(
      artifacts.diagnostics.runtime.issues.contains {
        $0.code == "navigation.multipleActiveDestinations"
      }
    )
  }

  @Test("the navigation depth safety cap reports instead of clearing silently")
  func depthCapReportsRuntimeIssue() {
    let artifacts = DefaultRenderer().render(
      NavigationStack {
        ActiveNavigationDepth(remaining: 33)
      },
      context: .init(identity: testIdentity("NavigationDepthCap")),
      proposal: .init(width: 40, height: 8)
    )

    #expect(
      artifacts.diagnostics.runtime.issues.contains {
        $0.code == "navigation.depthLimitExceeded"
      }
    )
  }

  @Test("navigationTitle contributes the visible destination title to stack toolbar chrome")
  func navigationTitleFeedsToolbarChrome() {
    let model = TypedNavigationPathModel(path: [.detail(1)])
    let artifacts = DefaultRenderer().render(
      typedNavigationStack(model: model)
        .toolbar(style: DefaultTopToolbarStyle()),
      context: .init(identity: testIdentity("TypedPathTitle")),
      proposal: .init(width: 40, height: 8)
    )
    let lines = artifacts.rasterSurface.lines
    let titleRow = lines.firstIndex { $0.contains("Detail 1") }
    let contentRow = lines.firstIndex { $0.contains("detail 1") }

    #expect(titleRow != nil)
    #expect(contentRow != nil)
    if let titleRow, let contentRow {
      #expect(titleRow < contentRow)
    }
  }
}

private enum TypedNavigationRoute: Hashable, Sendable {
  case detail(Int)

  var value: Int {
    switch self {
    case .detail(let value): value
    }
  }
}

@MainActor
private final class TypedNavigationPathModel {
  var path: [TypedNavigationRoute]

  init(path: [TypedNavigationRoute]) {
    self.path = path
  }
}

@MainActor
private func typedNavigationBinding(
  _ model: TypedNavigationPathModel
) -> Binding<[TypedNavigationRoute]> {
  Binding(
    get: { model.path },
    set: { model.path = $0 }
  )
}

@MainActor
private func typedNavigationStack(
  model: TypedNavigationPathModel
) -> some View & ActionScope {
  NavigationStack(path: typedNavigationBinding(model)) {
    Text("typed root")
      .navigationDestination(for: TypedNavigationRoute.self) { route in
        Text("detail \(route.value)")
          .navigationTitle("Detail \(route.value)")
      }
  }
}

@MainActor
private struct TypedNavigationEscapeFixture: View {
  @State private var path: [TypedNavigationRoute] = [.detail(1), .detail(2)]

  var body: some View {
    NavigationStack(path: $path) {
      Text("typed root")
        .navigationDestination(for: TypedNavigationRoute.self) { route in
          Text("detail \(route.value)")
        }
    }
  }
}

@MainActor
private struct TypedNavigationMutationFixture: View {
  @State private var path: [TypedNavigationRoute] = []

  var body: some View {
    NavigationStack(path: $path) {
      VStack(alignment: .leading, spacing: 0) {
        Text("typed root")
        Button("Push detail 1") { path.append(.detail(1)) }
      }
      .navigationDestination(for: TypedNavigationRoute.self) { route in
        VStack(alignment: .leading, spacing: 0) {
          Text("detail \(route.value)")
          Button("Push detail 2") { path.append(.detail(2)) }
          Button("Pop to root") { path.removeAll() }
        }
      }
    }
  }
}

@MainActor
private struct TypedNavigationStateFixture: View {
  @State private var path: [TypedNavigationRoute] = [.detail(1)]
  @State private var refresh = 0

  var body: some View {
    NavigationStack(path: $path) {
      Text("typed root")
        .navigationDestination(for: TypedNavigationRoute.self) { _ in
          TypedNavigationStateDestination(refresh: $refresh)
        }
    }
  }
}

@MainActor
private struct TypedNavigationStateDestination: View {
  var refresh: Binding<Int>
  @State private var local = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("route local \(local) refresh \(refresh.wrappedValue)")
      Button("Increment route local") { local += 1 }
      Button("Refresh route source") { refresh.wrappedValue += 1 }
    }
  }
}

@MainActor
private final class BindingDestinationConflictModel {
  var first = true
  var second = true

  var firstBinding: Binding<Bool> {
    Binding(get: { self.first }, set: { self.first = $0 })
  }

  var secondBinding: Binding<Bool> {
    Binding(get: { self.second }, set: { self.second = $0 })
  }
}

@MainActor
private struct ActiveNavigationDepth: View {
  var remaining: Int

  var body: some View {
    if remaining == 0 {
      Text("depth terminal")
    } else {
      Text("depth \(remaining)")
        .navigationDestination(isPresented: .constant(true)) {
          AnyView(ActiveNavigationDepth(remaining: remaining - 1))
        }
    }
  }
}
