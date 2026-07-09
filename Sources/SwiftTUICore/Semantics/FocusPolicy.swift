extension PlacedNode {
  package var participatesInTopLevelFocus: Bool {
    semanticMetadata.participatesInTopLevelFocus(kind: kind)
  }
}
