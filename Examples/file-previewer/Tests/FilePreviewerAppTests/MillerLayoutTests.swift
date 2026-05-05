import FilePreviewerApp
import Testing

struct MillerLayoutTests {
  @Test("two columns keep the left column at thirty cells")
  func twoColumnWidthAllocation() {
    #expect(MillerLayout.columnWidths(totalWidth: 100, columnCount: 2) == [30, 70])
  }

  @Test("three columns keep non-last columns fixed and assign the remainder to preview")
  func threeColumnWidthAllocation() {
    #expect(MillerLayout.columnWidths(totalWidth: 100, columnCount: 3) == [30, 30, 40])
  }

  @Test("narrow terminals split columns evenly before assigning the remainder")
  func narrowWidthAllocation() {
    #expect(MillerLayout.columnWidths(totalWidth: 61, columnCount: 3) == [20, 20, 21])
  }

  @Test("empty column sets allocate no widths")
  func emptyColumnAllocation() {
    #expect(MillerLayout.columnWidths(totalWidth: 100, columnCount: 0).isEmpty)
  }
}
