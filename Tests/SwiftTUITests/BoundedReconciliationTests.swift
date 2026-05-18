import Foundation
@_spi(Testing) import SwiftTUICore
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

  @Test("Bound exhaustion commits the final layout-dependent realization")
  func boundExhaustionCommitsFinalLayoutDependentRealization() {
    let panel =
      Panel(id: "oscillating") {
        GeometryReader { proxy in
          let isEvenHeight = proxy.size.height % 2 == 0
          Text("body-height-\(proxy.size.height)")
            .toolbarItem(
              .init(
                title: isEvenHeight ? "s" : "long-toolbar-title",
                action: {}
              )
            )
        }
      }
      .toolbar(style: OscillatingHeightToolbarStyle())
      .frame(width: 30, height: 4)

    let artifacts = DefaultRenderer().render(
      panel,
      context: .init(identity: testIdentity("bounded-reconciliation-overflow-root")),
      proposal: .init(width: 30, height: 4)
    )
    let limitIssues = artifacts.diagnostics.runtime.issues.filter {
      $0.code == "latePreference.reconciliationLimitExceeded"
    }
    let resolvedBodyText = textPayloads(in: artifacts.resolvedTree).filter {
      $0.hasPrefix("body-height-")
    }
    let placedBodyText = textPayloads(in: artifacts.placedTree).filter {
      $0.hasPrefix("body-height-")
    }

    #expect(!limitIssues.isEmpty)
    #expect(resolvedBodyText == placedBodyText)
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

private struct OscillatingHeightToolbarStyle: ToolbarStyle {
  var itemLayout: OscillatingHeightToolbarItemLayout { .init() }
  var placement: ToolbarPlacement { .bottom }
}

private struct OscillatingHeightToolbarItemLayout: Layout {
  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout ()
  ) -> LayoutSize {
    let width = subviews.reduce(0) { width, subview in
      width + subview.sizeThatFits(.unspecified).width
    }
    return .init(width: width, height: width > 8 ? 2 : 1)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout ()
  ) {
    for subview in subviews {
      subview.place(
        at: bounds.origin,
        proposal: .init(width: bounds.size.width, height: bounds.size.height)
      )
    }
  }
}

private func textPayloads(in node: ResolvedNode) -> [String] {
  var texts: [String] = []
  collectTextPayloads(in: node, into: &texts)
  return texts
}

private func collectTextPayloads(
  in node: ResolvedNode,
  into texts: inout [String]
) {
  if case .text(let text) = node.drawPayload {
    texts.append(text)
  }
  for child in node.children {
    collectTextPayloads(in: child, into: &texts)
  }
}

private func textPayloads(in node: PlacedNode) -> [String] {
  var texts: [String] = []
  collectTextPayloads(in: node, into: &texts)
  return texts
}

private func collectTextPayloads(
  in node: PlacedNode,
  into texts: inout [String]
) {
  if case .text(let text) = node.drawPayload {
    texts.append(text)
  }
  for child in node.children {
    collectTextPayloads(in: child, into: &texts)
  }
}
