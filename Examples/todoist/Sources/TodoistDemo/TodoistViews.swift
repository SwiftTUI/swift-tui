import Observation
import TerminalUI

struct TodoistDemoSceneView: View {
  @Bindable var launcher: TodoistDemoLauncher

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 1) {
        header

        if let model = launcher.model {
          TodoistDemoRootView(model: model)
        } else {
          TodoistSetupView(launcher: launcher)
        }
      }
      .padding(1)
    }
    .tint(Color.red)
    .chromePreset(.standard)
  }

  private var header: some View {
    GroupBox("Todoist Terminal Demo") {
      VStack(alignment: .leading, spacing: 1) {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
          Text(launcher.model == nil ? "Setup" : "Live")
            .foregroundStyle(launcher.model == nil ? .separator : .info)
          Text(
            launcher.model == nil
              ? "Initialize the local cache, then sync tasks."
              : "Dense, scroll-safe Todoist surface with live data."
          )
          .lineLimit(1)
          .truncationMode(.tail)
        }

        ScrollView(.horizontal) {
          Text(launcher.databasePath)
            .fixedSize(horizontal: true, vertical: false)
        }
      }
    }
  }
}

struct TodoistSetupView: View {
  @Bindable var launcher: TodoistDemoLauncher

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      GroupBox("Access") {
        VStack(alignment: .leading, spacing: 1) {
          Text(
            "A Todoist API token is required before the demo can initialize its local cache."
          )
          .lineLimit(2)
          .truncationMode(.tail)

          HStack(alignment: .center, spacing: 1) {
            SecureField("Todoist API token", text: $launcher.apiTokenInput)
              .frame(width: 42, alignment: .leading)

            Button("Initialize Database", action: launcher.requestInitialize)
              .controlProminence(.increased)
              .disabled(!launcher.canInitialize)
          }
        }
      }

      GroupBox("Local Cache") {
        VStack(alignment: .leading, spacing: 1) {
          Text("Database")
          ScrollView(.horizontal) {
            Text(launcher.databasePath)
              .fixedSize(horizontal: true, vertical: false)
          }
        }
      }

      GroupBox("Status") {
        VStack(alignment: .leading, spacing: 1) {
          Text(launcher.setupStatusMessage)
            .lineLimit(2)
            .truncationMode(.tail)
          Text("Tab moves focus, enter activates controls, and q exits.")
            .lineLimit(2)
            .truncationMode(.tail)
        }
      }
    }
  }
}

struct TodoistDemoRootView: View {
  @Bindable var model: TodoistAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      GroupBox("Overview") {
        VStack(alignment: .leading, spacing: 1) {
          HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("Todoist Terminal Demo")
              .bold()
            Text(model.subtitleText)
              .lineLimit(1)
              .truncationMode(.tail)
          }

          ScrollView(.horizontal) {
            HStack(alignment: .center, spacing: 1) {
              Text(model.isAuthenticated ? "Live" : "Offline")
                .foregroundStyle(model.isAuthenticated ? .info : .separator)
              Text(model.isBusy ? "Syncing" : "Idle")
              Text(model.selectedTask?.titleText ?? "No task selected")
                .lineLimit(1)
                .truncationMode(.tail)
            }
            .fixedSize(horizontal: true, vertical: false)
          }
        }
      }

      content
      actions

      GroupBox("Status") {
        VStack(alignment: .leading, spacing: 1) {
          Text(model.statusMessage)
            .lineLimit(2)
            .truncationMode(.tail)

          ScrollView(.horizontal) {
            Text(model.databasePath)
              .fixedSize(horizontal: true, vertical: false)
          }
        }
      }
    }
    .task { [model] in
      await model.start()
    }
  }

  private var content: some View {
    ViewThatFits {
      HStack(alignment: .top, spacing: 1) {
        projectsPane
          .frame(width: 30, alignment: .topLeading)
        tasksPane
          .frame(maxWidth: .infinity, alignment: .topLeading)
      }

      VStack(alignment: .leading, spacing: 1) {
        projectsPane
        tasksPane
      }
    }
  }

  private var projectsPane: some View {
    GroupBox("Projects") {
      List(selection: $model.selectedProject) {
        projectRow(
          title: "All Tasks",
          detail: "\(model.taskCount(for: .all)) active",
          tag: .all
        )

        ForEach(model.projects) { project in
          projectRow(
            title: project.name,
            detail: "\(model.taskCount(for: .project(project.id))) active | \(project.detailText)",
            tag: .project(project.id)
          )
        }
      }
      .frame(height: 14, alignment: .topLeading)
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
    GroupBox(model.title(for: model.selectedProject)) {
      VStack(alignment: .leading, spacing: 1) {
        TextField("Filter visible tasks", text: $model.searchText)
          .frame(width: 36, alignment: .leading)

        if model.visibleTasks.isEmpty {
          Text("No tasks match the current filter.")
            .lineLimit(2)
            .truncationMode(.tail)
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
          .frame(
            maxWidth: .infinity,
            minHeight: .finite(14),
            maxHeight: .finite(14),
            alignment: .topLeading
          )
        }
      }
    }
  }

  private var actions: some View {
    GroupBox("Actions") {
      VStack(alignment: .leading, spacing: 1) {
        HStack(alignment: .center, spacing: 1) {
          Button("Refresh", action: model.requestRefresh)
            .controlProminence(.increased)
            .disabled(!model.isAuthenticated || model.isBusy)

          Button("Close Selected", action: model.requestCloseSelectedTask)
            .disabled(!model.canCloseTask)

          ScrollView(.horizontal) {
            Text(model.selectedTask?.titleText ?? "No task selected")
              .fixedSize(horizontal: true, vertical: false)
          }
        }

        HStack(alignment: .center, spacing: 1) {
          TextField("Add a task to the selected project or inbox", text: $model.newTaskText)
            .frame(width: 38, alignment: .leading)

          Button("Add Task", action: model.requestAddTask)
            .controlProminence(.increased)
            .disabled(!model.canAddTask)
        }

        Text("Tab moves focus, arrows move through lists, enter activates controls, and q exits.")
          .lineLimit(2)
          .truncationMode(.tail)
      }
    }
  }
}

struct TodoistLaunchErrorView: View {
  let message: String

  var body: some View {
    GroupBox("Launch Error") {
      VStack(alignment: .leading, spacing: 1) {
        Text(message)
          .lineLimit(3)
          .truncationMode(.tail)
        Text("Check the example package dependencies and local database path, then try again.")
          .lineLimit(2)
          .truncationMode(.tail)
      }
    }
  }
}
