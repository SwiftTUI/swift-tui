import Observation
import TerminalUI

struct TodoistDemoSceneView: View {
  @Bindable var launcher: TodoistDemoLauncher

  var body: some View {
    GeometryReader { geometry in
      shell(contentHeight: max(0, geometry.size.height - 5))
    }
  }

  private func shell(contentHeight: Int) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      headerBar
      Divider()

      if let model = launcher.model {
        TodoistDemoRootView(model: model)
          .frame(
            maxWidth: .infinity,
            minHeight: .finite(contentHeight),
            idealHeight: .finite(contentHeight),
            maxHeight: .finite(contentHeight),
            alignment: .topLeading
          )
      } else {
        TodoistSetupView(launcher: launcher)
          .frame(
            maxWidth: .infinity,
            minHeight: .finite(contentHeight),
            idealHeight: .finite(contentHeight),
            maxHeight: .finite(contentHeight),
            alignment: .topLeading
          )
      }

      Divider()
      footerBar
    }
    .tint(Color.red)
    .chromePreset(.standard)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var headerBar: some View {
    HStack(alignment: .firstTextBaseline, spacing: 1) {
      Text("Todoist")
        .bold()
      Text(launcher.model == nil ? "Setup" : "Workspace")
        .foregroundStyle(launcher.model == nil ? .warning : .info)
      Spacer()
      Text(launcher.model == nil ? "Ready to initialize" : "Connected")
        .foregroundStyle(.separator)
    }
    .padding(.init(horizontal: 1, vertical: 0))
    .background(.terminalRow(.accent, isSelected: true))
  }

  private var footerBar: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .center, spacing: 1) {
        Text("Tab")
        Text("moves focus")
          .foregroundStyle(.separator)
        Spacer()
        Text("Arrows")
        Text("move lists")
          .foregroundStyle(.separator)
        Spacer()
        Text("Enter")
        Text("activates")
          .foregroundStyle(.separator)
        Spacer()
        Text("q")
        Text("quits")
          .foregroundStyle(.separator)
      }
      .padding(.init(horizontal: 1, vertical: 0))

      ScrollView(.horizontal) {
        Text(launcher.databasePath)
          .fixedSize(horizontal: true, vertical: false)
      }
      .padding(.init(horizontal: 1, vertical: 0))
    }
  }
}

struct TodoistSetupView: View {
  @Bindable var launcher: TodoistDemoLauncher

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Connect")
        .bold()
      Text(
        "This demo keeps a local Todoist cache and syncs active tasks into a terminal-native workspace."
      )
      .foregroundStyle(.separator)
      Divider()
      Text("Database")
        .foregroundStyle(.separator)
      ScrollView(.horizontal) {
        Text(launcher.databasePath)
          .fixedSize(horizontal: true, vertical: false)
      }
      Divider()
      Text("Todoist API token")
        .bold()
      Text("Enter a token once, initialize the cache, and the app will reopen directly into the workspace.")
        .foregroundStyle(.separator)
      SecureField("Todoist API token", text: $launcher.apiTokenInput)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button("Initialize Database", action: launcher.requestInitialize)
        .controlProminence(.increased)
        .disabled(!launcher.canInitialize)
      Divider()
      Text(launcher.setupStatusMessage)
        .foregroundStyle(.separator)
      Spacer(minLength: 0)
    }
    .padding(1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

struct TodoistDemoRootView: View {
  @Bindable var model: TodoistAppModel

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      projectsPane
        .frame(
          minWidth: 24,
          idealWidth: 24,
          maxWidth: 24,
          maxHeight: .infinity,
          alignment: .topLeading
        )
      Divider()
      tasksPane
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      Divider()
      inspectorPane
        .frame(
          minWidth: 30,
          idealWidth: 30,
          maxWidth: 30,
          maxHeight: .infinity,
          alignment: .topLeading
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task { [model] in
      await model.start()
    }
  }

  private var projectsPane: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline, spacing: 1) {
        Text("Projects")
          .bold()
        Spacer()
        Text("\(model.projects.count)")
          .foregroundStyle(.separator)
      }
      .padding(.init(horizontal: 1, vertical: 0))
      Divider()

      List(selection: $model.selectedProject) {
        projectRow(
          title: "All Tasks",
          detail: "\(model.taskCount(for: .all)) active",
          tag: .all
        )

        ForEach(model.projects) { project in
          projectRow(
            title: project.name,
            detail: "\(model.taskCount(for: .project(project.id))) active",
            tag: .project(project.id)
          )
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private func projectRow(
    title: String,
    detail: String,
    tag: ProjectSelection
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .bold()
      Text(detail)
        .lineLimit(1)
        .truncationMode(.tail)
        .foregroundStyle(.separator)
    }
    .tag(tag)
  }

  private var tasksPane: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline, spacing: 1) {
        Text(model.title(for: model.selectedProject))
          .bold()
        Text(model.isBusy ? "Syncing" : "Idle")
          .foregroundStyle(model.isBusy ? .warning : .separator)
        Spacer()
        if let lastSyncAt = model.lastSyncAt {
          Text(lastSyncAt)
            .foregroundStyle(.separator)
        }
      }
      .padding(.init(horizontal: 1, vertical: 0))
      Divider()

      TextField("Filter visible tasks", text: $model.searchText)
        .padding(.init(horizontal: 1, vertical: 0))
        .frame(maxWidth: .infinity, alignment: .leading)

      Divider()

      if model.visibleTasks.isEmpty {
        VStack(alignment: .leading, spacing: 1) {
          Text("No tasks match the current filter.")
          Text("Change the project or clear the filter to keep browsing.")
            .foregroundStyle(.separator)
        }
        .padding(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      } else {
        List(selection: $model.selectedTaskID) {
          ForEach(model.visibleTasks) { task in
            VStack(alignment: .leading, spacing: 0) {
              Text(task.titleText)
                .bold()
              Text(task.detailText)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.separator)
            }
            .tag(task.id)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }

      Divider()

      HStack(alignment: .center, spacing: 1) {
        Button("Refresh", action: model.requestRefresh)
          .controlProminence(.increased)
          .disabled(!model.isAuthenticated || model.isBusy)

        TextField("Add a task", text: $model.newTaskText)
          .frame(maxWidth: .infinity, alignment: .leading)

        Button("Add Task", action: model.requestAddTask)
          .disabled(!model.canAddTask)
      }
      .padding(.init(horizontal: 1, vertical: 0))
    }
  }

  private var inspectorPane: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Inspector")
        .bold()
      Divider()

      if let task = model.selectedTask {
        Text(task.titleText)
          .bold()
        Text(task.detailText)
          .foregroundStyle(.separator)
        Divider()
        LabeledContent("Project", value: task.projectName ?? "Inbox")
        LabeledContent("Due", value: task.dueText ?? "None")
        LabeledContent("State", value: model.isBusy ? "Syncing" : "Ready")
        Divider()
        Button("Close Selected", action: model.requestCloseSelectedTask)
          .disabled(!model.canCloseTask)
      } else {
        Text("No task selected")
        Text("Choose a task to inspect and close it from here.")
          .foregroundStyle(.separator)
      }

      Divider()
      Text(model.statusMessage)
        .foregroundStyle(.separator)
      Spacer(minLength: 0)
    }
    .padding(1)
  }
}

struct TodoistLaunchErrorView: View {
  let message: String

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Launch Error")
        .bold()
      Divider()
      Text(message)
      Text("Check the example package dependencies and local database path, then try again.")
        .foregroundStyle(.separator)
    }
    .padding(1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
