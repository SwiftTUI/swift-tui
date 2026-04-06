import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct ToolbarSurfaceTests {
  @Test("toolbar item registrations do not create a toolbar on their own")
  func toolbarItemDoesNotCreateToolbarByItself() {
    let plainSurface = renderedLines(Text("Workspace"), height: 1)
    let toolbarItemOnlySurface = renderedLines(
      Text("Workspace")
        .toolbarItem(alignment: .leading) {
          Text("Ignored")
        },
      height: 1
    )

    #expect(plainSurface == toolbarItemOnlySurface)
    #expect(toolbarItemOnlySurface.allSatisfy { !$0.contains("Ignored") })
  }

  @Test("toolbar leading and trailing content render at the outer edges")
  func toolbarLeadingAndTrailingContentRenderAtEdges() throws {
    let bottomLine = try #require(
      renderedLines(
        VStack(alignment: .leading, spacing: 0) {
          Text("Body")
        }
        .toolbarStyle(.default)
        .toolbar(
          placement: .bottom,
          leading: {
            Text("Start")
          },
          trailing: {
            Text("End")
          }
        ),
        height: 2
      ).last
    )
    let trimmedBottomLine = bottomLine.trimmingCharacters(in: .whitespaces)

    #expect(trimmedBottomLine.hasPrefix("Start"))
    #expect(trimmedBottomLine.hasSuffix("End"))
  }

  @Test("contextual toolbar items render inside the static outer items")
  func contextualToolbarItemsRenderInsideStaticItems() throws {
    let bottomLine = try #require(
      renderedLines(
        VStack(alignment: .leading, spacing: 0) {
          Text("Anchor")
            .id(testIdentity("ToolbarSurface", "Anchor"))
            .toolbarItem(alignment: .leading) {
              Text("Inner")
            }
        }
        .toolbar(
          placement: .bottom,
          leading: {
            Text("Outer")
          },
          trailing: {
            Text("Tail")
          }
        ),
        height: 2
      ).last
    )

    let outerRange = try #require(bottomLine.firstRange(of: "Outer"))
    let innerRange = try #require(bottomLine.firstRange(of: "Inner"))
    let tailRange = try #require(bottomLine.firstRange(of: "Tail"))

    #expect(outerRange.lowerBound < innerRange.lowerBound)
    #expect(innerRange.lowerBound < tailRange.lowerBound)
  }

  @Test("multiple toolbar declarations at the same placement consolidate")
  func multipleToolbarDeclarationsAtTheSamePlacementConsolidate() {
    let lines = renderedLines(
      VStack(alignment: .leading, spacing: 0) {
        Text("Body")
      }
      .toolbar(
        placement: .bottom,
        leading: {
          Text("One")
        },
        trailing: {
          Text("Two")
        }
      )
      .toolbar(
        placement: .bottom,
        leading: {
          Text("Three")
        },
        trailing: {
          Text("Four")
        }
      ),
      height: 2
    )

    #expect(lines.count == 2)
    #expect(lines[0].contains("Body"))

    let bottomLine = lines[1]
    #expect(bottomLine.contains("One"))
    #expect(bottomLine.contains("Two"))
    #expect(bottomLine.contains("Three"))
    #expect(bottomLine.contains("Four"))
  }

  @Test("toolbar actions come from the explicit action parameter")
  func toolbarActionsComeFromTheExplicitActionParameter() throws {
    let actionRegistry = LocalActionRegistry()
    var didTrigger = false

    let artifacts = renderedArtifacts(
      Text("Body")
        .toolbar(
          placement: .bottom,
          leadingAction: {
            didTrigger = true
          },
          leading: {
            Text("Run")
          },
          trailing: {
            Text("Idle")
          }
        ),
      height: 2,
      localActionRegistry: actionRegistry
    )

    let actionIdentity = try #require(
      artifacts.semanticSnapshot.focusRegions.first?.identity
    )
    #expect(actionRegistry.dispatch(identity: actionIdentity))
    #expect(didTrigger)
  }

  @Test("toolbar labels strip nested interactive behavior without an explicit action")
  func toolbarLabelsStripNestedInteractiveBehaviorWithoutAnExplicitAction() {
    let actionRegistry = LocalActionRegistry()

    let artifacts = renderedArtifacts(
      Text("Body")
        .toolbar(
          placement: .bottom,
          leading: {
            Button(
              "Nested",
              action: {}
            )
          },
          trailing: {
            Text("Idle")
          }
        ),
      height: 2,
      localActionRegistry: actionRegistry
    )

    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("Nested"))
    #expect(artifacts.semanticSnapshot.focusRegions.isEmpty)
  }
}

@MainActor
private func renderedLines<V: View>(
  _ view: V,
  width: Int = 32,
  height: Int = 4,
  focusedIdentity: Identity? = nil
) -> [String] {
  renderedArtifacts(
    view,
    width: width,
    height: height,
    focusedIdentity: focusedIdentity
  ).rasterSurface.lines
}

@MainActor
private func renderedArtifacts<V: View>(
  _ view: V,
  width: Int = 32,
  height: Int = 4,
  focusedIdentity: Identity? = nil,
  localActionRegistry: LocalActionRegistry? = nil
) -> FrameArtifacts {
  var environmentValues = EnvironmentValues()
  environmentValues.terminalSize = .init(width: width, height: height)
  environmentValues.focusedIdentity = focusedIdentity

  return DefaultRenderer().render(
    view,
    context: .init(
      identity: testIdentity("ToolbarSurface"),
      environmentValues: environmentValues,
      localActionRegistry: localActionRegistry,
      applyEnvironmentValues: true
    ),
    proposal: .init(width: width, height: height)
  )
}
