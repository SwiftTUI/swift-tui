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

// MARK: - Attempt 006: zero-height lazy-row transitions

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 006 empty lazy rows release following offsets")
  func collectionLayout006EmptyLazyRowsReleaseFollowingOffsets() {
    // Hypothesis: zero-height indexed children may leave stale offsets or a
    // visible-range boundary that hides the stable row following them.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout006")

    for generation in 0..<20 {
      let root = CollectionLayout006Root(expanded: !generation.isMultiple(of: 2))
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 16, height: 6)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: 16, height: 6)
      )
      let expectedHeight = root.expanded ? 6 : 1
      let matchesCurrentEmptyRows =
        retained.rasterSurface == fresh.rasterSurface
        && retained.semanticSnapshot.scrollRoutes.first?.contentBounds.size.height == expectedHeight
        && collectionLayoutText(retained).contains("006 stable tail")

      if root.expanded {
        withKnownIssue(
          "Lazy indexed allocation retains zero-height rows after their conditional content appears"
        ) {
          #expect(matchesCurrentEmptyRows)
        }
      } else {
        #expect(matchesCurrentEmptyRows)
      }
    }
  }
}

private struct CollectionLayout006Row: Identifiable {
  let id: Int
  let isVisible: Bool
}

@MainActor
private struct CollectionLayout006Root: View {
  let expanded: Bool

  private var rows: [CollectionLayout006Row] {
    (0..<6).map { value in
      .init(id: value, isVisible: expanded || value == 5)
    }
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(rows) { row in
          if row.isVisible {
            Text(row.id == 5 ? "006 stable tail" : "006 row \(row.id)")
          }
        }
      }
    }
    .frame(width: 16, height: 6, alignment: .topLeading)
  }
}

// MARK: - Attempt 007: conditional indexed-source replacement

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 007 conditional lazy source follows the live branch")
  func collectionLayout007ConditionalLazySourceFollowsLiveBranch() {
    // Hypothesis: ConditionalContent may retain the prior branch's indexed
    // source cache even though the child context and row geometry changed.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout007")

    for generation in 0..<20 {
      let alternate = !generation.isMultiple(of: 2)
      let root = CollectionLayout007Root(alternate: alternate)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 18, height: 6)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: 18, height: 6)
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.semanticSnapshot.scrollRoutes == fresh.semanticSnapshot.scrollRoutes)
      let expected = alternate ? "007 alternate 30" : "007 primary 1"
      #expect(collectionLayoutText(retained).contains(expected))
    }
  }
}

@MainActor
private struct CollectionLayout007Root: View {
  let alternate: Bool

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      LazyVStack(alignment: .leading, spacing: 0) {
        if alternate {
          ForEach([30, 20, 10], id: \.self) { value in
            Text("007 alternate \(value)")
              .frame(height: 2, alignment: .topLeading)
          }
        } else {
          ForEach([1, 2, 3], id: \.self) { value in
            Text("007 primary \(value)")
          }
        }
      }
    }
    .frame(width: 18, height: 6, alignment: .topLeading)
  }
}

// MARK: - Attempt 008: Group-forwarded indexed source

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 008 Group forwards current lazy collection order")
  func collectionLayout008GroupForwardsCurrentLazyCollectionOrder() {
    // Hypothesis: Group's indexed-source forwarding may preserve the first
    // ForEach provider after the wrapped collection changes count and order.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout008")
    let variants = [[1, 2, 3], [4, 3, 2, 1], [2], [5, 1, 3]]

    for generation in 0..<24 {
      let values = variants[generation % variants.count]
      let root = CollectionLayout008Root(values: values)
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
      #expect(collectionLayoutText(retained).contains("008 grouped \(values[0])"))
    }
  }
}

@MainActor
private struct CollectionLayout008Root: View {
  let values: [Int]

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      LazyVStack(alignment: .leading, spacing: 0) {
        Group {
          ForEach(values, id: \.self) { value in
            Text("008 grouped \(value)")
          }
        }
      }
    }
    .frame(width: 15, height: 5, alignment: .topLeading)
  }
}

// MARK: - Attempt 009: nested indexed collections

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 009 nested ForEach expands every lazy child")
  func collectionLayout009NestedForEachExpandsEveryLazyChild() {
    // Hypothesis: a nested ForEach resolves as one Group-valued indexed row,
    // overlapping its inner elements instead of contributing stack children.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout009")

    for generation in 0..<16 {
      let reversed = !generation.isMultiple(of: 2)
      let outer = reversed ? [2, 1] : [1, 2]
      let inner = reversed ? [3, 2, 1] : [1, 2, 3]
      let root = CollectionLayout009Root(outer: outer, inner: inner)
      let snapshot = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 18, height: 6)
      )
      let expected = outer.flatMap { outerValue in
        inner.map { "009 \(outerValue).\($0)" }
      }
      let expandedEveryNestedChild =
        Array(snapshot.rasterSurface.lines.prefix(6)) == expected
        && snapshot.semanticSnapshot.scrollRoutes.first?.contentBounds.size.height == 6

      withKnownIssue(
        "Indexed LazyVStack overlaps each inner ForEach as one Group-valued outer row"
      ) {
        #expect(expandedEveryNestedChild)
      }
    }
  }
}

@MainActor
private struct CollectionLayout009Root: View {
  let outer: [Int]
  let inner: [Int]

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(outer, id: \.self) { outerValue in
          ForEach(inner, id: \.self) { innerValue in
            Text("009 \(outerValue).\(innerValue)")
          }
        }
      }
    }
    .frame(width: 18, height: 6, alignment: .topLeading)
  }
}

// MARK: - Attempt 010: heterogeneous LazyHStack reorder

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 010 horizontal lazy reorder rebuilds row offsets")
  func collectionLayout010HorizontalLazyReorderRebuildsRowOffsets() {
    // Hypothesis: horizontal indexed allocation may preserve widths by source
    // index after stable entities move to different collection positions.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout010")

    for generation in 0..<24 {
      let root = CollectionLayout010Root(rotated: !generation.isMultiple(of: 2))
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 16, height: 3)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: 16, height: 3)
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.semanticSnapshot.scrollRoutes == fresh.semanticSnapshot.scrollRoutes)
      #expect(retained.measuredTree.measuredSize == fresh.measuredTree.measuredSize)
    }
  }
}

private struct CollectionLayout010Row: Identifiable {
  let id: Int
  let width: Int
}

@MainActor
private struct CollectionLayout010Root: View {
  let rotated: Bool

  private var rows: [CollectionLayout010Row] {
    let base = [
      CollectionLayout010Row(id: 1, width: 4),
      CollectionLayout010Row(id: 2, width: 8),
      CollectionLayout010Row(id: 3, width: 3),
    ]
    return rotated ? [base[1], base[2], base[0]] : base
  }

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      LazyHStack(alignment: .top, spacing: 1) {
        ForEach(rows) { row in
          Text("\(row.id)")
            .frame(width: row.width, height: 2, alignment: .topLeading)
        }
      }
    }
    .frame(width: 16, height: 3, alignment: .topLeading)
  }
}

// MARK: - Attempt 011: multi-view horizontal lazy rows

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 011 horizontal lazy ForEach flattens row children")
  func collectionLayout011HorizontalLazyForEachFlattensRowChildren() {
    // Hypothesis: LazyHStack's indexed source also treats each multi-view
    // ForEach result as an overlaying Group instead of distinct horizontal cells.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout011")

    for generation in 0..<16 {
      let values = generation.isMultiple(of: 2) ? [1, 2, 3] : [3, 2, 1]
      let root = CollectionLayout011Root(values: values)
      let snapshot = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 20, height: 2)
      )
      let rendered = collectionLayoutText(snapshot)
      let flattenedEveryChild =
        values.allSatisfy { rendered.contains("A\($0)") && rendered.contains("B\($0)") }
        && snapshot.semanticSnapshot.scrollRoutes.first?.contentBounds.size.width == 17

      withKnownIssue(
        "Indexed LazyHStack treats a multi-view ForEach row as one overlapping Group"
      ) {
        #expect(flattenedEveryChild)
      }
    }
  }
}

@MainActor
private struct CollectionLayout011Root: View {
  let values: [Int]

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      LazyHStack(alignment: .top, spacing: 1) {
        ForEach(values, id: \.self) { value in
          Text("A\(value)")
          Text("B\(value)")
        }
      }
    }
    .frame(width: 20, height: 2, alignment: .topLeading)
  }
}

// MARK: - Attempt 012: duplicate-ID occurrence geometry

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 012 duplicate lazy IDs keep occurrence geometry")
  func collectionLayout012DuplicateLazyIDsKeepOccurrenceGeometry() {
    // Hypothesis: duplicate IDs produce the same measurement-signature path,
    // so swapping occurrence payloads may preserve heights by old index.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout012")

    for generation in 0..<20 {
      let swapped = !generation.isMultiple(of: 2)
      let root = CollectionLayout012Root(swapped: swapped)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 18, height: 6)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: 18, height: 6)
      )
      let matchesOccurrenceGeometry =
        retained.rasterSurface == fresh.rasterSurface
        && retained.semanticSnapshot.scrollRoutes == fresh.semanticSnapshot.scrollRoutes

      #expect(matchesOccurrenceGeometry)
    }
  }
}

private struct CollectionLayout012Row: Identifiable {
  let id: Int
  let label: String
  let height: Int
}

@MainActor
private struct CollectionLayout012Root: View {
  let swapped: Bool

  private var rows: [CollectionLayout012Row] {
    let short = CollectionLayout012Row(id: 7, label: "A", height: 1)
    let tall = CollectionLayout012Row(id: 7, label: "B", height: 3)
    let tail = CollectionLayout012Row(id: 8, label: "C", height: 1)
    return swapped ? [tall, short, tail] : [short, tall, tail]
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(rows) { row in
          Text("012 \(row.label) h\(row.height)")
            .frame(height: row.height, alignment: .topLeading)
        }
      }
    }
    .frame(width: 18, height: 6, alignment: .topLeading)
  }
}

// MARK: - Attempt 013: stable lazy entity payload topology

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 013 stable lazy entity updates payload extent")
  func collectionLayout013StableLazyEntityUpdatesPayloadExtent() {
    // Hypothesis: an ID-stable indexed row may preserve its scalar Text
    // measurement after its payload becomes a two-child stack.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout013")

    for generation in 0..<20 {
      let root = CollectionLayout013Root(expanded: !generation.isMultiple(of: 2))
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 18, height: 4)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: 18, height: 4)
      )
      let matchesCurrentTopology =
        retained.rasterSurface == fresh.rasterSurface
        && retained.semanticSnapshot.scrollRoutes == fresh.semanticSnapshot.scrollRoutes

      if root.expanded {
        withKnownIssue(
          "Lazy indexed allocation retains the scalar extent after an ID-stable row becomes a stack"
        ) {
          #expect(matchesCurrentTopology)
        }
      } else {
        #expect(matchesCurrentTopology)
      }
    }
  }
}

@MainActor
private struct CollectionLayout013Root: View {
  let expanded: Bool

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach([13], id: \.self) { _ in
          if expanded {
            VStack(alignment: .leading, spacing: 0) {
              Text("013 expanded top")
              Text("013 expanded bottom")
            }
          } else {
            Text("013 collapsed")
          }
        }
      }
    }
    .frame(width: 18, height: 4, alignment: .topLeading)
  }
}

// MARK: - Attempt 014: indexed-to-eager lazy topology switching

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 014 lazy fast path and fallback preserve order")
  func collectionLayout014LazyFastPathAndFallbackPreserveOrder() {
    // Hypothesis: replacing an indexed single-ForEach LazyVStack with the
    // mixed-static fallback can reuse the former child topology or offsets.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout014")

    for generation in 0..<20 {
      let mixed = !generation.isMultiple(of: 2)
      let root = CollectionLayout014Root(mixed: mixed)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 18, height: 5)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: 18, height: 5)
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.semanticSnapshot.scrollRoutes == fresh.semanticSnapshot.scrollRoutes)
      let expectedFirst = mixed ? "014 static head" : "014 row 1"
      #expect(retained.rasterSurface.lines.first == expectedFirst)
    }
  }
}

@MainActor
private struct CollectionLayout014Root: View {
  let mixed: Bool

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      if mixed {
        LazyVStack(alignment: .leading, spacing: 0) {
          Text("014 static head")
          ForEach([1, 2, 3], id: \.self) { value in
            Text("014 row \(value)")
          }
        }
      } else {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach([1, 2, 3], id: \.self) { value in
            Text("014 row \(value)")
          }
        }
      }
    }
    .frame(width: 18, height: 5, alignment: .topLeading)
  }
}
