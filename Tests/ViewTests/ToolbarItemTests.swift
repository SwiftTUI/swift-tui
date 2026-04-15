import Testing

@testable import Core
@testable import View

@MainActor
@Suite
struct ToolbarItemTests {
  // MARK: - Free-form ToolbarItem

  @Test("free-form ToolbarItem stores the view body and no commandID")
  func freeFormToolbarItemStoresBody() {
    let item = ToolbarItem(placement: .status) {
      Text("Mode")
    }
    #expect(item.placement == .status)
    #expect(item.commandID == nil)
    #expect(item.hasCustomBody == true)
  }

  @Test("free-form ToolbarItem defaults to .automatic placement")
  func freeFormToolbarItemDefaultsAutomatic() {
    let item = ToolbarItem {
      Text("Body")
    }
    #expect(item.placement == .automatic)
  }

  // MARK: - Closure-form command-bound ToolbarItem

  @Test("closure-form command-bound ToolbarItem stores commandID and body")
  func commandBoundClosureFormStoresCommandID() {
    let item = ToolbarItem(
      placement: .primaryAction,
      command: "save"
    ) {
      Text("Save File")
    }
    #expect(item.placement == .primaryAction)
    #expect(item.commandID == "save")
    #expect(item.hasCustomBody == true)
  }

  // MARK: - Text-specialized command-bound ToolbarItem

  @Test("Text-specialized command-bound ToolbarItem uses placeholder body")
  func textSpecializedCommandBoundUsesPlaceholder() {
    let item = ToolbarItem(.primaryAction, command: "save")
    #expect(item.placement == .primaryAction)
    #expect(item.commandID == "save")
    #expect(item.hasCustomBody == false)
  }

  @Test("Text-specialized overload defaults to .automatic placement")
  func textSpecializedCommandBoundDefaultsAutomatic() {
    let item = ToolbarItem(command: "save")
    #expect(item.placement == .automatic)
    #expect(item.commandID == "save")
  }

  // MARK: - ToolbarItemGroup

  @Test("ToolbarItemGroup stores placement and inner content")
  func toolbarItemGroupStoresPlacementAndContent() {
    let group = ToolbarItemGroup(placement: .primaryAction) {
      ToolbarItem { Text("A") }
      ToolbarItem { Text("B") }
    }
    #expect(group.placement == .primaryAction)

    var records: [ToolbarItemRecord] = []
    flattenToolbarContent(group, records: &records)
    // Both inner items inherit the group's placement because they
    // declare `.automatic` themselves.
    #expect(records.count == 2)
    #expect(records[0].placement == .primaryAction)
    #expect(records[1].placement == .primaryAction)
  }

  @Test("ToolbarItemGroup inner explicit placement wins over group placement")
  func toolbarItemGroupInnerExplicitWins() {
    let group = ToolbarItemGroup(placement: .primaryAction) {
      ToolbarItem(placement: .status) { Text("Explicit status") }
      ToolbarItem { Text("Inherited primary") }
    }

    var records: [ToolbarItemRecord] = []
    flattenToolbarContent(group, records: &records)

    #expect(records.count == 2)
    #expect(records[0].placement == .status)
    #expect(records[1].placement == .primaryAction)
  }

  // MARK: - ToolbarSpacer

  @Test("ToolbarSpacer stores sizing and placement")
  func toolbarSpacerStoresSizingAndPlacement() {
    let flexible = ToolbarSpacer(.flexible, placement: .secondaryAction)
    #expect(flexible.sizing == .flexible)
    #expect(flexible.placement == .secondaryAction)

    let fixed = ToolbarSpacer(.fixed(4), placement: .primaryAction)
    #expect(fixed.sizing == .fixed(4))
    #expect(fixed.placement == .primaryAction)
  }

  @Test("ToolbarSpacer defaults to flexible sizing and automatic placement")
  func toolbarSpacerDefaults() {
    let spacer = ToolbarSpacer()
    #expect(spacer.sizing == .flexible)
    #expect(spacer.placement == .automatic)
  }

  // MARK: - ToolbarSpacer flatten

  @Test("ToolbarSpacer flattens into a spacer record")
  func toolbarSpacerFlattensToSpacer() {
    let spacer = ToolbarSpacer(.fixed(3), placement: .secondaryAction)
    var records: [ToolbarItemRecord] = []
    flattenToolbarContent(spacer, records: &records)

    #expect(records.count == 1)
    #expect(records[0].placement == .secondaryAction)
    if case .spacer(let sizing) = records[0].shape {
      #expect(sizing == .fixed(3))
    } else {
      Issue.record("Expected spacer shape, got \(records[0].shape)")
    }
  }
}
