import Testing

@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct OutlineSurfaceTests {
  private struct OutlineNode: Identifiable {
    let id: String
    let title: String
    let children: [OutlineNode]

    init(
      id: String,
      title: String,
      children: [OutlineNode] = []
    ) {
      self.id = id
      self.title = title
      self.children = children
    }
  }

  @Test(
    "OutlineGroup renders connector variants through the public outlineStyle environment",
    arguments: [
      (OutlineStyle.rounded, "╰─"),
      (OutlineStyle.plain, "└─"),
      (OutlineStyle.ascii, "`-"),
    ]
  )
  func outlineGroupRendersConnectorVariants(
    style: OutlineStyle,
    connector: String
  ) {
    let artifacts = DefaultRenderer().render(
      OutlineGroup(
        [
          OutlineNode(
            id: "root",
            title: "Root",
            children: [
              .init(id: "leaf", title: "Leaf")
            ]
          )
        ],
        children: \.children
      ) { node in
        Text(node.title)
      }
      .outlineStyle(style),
      context: .init(identity: testIdentity("OutlineGroup"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Root"))
    #expect(!surface.contains("\(connector) Root"))
    #expect(surface.contains("\(connector) Leaf"))
  }

  @Test("List(data, selection:, children:) flattens outline rows and navigates them in preorder")
  func listOutlineInitializerSupportsSelectionAndNavigation() {
    final class SelectionBox {
      var value = "sources"
    }

    let box = SelectionBox()
    let registry = LocalKeyHandlerRegistry()
    var environmentValues = EnvironmentValues()
    environmentValues.parallelFocusedIdentity = testIdentity("OutlineList")

    let artifacts = DefaultRenderer().render(
      List(
        [
          OutlineNode(
            id: "sources",
            title: "Sources",
            children: [
              .init(id: "app", title: "App.swift"),
              .init(id: "tests", title: "Tests"),
            ]
          ),
          .init(id: "package", title: "Package.swift"),
        ],
        selection: Binding(
          get: { box.value },
          set: { box.value = $0 }
        ),
        children: \.children
      ) { node in
        Text(node.title)
      }
      .outlineStyle(.rounded)
      .listStyle(.insetGrouped)
      .id(testIdentity("OutlineList")),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("▌ Sources"))
    #expect(surface.contains("  │ ├─  App.swift"))
    #expect(surface.contains("  │ ╰─  Tests"))
    #expect(surface.contains("  Package.swift"))
    #expect(registry.dispatch(identity: testIdentity("OutlineList"), event: .arrowDown))
    #expect(box.value == "app")
    #expect(registry.dispatch(identity: testIdentity("OutlineList"), event: .arrowDown))
    #expect(box.value == "tests")
  }

  @Test("tagged OutlineGroup rows keep their connector prefixes when rendered inside List")
  func manualOutlineGroupRowsRenderAsSelectableListRows() {
    var environmentValues = EnvironmentValues()
    environmentValues.parallelFocusedIdentity = testIdentity("TaggedOutlineList")

    let artifacts = DefaultRenderer().render(
      List(selection: .constant("leaf")) {
        OutlineGroup(
          [
            OutlineNode(
              id: "root",
              title: "Root",
              children: [
                .init(id: "leaf", title: "Leaf")
              ]
            )
          ],
          children: \.children
        ) { node in
          Text(node.title).tag(node.id)
        }
      }
      .outlineStyle(.rounded)
      .listStyle(.insetGrouped)
      .id(testIdentity("TaggedOutlineList")),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      )
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("  Root"))
    #expect(surface.contains("▌ ╰─  Leaf"))
  }
}
