public import Core
public import View

/// A compact, horizontally scrollable help strip for terminal-native apps.
public struct PrototypeHelpSurface: View {
  public var groups: [PrototypeKeyBindingGroup]

  public init(_ groups: [PrototypeKeyBindingGroup]) {
    self.groups = groups
  }

  public var body: some View {
    ScrollView(.horizontal) {
      HStack(alignment: .center, spacing: 2) {
        ForEach(groups) { group in
          PrototypeHelpGroupView(group: group)
        }
      }
    }
  }
}

/// A searchable, scrollable command palette for terminal-native workflows.
public struct PrototypeCommandPalette: View {
  public var query: Binding<String>
  public var commands: [PrototypeCommand]
  public var placeholder: String
  public var emptyState: String
  public var maximumResults: Int?
  public var onExecute: @MainActor @Sendable (PrototypeCommand) -> Void

  public init(
    query: Binding<String>,
    commands: [PrototypeCommand],
    placeholder: String = "Search commands",
    emptyState: String = "No matching commands",
    maximumResults: Int? = 8,
    onExecute: @escaping @MainActor @Sendable (PrototypeCommand) -> Void = { _ in }
  ) {
    self.query = query
    self.commands = commands
    self.placeholder = placeholder
    self.emptyState = emptyState
    self.maximumResults = maximumResults
    self.onExecute = onExecute
  }

  public var body: some View {
    let matches = PrototypeCommandCatalog(commands).matching(
      query.wrappedValue,
      limit: maximumResults
    )

    return VStack(alignment: .leading, spacing: 1) {
      TextField(placeholder, text: query)
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 1) {
          if matches.isEmpty {
            Text(emptyState)
              .foregroundStyle(.separator)
          } else {
            ForEach(matches) { command in
              Button(
                role: command.kind == .destructive ? .destructive : nil,
                action: {
                  onExecute(command)
                }
              ) {
                PrototypeCommandRow(command: command)
              }
              .disabled(command.isDisabled)
            }
          }
        }
      }
    }
  }
}

private struct PrototypeHelpGroupView: View {
  let group: PrototypeKeyBindingGroup

  var body: some View {
    HStack(alignment: .center, spacing: 1) {
      if let title = group.title, !title.isEmpty {
        Text(title)
          .foregroundStyle(.separator)
      }

      ForEach(group.bindings) { binding in
        PrototypeKeyBindingToken(binding: binding)
      }
    }
  }
}

private struct PrototypeKeyBindingToken: View {
  let binding: PrototypeKeyBinding

  var body: some View {
    HStack(alignment: .center, spacing: 1) {
      Text("[\(binding.key)]")
        .bold()
      Text(binding.label)
      if let detail = binding.detail, !detail.isEmpty {
        Text(detail)
          .foregroundStyle(.separator)
      }
    }
  }
}

private struct PrototypeCommandRow: View {
  let command: PrototypeCommand

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 1) {
      Text(command.kind.symbol)
        .foregroundStyle(.separator)

      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
          Text(command.title)
          Spacer()
          if let shortcut = command.shortcut, !shortcut.isEmpty {
            Text(shortcut)
              .foregroundStyle(.separator)
          }
        }

        if let detail = command.detail, !detail.isEmpty {
          Text(detail)
            .foregroundStyle(.separator)
        }
      }
    }
    .drawMetadata(.init(opacity: command.isDisabled ? 0.6 : 1))
  }
}
