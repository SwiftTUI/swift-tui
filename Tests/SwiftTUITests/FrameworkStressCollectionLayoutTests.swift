import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI collection and layout stress behavior", .serialized)
struct FrameworkStressCollectionLayoutTests {}

private func collectionLayoutText(_ snapshot: RenderSnapshot) -> String {
  snapshot.rasterSurface.lines.joined(separator: "\n")
}

// MARK: - Attempt 001: lazy ArraySlice indexing

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 001 lazy ArraySlice honors its live start index")
  func collectionLayout001LazyArraySliceHonorsLiveStartIndex() {
    // Hypothesis: ForEachIndexedChildSource may treat its zero-based child
    // offset as the collection's native index and read the wrong ArraySlice row.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout001")

    for generation in 0..<20 {
      let lowerBound = generation % 7
      let root = CollectionLayout001Root(lowerBound: lowerBound)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      let fresh = DefaultRenderer().render(root, context: .init(identity: rootIdentity))

      #expect(retained.rasterSurface == fresh.rasterSurface)
      let rendered = collectionLayoutText(retained)
      #expect(rendered.contains("001 row \(lowerBound)"))
      #expect(rendered.contains("001 row \(lowerBound + 1)"))
      #expect(rendered.contains("001 row \(lowerBound + 2)"))
      #expect(!rendered.contains("001 row \(lowerBound + 4)"))
    }
  }
}

@MainActor
private struct CollectionLayout001Root: View {
  let lowerBound: Int

  var body: some View {
    let values = Array(0..<12)
    ScrollView(.vertical, showsIndicators: false) {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(values[lowerBound..<(lowerBound + 5)], id: \.self) { value in
          Text("001 row \(value)")
        }
      }
    }
    .frame(width: 16, height: 3, alignment: .topLeading)
  }
}
