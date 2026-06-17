import Testing

@testable import SwiftTUICore

@Suite
struct MemoValueComparatorTests {
  private struct EquatableStruct: Equatable {
    var x: Int
    var label: String
  }

  private struct PlainStruct {
    var a: Int
    var b: String
  }

  private struct ClosureStruct {
    var label: String
    var action: () -> Void
  }

  private struct NestedStruct {
    var inner: PlainStruct
    var tag: Int
  }

  private final class RefBox {
    let id: Int
    init(_ id: Int) { self.id = id }
  }

  @Test("Equatable values compare by ==")
  func equatableFastPath() {
    #expect(MemoValueComparator.compare(1, 1) == .equal)
    #expect(MemoValueComparator.compare(1, 2) == .changed)
    #expect(
      MemoValueComparator.compare(
        EquatableStruct(x: 5, label: "a"),
        EquatableStruct(x: 5, label: "a")
      ) == .equal)
    #expect(
      MemoValueComparator.compare(
        EquatableStruct(x: 5, label: "a"),
        EquatableStruct(x: 6, label: "a")
      ) == .changed)
  }

  @Test("Non-Equatable structs compare field-wise via Mirror")
  func fieldWiseStructural() {
    #expect(
      MemoValueComparator.compare(
        PlainStruct(a: 1, b: "x"),
        PlainStruct(a: 1, b: "x")
      ) == .equal)
    #expect(
      MemoValueComparator.compare(
        PlainStruct(a: 1, b: "x"),
        PlainStruct(a: 2, b: "x")
      ) == .changed)
    #expect(
      MemoValueComparator.compare(
        NestedStruct(inner: PlainStruct(a: 1, b: "x"), tag: 7),
        NestedStruct(inner: PlainStruct(a: 1, b: "x"), tag: 7)
      ) == .equal)
    #expect(
      MemoValueComparator.compare(
        NestedStruct(inner: PlainStruct(a: 1, b: "x"), tag: 7),
        NestedStruct(inner: PlainStruct(a: 9, b: "x"), tag: 7)
      ) == .changed)
  }

  @Test("Closure-bearing views are blocked (the interactive-leaf ceiling)")
  func closureFieldsBlock() {
    let a = ClosureStruct(label: "x", action: {})
    let b = ClosureStruct(label: "x", action: {})
    #expect(MemoValueComparator.compare(a, b) == .blocked(.closure))
  }

  @Test("Reference types compare by identity")
  func referenceIdentity() {
    let box = RefBox(1)
    #expect(MemoValueComparator.compare(box, box) == .equal)
    #expect(MemoValueComparator.compare(RefBox(1), RefBox(1)) == .changed)
  }
}
