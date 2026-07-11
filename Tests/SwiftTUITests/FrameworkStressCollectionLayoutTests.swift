import Foundation
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

// MARK: - Attempt 015: lazy cross-axis alignment churn

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 015 lazy alignment tracks changing row widths")
  func collectionLayout015LazyAlignmentTracksChangingRowWidths() {
    // Hypothesis: retained lazy cross metrics may keep the previous leading
    // edge when alignment and the widest collection child change together.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout015")

    for generation in 0..<24 {
      let trailing = !generation.isMultiple(of: 2)
      let root = CollectionLayout015Root(trailing: trailing)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 20, height: 4)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: 20, height: 4)
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.measuredTree.measuredSize == fresh.measuredTree.measuredSize)
      #expect(retained.semanticSnapshot.scrollRoutes == fresh.semanticSnapshot.scrollRoutes)
    }
  }
}

private struct CollectionLayout015Row: Identifiable {
  let id: Int
  let label: String
  let width: Int
}

@MainActor
private struct CollectionLayout015Root: View {
  let trailing: Bool

  private var rows: [CollectionLayout015Row] {
    trailing
      ? [
        .init(id: 3, label: "wide", width: 14),
        .init(id: 4, label: "narrow", width: 7),
      ]
      : [
        .init(id: 1, label: "short", width: 7),
        .init(id: 2, label: "medium", width: 10),
      ]
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      LazyVStack(alignment: trailing ? .trailing : .leading, spacing: 0) {
        ForEach(rows) { row in
          Text("015 \(row.label)")
            .frame(width: row.width, alignment: .leading)
        }
      }
      .frame(width: 20, alignment: .topLeading)
    }
    .frame(width: 20, height: 4, alignment: .topLeading)
  }
}

// MARK: - Attempt 016: scroll offset after lazy shrink

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 016 lazy shrink clamps retained scroll offset")
  func collectionLayout016LazyShrinkClampsRetainedScrollOffset() {
    // Hypothesis: ScrollViewLayout may reuse the large collection's content
    // bounds and place a shrunken lazy source at an unreachable stale offset.
    let position = CollectionLayout016ScrollBox()
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout016")

    for generation in 0..<20 {
      let count = generation.isMultiple(of: 2) ? 20 : 4
      position.value = .init(x: 0, y: 14)
      let root = CollectionLayout016Root(count: count, position: position)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 16, height: 4)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: 16, height: 4)
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.semanticSnapshot.scrollRoutes == fresh.semanticSnapshot.scrollRoutes)
      let expectedFirst = count == 4 ? "016 row 0" : "016 row 14"
      #expect(retained.rasterSurface.lines.first == expectedFirst)
    }
  }
}

@MainActor
private final class CollectionLayout016ScrollBox {
  var value = ScrollPosition.zero
}

@MainActor
private struct CollectionLayout016Root: View {
  let count: Int
  let position: CollectionLayout016ScrollBox

  var body: some View {
    ScrollView(
      .vertical,
      showsIndicators: false,
      position: Binding(
        get: { position.value },
        set: { position.value = $0 }
      )
    ) {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(0..<count) { value in
          Text("016 row \(value)")
        }
      }
    }
    .frame(width: 16, height: 4, alignment: .topLeading)
  }
}

// MARK: - Attempt 017: lazy viewport proposal churn

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 017 viewport resize rematerializes lazy range")
  func collectionLayout017ViewportResizeRematerializesLazyRange() {
    // Hypothesis: the visible-range binary search may reuse the previous
    // viewport length when only the enclosing frame proposal changes.
    let position = CollectionLayout017ScrollBox()
    position.value = .init(x: 0, y: 5)
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout017")

    for generation in 0..<24 {
      let height = generation.isMultiple(of: 2) ? 2 : 5
      let root = CollectionLayout017Root(height: height, position: position)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 16, height: height)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: 16, height: height)
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.semanticSnapshot.scrollRoutes == fresh.semanticSnapshot.scrollRoutes)
      #expect(retained.rasterSurface.lines.first == "017 row 5")
      #expect(retained.rasterSurface.lines[height - 1] == "017 row \(4 + height)")
    }
  }
}

@MainActor
private final class CollectionLayout017ScrollBox {
  var value = ScrollPosition.zero
}

@MainActor
private struct CollectionLayout017Root: View {
  let height: Int
  let position: CollectionLayout017ScrollBox

  var body: some View {
    ScrollView(
      .vertical,
      showsIndicators: false,
      position: Binding(
        get: { position.value },
        set: { position.value = $0 }
      )
    ) {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(0..<20) { value in
          Text("017 row \(value)")
        }
      }
    }
    .frame(width: 16, height: height, alignment: .topLeading)
  }
}

// MARK: - Attempt 018: prefix removal at retained offset

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 018 prefix removal paints current lazy rows")
  func collectionLayout018PrefixRemovalPaintsCurrentLazyRows() {
    // Hypothesis: retained viewport placement may translate cached children
    // from before a prefix removal instead of materializing the new indices.
    let position = CollectionLayout018ScrollBox()
    position.value = .init(x: 0, y: 5)
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout018")

    for generation in 0..<24 {
      let removedPrefix = !generation.isMultiple(of: 2)
      let values = removedPrefix ? Array(3..<12) : Array(0..<12)
      let root = CollectionLayout018Root(values: values, position: position)
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
      let expectedFirst = removedPrefix ? "018 row 8" : "018 row 5"
      #expect(retained.rasterSurface.lines.first == expectedFirst)
    }
  }
}

@MainActor
private final class CollectionLayout018ScrollBox {
  var value = ScrollPosition.zero
}

@MainActor
private struct CollectionLayout018Root: View {
  let values: [Int]
  let position: CollectionLayout018ScrollBox

  var body: some View {
    ScrollView(
      .vertical,
      showsIndicators: false,
      position: Binding(
        get: { position.value },
        set: { position.value = $0 }
      )
    ) {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(values, id: \.self) { value in
          Text("018 row \(value)")
        }
      }
    }
    .frame(width: 16, height: 3, alignment: .topLeading)
  }
}

// MARK: - Attempt 019: horizontal viewport reorder

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 019 horizontal viewport paints reordered entities")
  func collectionLayout019HorizontalViewportPaintsReorderedEntities() {
    // Hypothesis: an x-offset viewport can retain the previously realized
    // source indices after the same entities reorder horizontally.
    let position = CollectionLayout019ScrollBox()
    position.value = .init(x: 6, y: 0)
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout019")

    for generation in 0..<24 {
      let values = generation.isMultiple(of: 2)
        ? ["A", "B", "C", "D", "E", "F"]
        : ["F", "E", "D", "C", "B", "A"]
      let root = CollectionLayout019Root(values: values, position: position)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 8, height: 2)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: 8, height: 2)
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.semanticSnapshot.scrollRoutes == fresh.semanticSnapshot.scrollRoutes)
      #expect(retained.rasterSurface.lines.first?.hasPrefix(values[2]) == true)
    }
  }
}

@MainActor
private final class CollectionLayout019ScrollBox {
  var value = ScrollPosition.zero
}

@MainActor
private struct CollectionLayout019Root: View {
  let values: [String]
  let position: CollectionLayout019ScrollBox

  var body: some View {
    ScrollView(
      .horizontal,
      showsIndicators: false,
      position: Binding(
        get: { position.value },
        set: { position.value = $0 }
      )
    ) {
      LazyHStack(alignment: .top, spacing: 0) {
        ForEach(values, id: \.self) { value in
          Text(value)
            .frame(width: 3, alignment: .leading)
        }
      }
    }
    .frame(width: 8, height: 2, alignment: .topLeading)
  }
}

// MARK: - Attempt 020: List payload and selection reorder

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 020 List selection follows current row payload order")
  func collectionLayout020ListSelectionFollowsCurrentRowPayloadOrder() {
    // Hypothesis: List may reuse its row-index payload array after same-ID
    // labels reorder, leaving selection chrome on an obsolete visual row.
    let selection = CollectionLayout020SelectionBox()
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout020")

    for generation in 0..<24 {
      let reordered = !generation.isMultiple(of: 2)
      let root = CollectionLayout020Root(
        generation: generation,
        reordered: reordered,
        selection: selection
      )
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 20, height: 6)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: 20, height: 6)
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.semanticSnapshot == fresh.semanticSnapshot)
      #expect(collectionLayoutText(retained).contains("020 B-\(generation)"))
    }
  }
}

@MainActor
private final class CollectionLayout020SelectionBox {
  var value = 2
}

private struct CollectionLayout020Row: Identifiable {
  let id: Int
  let label: String
}

@MainActor
private struct CollectionLayout020Root: View {
  let generation: Int
  let reordered: Bool
  let selection: CollectionLayout020SelectionBox

  private var rows: [CollectionLayout020Row] {
    let values = [
      CollectionLayout020Row(id: 1, label: "A-\(generation)"),
      CollectionLayout020Row(id: 2, label: "B-\(generation)"),
      CollectionLayout020Row(id: 3, label: "C-\(generation)"),
    ]
    return reordered ? [values[2], values[0], values[1]] : values
  }

  var body: some View {
    List(
      selection: Binding(
        get: { selection.value },
        set: { selection.value = $0 }
      )
    ) {
      ForEach(rows) { row in
        Text("020 \(row.label)").tag(row.id)
      }
    }
    .frame(width: 20, height: 6, alignment: .topLeading)
  }
}

// MARK: - Attempt 021: List section reorder

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 021 reordered List sections keep authored item order")
  func collectionLayout021ReorderedListSectionsKeepAuthoredItemOrder() {
    // Hypothesis: recursive List payload collection may retain the old section
    // traversal order after stable section entities move.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout021")

    for generation in 0..<20 {
      let reversed = !generation.isMultiple(of: 2)
      let root = CollectionLayout021Root(generation: generation, reversed: reversed)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 24, height: 12)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: 24, height: 12)
      )
      let order = reversed ? [2, 1] : [1, 2]
      let expectedTokens = order.flatMap { value in
        [
          "021 header \(value)-\(generation)",
          "021 row \(value)-\(generation)",
          "021 footer \(value)-\(generation)",
        ]
      }
      let rendered = collectionLayoutText(retained)

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(collectionLayoutContainsInOrder(expectedTokens, in: rendered))
    }
  }
}

private func collectionLayoutContainsInOrder(_ tokens: [String], in text: String) -> Bool {
  var cursor = text.startIndex
  for token in tokens {
    guard let range = text.range(of: token, range: cursor..<text.endIndex) else {
      return false
    }
    cursor = range.upperBound
  }
  return true
}

private struct CollectionLayout021Section: Identifiable {
  let id: Int
}

@MainActor
private struct CollectionLayout021Root: View {
  let generation: Int
  let reversed: Bool

  private var sections: [CollectionLayout021Section] {
    let values = [CollectionLayout021Section(id: 1), CollectionLayout021Section(id: 2)]
    return reversed ? Array(values.reversed()) : values
  }

  var body: some View {
    List(selection: .constant(1)) {
      ForEach(sections) { section in
        Section {
          Text("021 row \(section.id)-\(generation)").tag(section.id)
        } header: {
          Text("021 header \(section.id)-\(generation)")
        } footer: {
          Text("021 footer \(section.id)-\(generation)")
        }
      }
    }
    .listStyle(.plain)
    .frame(width: 24, height: 12, alignment: .topLeading)
  }
}

// MARK: - Attempt 022: conditional List section breaks

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 022 conditional List section leaves no phantom break")
  func collectionLayout022ConditionalListSectionLeavesNoPhantomBreak() {
    // Hypothesis: List's previousSectionBottomVisibility fold may retain a
    // section break after the middle section departs and later returns.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout022")

    for generation in 0..<24 {
      let includesMiddle = !generation.isMultiple(of: 2)
      let root = CollectionLayout022Root(includesMiddle: includesMiddle)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 22, height: 12)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: 22, height: 12)
      )
      let rendered = collectionLayoutText(retained)

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(rendered.contains("022 middle") == includesMiddle)
      #expect(
        retained.rasterSurface.lines.filter { $0.contains("─") }.count
          == fresh.rasterSurface.lines.filter { $0.contains("─") }.count
      )
    }
  }
}

@MainActor
private struct CollectionLayout022Root: View {
  let includesMiddle: Bool

  var body: some View {
    List(selection: .constant(1)) {
      Section("022 first") {
        Text("022 row first").tag(1)
      }
      if includesMiddle {
        Section("022 middle") {
          Text("022 row middle").tag(2)
        }
      }
      Section("022 last") {
        Text("022 row last").tag(3)
      }
    }
    .listStyle(.plain)
    .frame(width: 22, height: 12, alignment: .topLeading)
  }
}

// MARK: - Attempt 023: empty-to-scrollable List cardinality

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 023 List zero to many rebuilds viewport payload")
  func collectionLayout023ListZeroToManyRebuildsViewportPayload() {
    // Hypothesis: List may retain selection-marker or scroll-extent fields
    // when its collapsed payload crosses between zero and many rows.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout023")

    for generation in 0..<24 {
      let count = generation.isMultiple(of: 2) ? 0 : 10
      let root = CollectionLayout023Root(count: count)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 20, height: 5)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: 20, height: 5)
      )
      let rendered = collectionLayoutText(retained)

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.semanticSnapshot == fresh.semanticSnapshot)
      #expect(rendered.contains("023 row") == (count > 0))
      #expect(rendered.contains("↓") == (count > 0))
    }
  }
}

@MainActor
private struct CollectionLayout023Root: View {
  let count: Int

  var body: some View {
    List(selection: .constant(2)) {
      ForEach(0..<count) { value in
        Text("023 row \(value)").tag(value)
      }
    }
    .listStyle(.insetGrouped)
    .frame(width: 20, height: 5, alignment: .topLeading)
  }
}

// MARK: - Attempt 024: List presentation geometry churn

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 024 List style and indicators replace geometry")
  func collectionLayout024ListStyleAndIndicatorsReplaceGeometry() {
    // Hypothesis: retained List measurement may ignore style or indicator
    // presentation fields and replay an obsolete viewport/chrome inset.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout024")

    for generation in 0..<24 {
      let grouped = generation % 4 >= 2
      let showsIndicators = generation % 2 == 0
      let root = CollectionLayout024Root(
        grouped: grouped,
        showsIndicators: showsIndicators
      )
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 20, height: 6)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: 20, height: 6)
      )
      let rendered = collectionLayoutText(retained)

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.measuredTree.measuredSize == fresh.measuredTree.measuredSize)
      #expect(retained.semanticSnapshot == fresh.semanticSnapshot)
      #expect(rendered.contains("↓") == showsIndicators)
    }
  }
}

@MainActor
private struct CollectionLayout024Root: View {
  let grouped: Bool
  let showsIndicators: Bool

  var body: some View {
    List(selection: .constant(2)) {
      Section("024 section") {
        ForEach(0..<8) { value in
          Text("024 row \(value)").tag(value)
        }
      }
    }
    .listStyle(grouped ? AnyListStyle.insetGrouped : .plain)
    .scrollIndicators(showsIndicators ? .visible : .hidden)
    .frame(width: 20, height: 6, alignment: .topLeading)
  }
}

// MARK: - Attempt 025: duplicate List tag occurrence geometry

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 025 duplicate List tags mark current first occurrence")
  func collectionLayout025DuplicateListTagsMarkCurrentFirstOccurrence() {
    // Hypothesis: List selection geometry may retain the old row index for a
    // duplicate tag after its first occurrence moves or temporarily departs.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout025")
    let listIdentity = testIdentity("CollectionLayout025", "List")
    let a = CollectionLayout025Row(id: 1, tag: 7, label: "A")
    let b = CollectionLayout025Row(id: 2, tag: 7, label: "B")
    let c = CollectionLayout025Row(id: 3, tag: 8, label: "C")
    let variants = [[a, b, c], [b, c, a], [c, a], [a, c, b]]
    var environment = EnvironmentValues()
    environment.focusedIdentity = listIdentity

    for generation in 0..<24 {
      let rows = variants[generation % variants.count]
      let root = CollectionLayout025Root(rows: rows, listIdentity: listIdentity)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          environmentValues: environment,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity],
          applyEnvironmentValues: true
        ),
        proposal: .init(width: 18, height: 6)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(
          identity: rootIdentity,
          environmentValues: environment,
          applyEnvironmentValues: true
        ),
        proposal: .init(width: 18, height: 6)
      )
      let expectedSelectedLabel = rows.first { $0.tag == 7 }!.label
      let selectedLine = retained.rasterSurface.lines.first { $0.contains("▌") }

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(selectedLine?.contains("025 \(expectedSelectedLabel)") == true)
    }
  }
}

private struct CollectionLayout025Row: Identifiable {
  let id: Int
  let tag: Int
  let label: String
}

@MainActor
private struct CollectionLayout025Root: View {
  let rows: [CollectionLayout025Row]
  let listIdentity: Identity

  var body: some View {
    List(selection: .constant(7)) {
      ForEach(rows) { row in
        Text("025 \(row.label)").tag(row.tag)
      }
    }
    .id(listIdentity)
    .listStyle(.plain)
    .frame(width: 18, height: 6, alignment: .topLeading)
  }
}

// MARK: - Attempt 026: VStack spacing across collection reorder

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 026 VStack spacing follows reordered children")
  func collectionLayout026VStackSpacingFollowsReorderedChildren() {
    // Hypothesis: retained stack spacing vectors may remain indexed to the
    // previous ForEach order when both spacing and entity order change.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout026")

    for generation in 0..<24 {
      let spaced = !generation.isMultiple(of: 2)
      let values = spaced ? [3, 1, 2] : [1, 2, 3]
      let root = CollectionLayout026Root(values: values, spacing: spaced ? 2 : 0)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 16, height: 8)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: 16, height: 8)
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.measuredTree.measuredSize == fresh.measuredTree.measuredSize)
      #expect(retained.rasterSurface.lines.first == "026 row \(values[0])")
    }
  }
}

@MainActor
private struct CollectionLayout026Root: View {
  let values: [Int]
  let spacing: Int

  var body: some View {
    VStack(alignment: .leading, spacing: spacing) {
      ForEach(values, id: \.self) { value in
        Text("026 row \(value)")
      }
    }
  }
}

// MARK: - Attempt 027: HStack cross-axis alignment churn

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 027 HStack alignment relocates collection children")
  func collectionLayout027HStackAlignmentRelocatesCollectionChildren() {
    // Hypothesis: retained cross-axis metrics may preserve the prior vertical
    // guide after heterogeneous ForEach children reorder and alignment flips.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout027")

    for generation in 0..<24 {
      let bottom = !generation.isMultiple(of: 2)
      let root = CollectionLayout027Root(bottom: bottom)
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

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.measuredTree.measuredSize == fresh.measuredTree.measuredSize)
    }
  }
}

private struct CollectionLayout027Row: Identifiable {
  let id: Int
  let height: Int
}

@MainActor
private struct CollectionLayout027Root: View {
  let bottom: Bool

  private var rows: [CollectionLayout027Row] {
    let values = [
      CollectionLayout027Row(id: 1, height: 1),
      CollectionLayout027Row(id: 2, height: 3),
      CollectionLayout027Row(id: 3, height: 2),
    ]
    return bottom ? [values[2], values[0], values[1]] : values
  }

  var body: some View {
    HStack(alignment: bottom ? .bottom : .top, spacing: 1) {
      ForEach(rows) { row in
        Text("\(row.id)")
          .frame(width: 4, height: row.height, alignment: .topLeading)
      }
    }
  }
}

// MARK: - Attempt 028: collection layout priority allocation

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 028 scarce width follows reordered row priorities")
  func collectionLayout028ScarceWidthFollowsReorderedRowPriorities() {
    // Hypothesis: stack allocation may reuse priority-sorted child indices
    // from before ForEach entities reorder and their priorities change.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout028")

    for generation in 0..<24 {
      let alternate = !generation.isMultiple(of: 2)
      let root = CollectionLayout028Root(alternate: alternate)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 9, height: 1)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: 9, height: 1)
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.measuredTree.measuredSize == fresh.measuredTree.measuredSize)
      #expect(retained.rasterSurface.lines.first == fresh.rasterSurface.lines.first)
    }
  }
}

private struct CollectionLayout028Row: Identifiable {
  let id: Int
  let label: String
  let priority: Double
}

@MainActor
private struct CollectionLayout028Root: View {
  let alternate: Bool

  private var rows: [CollectionLayout028Row] {
    alternate
      ? [
        .init(id: 3, label: "THREE", priority: 3),
        .init(id: 1, label: "ONEEE", priority: 1),
        .init(id: 2, label: "TWOOO", priority: 2),
      ]
      : [
        .init(id: 1, label: "ONEEE", priority: 3),
        .init(id: 2, label: "TWOOO", priority: 1),
        .init(id: 3, label: "THREE", priority: 2),
      ]
  }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(rows) { row in
        Text(row.label)
          .layoutPriority(row.priority)
      }
    }
    .frame(width: 9, height: 1, alignment: .leading)
  }
}

// MARK: - Attempt 029: custom-layout ForEach flattening

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 029 custom Layout receives every ForEach child")
  func collectionLayout029CustomLayoutReceivesEveryForEachChild() {
    // Hypothesis: LayoutContainer may collapse a ForEach into one Group proxy,
    // hiding current element order and cardinality from the custom algorithm.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout029")
    let variants = [[1, 2, 3], [4, 2], [3, 1, 4, 2], [2]]

    for generation in 0..<24 {
      let values = variants[generation % variants.count]
      let root = CollectionLayout029Root(values: values)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 24, height: 2)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: 24, height: 2)
      )
      let expected = values.map { "29\($0)" }.joined(separator: " ")

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.measuredTree.measuredSize == fresh.measuredTree.measuredSize)
      #expect(retained.rasterSurface.lines.first == expected)
    }
  }
}

private struct CollectionLayout029LinearLayout: Layout {
  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    return .init(
      width: sizes.reduce(0) { $0 + $1.width } + max(0, sizes.count - 1),
      height: sizes.map(\.height).max() ?? 0
    )
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    var x = bounds.origin.x
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      subview.place(
        at: .init(x: x, y: bounds.origin.y),
        anchor: .topLeading,
        proposal: .init(width: size.width, height: size.height)
      )
      x += size.width + 1
    }
  }
}

@MainActor
private struct CollectionLayout029Root: View {
  let values: [Int]

  var body: some View {
    CollectionLayout029LinearLayout() {
      ForEach(values, id: \.self) { value in
        Text("29\(value)")
      }
    }
  }
}

// MARK: - Attempt 030: custom-layout cache cardinality

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 030 custom cache tracks subview cardinality")
  func collectionLayout030CustomCacheTracksSubviewCardinality() {
    // Hypothesis: pass-local custom-layout cache storage may survive a
    // structural update and report the previous ForEach subview count.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout030")
    let counts = [1, 5, 2, 4, 0, 3]

    for generation in 0..<24 {
      let count = counts[generation % counts.count]
      let root = CollectionLayout030Root(count: count)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 24, height: 2)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: 24, height: 2)
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.measuredTree.measuredSize == fresh.measuredTree.measuredSize)
      #expect(retained.measuredTree.measuredSize.width == count * 3)
    }
  }
}

private struct CollectionLayout030Cache: Sendable {
  var count: Int
}

private struct CollectionLayout030CachedLayout: Layout {
  var measurementReuseSignature: String? { "CollectionLayout030.measure" }
  var placementReuseSignature: String? { "CollectionLayout030.place" }

  func makeCache(subviews: LayoutSubviews) -> CollectionLayout030Cache {
    .init(count: subviews.count)
  }

  func updateCache(
    _ cache: inout CollectionLayout030Cache,
    subviews: LayoutSubviews
  ) {
    cache.count = subviews.count
  }

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews _: LayoutSubviews,
    cache: inout CollectionLayout030Cache
  ) -> LayoutSize {
    .init(width: cache.count * 3, height: cache.count == 0 ? 0 : 1)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout CollectionLayout030Cache
  ) {
    for index in subviews.indices {
      subviews[index].place(
        at: .init(x: bounds.origin.x + index * 3, y: bounds.origin.y),
        anchor: .topLeading,
        proposal: .init(width: 3, height: 1)
      )
    }
  }
}

@MainActor
private struct CollectionLayout030Root: View {
  let count: Int

  var body: some View {
    CollectionLayout030CachedLayout() {
      ForEach(0..<count) { value in
        Text("\(value)").frame(width: 3, alignment: .leading)
      }
    }
  }
}

// MARK: - Attempt 031: custom cache proposal revisit

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 031 custom cache follows revisited proposals")
  func collectionLayout031CustomCacheFollowsRevisitedProposals() {
    // Hypothesis: proposal-keyed pass cache entries or retained measurement
    // reuse may feed placement the width recorded for another proposal.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout031")
    let widths = [6, 11, 8, 14, 9, 6, 14, 8, 11, 9]

    for generation in 0..<30 {
      let width = widths[generation % widths.count]
      let root = CollectionLayout031Root()
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: width, height: 1)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: width, height: 1)
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.measuredTree.measuredSize == .init(width: width, height: 1))
      #expect(retained.rasterSurface.lines.first?.last == "X")
    }
  }
}

private struct CollectionLayout031Cache: Sendable {
  var measuredWidth = 0
}

private struct CollectionLayout031ProposalLayout: Layout {
  var measurementReuseSignature: String? { "CollectionLayout031.measure" }
  var placementReuseSignature: String? { "CollectionLayout031.place" }

  func makeCache(subviews _: LayoutSubviews) -> CollectionLayout031Cache {
    .init()
  }

  func updateCache(
    _ cache: inout CollectionLayout031Cache,
    subviews _: LayoutSubviews
  ) {
    cache.measuredWidth = 0
  }

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews _: LayoutSubviews,
    cache: inout CollectionLayout031Cache
  ) -> LayoutSize {
    let width: Int
    switch proposal.width {
    case .finite(let value):
      width = value
    case .unspecified, .infinity:
      width = 1
    }
    cache.measuredWidth = width
    return .init(width: width, height: 1)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout CollectionLayout031Cache
  ) {
    guard let child = subviews.first else {
      return
    }
    child.place(
      at: .init(x: bounds.origin.x + max(0, cache.measuredWidth - 1), y: bounds.origin.y),
      anchor: .topLeading,
      proposal: .init(width: 1, height: 1)
    )
  }
}

@MainActor
private struct CollectionLayout031Root: View {
  var body: some View {
    CollectionLayout031ProposalLayout() {
      Text("X")
    }
  }
}

// MARK: - Attempt 032: AnyLayout axis replacement

extension FrameworkStressCollectionLayoutTests {
  @Test("stress collection layout 032 AnyLayout replaces stack axis contracts")
  func collectionLayout032AnyLayoutReplacesStackAxisContracts() {
    // Hypothesis: a stable AnyLayout container may retain HStack measurement
    // or placement after its erased algorithm becomes a VStack.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("CollectionLayout032")

    for generation in 0..<24 {
      let horizontal = generation.isMultiple(of: 2)
      let root = CollectionLayout032Root(horizontal: horizontal)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: 12, height: 4)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: 12, height: 4)
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.measuredTree.measuredSize == fresh.measuredTree.measuredSize)
      if horizontal {
        #expect(retained.rasterSurface.lines.first == "32A 32B 32C")
      } else {
        #expect(Array(retained.rasterSurface.lines.prefix(3)) == ["32A", "32B", "32C"])
      }
    }
  }
}

@MainActor
private struct CollectionLayout032Root: View {
  let horizontal: Bool

  var body: some View {
    let layout = horizontal
      ? AnyLayout(HStackLayout(alignment: .top, spacing: 1))
      : AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
    layout {
      ForEach(["A", "B", "C"], id: \.self) { value in
        Text("32\(value)")
      }
    }
  }
}
