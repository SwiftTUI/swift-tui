public import SwiftTUICore

extension Text {
  /// Marks this text as one authored paragraph.
  ///
  /// Swift retains ownership of wrapping and placement. A supporting host can
  /// request additional space after paragraphs through its geometry contract;
  /// the space is rounded up to whole terminal rows. Ordinary text, blank rows,
  /// and explicit newlines do not implicitly create paragraph boundaries.
  ///
  /// Apply text styling before this modifier. Hosts without paragraph-spacing
  /// negotiation retain the authored layout without additional spacing.
  public func paragraph() -> some View {
    var text = self
    text.semanticMetadata.isParagraph = true
    return ParagraphText(text: text)
  }
}

private enum HostParagraphSpacingKey: EnvironmentKey, FrameworkEnvironmentKey {
  static let defaultValue = 0
}

extension EnvironmentValues {
  package var hostParagraphSpacing: Int {
    get { self[HostParagraphSpacingKey.self] }
    set { self[HostParagraphSpacingKey.self] = max(0, newValue) }
  }
}

private struct ParagraphText: View {
  let text: Text
  @Environment(\.hostParagraphSpacing) private var spacing

  var body: some View {
    text.padding(.bottom, spacing)
  }
}
