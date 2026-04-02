package import TerminalUI

package enum InteractiveDemoSelectionMode: String, CaseIterable, Equatable, Sendable {
  case inspect
  case accent
  case runtime
}

package struct InteractiveDemoState: Equatable, Sendable {
  package static let defaultPresets = [-9, -5, -3, 0, 2, 4, 7, 12]

  package var value: Int
  package var accentPreviewEnabled: Bool
  package var selectionMode: InteractiveDemoSelectionMode
  package var textLabExpanded: Bool
  package var presets: [Int]
  package var selectedPresetIndex: Int
  package var inputBuffer: String

  package init(
    value: Int = 0,
    accentPreviewEnabled: Bool = false,
    selectionMode: InteractiveDemoSelectionMode = .inspect,
    textLabExpanded: Bool = true,
    presets: [Int] = Self.defaultPresets,
    inputBuffer: String? = nil
  ) {
    self.value = value
    self.accentPreviewEnabled = accentPreviewEnabled
    self.selectionMode = selectionMode
    self.textLabExpanded = textLabExpanded
    self.presets = presets
    selectedPresetIndex = presets.firstIndex(of: value) ?? 0
    self.inputBuffer = inputBuffer ?? String(value)
  }

  package mutating func increment() {
    applyValue(value + 1)
  }

  package mutating func decrement() {
    applyValue(value - 1)
  }

  package mutating func reset() {
    applyValue(0)
  }

  package mutating func applySelectedPreset() {
    guard presets.indices.contains(selectedPresetIndex) else {
      return
    }
    applyValue(presets[selectedPresetIndex])
  }

  package mutating func appendInput(_ character: Character) -> Bool {
    if character == "-" {
      guard inputBuffer.isEmpty else {
        return false
      }
      inputBuffer = "-"
      return true
    }

    guard character.isASCII, character.isNumber else {
      return false
    }

    if inputBuffer == "0" {
      inputBuffer = String(character)
      return true
    }

    if inputBuffer == "-0" {
      inputBuffer = "-\(character)"
      return true
    }

    inputBuffer.append(character)
    return true
  }

  package mutating func removeInputCharacter() -> Bool {
    guard !inputBuffer.isEmpty else {
      return false
    }

    inputBuffer.removeLast()
    return true
  }

  package mutating func applyInput() -> Bool {
    guard inputBuffer != "-", let parsed = Int(inputBuffer) else {
      return false
    }

    applyValue(parsed)
    return true
  }

  package func displayedInput(focused: Bool) -> String {
    if focused {
      return inputBuffer.isEmpty ? "_" : "\(inputBuffer)_"
    }

    return inputBuffer.isEmpty ? "type number" : inputBuffer
  }

  package func appendable(_ character: Character) -> Bool {
    if character == "-" {
      return inputBuffer.isEmpty
    }

    return character.isASCII && character.isNumber
  }
}

extension InteractiveDemoState {
  fileprivate mutating func applyValue(_ newValue: Int) {
    value = newValue
    inputBuffer = String(newValue)

    if let matchingIndex = presets.firstIndex(of: newValue) {
      selectedPresetIndex = matchingIndex
    }
  }
}

package enum InteractiveDemoLayout {
  package static let frameSize = Size(width: 72, height: 40)
  package static let interiorWidth = 70
  package static let controlsColumnWidth = 24
  package static let showcaseColumnWidth = 44
  package static let listBoxSize = Size(width: 24, height: 7)
  package static let textFieldSize = Size(width: 24, height: 3)
  package static let textLabBoxSize = Size(width: 44, height: 8)
  package static let buttonSize = Size(width: 9, height: 3)
}

package enum InteractiveDemoIdentity {
  package static let root = testIdentity("InteractiveDemo")
  package static let title = testIdentity("InteractiveDemo", "title")
  package static let incrementButton = testIdentity("InteractiveDemo", "buttons", "increment")
  package static let decrementButton = testIdentity("InteractiveDemo", "buttons", "decrement")
  package static let resetButton = testIdentity("InteractiveDemo", "buttons", "reset")
  package static let accentToggle = testIdentity("InteractiveDemo", "toggles", "accentPreview")
  package static let presetMenu = testIdentity("InteractiveDemo", "presets", "menu")
  package static let presetList = testIdentity("InteractiveDemo", "presets", "list")
  package static let inputField = testIdentity("InteractiveDemo", "input", "field")
  package static let selectionModePicker = testIdentity("InteractiveDemo", "selection", "mode")
  package static let textLabDisclosure = testIdentity("InteractiveDemo", "disclosure", "textLab")
  package static let textLabScrollPreview: Identity =
    testIdentity("InteractiveDemo", "disclosure", "textLab", "scrollPreview")
}

private enum InteractiveDemoTerminalCapabilityKey: EnvironmentKey {
  static let defaultValue = TerminalCapabilityProfile.previewUnicode
}

extension EnvironmentValues {
  package var interactiveDemoTerminalCapability: TerminalCapabilityProfile {
    get { self[InteractiveDemoTerminalCapabilityKey.self] }
    set { self[InteractiveDemoTerminalCapabilityKey.self] = newValue }
  }
}

@MainActor
package func handleFocusedInteractiveDemoInput(
  keyPress: KeyPress,
  focusedIdentity: Identity?,
  stateContainer: StateContainer<InteractiveDemoState>
) -> KeyHandlingResult {
  guard keyPress.modifiers.isEmpty else {
    return .ignored
  }

  switch focusedIdentity {
  case InteractiveDemoIdentity.presetList:
    switch keyPress.key {
    case .return, .space:
      _ = stateContainer.mutate { state in
        state.applySelectedPreset()
      }
      return .handled
    default:
      return .ignored
    }

  case InteractiveDemoIdentity.inputField:
    switch keyPress.key {
    case .return:
      _ = stateContainer.mutate { state in
        _ = state.applyInput()
      }
      return .handled
    default:
      return .ignored
    }

  default:
    return .ignored
  }
}

@MainActor
package func interactiveDemoScene(
  state: InteractiveDemoState,
  focusedIdentity: Identity?
) -> AnyView {
  interactiveDemoRootView(
    state: state,
    focusedIdentity: focusedIdentity,
    bindings: .constant(state: state)
  )
}

@MainActor
package struct InteractiveDemoBindings {
  package var accentPreviewEnabled: Binding<Bool>
  package var value: Binding<Int>
  package var selectedPresetIndex: Binding<Int>
  package var inputBuffer: Binding<String>
  package var selectionMode: Binding<InteractiveDemoSelectionMode>
  package var textLabExpanded: Binding<Bool>

  package static func constant(
    state: InteractiveDemoState
  ) -> Self {
    Self(
      accentPreviewEnabled: .constant(state.accentPreviewEnabled),
      value: .constant(state.value),
      selectedPresetIndex: .constant(state.selectedPresetIndex),
      inputBuffer: .constant(state.inputBuffer),
      selectionMode: .constant(state.selectionMode),
      textLabExpanded: .constant(state.textLabExpanded)
    )
  }
}

@MainActor
package func interactiveDemoBindings(
  stateContainer: StateContainer<InteractiveDemoState>
) -> InteractiveDemoBindings {
  InteractiveDemoBindings(
    accentPreviewEnabled: Binding(
      get: { stateContainer.state.accentPreviewEnabled },
      set: { newValue in
        _ = stateContainer.mutate { state in
          state.accentPreviewEnabled = newValue
        }
      }
    ),
    value: Binding(
      get: { stateContainer.state.value },
      set: { newValue in
        _ = stateContainer.mutate { state in
          state.applyValue(newValue)
        }
      }
    ),
    selectedPresetIndex: Binding(
      get: { stateContainer.state.selectedPresetIndex },
      set: { newValue in
        _ = stateContainer.mutate { state in
          state.selectedPresetIndex = min(
            max(0, newValue),
            max(0, state.presets.count - 1)
          )
        }
      }
    ),
    inputBuffer: Binding(
      get: { stateContainer.state.inputBuffer },
      set: { newValue in
        _ = stateContainer.mutate { state in
          state.inputBuffer = newValue
        }
      }
    ),
    selectionMode: Binding(
      get: { stateContainer.state.selectionMode },
      set: { newValue in
        _ = stateContainer.mutate { state in
          state.selectionMode = newValue
        }
      }
    ),
    textLabExpanded: Binding(
      get: { stateContainer.state.textLabExpanded },
      set: { newValue in
        _ = stateContainer.mutate { state in
          state.textLabExpanded = newValue
        }
      }
    )
  )
}

@MainActor
package func interactiveDemoScene(
  state: InteractiveDemoState,
  focusedIdentity: Identity?,
  bindings: InteractiveDemoBindings
) -> AnyView {
  interactiveDemoRootView(
    state: state,
    focusedIdentity: focusedIdentity,
    bindings: bindings
  )
}

@MainActor
private func interactiveDemoRootView(
  state: InteractiveDemoState,
  focusedIdentity: Identity?,
  bindings: InteractiveDemoBindings
) -> AnyView {
  AnyView(
    VStack(alignment: .leading, spacing: 1) {
      Text(" Showcase | value \(state.value)")
        .bold()
        .id(InteractiveDemoIdentity.title)
        .frame(width: InteractiveDemoLayout.interiorWidth, alignment: .leading)

      HStack(alignment: .top, spacing: 2) {
        controlsColumn(
          state: state,
          bindings: bindings
        )
        showcaseColumn(
          state: state,
          bindings: bindings
        )
      }

      HStack(alignment: .top, spacing: 0) {
        Spacer(minLength: 0)
        selectionSummary(state: state)
      }

      EnvironmentReader(\.interactiveDemoTerminalCapability) { capabilityProfile in
        EnvironmentReader(\.terminalAppearance) { appearance in
          Text(
            "Tab | Enter | arrows | q | \(interactiveDemoCapabilityBadge(capabilityProfile, appearance: appearance))"
          )
          .foregroundStyle(.muted)
          .frame(width: InteractiveDemoLayout.interiorWidth, alignment: .leading)
        }
      }
    }
    .padding(1)
    .frame(
      width: InteractiveDemoLayout.frameSize.width,
      height: InteractiveDemoLayout.frameSize.height,
      alignment: .topLeading
    )
    .background {
      Rectangle().fill(.background)
    }
    .environment(\.focusedIdentity, focusedIdentity)
    .foregroundStyle(.foreground)
    .tint(.tint)
  )
}

@MainActor
private func controlsColumn(
  state: InteractiveDemoState,
  bindings: InteractiveDemoBindings
) -> AnyView {
  AnyView(
    VStack(alignment: .leading, spacing: 1) {
      GroupBox("Actions") {
        buttonRow(state: state, bindings: bindings)
        accentToggleRow(bindings: bindings)
      }
      .frame(width: InteractiveDemoLayout.controlsColumnWidth, alignment: .leading)

      GroupBox {
        VStack(alignment: .leading, spacing: 0) {
          HStack(alignment: .center, spacing: 1) {
            Label("Presets") {
              Text("▤")
            }
            Spacer()
            quickPresetMenuView(state: state, bindings: bindings)
          }
          .frame(width: InteractiveDemoLayout.controlsColumnWidth - 4, alignment: .leading)
          presetListView(state: state, bindings: bindings)
        }
      }
      .frame(width: InteractiveDemoLayout.controlsColumnWidth, alignment: .leading)

      GroupBox("Direct Set") {
        directSetField(bindings: bindings)
      }
      .frame(width: InteractiveDemoLayout.controlsColumnWidth, alignment: .leading)
    }
  )
}

@MainActor
private func showcaseColumn(
  state: InteractiveDemoState,
  bindings: InteractiveDemoBindings
) -> AnyView {
  AnyView(
    VStack(alignment: .leading, spacing: 1) {
      GroupBox("Live Metrics") {
        LabeledContent("Current", value: "\(state.value)")
        LabeledContent("Preset", value: "\(state.presets[state.selectedPresetIndex])")
        Text("Preset Sync")
        Text("Run Compare")
        Text("Preset Trend")
        Text("Run Stats")
        Text("Preset Flow")
      }
      .frame(width: InteractiveDemoLayout.showcaseColumnWidth, alignment: .leading)

      GroupBox("Selection Modes") {
        Picker(selection: bindings.selectionMode) {
          Text("Inspect").tag(InteractiveDemoSelectionMode.inspect)
          Text("Accent").tag(InteractiveDemoSelectionMode.accent)
          Text("Runtime").tag(InteractiveDemoSelectionMode.runtime)
        } label: {
          Text("Mode")
        }
        .id(InteractiveDemoIdentity.selectionModePicker)
        .pickerStyle(.radioGroup)
        .frame(
          width: InteractiveDemoLayout.showcaseColumnWidth - 4,
          alignment: .leading
        )
      }
      .frame(width: InteractiveDemoLayout.showcaseColumnWidth, alignment: .leading)

      textLabColumn(state: state, bindings: bindings)
    }
  )
}

@MainActor
private func selectionSummary(
  state: InteractiveDemoState
) -> AnyView {
  AnyView(
    VStack(alignment: .leading, spacing: 0) {
      Text(state.accentPreviewEnabled ? "Accent live" : "Neutral flow")
        .bold()
      Text("Mode \(state.selectionMode.rawValue)")
      Text("Preset \(state.presets[state.selectedPresetIndex])")
        .foregroundStyle(.muted)
    }
    .padding(1)
    .background {
      RoundedRectangle(cornerRadius: 1).chromeFill(.windowBackground)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(.separator)
    }
  )
}

@MainActor
private func textLabColumn(
  state: InteractiveDemoState,
  bindings: InteractiveDemoBindings
) -> AnyView {
  AnyView(
    GroupBox {
      DisclosureGroup("Text Lab", isExpanded: bindings.textLabExpanded) {
        VStack(alignment: .leading, spacing: 0) {
          Stepper("Stepper", value: .constant(state.value), in: -12...12)
            .disabled(true)
            .frame(
              width: InteractiveDemoLayout.textLabBoxSize.width - 4,
              height: 1,
              alignment: .leading
            )
          Slider("Slider", value: .constant(min(max(state.value, -12), 12)), in: -12...12)
            .disabled(true)
            .frame(
              width: InteractiveDemoLayout.textLabBoxSize.width - 4,
              height: 1,
              alignment: .leading
            )
          Text("Wide: \u{754C}\u{1F642}e\u{301} cells align")
            .foregroundStyle(
              .linearGradient(
                stops: [
                  .init(color: .cyan, location: 0),
                  .init(color: .yellow, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
              )
            )
            .frame(
              width: InteractiveDemoLayout.textLabBoxSize.width - 4,
              height: 1,
              alignment: .leading
            )
          Text("Clip: [\(state.displayedInput(focused: false))] orbit preview")
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(
              width: InteractiveDemoLayout.textLabBoxSize.width - 4,
              height: 1,
              alignment: .leading
            )
          ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
              Text("Scroll: viewport clips overflow")
              Text("Scroll: semantic content bounds persist")
              Text("Scroll: runtime offset comes next")
            }
          }
          .id(InteractiveDemoIdentity.textLabScrollPreview)
          .frame(
            width: InteractiveDemoLayout.textLabBoxSize.width - 4,
            height: 1,
            alignment: .leading
          )
          Text("Style run: accent emphasis")
            .bold()
            .underline(pattern: .dash, color: .yellow)
            .strikethrough(pattern: .dot, color: .red)
            .foregroundStyle(.tint)
            .drawMetadata(.init(opacity: 0.8))
            .lineLimit(1)
            .padding(.init(horizontal: 1))
            .background {
              RoundedRectangle(cornerRadius: 1).chromeFill(.windowBackground)
            }
            .overlay {
              RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(
                state.accentPreviewEnabled ? .success : .info
              )
            }
            .frame(
              width: InteractiveDemoLayout.textLabBoxSize.width - 4,
              height: 1,
              alignment: .leading
            )
        }
      }
      .id(InteractiveDemoIdentity.textLabDisclosure)
    }
  )
}

@MainActor
private func accentToggleRow(
  bindings: InteractiveDemoBindings
) -> AnyView {
  AnyView(
    Toggle("Accent Preview", isOn: bindings.accentPreviewEnabled)
      .id(InteractiveDemoIdentity.accentToggle)
      .frame(width: InteractiveDemoLayout.controlsColumnWidth - 4, alignment: .leading)
  )
}

@MainActor
private func buttonRow(
  state: InteractiveDemoState,
  bindings: InteractiveDemoBindings
) -> AnyView {
  AnyView(
    ControlGroup {
      buttonControl(
        identity: InteractiveDemoIdentity.incrementButton,
        label: "+1",
        action: {
          bindings.value.wrappedValue += 1
        },
        buttonStyle: .borderedProminent
      )
      buttonControl(
        identity: InteractiveDemoIdentity.decrementButton,
        label: "-1",
        action: {
          bindings.value.wrappedValue -= 1
        }
      )
      buttonControl(
        identity: InteractiveDemoIdentity.resetButton,
        label: "Reset",
        action: {
          bindings.value.wrappedValue = 0
        },
        buttonRole: .destructive,
        buttonStyle: .borderedProminent,
        disabled: state.value == 0
      )
    }
    .buttonBorderShape(.roundedRectangle)
    .frame(
      width: InteractiveDemoLayout.controlsColumnWidth - 4,
      height: InteractiveDemoLayout.buttonSize.height,
      alignment: .leading
    )
  )
}

@MainActor
private func buttonControl(
  identity: Identity,
  label: String,
  action: @escaping @MainActor @Sendable () -> Void,
  buttonRole: ButtonRole? = nil,
  buttonStyle: ButtonStyle = .automatic,
  disabled: Bool = false
) -> AnyView {
  AnyView(
    Button(
      role: buttonRole,
      action: action
    ) {
      Text(label)
        .lineLimit(1)
        .frame(
          width: InteractiveDemoLayout.buttonSize.width - 2,
          height: InteractiveDemoLayout.buttonSize.height - 2,
          alignment: .center
        )
    }
    .id(identity)
    .buttonStyle(buttonStyle)
    .disabled(disabled)
  )
}

@MainActor
private func quickPresetMenuView(
  state: InteractiveDemoState,
  bindings: InteractiveDemoBindings
) -> AnyView {
  AnyView(
    Picker(selection: bindings.value) {
      ForEach(state.presets.indices, id: \.self) { index in
        Text("\(state.presets[index])").tag(state.presets[index])
      }
    } label: {
      EmptyView()
    }
    .id(InteractiveDemoIdentity.presetMenu)
    .pickerStyle(.menu)
    .frame(width: 6, alignment: .trailing)
  )
}

@MainActor
private func presetListView(
  state: InteractiveDemoState,
  bindings: InteractiveDemoBindings
) -> AnyView {
  AnyView(
    List(selection: bindings.selectedPresetIndex) {
      Section {
        ForEach(state.presets.indices, id: \.self) { index in
          Text(
            presetRowLabel(
              preset: state.presets[index],
              isCurrentValue: state.presets[index] == state.value
            )
          )
          .tag(index)
          .listRowForegroundStyle(.foreground)
          .listRowBackground(
            presetRowBackgroundStyle(
              preset: state.presets[index],
              currentValue: state.value
            )
          )
        }
      } header: {
        Text("Presets")
      } footer: {
        Text("Enter applies")
      }
    }
    .id(InteractiveDemoIdentity.presetList)
    .listStyle(.insetGrouped)
    .frame(
      width: InteractiveDemoLayout.listBoxSize.width,
      height: InteractiveDemoLayout.listBoxSize.height,
      alignment: .leading
    )
  )
}

@MainActor
private func presetRowBackgroundStyle(
  preset: Int,
  currentValue: Int
) -> AnyShapeStyle {
  if preset == currentValue {
    return AnyShapeStyle(.fill)
  }
  if preset > currentValue {
    return AnyShapeStyle(.success)
  }
  return AnyShapeStyle(.warning)
}

@MainActor
private func directSetField(
  bindings: InteractiveDemoBindings
) -> AnyView {
  AnyView(
    TextField("type number", text: bindings.inputBuffer)
      .id(InteractiveDemoIdentity.inputField)
      .textFieldStyle(.roundedBorder)
      .frame(
        width: InteractiveDemoLayout.textFieldSize.width,
        height: InteractiveDemoLayout.textFieldSize.height,
        alignment: .leading
      )
  )
}

@MainActor
private func interactiveDemoCapabilityBadge(
  _ profile: TerminalCapabilityProfile,
  appearance: TerminalAppearance
) -> String {
  let glyphLabel =
    switch profile.glyphLevel {
    case .ascii:
      "ascii"
    case .unicode:
      "unicode"
    }

  let colorLabel =
    switch profile.colorLevel {
    case .none:
      "mono"
    case .ansi16:
      "ansi16"
    case .ansi256:
      "ansi256"
    case .trueColor:
      "rgb"
    }

  let styleLabel = profile.emitsStyleEscapeSequences ? "styled" : "plain"
  return "\(glyphLabel) | \(colorLabel) | \(styleLabel) | \(appearance.colorScheme.rawValue)"
}

@MainActor
private func presetRowLabel(
  preset: Int,
  isCurrentValue: Bool
) -> String {
  let currentMarker = isCurrentValue ? " *" : ""
  return "\(preset)\(currentMarker)"
}
