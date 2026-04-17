import TerminalUI

/// A simple command-palette list view used inside the Gallery's
/// palette sheet. Renders each `ActivePaletteCommand` as a button that
/// fires the captured action and then dismisses the palette.
///
/// The commands are passed in explicitly (rather than read from the
/// environment) because opening the palette as a sheet moves focus
/// into the overlay tree, where the scope chain no longer includes
/// the Gallery's Panel. The caller snapshots `activePaletteCommands`
/// at the moment the palette opens and passes that snapshot through
/// — so the list reflects "what was visible when the user invoked
/// the palette", which is the right UX for a command palette.
struct CommandPaletteList: View {
  let commands: [ActivePaletteCommand]
  let dismiss: @MainActor @Sendable () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      body(for: commands)
    }
    .padding(1)
    .frame(minWidth: 40, alignment: .leading)
  }

  private var header: some View {
    HStack(spacing: 2) {
      Text("Command palette").bold()
      Spacer()
      Text("Enter to run · Esc to close").foregroundStyle(.separator)
    }
  }

  @ViewBuilder
  private func body(for commands: [ActivePaletteCommand]) -> some View {
    if commands.isEmpty {
      Text("No commands available in the current scope.")
        .foregroundStyle(.separator)
        .padding(.vertical, 1)
    } else {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(0..<commands.count, id: \.self) { index in
          row(for: commands[index])
        }
      }
    }
  }

  private func row(for command: ActivePaletteCommand) -> some View {
    Button {
      command.action()
      dismiss()
    } label: {
      HStack(spacing: 2) {
        Text(command.name)
        Spacer()
        if let description = command.description {
          Text(description).foregroundStyle(.separator)
        }
      }
    }
    .disabled(!command.isEnabled)
  }
}
