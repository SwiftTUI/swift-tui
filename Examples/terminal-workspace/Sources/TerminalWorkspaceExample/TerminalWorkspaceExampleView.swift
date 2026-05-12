import Foundation
import SwiftTUI
import SwiftTUITerminalWorkspace

public struct TerminalWorkspaceExampleView: View {
  @State private var workspace: TerminalWorkspaceState

  public init() {
    _workspace = State(
      wrappedValue: TerminalWorkspacePersistence.load()
        ?? TerminalWorkspaceExampleModel.initialWorkspace()
    )
  }

  public var body: some View {
    TerminalWorkspaceView(workspace: $workspace)
      .onChange(of: workspace) {
        TerminalWorkspacePersistence.save(workspace)
      }
  }
}

public enum TerminalWorkspaceExampleModel {
  public static func initialWorkspace(
    workingDirectory: String = FileManager.default.currentDirectoryPath
  ) -> TerminalWorkspaceState {
    TerminalWorkspaceState(
      tabs: [
        TerminalWorkspaceTab(
          id: "dev",
          title: "dev",
          root: .split(
            TerminalSplit(
              axis: .horizontal,
              fraction: 0.62,
              first: .terminal(
                .shell(
                  id: "dev-shell",
                  title: "shell",
                  workingDirectory: workingDirectory
                )
              ),
              second: .split(
                TerminalSplit(
                  axis: .vertical,
                  fraction: 0.5,
                  first: .terminal(
                    TerminalPaneSpec(
                      id: "git-status",
                      title: "git",
                      command: "/bin/sh",
                      arguments: [
                        "-lc",
                        """
                        while true; do \
                        printf '\\033[2J\\033[H'; \
                        printf 'git status\\n\\n'; \
                        git status --short 2>/dev/null || echo 'not a git repository'; \
                        sleep 2; \
                        done
                        """,
                      ],
                      workingDirectory: workingDirectory
                    )
                  ),
                  second: .terminal(
                    TerminalPaneSpec(
                      id: "clock",
                      title: "activity",
                      command: "/bin/sh",
                      arguments: [
                        "-lc",
                        """
                        while true; do \
                        printf '\\033[2J\\033[H'; \
                        date; \
                        printf '\\nSwiftTUI terminal workspace\\n'; \
                        printf 'Alt+V split right, Alt+S split down, Ctrl+K commands\\n'; \
                        sleep 1; \
                        done
                        """,
                      ],
                      workingDirectory: workingDirectory
                    )
                  )
                )
              )
            )
          )
        ),
        TerminalWorkspaceTab(
          id: "ops",
          title: "ops",
          root: .split(
            TerminalSplit(
              axis: .vertical,
              fraction: 0.55,
              first: .terminal(
                TerminalPaneSpec(
                  id: "processes",
                  title: "processes",
                  command: "/bin/sh",
                  arguments: [
                    "-lc",
                    """
                    while true; do \
                    printf '\\033[2J\\033[H'; \
                    ps -axo pid,comm | head -24; \
                    sleep 3; \
                    done
                    """,
                  ],
                  workingDirectory: workingDirectory
                )
              ),
              second: .terminal(
                .shell(
                  id: "ops-shell",
                  title: "ops shell",
                  workingDirectory: workingDirectory
                )
              )
            )
          )
        ),
      ],
      activeTabID: "dev",
      focusedPaneID: "dev-shell"
    )
  }
}

enum TerminalWorkspacePersistence {
  static func load() -> TerminalWorkspaceState? {
    guard let data = try? Data(contentsOf: fileURL) else {
      return nil
    }
    return try? JSONDecoder().decode(TerminalWorkspaceState.self, from: data)
  }

  static func save(_ workspace: TerminalWorkspaceState) {
    guard let data = try? JSONEncoder().encode(workspace) else {
      return
    }
    try? data.write(to: fileURL, options: [.atomic])
  }

  private static var fileURL: URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".swift-tui-terminal-workspace.json")
  }
}
