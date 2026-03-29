import Observation
import TerminalUI

struct TodoistDemoRootView: View {
  @Bindable var model: TodoistAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      header
      content
      actions
      Text(model.statusMessage)
        .foregroundStyle(.muted)
    }
    .padding(1)
    .task { [model] in
      await model.start()
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 1) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Todoist Terminal Demo")
          .bold()
        Text(model.subtitleText)
          .foregroundStyle(.muted)
      }
      Spacer()
      Text(model.isAuthenticated ? "Online" : "Offline")
        .foregroundStyle(model.isAuthenticated ? .foreground : .muted)
    }
  }

  private var content: some View {
    HStack(alignment: .top, spacing: 1) {
      projectsPane
        .frame(width: 30, height: 20, alignment: .topLeading)
      tasksPane
        .frame(
          minWidth: .finite(36),
          maxWidth: .infinity,
          minHeight: .finite(20),
          maxHeight: .finite(20),
          alignment: .topLeading
        )
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
      .listStyle(.plain)
      .frame(width: 28, height: 18, alignment: .topLeading)
    }
  }

  private func projectRow(
    title: String,
    detail: String,
    tag: ProjectSelection
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
      Text(detail)
        .foregroundStyle(.muted)
    }
    .tag(tag)
  }

  private var tasksPane: some View {
    GroupBox(model.title(for: model.selectedProject)) {
      VStack(alignment: .leading, spacing: 1) {
        TextField("Filter visible tasks", text: $model.searchText)
          .frame(width: 40, alignment: .leading)

        if model.visibleTasks.isEmpty {
          Text("No tasks match the current filter.")
            .foregroundStyle(.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
          List(selection: $model.selectedTaskID) {
            ForEach(model.visibleTasks) { task in
              VStack(alignment: .leading, spacing: 0) {
                Text(task.titleText)
                Text(task.detailText)
                  .foregroundStyle(.muted)
              }
              .tag(task.id)
            }
          }
          .listStyle(.plain)
          .frame(
            maxWidth: .infinity,
            minHeight: .finite(16),
            maxHeight: .finite(16),
            alignment: .topLeading
          )
        }
      }
    }
  }

  private var actions: some View {
    GroupBox("Actions") {
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 1) {
          Button("Refresh", action: model.requestRefresh)
            .buttonStyle(.borderedProminent)
            .disabled(!model.isAuthenticated || model.isBusy)

          Button("Close Selected", action: model.requestCloseSelectedTask)
            .disabled(!model.canCloseTask)

          Text(model.selectedTask?.titleText ?? "No task selected")
            .foregroundStyle(.muted)
        }

        HStack(spacing: 1) {
          TextField("Add a task to the selected project or inbox", text: $model.newTaskText)
            .frame(width: 40, alignment: .leading)
          Button("Add Task", action: model.requestAddTask)
            .disabled(!model.canAddTask)
        }

        Text("Tab moves focus, arrows move through lists, enter activates controls, and q exits.")
          .foregroundStyle(.muted)
      }
    }
  }
}

struct TodoistLaunchErrorView: View {
  let message: String

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Todoist demo failed to launch")
        .bold()
      Text(message)
      Text("Check the example package dependencies and local database path, then try again.")
        .foregroundStyle(.muted)
    }
    .padding(1)
  }
}
