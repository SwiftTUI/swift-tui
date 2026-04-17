import Testing

@testable import Core
@testable import View

@MainActor
@Suite
struct ToolbarTests {
  @Test("DefaultTopToolbarStyle and DefaultBottomToolbarStyle conform to ToolbarStyle")
  func defaultStylesExist() {
    let top: any ToolbarStyle = DefaultTopToolbarStyle()
    let bottom: any ToolbarStyle = DefaultBottomToolbarStyle()
    #expect(top.placement == .top)
    #expect(bottom.placement == .bottom)
  }
}
