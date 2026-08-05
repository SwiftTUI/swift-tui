import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

// The diagnostic memo comparator must classify property-wrapper storage by
// `DynamicProperty` conformance, not by a hard-coded type-name prefix list
// (plan 2026-08-04-003 §1.3): the prefix list omits four of the nine
// built-ins and every third-party wrapper, so the shadow oracle mis-compares
// values that differ only in wrapper box identity.
@propertyWrapper
@MainActor
private struct BoxedProbe: DynamicProperty {
  private final class Box {}

  private let box = Box()
  var constant: Int

  init(constant: Int) {
    self.constant = constant
  }

  var wrappedValue: Int {
    constant
  }
}

@MainActor
private struct CustomWrapperHost {
  @BoxedProbe private var probe: Int
  var label: String

  init(constant: Int, label: String) {
    _probe = BoxedProbe(constant: constant)
    self.label = label
  }
}

@MainActor
private struct NamespaceHost {
  @Namespace private var namespace
  var label: String

  init(label: String) {
    self.label = label
  }
}

@MainActor
struct DynamicPropertyMemoClassificationTests {
  @Test("a custom wrapper's storage is classified as wrapper storage")
  func customWrapperStorageIsSkipped() {
    // The two values differ only in the wrapper's private box identity —
    // slot identity, not data. The comparator must not let the box identity
    // read as a value change.
    let first = CustomWrapperHost(constant: 1, label: "same")
    let second = CustomWrapperHost(constant: 1, label: "same")
    #expect(MemoValueComparator.compare(first, second) == .equal)

    // A genuine data change outside the wrapper storage still reads as one.
    let changed = CustomWrapperHost(constant: 1, label: "different")
    #expect(MemoValueComparator.compare(first, changed) == .changed)
  }

  @Test("@Namespace storage is classified as wrapper storage")
  func namespaceStorageIsSkipped() {
    // `Namespace` was one of the four built-ins the retired prefix list
    // omitted: each instance composes a fresh `State` box, so two hosts
    // differing only in that box identity mis-compared as `.changed`.
    let first = NamespaceHost(label: "same")
    let second = NamespaceHost(label: "same")
    #expect(MemoValueComparator.compare(first, second) == .equal)
  }

  @Test("directly-declared @State storage stays classified as wrapper storage")
  func stateStorageClassificationIsUnchanged() {
    @MainActor
    struct StateHost {
      @State var count = 0
      var label: String

      init(label: String) {
        self.label = label
      }
    }
    let first = StateHost(label: "same")
    let second = StateHost(label: "same")
    #expect(MemoValueComparator.compare(first, second) == .equal)
  }
}
