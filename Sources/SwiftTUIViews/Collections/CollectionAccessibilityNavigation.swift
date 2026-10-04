import SwiftTUICore

/// Identity-only access never resolves an offscreen row. Lazy sources share
/// their retained membership signature instead of rebuilding an N-row index.
package struct CollectionAccessibilitySource: Sendable {
  let count: Int
  let signature: IndexedChildMeasurementSignature
  let identity: @Sendable (Int) -> Identity
  let index: @Sendable (Identity) -> Int?

  package init(indexed source: any IndexedChildSource) {
    count = source.count
    signature = source.measurementSignature
    identity = { source.elementIdentity(at: $0) }
    index = { source.elementIndex(matching: .init(identity: $0)) }
  }

  package init(identities: [Identity]) {
    count = identities.count
    signature = .init(elementPaths: identities.lazy.map(\.path))
    identity = { identities[$0] }
    index = { identities.firstIndex(of: $0) }
  }
}

private struct CollectionReviewBookmark: Equatable, Sendable {
  var identity: Identity
  var index: Int
}

private struct CollectionReviewState: Equatable, Sendable {
  var signature: IndexedChildMeasurementSignature?
  var epoch: UInt64 = 0
  var current: CollectionReviewBookmark?
  var previous: CollectionReviewBookmark?
  var requestGeneration: UInt64 = 0
  var requestPending = false
  var isReviewed = false
}

/// Stores two logical bookmarks and one request, independent of dataset size.
/// Resolve only reconciles identities; scrolling happens in input or the
/// post-commit preparation of an explicit assistive-focus request.
@MainActor
package struct CollectionAccessibilityNavigation {
  package let metadata: AccessibilityCollectionNavigation
  private let reviewedRow: Int
  private let rowReview: HostedCollectionReview

  package init?(
    source: CollectionAccessibilitySource, currency: CollectionScrollCurrency?,
    owner: SwiftTUICore.ViewNode?, context: ResolveContext
  ) {
    guard source.count > 0, let currency else { return nil }
    func reveal(_ row: Int) -> Bool {
      // Disabled collections have no physical scroll route. Their logical
      // reading control can still place an anchor; layout clamps its window.
      currency.visibleLineCount > 0 ? currency.reveal(row: row) : currency.setAnchorRow(row)
    }
    let ordinal = StateSlotOrdinals.collectionAccessibilityReview
    func read() -> CollectionReviewState {
      withPersistentDormantStateSlot {
        owner?.stateSlot(ordinal: ordinal, seed: CollectionReviewState()) ?? .init()
      }
    }
    var state = read()
    if state.signature != source.signature {
      precondition(state.epoch < UInt64.max, "Collection membership generation exhausted")
      state.epoch += 1
      state.signature = source.signature
      let index =
        state.current.flatMap { source.index($0.identity) }
        ?? min(state.current?.index ?? currency.effectiveAnchorRow, source.count - 1)
      state.current = .init(identity: source.identity(index), index: index)
      state.previous = state.previous.flatMap { bookmark in
        source.index(bookmark.identity).map { .init(identity: bookmark.identity, index: $0) }
      }
      if state.isReviewed {
        precondition(state.requestGeneration < UInt64.max, "Collection review request exhausted")
        state.requestGeneration += 1
        state.requestPending = true
      }
      withPersistentDormantStateSlot { owner?.setStateSlotSilently(ordinal: ordinal, value: state) }
    }
    guard let current = state.current else { return nil }
    let epoch = state.epoch
    let navigatorIdentity = context.identity.child("AccessibilityCollection\(epoch)")
    let reviewIdentity = navigatorIdentity.child(.indexed("Row", index: current.index))
    metadata = .init(
      identity: navigatorIdentity, position: current.index + 1,
      count: source.count, canReturn: state.previous != nil)
    reviewedRow = current.index
    rowReview = .init(identity: reviewIdentity, ownerNodeID: owner?.viewNodeID)

    let intake = HandlerDescriptorIntake(context: context)
    intake.composeAccessibilityAction(identity: navigatorIdentity, preservingExisting: false) {
      action in
      var next = read()
      guard next.epoch == epoch, let current = next.current else { return .unsupported }
      var destination = current.index
      var readItem = false
      var returning = false
      switch action {
      case .increment: destination += 1
      case .decrement: destination -= 1
      case .setValue(.number(let value)):
        guard value.isFinite, value.rounded() == value, value >= 1, value <= Double(source.count)
        else { return .invalidValue }
        destination = Int(value) - 1
      case .custom("First item"): destination = 0
      case .custom("Last item"): destination = source.count - 1
      case .custom("Next page"):
        destination += max(1, currency.visibleLineCount / currency.geometry.rowSpan - 1)
      case .custom("Previous page"):
        destination -= max(1, currency.visibleLineCount / currency.geometry.rowSpan - 1)
      case .custom("Read item"): readItem = true
      case .custom("Return to previous item"):
        guard let previous = next.previous else { return .unsupported }
        destination = previous.index
        returning = true
        readItem = true
      default: return .unsupported
      }
      destination = min(max(0, destination), source.count - 1)
      let changed = destination != current.index
      if changed {
        next.previous = current
        next.current = .init(identity: source.identity(destination), index: destination)
        next.isReviewed = false
      } else if returning {
        return .unchanged
      }
      if readItem {
        precondition(next.requestGeneration < UInt64.max, "Collection review request exhausted")
        next.requestGeneration += 1
        next.requestPending = true
      }
      let moved = reveal(destination)
      guard changed || readItem || moved else { return .unchanged }
      withPersistentDormantStateSlot {
        owner?.setStateSlot(ordinal: ordinal, value: next, invalidationIdentity: context.identity)
      }
      return .changed
    }

    let requestGeneration = state.requestGeneration
    context.localFocusBindingRegistry?.register(
      identity: reviewIdentity,
      bindingKey: .init(owner: owner?.stateOwnerHandle, suffix: .stateSlot(ordinal: ordinal)),
      bindingID: navigatorIdentity.path, hasPendingRequest: state.requestPending,
      isSelected: true, domain: .accessibility, requestGeneration: requestGeneration,
      prepareFocus: { reveal(current.index) },
      preparationIdentity: navigatorIdentity,
      applyRuntimeFocus: { focused in
        var latest = read()
        guard latest.epoch == epoch, latest.requestGeneration == requestGeneration else {
          return false
        }
        latest.isReviewed = focused
        if focused { latest.requestPending = false }
        withPersistentDormantStateSlot {
          owner?.setStateSlotSilently(ordinal: ordinal, value: latest)
        }
        return false
      })
  }

  package func decorate(_ original: ResolvedNode, index: Int) -> ResolvedNode {
    var node = original
    node.semanticMetadata.hostedCollectionItem?.review = index == reviewedRow ? rowReview : nil
    return node
  }
}
