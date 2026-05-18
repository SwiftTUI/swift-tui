import Foundation
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

  @Test("Fixpoint loop limits are derived and do not document stale overflow commits")
  func fixpointLoopLimitsAreDerivedAndDoNotCommitStaleOverflow() throws {
    let root = try repositoryRoot()
    let rendererSource = try String(
      contentsOf: root.appendingPathComponent("Sources/SwiftTUIRuntime/SwiftTUI.swift"),
      encoding: .utf8
    )
    let runLoopSource = try String(
      contentsOf: root.appendingPathComponent(
        "Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift"
      ),
      encoding: .utf8
    )

    #expect(!rendererSource.contains("maximumRelayoutPasses: 4"))
    #expect(!rendererSource.contains("warnAndCommitLastLayout"))
    #expect(!rendererSource.contains("last fully laid-out tree without applying"))
    #expect(!runLoopSource.contains("maximumRerenders: Int = 16"))
    #expect(!runLoopSource.contains("latest available tree and continue"))
  }
}

private func repositoryRoot() throws -> URL {
  var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  while directory.path != "/" {
    if FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("Package.swift").path
    ) {
      return directory
    }
    directory.deleteLastPathComponent()
  }
  throw BoundedReconciliationSourceError.missingPackageRoot
}

private enum BoundedReconciliationSourceError: Error {
  case missingPackageRoot
}
