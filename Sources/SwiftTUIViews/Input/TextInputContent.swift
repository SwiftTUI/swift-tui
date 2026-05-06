package import SwiftTUICore

package struct TextInputContent: View, Sendable {
  package var displayText: String
  package var ownerIdentity: Identity?
  package var caretAnchor: CellPoint?

  nonisolated package init(
    displayText: String,
    ownerIdentity: Identity? = nil,
    caretAnchor: CellPoint? = nil
  ) {
    self.displayText = displayText
    self.ownerIdentity = ownerIdentity
    self.caretAnchor = caretAnchor
  }

  @ViewBuilder
  package var body: some View {
    if let ownerIdentity, let caretAnchor {
      Text(displayText)
        .semanticMetadata(
          .init(
            textInputAccessibilityCursorAnchor: .init(
              ownerIdentity: ownerIdentity,
              anchor: caretAnchor
            )
          )
        )
    } else {
      Text(displayText)
    }
  }
}
