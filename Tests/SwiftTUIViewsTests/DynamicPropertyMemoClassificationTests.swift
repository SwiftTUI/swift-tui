import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

// Only graph-slot wrappers whose visible values are covered by recorded graph
// dependencies may disappear from memo comparison. A custom DynamicProperty's
// box and configuration are authored inputs unless it can use the framework's
// package-only storage marker.
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
private struct ErasedStorageHost {
  let _storage: any DynamicProperty
  let label: String
}

@MainActor
struct DynamicPropertyMemoClassificationTests {
  @Test("a custom wrapper's storage remains an authored memo input")
  func customWrapperStorageIsCompared() {
    // The wrapper's private box may hold evaluation-visible state. Treating
    // every DynamicProperty field as graph-slot identity false-equals two
    // independently authored wrapper values.
    let first = CustomWrapperHost(constant: 1, label: "same")
    let second = CustomWrapperHost(constant: 1, label: "same")
    #expect(MemoValueComparator.compare(first, second) == .changed)

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

  @Test("diagnostic storage omission requires marker certification on both children")
  func storageClassificationRequiresBothChildrenToBeCertified() {
    let certified = ErasedStorageHost(_storage: State(initialValue: 0), label: "same")
    let uncertified = ErasedStorageHost(_storage: Binding.constant(0), label: "same")

    #expect(MemoValueComparator.compare(certified, uncertified) == .changed)
  }

  @Test("diagnostic storage omission requires the same marker-backed child type")
  func storageClassificationRequiresMatchingCertifiedTypes() {
    let state = ErasedStorageHost(_storage: State(initialValue: 0), label: "same")
    let focus = ErasedStorageHost(_storage: FocusState<Bool>(), label: "same")

    #expect(MemoValueComparator.compare(state, focus) == .changed)
  }
}
