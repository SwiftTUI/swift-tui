import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct CapturedSubviewStateTests {
  @Test("reference-valued state survives omission and is released with its declaring group")
  func referenceState() {
    let probe = ReferenceStateProbe()
    let renderer = DefaultRenderer()
    let context = ResolveContext(identity: testIdentity("RetainedReference"))
    _ = renderer.render(ReferenceGroup(hidden: false, probe: probe), context: context)
    probe.binding?.wrappedValue = RetainedReference(7)
    weak let retained = probe.binding?.wrappedValue
    let hidden = renderer.render(ReferenceGroup(hidden: true, probe: probe), context: context)
    #expect(hidden.diagnostics.runtime.issues.isEmpty)
    #expect(retained != nil)
    let shown = renderer.render(ReferenceGroup(hidden: false, probe: probe), context: context)
    #expect(shown.rasterSurface.lines.joined(separator: "\n").contains("Reference 7"))
    #expect(probe.binding?.wrappedValue === retained)
    probe.binding = nil
    _ = renderer.render(Text("Removed"), context: context)
    #expect(retained == nil)
  }

  @Test("identified children retain their own values when reordered while omitted")
  func dormantReorder() {
    let probe = IndexedStateProbe()
    let renderer = DefaultRenderer()
    let context = ResolveContext(identity: testIdentity("RetainedReorder"))
    _ = renderer.render(
      IndexedGroup(hidden: false, ids: [1, 2, 3], probe: probe), context: context)
    probe.bindings[1]?.wrappedValue = 11
    probe.bindings[2]?.wrappedValue = 22
    probe.bindings[3]?.wrappedValue = 33
    let updated = renderer.render(
      IndexedGroup(hidden: false, ids: [1, 2, 3], probe: probe), context: context)
    #expect(updated.rasterSurface.lines.joined(separator: "\n").contains("Item 1:11"))
    _ = renderer.render(IndexedGroup(hidden: true, ids: [1, 2, 3], probe: probe), context: context)
    _ = renderer.render(IndexedGroup(hidden: true, ids: [3, 1, 2], probe: probe), context: context)
    let shown = renderer.render(
      IndexedGroup(hidden: false, ids: [3, 1, 2], probe: probe), context: context)
    let text = shown.rasterSurface.lines.joined(separator: "\n")
    for (id, value) in [(1, 11), (2, 22), (3, 33)] {
      #expect(text.contains("Item \(id):\(value)"))
    }
  }

  @Test("nested omitted groups retain the inner state through outer host teardown")
  func nestedOmission() {
    let probe = IndexedStateProbe()
    let renderer = DefaultRenderer()
    let context = ResolveContext(identity: testIdentity("NestedRetention"))
    _ = renderer.render(
      NestedGroup(outerHidden: false, innerHidden: false, probe: probe), context: context)
    probe.bindings[1]?.wrappedValue = 42
    let updated = renderer.render(
      NestedGroup(outerHidden: false, innerHidden: false, probe: probe), context: context)
    #expect(updated.rasterSurface.lines.joined(separator: "\n").contains("Item 1:42"))
    _ = renderer.render(
      NestedGroup(outerHidden: false, innerHidden: true, probe: probe), context: context)
    _ = renderer.render(
      NestedGroup(outerHidden: true, innerHidden: true, probe: probe), context: context)
    _ = renderer.render(
      NestedGroup(outerHidden: false, innerHidden: true, probe: probe), context: context)
    let shown = renderer.render(
      NestedGroup(outerHidden: false, innerHidden: false, probe: probe), context: context)
    #expect(shown.rasterSurface.lines.joined(separator: "\n").contains("Item 1:42"))
  }

}

@MainActor private final class RetainedReference {
  let value: Int
  init(_ value: Int) { self.value = value }
}
@MainActor private final class ReferenceStateProbe {
  var binding: Binding<RetainedReference>?
}
private struct ReferenceGroup: View {
  let hidden: Bool
  let probe: ReferenceStateProbe
  var body: some View {
    ControlGroup("References") { ReferenceChild(probe: probe) }
      .controlGroupStyle(hidden ? AnyControlGroupStyle.compactMenu : .horizontal)
  }
}
private struct ReferenceChild: View {
  @State private var value = RetainedReference(0)
  let probe: ReferenceStateProbe
  var body: some View {
    probe.binding = $value
    return Text("Reference \(value.value)")
  }
}
@MainActor private final class IndexedStateProbe {
  var bindings: [Int: Binding<Int>] = [:]
}
private struct IndexedGroup: View {
  let hidden: Bool
  let ids: [Int]
  let probe: IndexedStateProbe
  var body: some View {
    ControlGroup("Items") {
      ForEach(ids, id: \.self) { id in IndexedChild(id: id, probe: probe) }
    }.controlGroupStyle(hidden ? AnyControlGroupStyle.compactMenu : .vertical)
  }
}
private struct IndexedChild: View {
  @State private var value = 0
  let id: Int
  let probe: IndexedStateProbe
  var body: some View {
    probe.bindings[id] = $value
    return Text("Item \(id):\(value)")
  }
}
private struct NestedGroup: View {
  let outerHidden: Bool
  let innerHidden: Bool
  let probe: IndexedStateProbe
  var body: some View {
    ControlGroup("Outer") {
      IndexedGroup(hidden: innerHidden, ids: [1], probe: probe)
    }.controlGroupStyle(outerHidden ? AnyControlGroupStyle.compactMenu : .horizontal)
  }
}
