import Testing

@testable import Core
@testable import View

@MainActor
@Suite
struct DismissStackTests {
  @Test("dismiss stack chooses topmost eligible entry")
  func dismissStackChoosesTopmostEligibleEntry() {
    var dismissed: [String] = []
    let stack = DismissStack(entries: [
      entry("sheet", zIndex: 200, activationOrdinal: 1, acceptsEscape: true) {
        dismissed.append("sheet")
      },
      entry("toast", zIndex: 300, activationOrdinal: 1, acceptsEscape: false) {
        dismissed.append("toast")
      },
      entry("dialog", zIndex: 240, activationOrdinal: 1, acceptsEscape: true) {
        dismissed.append("dialog")
      },
    ])

    stack.topmostEscapeDismissAction()?()

    #expect(dismissed == ["dialog"])
  }

  @Test("dismiss stack uses activation ordinal within the same z index")
  func dismissStackUsesActivationOrdinalWithinSameZIndex() {
    var dismissed: [String] = []
    let stack = DismissStack(entries: [
      entry("first", zIndex: 200, activationOrdinal: 1, acceptsEscape: true) {
        dismissed.append("first")
      },
      entry("second", zIndex: 200, activationOrdinal: 2, acceptsEscape: true) {
        dismissed.append("second")
      },
    ])

    stack.topmostEscapeDismissAction()?()

    #expect(dismissed == ["second"])
  }

  private func entry(
    _ id: String,
    zIndex: Int,
    activationOrdinal: Int,
    acceptsEscape: Bool,
    dismiss: @escaping @MainActor @Sendable () -> Void
  ) -> DismissStackEntry<String> {
    DismissStackEntry(
      id: id,
      ordering: .init(
        zIndex: zIndex,
        activationOrdinal: activationOrdinal,
        stableTieBreaker: id
      ),
      acceptsEscape: acceptsEscape,
      dismiss: dismiss
    )
  }
}
