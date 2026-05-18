import Testing

@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct BoundedReconciliationTests {
  @Test("Late-preference reconciliation converges within the documented bound")
  func reconciliationConvergesWithinBound() {
    let panel =
      Panel(id: "outer") {
        GeometryReader { proxy in
          Text("body \(proxy.size.width)x\(proxy.size.height)")
            .toolbarItem(
              .init(
                title: proxy.size.height == 6
                  ? "First pass still sees the full height"
                  : "Settled",
                icon: nil,
                position: .bottom,
                isEnabled: true,
                action: {}
              )
            )
        }
      }
      .toolbar(style: DefaultBottomToolbarStyle())
      .frame(width: 30, height: 6)

    let artifacts = DefaultRenderer().render(
      panel,
      context: .init(identity: testIdentity("bounded-reconciliation-root")),
      proposal: .init(width: 30, height: 6)
    )
    let rendered = artifacts.rasterSurface.lines.joined(separator: "\n")
    let limitIssues = artifacts.diagnostics.runtime.issues.filter {
      $0.code == "latePreference.reconciliationLimitExceeded"
    }

    #expect(limitIssues.isEmpty)
    #expect(rendered.contains("body 30x5"))
    #expect(rendered.contains("Settled"))
    #expect(!rendered.contains("First pass"))
  }
}
