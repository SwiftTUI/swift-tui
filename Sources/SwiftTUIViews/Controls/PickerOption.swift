/// Declares a picker's option label and selection value without authoring a row view.
///
/// Use this declaration when your model supplies option metadata. The selected
/// picker style owns the row's appearance and interactions. For example:
///
/// ```swift
/// Picker("Mode", selection: $mode) {
///   PickerOption("Compact", value: Mode.compact)
///   PickerOption("Detailed", value: Mode.detailed)
/// }
/// ```
///
/// This is equivalent to an unmodified `Text` with a selection tag. Applying
/// visual or behavioral modifiers does not customize the picker row; implement
/// `PickerStyle` to do that. Outside a picker, it displays its label as text.
public struct PickerOption<Value: Hashable & Sendable>: View {
  private let title: String
  private let value: Value

  /// Creates an option with a plain-text label and its selection value.
  public init<S: StringProtocol>(_ title: S, value: Value) {
    self.title = String(title)
    self.value = value
  }

  /// The text and tag from which the picker extracts option metadata.
  public var body: some View {
    Text(title).tag(value)
  }
}
