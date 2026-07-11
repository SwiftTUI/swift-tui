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

// MARK: - Attempt 003: heterogeneous lazy-row reorder

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 003 lazy reorder rebuilds heterogeneous row offsets")
  func collectionLayout003LazyReorderRebuildsHeterogeneousRowOffsets() {
    // Hypothesis: a reordered indexed source may reuse the prior allocation
    // vector by child index, assigning each entity another row's height.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout003")

    for generation in 0..<24 {
      let root = CollectionLayout003Root(rotated: !generation.isMultiple(of: 2))
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 14, height: 8)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: 14, height: 8)
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.measuredTree.measuredSize == fresh.measuredTree.measuredSize)
      #expect(retained.semanticSnapshot.scrollRoutes == fresh.semanticSnapshot.scrollRoutes)
    }
  }
}

private struct CollectionLayout003Row: Identifiable {
  let id: Int
  let height: Int
}

@MainActor
private struct CollectionLayout003Root: View {
  let rotated: Bool

  private var rows: [CollectionLayout003Row] {
    let base = [
      CollectionLayout003Row(id: 1, height: 1),
      CollectionLayout003Row(id: 2, height: 3),
      CollectionLayout003Row(id: 3, height: 2),
    ]
    return rotated ? [base[2], base[0], base[1]] : base
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(rows) { row in
          Text("003 row \(row.id) h\(row.height)")
            .frame(height: row.height, alignment: .topLeading)
        }
      }
    }
    .frame(width: 14, height: 6, alignment: .topLeading)
  }
}

// MARK: - Attempt 004: lazy indexed cardinality churn

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 004 lazy allocation follows collection cardinality")
  func collectionLayout004LazyAllocationFollowsCollectionCardinality() {
    // Hypothesis: retained lazy allocation may keep childSizes or content
    // length from a prior source after the ForEach count grows or contracts.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout004")
    let counts = [1, 7, 3, 9, 2, 6]

    for generation in 0..<24 {
      let count = counts[generation % counts.count]
      let root = CollectionLayout004Root(count: count)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 15, height: 5)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: 15, height: 5)
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.semanticSnapshot.scrollRoutes == fresh.semanticSnapshot.scrollRoutes)
      #expect(retained.measuredTree.measuredSize == fresh.measuredTree.measuredSize)
      #expect(collectionLayoutText(retained).contains("004 row 0 of \(count)"))
    }
  }
}

@MainActor
private struct CollectionLayout004Root: View {
  let count: Int

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(0..<count) { value in
          Text("004 row \(value) of \(count)")
        }
      }
    }
    .frame(width: 15, height: 5, alignment: .topLeading)
  }
}

// MARK: - Attempt 005: multi-view lazy ForEach rows

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 005 lazy ForEach flattens every authored row child")
  func collectionLayout005LazyForEachFlattensEveryAuthoredRowChild() {
    // Hypothesis: the indexed lazy source may expose one Group per ForEach
    // element, causing that row's multiple authored children to overlap.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout005")

    for generation in 0..<16 {
      let reversed = !generation.isMultiple(of: 2)
      let values = reversed ? [3, 2, 1] : [1, 2, 3]
      let root = CollectionLayout005Root(values: values)
      let snapshot = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 18, height: 6)
      )
      let expected = values.flatMap { value in
        ["005 label \(value)", "005 detail \(value)"]
      }

      let flattenedEveryChild =
        Array(snapshot.rasterSurface.lines.prefix(6)) == expected
        && snapshot.semanticSnapshot.scrollRoutes.first?.contentBounds.size.height == 6
      withKnownIssue(
        "Indexed LazyVStack treats a multi-view ForEach row as one overlapping Group"
      ) {
        #expect(flattenedEveryChild)
      }
    }
  }
}

@MainActor
private struct CollectionLayout005Root: View {
  let values: [Int]

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(values, id: \.self) { value in
          Text("005 label \(value)")
          Text("005 detail \(value)")
        }
      }
    }
    .frame(width: 18, height: 6, alignment: .topLeading)
  }
}
