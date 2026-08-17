// Excluded from Windows builds (Windows plan, Stage 6 item 3): exercises a
// POSIX-only subsystem whose modules build empty (or not at all) on Windows.
#if !os(Windows)

  import SwiftTUIRuntime
  import Testing

  @testable import SwiftTUITerminal

  @MainActor
  @Suite("TerminalView modifiers")
  struct TerminalViewModifierTests {
    @Test("terminalTitleChanged installs a title event handler")
    func terminalTitleChangedModifier() {
      final class Recorder {
        var title: String?
      }

      let recorder = Recorder()

      _ = DefaultRenderer().render(
        EnvironmentReader(\.terminalEventHandlers) { handlers in
          handlers.titleChanged?("Preview")
          return Text("ok")
        }
        .terminalTitleChanged { title in
          recorder.title = title
        }
      )

      #expect(recorder.title == "Preview")
    }

    @Test("terminalWorkingDirectoryChanged installs a cwd event handler")
    func terminalWorkingDirectoryChangedModifier() {
      final class Recorder {
        var directory: String?
      }

      let recorder = Recorder()

      _ = DefaultRenderer().render(
        EnvironmentReader(\.terminalEventHandlers) { handlers in
          handlers.workingDirectoryChanged?("file:///tmp")
          return Text("ok")
        }
        .terminalWorkingDirectoryChanged { directory in
          recorder.directory = directory
        }
      )

      #expect(recorder.directory == "file:///tmp")
    }
  }

#endif
