import Testing

@testable import Core
@testable import View

@MainActor
@Suite
struct ToolbarContentBuilderTests {
  // MARK: - buildBlock

  @Test("empty buildBlock produces EmptyToolbarContent")
  func emptyBuildBlockProducesEmpty() {
    let built = ToolbarContentBuilder.buildBlock()
    #expect(type(of: built) == EmptyToolbarContent.self)
  }

  @Test("single-item buildBlock returns the item unchanged")
  func singleItemBuildBlockReturnsItem() {
    let item = ToolbarItem(placement: .primaryAction) {
      Text("Save")
    }
    let built = ToolbarContentBuilder.buildBlock(item)
    #expect(built.placement == .primaryAction)
    #expect(built.commandID == nil)
  }

  @Test("variadic buildBlock packs three items into a TupleToolbarContent")
  func variadicBuildBlockPacksThree() {
    let a = ToolbarItem(placement: .status) { Text("A") }
    let b = ToolbarSpacer(.flexible, placement: .secondaryAction)
    let c = ToolbarItem(placement: .primaryAction) { Text("C") }

    let tuple = ToolbarContentBuilder.buildBlock(a, b, c)
    var records: [ToolbarItemRecord] = []
    flattenToolbarContent(tuple, records: &records)

    #expect(records.count == 3)
    #expect(records[0].placement == .status)
    #expect(records[1].placement == .secondaryAction)
    #expect(records[2].placement == .primaryAction)
  }

  // MARK: - buildIf / buildOptional

  @Test("buildIf wraps a present value")
  func buildIfWrapsPresentValue() {
    let item = ToolbarItem(placement: .status) { Text("Present") }
    let built = ToolbarContentBuilder.buildIf(item)

    var records: [ToolbarItemRecord] = []
    flattenToolbarContent(built, records: &records)

    #expect(records.count == 1)
    #expect(records[0].placement == .status)
  }

  @Test("buildIf wraps nil as empty output")
  func buildIfWrapsNilAsEmpty() {
    let built = ToolbarContentBuilder.buildIf(
      ToolbarItem<Text>?.none
    )
    var records: [ToolbarItemRecord] = []
    flattenToolbarContent(built, records: &records)

    #expect(records.isEmpty)
  }

  // MARK: - buildEither

  @Test("buildEither .first routes through trueContent")
  func buildEitherFirstRoutesTrue() {
    let trueItem = ToolbarItem(placement: .primaryAction) {
      Text("True")
    }
    let conditional:
      ConditionalToolbarContent<
        ToolbarItem<Text>, ToolbarItem<Text>
      > = ToolbarContentBuilder.buildEither(first: trueItem)

    var records: [ToolbarItemRecord] = []
    flattenToolbarContent(conditional, records: &records)

    #expect(records.count == 1)
    #expect(records[0].placement == .primaryAction)
  }

  @Test("buildEither .second routes through falseContent")
  func buildEitherSecondRoutesFalse() {
    let falseItem = ToolbarItem(placement: .secondaryAction) {
      Text("False")
    }
    let conditional:
      ConditionalToolbarContent<
        ToolbarItem<Text>, ToolbarItem<Text>
      > = ToolbarContentBuilder.buildEither(second: falseItem)

    var records: [ToolbarItemRecord] = []
    flattenToolbarContent(conditional, records: &records)

    #expect(records.count == 1)
    #expect(records[0].placement == .secondaryAction)
  }

  // MARK: - buildLimitedAvailability

  @Test("buildLimitedAvailability returns its component unchanged")
  func buildLimitedAvailabilityPassthrough() {
    let item = ToolbarItem(placement: .status) { Text("Limited") }
    let built = ToolbarContentBuilder.buildLimitedAvailability(item)

    var records: [ToolbarItemRecord] = []
    flattenToolbarContent(built, records: &records)

    #expect(records.count == 1)
    #expect(records[0].placement == .status)
  }

  // MARK: - Builder end-to-end through an authored literal

  @Test("builder end-to-end: composes single items, if-else, and variadic blocks")
  func builderEndToEndComposesAllCases() {
    let enabled = true

    @ToolbarContentBuilder
    func build() -> some ToolbarContent {
      ToolbarItem(placement: .status) { Text("Mode") }
      ToolbarItem(placement: .secondaryAction) { Text("Lint") }
      if enabled {
        ToolbarItem(placement: .secondaryAction) { Text("Format") }
      }
      if !enabled {
        ToolbarItem(placement: .secondaryAction) { Text("Disabled") }
      }
      ToolbarItem(placement: .primaryAction) { Text("Save") }
    }

    var records: [ToolbarItemRecord] = []
    flattenToolbarContent(build(), records: &records)

    let placements = records.map(\.placement)
    #expect(
      placements == [
        .status,
        .secondaryAction,
        .secondaryAction,
        .primaryAction,
      ]
    )
  }

  @Test("builder preserves if/else branch selection")
  func builderPreservesConditionalBranchSelection() {
    let showAdvanced = false

    @ToolbarContentBuilder
    func build() -> some ToolbarContent {
      if showAdvanced {
        ToolbarItem(placement: .primaryAction) { Text("Advanced") }
      } else {
        ToolbarItem(placement: .primaryAction) { Text("Basic") }
      }
    }

    var records: [ToolbarItemRecord] = []
    flattenToolbarContent(build(), records: &records)

    #expect(records.count == 1)
  }
}
