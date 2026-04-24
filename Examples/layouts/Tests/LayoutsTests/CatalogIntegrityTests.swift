import Testing

@testable import Layouts

@Suite
struct CatalogIntegrityTests {
  @Test("All catalog IDs are unique")
  func ids_areUnique() {
    let ids = LayoutCatalog.all.map(\.id)
    let unique = Set(ids)
    #expect(ids.count == unique.count, "duplicate IDs: \(ids)")
  }

  @Test("All entries have non-empty title, blurb, and marker")
  func entries_haveRequiredFields() {
    for entry in LayoutCatalog.all {
      #expect(!entry.title.isEmpty, "entry \(entry.id) has empty title")
      #expect(!entry.blurb.isEmpty, "entry \(entry.id) has empty blurb")
      #expect(!entry.marker.isEmpty, "entry \(entry.id) has empty marker")
    }
  }

  @Test("Every Category case is represented by at least one entry")
  func entries_coverAllCategories() {
    let represented = Set(LayoutCatalog.all.map(\.category))
    let missing = Set(LayoutEntry.Category.allCases).subtracting(represented)
    #expect(
      missing.isEmpty,
      "categories with no entries: \(missing.map(\.rawValue).sorted())"
    )
  }

  @Test("entry(id:) returns the matching entry")
  func lookup_returnsMatch() {
    guard let first = LayoutCatalog.all.first else {
      return  // empty catalog is valid during early plan tasks
    }
    #expect(LayoutCatalog.entry(id: first.id)?.id == first.id)
    #expect(LayoutCatalog.entry(id: "::not-a-real-id::") == nil)
  }
}
