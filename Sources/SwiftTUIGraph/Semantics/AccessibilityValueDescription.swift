extension AccessibilityNode {
  /// A readable value shared by semantic composition and linear presentation.
  /// Selection IDs remain opaque: report their labels, never their tokens.
  package var readableValueDescription: String? {
    if role == .secureField { return "Protected value" }
    if let description = properties?.valueDescription { return description }
    switch control?.value {
    case .boolean(let value): return value ? "On" : "Off"
    case .number(let value):
      let text = String(value)
      return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    case .text(let value):
      if let selection = control?.selection {
        return selection.options.first(where: { $0.id == value })?.label
      }
      return value
    case nil: return nil
    }
  }
}
