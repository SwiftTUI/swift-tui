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

// MARK: - Attempt 002: same-entity lazy payload measurement

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 002 lazy row payload remeasures downstream offsets")
  func collectionLayout002LazyRowPayloadRemeasuresDownstreamOffsets() {
    // Hypothesis: the indexed source's ID-only measurement signature may
    // preserve a short row allocation when that same entity starts wrapping.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout002")

    for generation in 0..<20 {
      let root = CollectionLayout002Root(expanded: !generation.isMultiple(of: 2))
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 12, height: 8)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: 12, height: 8)
      )

      let matchesFreshGeometry =
        retained.rasterSurface == fresh.rasterSurface
        && retained.measuredTree.measuredSize == fresh.measuredTree.measuredSize
        && collectionLayoutText(retained).contains("002 tail")
      if root.expanded {
        withKnownIssue(
          "Lazy indexed allocation reuses the prior same-ID row measurement after payload growth"
        ) {
          #expect(matchesFreshGeometry)
        }
      } else {
        #expect(matchesFreshGeometry)
      }
    }
  }
}

private struct CollectionLayout002Row: Identifiable {
  let id: Int
  let label: String
}

@MainActor
private struct CollectionLayout002Root: View {
  let expanded: Bool

  private var rows: [CollectionLayout002Row] {
    [
      .init(
        id: 1,
        label: expanded ? "one payload wraps across several terminal rows" : "one"
      ),
      .init(id: 2, label: "tail"),
    ]
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(rows) { row in
          Text("002 \(row.label)")
        }
      }
    }
    .frame(width: 12, height: 8, alignment: .topLeading)
  }
}
