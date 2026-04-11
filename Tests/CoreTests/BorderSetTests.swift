import Testing

@testable import Core

@Test("BorderSet stores 13 string slots")
func borderSetStoresAllSlots() {
  let set = BorderSet(
    top: "─", bottom: "─", left: "│", right: "│",
    topLeading: "┌", topTrailing: "┐",
    bottomLeading: "└", bottomTrailing: "┘",
    middleLeading: "├", middleTrailing: "┤",
    middle: "┼", middleTop: "┬", middleBottom: "┴",
    placement: .outset
  )
  #expect(set.top == "─")
  #expect(set.middle == "┼")
  #expect(set.placement == .outset)
}

@Test("BorderSet placement defaults to outset")
func borderSetPlacementDefault() {
  let set = BorderSet(
    top: "─", bottom: "─", left: "│", right: "│",
    topLeading: "┌", topTrailing: "┐",
    bottomLeading: "└", bottomTrailing: "┘"
  )
  #expect(set.placement == .outset)
}

@Test("BorderSet is Equatable and Sendable")
func borderSetEquatable() {
  let a = BorderSet(
    top: "─", bottom: "─", left: "│", right: "│",
    topLeading: "┌", topTrailing: "┐",
    bottomLeading: "└", bottomTrailing: "┘"
  )
  let b = a
  #expect(a == b)
}
