package struct TextInputContent: View, Sendable {
  package var displayText: String

  nonisolated package init(displayText: String) {
    self.displayText = displayText
  }

  package var body: some View {
    Text(displayText)
  }
}
