import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Ambient-propagation contract, Stage 3 (org root
// docs/plans/2026-08-04-001-ambient-propagation-contract-plan.md): authored
// and ambient text-layout attributes reach List/Table rows and cells instead
// of being destroyed at the payload boundary or clobbered on the hosted
// path. The default row limit REMAINS 1 (ratified terminal-native default);
// an unhonorable authored value on flattened section chrome reports a
// runtime issue and renders one line.
@MainActor
@Suite
struct AmbientCollectionAttributeTests {
  private struct EmittedText {
    var content: String
    var lineLimit: Int?
    var truncationMode: TextTruncationMode
  }

  private func emittedTexts(in root: DrawNode) -> [EmittedText] {
    var texts: [EmittedText] = []
    func visit(_ command: DrawCommand) {
      switch command {
      case .group(_, let children):
        for child in children {
          visit(child)
        }
      case .clip(_, let child):
        visit(child)
      case .text(_, let content, _, let lineLimit, let truncationMode, _):
        texts.append(
          .init(content: content, lineLimit: lineLimit, truncationMode: truncationMode)
        )
      default:
        break
      }
    }
    func walk(_ node: DrawNode) {
      for command in node.commands {
        visit(command)
      }
      for command in node.postCommands {
        visit(command)
      }
      for child in node.children {
        walk(child)
      }
    }
    walk(root)
    return texts
  }

  @Test("a hosted list row honors an authored lineLimit above one")
  func hostedListRowHonorsAuthoredLineLimit() {
    let artifacts = DefaultRenderer().render(
      List {
        Text("alpha beta gamma delta zebrafinch").lineLimit(2)
      },
      context: .init(identity: testIdentity("TallRowList")),
      proposal: .init(width: .finite(16), height: .finite(8))
    )

    let rowText = emittedTexts(in: artifacts.drawTree).first {
      $0.content.contains("alpha")
    }
    #expect(rowText?.lineLimit == 2)
    // The wrapped tail actually lands in the committed surface.
    let rendered = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("zebrafinch") || rendered.contains("zebrafi"))
  }

  @Test("ambient truncationMode reaches hosted list rows")
  func ambientTruncationModeReachesHostedListRows() {
    let artifacts = DefaultRenderer().render(
      List {
        Text("alpha beta gamma delta")
      }
      .truncationMode(.head),
      context: .init(identity: testIdentity("HeadTruncatedList")),
      proposal: .init(width: .finite(14), height: .finite(6))
    )

    let rowText = emittedTexts(in: artifacts.drawTree).first {
      $0.content.contains("alpha")
    }
    #expect(rowText?.truncationMode == .head)
  }

  @Test("a section header clamps an unhonorable authored lineLimit and reports it")
  func sectionHeaderClampsUnhonorableLineLimitWithRuntimeIssue() {
    let artifacts = DefaultRenderer().render(
      List {
        Section {
          Text("Row")
        } header: {
          Text("alpha beta gamma delta").lineLimit(3)
        }
      },
      context: .init(identity: testIdentity("HeaderClampList")),
      proposal: .init(width: .finite(14), height: .finite(8))
    )

    #expect(
      artifacts.diagnostics.runtime.issues.map(\.code).contains(
        "collection.unsupportedSectionChromeLineLimit"
      )
    )
  }

  @Test("a hosted table cell honors an authored truncationMode")
  func hostedTableCellHonorsAuthoredTruncationMode() {
    let artifacts = DefaultRenderer().render(
      Table(columns: [.init("Name", width: 8)]) {
        TableRow {
          Text("alpha beta gamma").truncationMode(.head)
        }
      },
      context: .init(identity: testIdentity("HeadTruncatedTable")),
      proposal: .init(width: .finite(20), height: .finite(6))
    )

    let cellText = emittedTexts(in: artifacts.drawTree).first {
      $0.content.contains("alpha") || $0.content.contains("gamma")
    }
    #expect(cellText?.truncationMode == .head)
  }

  @Test("a hosted table cell keeps an authored lineLimit above one")
  func hostedTableCellKeepsAuthoredLineLimit() {
    let artifacts = DefaultRenderer().render(
      Table(columns: [.init("Name", width: 10)]) {
        TableRow {
          Text("alpha beta zebrafinch").lineLimit(2)
        }
      },
      context: .init(identity: testIdentity("TallCellTable")),
      proposal: .init(width: .finite(20), height: .finite(8))
    )

    let cellText = emittedTexts(in: artifacts.drawTree).first {
      $0.content.contains("alpha")
    }
    #expect(cellText?.lineLimit == 2)
  }

  @Test("default list and table appearance is unchanged: flattened lines stay single-line tail")
  func defaultCollectionAppearanceUnchanged() {
    let artifacts = DefaultRenderer().render(
      List {
        Section {
          Text("alpha beta gamma delta epsilon")
        } header: {
          Text("Header")
        }
      },
      context: .init(identity: testIdentity("DefaultList")),
      proposal: .init(width: .finite(14), height: .finite(8))
    )

    // Every emitted text stays on the tail default, and the unlimited/1-line
    // defaults reach the commands unchanged (hosted headers draw through
    // their committed children, whose default limit is nil).
    let texts = emittedTexts(in: artifacts.drawTree)
    #expect(texts.allSatisfy { $0.truncationMode == .tail })
    #expect(texts.allSatisfy { $0.lineLimit == nil || $0.lineLimit == 1 })
    #expect(artifacts.diagnostics.runtime.issues.isEmpty)
  }
}
