import SwiftTUIViews

// Also typechecked as an external consumer in the B1 acceptance probe. Style
// authoring uses only public API; fixture construction is a separate concern.
struct ConsumerPickerStyle: PickerStyle {
  var menu = false
  var duplicates = false
  var omitsRoutes = false

  var wantsTriggerPointerRoute: Bool { menu }

  func selectionDelta(for event: KeyEvent) -> Int? {
    switch event {
    case .arrowUp: -1
    case .arrowDown: 1
    default: nil
    }
  }

  func makeBody(configuration: PickerStyleConfiguration) -> some View {
    ConsumerPickerStyleBody(configuration: configuration, style: self)
  }
}

private struct ConsumerPickerStyleBody: View {
  let configuration: PickerStyleConfiguration
  let style: ConsumerPickerStyle

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      configuration.label
      if style.menu {
        let label = configuration.options.first(where: \.isSelected)?.label ?? "Select"
        if style.omitsRoutes {
          Text(label)
        } else {
          configuration.trigger { Text(label) }
          if style.duplicates {
            configuration.trigger { Text("duplicate trigger") }
          }
        }
      }
      if !style.menu || configuration.isActiveNavigation {
        ForEach(0..<configuration.options.count) { index in
          let option = configuration.options[index]
          if style.omitsRoutes {
            Text(option.label)
          } else {
            option.route { Text(option.label) }
            if style.duplicates {
              option.route { Text("duplicate route") }
            }
          }
        }
      }
    }
  }
}
