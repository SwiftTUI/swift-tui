/// How animation intent flows through a transaction.
package enum AnimationRequest: Equatable, Sendable {
  /// Use whatever the parent transaction says.
  case inherit
  /// Explicitly suppress animation in this subtree.
  case disabled
  /// Animate with this curve (type-erased box used to avoid depending on
  /// View-layer ``Animation`` from Core).
  case animate(AnimationBox)

  /// Returns the underlying animation box when the request carries one.
  package var animationBoxIfAny: AnimationBox? {
    if case .animate(let box) = self {
      return box
    }
    return nil
  }
}

/// Type-erased animation storage that Core can carry without depending on
/// the View module's ``Animation`` type.
///
/// The View module creates concrete instances; Core only stores and
/// compares them by identity.
package typealias AnimationBox = AnyHashableSendable

private protocol HashableBox: Sendable {
  func hash(into hasher: inout Hasher)
  func isEqual(to other: any HashableBox) -> Bool
  func unwrap<H: Hashable & Sendable>(as _: H.Type) -> H?
}

private struct ConcreteHashableBox<T: Hashable & Sendable>: HashableBox {
  let value: T

  func hash(into hasher: inout Hasher) {
    value.hash(into: &hasher)
  }

  func isEqual(to other: any HashableBox) -> Bool {
    guard let other = other as? ConcreteHashableBox<T> else { return false }
    return value == other.value
  }

  func unwrap<H: Hashable & Sendable>(as _: H.Type) -> H? {
    if let v = value as? H {
      v
    } else {
      nil
    }
  }
}

/// Wrapper that asserts Sendable for hashable values known to be
/// sendable at construction time.
package struct AnyHashableSendable: Hashable, Sendable {
  private let box: any HashableBox

  package init<Item: Hashable & Sendable>(_ item: Item) {
    box = ConcreteHashableBox(value: item)
  }

  package func hash(into hasher: inout Hasher) {
    box.hash(into: &hasher)
  }

  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.box.isEqual(to: rhs.box)
  }

  package func unwrap<H: Hashable & Sendable>(as _: H.Type = H.self) -> H? {
    box.unwrap(as: H.self)
  }
}

// MARK: - AnimationAwareInvalidating

/// Extended invalidation interface that carries animation intent alongside
/// identity invalidation.
///
/// `FrameScheduler` conforms and stores a pending coalesced animation
/// request on `ScheduledFrame`.
package protocol AnimationAwareInvalidating: Invalidating {
  func requestInvalidation(
    of identities: Set<Identity>,
    animation: AnimationRequest,
    batchID: AnimationBatchID?
  )
}

extension AnimationAwareInvalidating {
  /// Back-compat shim for call sites that do not carry a batch ID.
  package func requestInvalidation(
    of identities: Set<Identity>,
    animation: AnimationRequest
  ) {
    requestInvalidation(of: identities, animation: animation, batchID: nil)
  }
}

// MARK: - AnimationBatchID

/// Identifies one logical animation batch — every animation enqueued
/// under the same ``withAnimation(_:_:completion:)`` scope shares the
/// same batch ID, so the controller can fire one completion closure
/// once the whole batch has settled.
///
/// Batch IDs are opaque and never exposed to user code.  They are
/// allocated monotonically by whichever component creates the batch
/// (in practice: ``withAnimation`` on the View side).
package struct AnimationBatchID: Hashable, Sendable {
  package let value: UInt64

  package init(_ value: UInt64) {
    self.value = value
  }
}
