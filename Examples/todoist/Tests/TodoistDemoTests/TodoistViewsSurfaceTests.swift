import Foundation
import TerminalUI
import Testing

@testable import TodoistDemo

private func testIdentity(_ components: String...) -> Identity {
  Identity(components: components)
}

@MainActor
@Suite(.serialized)
struct TodoistViewsSurfaceTests {
  @Test("Todoist setup view stays compact on a narrow terminal")
  func setupViewStaysCompactOnNarrowSurface() throws {
    let launcher = try TodoistDemoLauncher()
    launcher.model = nil
    launcher.apiTokenInput = "token-123"
    launcher.databasePath =
      "/Users/example/Library/Application Support/swift-terminal-ui/todoist-demo/todoist.sqlite3"
    launcher.setupStatusMessage = "Enter your Todoist API token to initialize the cache."

    let surface = renderText(
      TodoistDemoSceneView(launcher: launcher)
        .preferredColorScheme(.light),
      width: 72,
      height: 28
    )

    #expect(surface.contains("Todoist"))
    #expect(surface.contains("Setup"))
    #expect(surface.contains("Initialize Database"))
    #expect(surface.contains("Todoist API token"))
    #expect(surface.contains("Database"))
  }

  @Test("Todoist scene renders distinct light and dark chrome")
  func sceneRendersDistinctLightAndDarkChrome() throws {
    let launcher = try TodoistDemoLauncher()
    launcher.model = sampleModel()

    let light = renderANSI(
      TodoistDemoSceneView(launcher: launcher)
        .preferredColorScheme(.light),
      width: 88,
      height: 40
    )
    let dark = renderANSI(
      TodoistDemoSceneView(launcher: launcher)
        .preferredColorScheme(.dark),
      width: 88,
      height: 40
    )

    #expect(light != dark)
    #expect(light.contains("Todoist"))
    #expect(dark.contains("Todoist"))
    #expect(light.contains("Workspace"))
    #expect(dark.contains("Workspace"))
    #expect(light.contains("Ship dense chrome refresh"))
    #expect(dark.contains("Ship dense chrome refresh"))
  }

  @Test("Todoist workspace shows sync progress while busy")
  func workspaceShowsSyncProgressWhenBusy() throws {
    let launcher = try TodoistDemoLauncher()
    let model = sampleModel()
    model.isBusy = true
    launcher.model = model

    let surface = renderText(
      TodoistDemoSceneView(launcher: launcher)
        .preferredColorScheme(.dark),
      width: 88,
      height: 40
    )

    #expect(surface.contains("Syncing"))
    #expect(surface.contains("Close Selected"))
  }

  @Test("Todoist workspace keeps empty-state panes readable on a terminal-sized surface")
  func workspaceKeepsEmptyStateReadable() throws {
    let launcher = try TodoistDemoLauncher()
    let model = sampleModel()
    model.projects = []
    model.tasks = []
    model.selectedProject = .all
    model.selectedTaskID = ""
    model.statusMessage = "Ready to sync Todoist."
    launcher.model = model

    let surface = renderText(
      TodoistDemoSceneView(launcher: launcher)
        .preferredColorScheme(.dark),
      width: 121,
      height: 24
    )

    #expect(surface.contains("Projects"))
    #expect(surface.contains("Inspector"))
    #expect(surface.contains("No tasks match the current filter."))
    #expect(surface.contains("No task selected"))
    #expect(surface.contains("move focus"))
  }

  @Test("Inspector surfaces last error details")
  func inspectorSurfacesLastErrorDetails() throws {
    let launcher = try TodoistDemoLauncher()
    let model = sampleModel()
    model.statusMessage = "Sync failed. See Last Error in the inspector."
    model.lastErrorDetails =
      "Decode Error: missing key results.0.isUncompletable\nExpected Type: TodoistAPI.TodoistPage<TodoistAPI.Task>"
    launcher.model = model

    let surface = renderText(
      TodoistDemoSceneView(launcher: launcher)
        .preferredColorScheme(.dark),
      width: 121,
      height: 30
    )

    #expect(surface.contains("Last Error"))
    #expect(surface.contains("Decode Error"))
    #expect(surface.contains("Status"))
  }

  @Test("Filled and plain controls render different default chrome")
  func filledControlsRenderDifferentChrome() {
    let plainText = renderText(
      ChromeProbeView(filled: false)
        .preferredColorScheme(.dark),
      width: 40,
      height: 8
    )
    let plain = renderANSI(
      ChromeProbeView(filled: false)
        .preferredColorScheme(.dark),
      width: 40,
      height: 8
    )

    let filledText = renderText(
      ChromeProbeView(filled: true)
        .preferredColorScheme(.dark),
      width: 40,
      height: 8
    )
    let filled = renderANSI(
      ChromeProbeView(filled: true)
        .preferredColorScheme(.dark),
      width: 40,
      height: 8
    )

    #expect(plain != filled)
    #expect(plainText.contains("Refresh"))
    #expect(filledText.contains("Refresh"))
  }
}

private struct ChromeProbeView: View {
  let filled: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Button("Refresh") {}
        .id(testIdentity("FocusProbe", "Refresh"))
        .buttonStyle(filled ? .automatic : .plain)
      TextField("Filter", text: .constant(""))
        .id(testIdentity("FocusProbe", "Filter"))
    }
    .tint(Color.red)
  }
}

@MainActor
private func sampleModel() -> TodoistAppModel {
  let databaseURL =
    FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
    .appendingPathComponent("todoist.sqlite3")
  let repository = try! TodoistRepository(databaseURL: databaseURL, authToken: nil)
  let model = TodoistAppModel(
    repository: repository,
    databasePath: databaseURL.path,
    isAuthenticated: false
  )

  model.projects = [
    .init(
      id: "inbox",
      name: "Inbox",
      isFavorite: false,
      isInboxProject: true,
      colorName: nil
    ),
    .init(
      id: "work",
      name: "Work",
      isFavorite: true,
      isInboxProject: false,
      colorName: "red"
    ),
  ]
  model.tasks = [
    .init(
      id: "task-1",
      projectID: "work",
      projectName: "Work",
      content: "Ship dense chrome refresh",
      details: "Verify focused states and scroll-safe surfaces",
      priority: 1,
      dueText: "Today"
    ),
    .init(
      id: "task-2",
      projectID: "inbox",
      projectName: "Inbox",
      content: "Gather remaining fixture updates",
      details: "Todoist demo and component gallery",
      priority: 2,
      dueText: "Tomorrow"
    ),
  ]
  model.selectedProject = .project("work")
  model.selectedTaskID = "task-1"
  model.searchText = ""
  model.newTaskText = ""
  model.lastSyncAt = "2026-03-29T12:00:00Z"
  model.isAuthenticated = true
  model.statusMessage = "Cache ready."
  return model
}

@MainActor
private func renderText<V: View>(
  _ view: V,
  width: Int,
  height: Int,
  environmentValues: EnvironmentValues = .init()
) -> String {
  let artifacts = DefaultRenderer().render(
    view.frame(width: width, height: height, alignment: .topLeading),
    context: .init(
      identity: testIdentity("TodoistDemo"),
      environmentValues: environmentValues
    ),
    proposal: .init(width: width, height: height)
  )

  return artifacts.rasterSurface.lines.joined(separator: "\n")
}

@MainActor
private func renderANSI<V: View>(
  _ view: V,
  width: Int,
  height: Int,
  environmentValues: EnvironmentValues = .init(),
  capabilityProfile: TerminalCapabilityProfile = .ansi16
) -> String {
  let artifacts = DefaultRenderer().render(
    view.frame(width: width, height: height, alignment: .topLeading),
    context: .init(
      identity: testIdentity("TodoistDemo"),
      environmentValues: environmentValues
    ),
    proposal: .init(width: width, height: height)
  )

  return TerminalSurfaceRenderer(capabilityProfile: capabilityProfile).render(
    artifacts.rasterSurface
  )
}
