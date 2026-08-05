import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph
@testable import SwiftTUIViews

/// Binding projections (org plan 2026-08-04-002 §4), pinned to the SwiftUI
/// ground truth probed on 2026-08-05:
///
/// - An explicit ambient scope (`withAnimation`/`withTransaction`) wins over
///   the binding-stored transaction — including a stored
///   `disablesAnimations` losing to an ambient animation. The stored
///   transaction governs only writes made outside any explicit scope.
/// - `init?(_:)` returns nil for a nil base, unwraps otherwise, writes
///   through as `.some`, and a read after the base became nil traps.
/// - The wrapping `init(_:)` ignores nil writes — the base keeps its value.
/// - `dynamicMember` projections carry the stored transaction along.
@MainActor
@Suite("Binding projections")
struct BindingProjectionTests {
  /// A binding over plain box storage whose setter records the ambient
  /// animation request visible at write time — the exact value
  /// `ViewNode.setStateSlot` would read for a slot-backed binding.
  @MainActor
  private final class WriteProbe {
    var value = 0.0
    var observedRequests: [AnimationRequest] = []

    var binding: Binding<Double> {
      Binding(
        get: { self.value },
        set: { newValue in
          self.observedRequests.append(AnimationContextStorage.currentRequest)
          self.value = newValue
        }
      )
    }
  }

  // MARK: - Projection shape

  @Test("animation(_:) stores the animation on the binding's transaction")
  func animationStoresTransaction() {
    let probe = WriteProbe()
    let animation = Animation.easeIn(duration: .milliseconds(120))

    let projected = probe.binding.animation(animation)

    #expect(projected.transaction.animation == animation)
  }

  @Test("animation(nil) maps to disablesAnimations")
  func animationNilDisables() {
    let probe = WriteProbe()

    let projected = probe.binding.animation(nil)

    #expect(projected.transaction.disablesAnimations)
  }

  @Test("transaction(_:) replaces the stored transaction")
  func transactionProjectionStores() {
    let probe = WriteProbe()
    let animation = Animation.linear(duration: .milliseconds(80))
    var transaction = Transaction()
    transaction.animation = animation

    let projected = probe.binding.transaction(transaction)

    #expect(projected.transaction.animation == animation)
  }

  @Test("dynamicMember projections carry the stored transaction")
  func dynamicMemberPropagatesTransaction() {
    struct Pair {
      var a = 0.0
      var b = 0.0
    }
    @MainActor final class PairBox {
      var pair = Pair()
    }
    let box = PairBox()
    let animation = Animation.easeOut(duration: .milliseconds(90))
    let base = Binding(
      get: { box.pair },
      set: { box.pair = $0 }
    ).animation(animation)

    let member = base.a

    #expect(member.transaction.animation == animation)
    // Pre-existing behavior stays: the source token does not propagate
    // through member projections (see the subscript's doc comment).
    #expect(member.bindingSourceID == nil)
  }

  // MARK: - Write-time precedence (SwiftUI probe 2026-08-05)

  @Test("the stored transaction governs writes outside any explicit scope")
  func storedAppliesWhenAmbientInert() {
    let probe = WriteProbe()
    let animation = Animation.easeIn(duration: .milliseconds(120))

    probe.binding.animation(animation).wrappedValue = 1

    #expect(probe.value == 1)
    #expect(probe.observedRequests == [.animate(animation.animationBox)])
  }

  @Test("an explicit ambient animation wins over the stored animation")
  func ambientWinsOverStoredAnimation() {
    let probe = WriteProbe()
    let stored = Animation.easeIn(duration: .milliseconds(120))
    let ambient = Animation.linear(duration: .milliseconds(250))

    withAnimation(ambient) {
      probe.binding.animation(stored).wrappedValue = 1
    }

    #expect(probe.observedRequests == [.animate(ambient.animationBox)])
  }

  @Test("an explicit ambient animation wins over stored disablesAnimations")
  func ambientWinsOverStoredDisables() {
    let probe = WriteProbe()
    let ambient = Animation.linear(duration: .milliseconds(250))
    var snapping = Transaction()
    snapping.disablesAnimations = true

    withAnimation(ambient) {
      probe.binding.transaction(snapping).wrappedValue = 1
    }

    #expect(probe.observedRequests == [.animate(ambient.animationBox)])
  }

  @Test("stored disablesAnimations snaps writes outside any explicit scope")
  func storedDisablesAppliesWhenAmbientInert() {
    let probe = WriteProbe()
    var snapping = Transaction()
    snapping.disablesAnimations = true

    probe.binding.transaction(snapping).wrappedValue = 1

    #expect(probe.observedRequests == [.disabled])
  }

  @Test("both halves of a control double-write carry the stored intent")
  func doubleWriteBothCarryStoredIntent() {
    // Text input performs two writes per mutation (text, then cursor —
    // TextInputControlSupport); each goes through the same wrappedValue
    // setter, so each independently re-applies the stored transaction.
    let probe = WriteProbe()
    let animation = Animation.easeIn(duration: .milliseconds(120))
    let projected = probe.binding.animation(animation)

    projected.wrappedValue = 1
    projected.wrappedValue = 2

    #expect(
      probe.observedRequests == [
        .animate(animation.animationBox),
        .animate(animation.animationBox),
      ]
    )
  }

  // MARK: - Optional unwrap / wrap inits

  @Test("init? unwraps a some base, reads and writes through")
  func unwrapInitReadsAndWritesThrough() throws {
    @MainActor final class OptionalBox {
      var value: Int? = 5
    }
    let box = OptionalBox()
    let base = Binding(
      get: { box.value },
      set: { box.value = $0 }
    )

    let unwrapped = try #require(Binding<Int>(base))

    #expect(unwrapped.wrappedValue == 5)
    unwrapped.wrappedValue = 7
    #expect(box.value == 7)
  }

  @Test("init? fails for a nil base")
  func unwrapInitFailsForNilBase() {
    @MainActor final class OptionalBox {
      var value: Int?
    }
    let box = OptionalBox()
    let base = Binding(
      get: { box.value },
      set: { box.value = $0 }
    )

    #expect(Binding<Int>(base) == nil)
  }

  @Test("init? carries the base's stored transaction")
  func unwrapInitCarriesStoredTransaction() throws {
    @MainActor final class OptionalBox {
      var value: Int? = 5
    }
    let box = OptionalBox()
    let animation = Animation.easeIn(duration: .milliseconds(120))
    let base = Binding(
      get: { box.value },
      set: { box.value = $0 }
    ).animation(animation)

    let unwrapped = try #require(Binding<Int>(base))

    #expect(unwrapped.transaction.animation == animation)
  }

  @Test("a read after the base became nil traps with a loud diagnostic")
  func unwrapReadAfterNilBaseTraps() async {
    // SwiftUI probe (2026-08-05): the same read crashes there too (SIGTRAP);
    // SwiftTUI adds a precise message. Exit-test body stays capture-free.
    await #expect(processExitsWith: .failure) {
      await MainActor.run {
        final class OptionalBox {
          var value: Int? = 5
        }
        let box = OptionalBox()
        let base = Binding<Int?>(
          get: { box.value },
          set: { box.value = $0 }
        )
        guard let unwrapped = Binding<Int>(base) else {
          return
        }
        box.value = nil
        _ = unwrapped.wrappedValue
      }
    }
  }

  @Test("the wrapping init reads some and writes through non-nil values")
  func wrapInitReadsAndWritesSome() {
    @MainActor final class PlainBox {
      var value = 3
    }
    let box = PlainBox()
    let base = Binding(
      get: { box.value },
      set: { box.value = $0 }
    )

    let wrapped = Binding<Int?>(base)

    #expect(wrapped.wrappedValue == 3)
    wrapped.wrappedValue = 9
    #expect(box.value == 9)
  }

  @Test("the wrapping init ignores nil writes")
  func wrapInitIgnoresNilWrites() {
    // SwiftUI probe (2026-08-05): writing nil through the wrapping
    // projection leaves the base untouched.
    @MainActor final class PlainBox {
      var value = 3
    }
    let box = PlainBox()
    let base = Binding(
      get: { box.value },
      set: { box.value = $0 }
    )

    let wrapped = Binding<Int?>(base)
    wrapped.wrappedValue = nil

    #expect(box.value == 3)
  }

  @Test("init(projectedValue:) copies the binding, stored transaction included")
  func initProjectedValueCopies() {
    let probe = WriteProbe()
    let animation = Animation.easeIn(duration: .milliseconds(120))
    let projected = probe.binding.animation(animation)

    let copy = Binding(projectedValue: projected)

    #expect(copy.transaction.animation == animation)
    copy.wrappedValue = 4
    #expect(probe.value == 4)
  }

  // MARK: - Equality seams

  @Test("focused-value equality ignores the stored transaction")
  func focusedValueEqualityIgnoresStoredTransaction() {
    let probe = WriteProbe()
    let plain = probe.binding
    let animated = probe.binding.animation(.easeIn(duration: .milliseconds(120)))

    // Equal wrapped values compare equal regardless of stored transactions,
    // so a `.animation`-projected focused-value binding still converges the
    // focus-sync loop.
    #expect(plain.isFocusedValueEqual(to: animated))

    probe.value = 1
    let changed = Binding(
      get: { 2.0 },
      set: { _ in }
    )
    #expect(!plain.isFocusedValueEqual(to: changed))
  }
}
