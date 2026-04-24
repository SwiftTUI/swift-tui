/// Source-of-truth list of every layout in the Layouts example app.
///
/// The app picker iterates this to render the list; the parameterised
/// smoke test iterates it to prove every entry resolves. Adding a
/// layout is one struct literal in ``all`` — do not introduce any
/// other registration seam.
public enum LayoutCatalog {
  /// All 56 layouts, in picker display order.
  ///
  /// Entries are appended as their underlying layout file lands;
  /// the list is deliberately sparse during the mid-implementation
  /// phase of the plan. `LayoutCatalog` is complete once 56 entries
  /// are listed and `CatalogIntegrityTests.entries_coverAllCategories`
  /// passes.
  public static let all: [LayoutEntry] = []

  public static func entry(id: String) -> LayoutEntry? {
    all.first { $0.id == id }
  }
}
