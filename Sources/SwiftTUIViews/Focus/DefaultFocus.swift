public import SwiftTUICore

extension View {
  public func prefersDefaultFocus(
    _ prefersDefaultFocus: Bool = true,
    in namespace: Namespace.ID
  ) -> some View {
    modifier(
      PreferredDefaultFocusModifier(
        prefersDefaultFocus: prefersDefaultFocus,
        namespace: namespace
      )
    )
  }

  public func focusScope(
    _ namespace: Namespace.ID
  ) -> some View {
    modifier(
      DefaultFocusScopeModifier(namespace: namespace)
    )
  }

  public func defaultFocus(
    _ binding: FocusState<Bool>.Binding,
    _ value: Bool = true
  ) -> some View {
    modifier(
      BoolDefaultFocusModifier(
        binding: binding,
        value: value
      )
    )
  }

  public func defaultFocus<Value: Hashable>(
    _ binding: FocusState<Value?>.Binding,
    _ value: Value
  ) -> some View {
    modifier(
      OptionalDefaultFocusModifier(
        binding: binding,
        value: value
      )
    )
  }
}

public struct PreferredDefaultFocusModifier: IterativePrimitiveViewModifier, Sendable, Equatable {
  var prefersDefaultFocus: Bool
  var namespace: Namespace.ID

  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    return content.resolveWork(in: context).map { completed in
      let node = completed
      if prefersDefaultFocus {
        context.localDefaultFocusRegistry?.registerCandidate(
          namespace: namespace,
          identity: node.identity
        )
      }
      return [node]

    }
  }
}

public struct DefaultFocusScopeModifier: IterativePrimitiveViewModifier, Sendable, Equatable {
  var namespace: Namespace.ID

  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    return content.resolveWork(in: context).map { completed in
      var node = completed
      context.localDefaultFocusRegistry?.registerScope(
        namespace: namespace,
        identity: node.identity
      )
      node.semanticMetadata = node.semanticMetadata.merging(
        focusStructureMetadata(scopeBoundary: true)
      )
      return [node]

    }
  }
}

public struct BoolDefaultFocusModifier: IterativePrimitiveViewModifier {
  var binding: FocusState<Bool>.Binding
  var value: Bool

  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    applyDefaultFocus(in: context)
    return content.resolveElementsWork(in: context)
  }

  private func applyDefaultFocus(
    in context: ResolveContext
  ) {
    guard value else {
      return
    }
    // Consume the seed before reading the focus environment: a claim gated on
    // transient focus state would drift sibling modifiers' slot ordinals
    // between frames.
    let seed = consumeDefaultFocusSeed(in: context)
    guard seed.isFresh else {
      return
    }
    guard context.environmentValues.focusedIdentity == nil else {
      recordArrivalDefault(
        binding: binding,
        value: true,
        ownerIdentity: seed.ownerIdentity,
        in: context
      )
      return
    }
    guard !binding.wrappedValue else {
      return
    }
    binding.wrappedValue = true
  }

  private func consumeDefaultFocusSeed(
    in context: ResolveContext
  ) -> (isFresh: Bool, ownerIdentity: Identity?) {
    guard
      let authoringContext = currentAuthoringContext(),
      let modifierOrdinal = authoringContext.ordinalTracker.claimOrdinal(),
      let viewNode = authoringContext.viewNode
    else {
      return (true, nil)
    }
    let ordinal = StateSlotOrdinals.defaultFocus(modifierOrdinal)

    let hasSeeded: Bool = viewNode.stateSlot(
      ordinal: ordinal,
      seed: false
    )
    guard !hasSeeded else {
      return (false, viewNode.identity)
    }
    viewNode.setStateSlot(ordinal: ordinal, value: true)
    return (true, viewNode.identity)
  }
}

public struct OptionalDefaultFocusModifier<Value: Hashable>: IterativePrimitiveViewModifier {
  var binding: FocusState<Value?>.Binding
  var value: Value

  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    applyDefaultFocus(in: context)
    return content.resolveElementsWork(in: context)
  }

  private func applyDefaultFocus(
    in context: ResolveContext
  ) {
    // Consume the seed before reading the focus environment — see
    // `BoolDefaultFocusModifier.applyDefaultFocus`.
    let seed = consumeDefaultFocusSeed(in: context)
    guard seed.isFresh else {
      return
    }
    guard context.environmentValues.focusedIdentity == nil else {
      recordArrivalDefault(
        binding: binding,
        value: value,
        ownerIdentity: seed.ownerIdentity,
        in: context
      )
      return
    }
    guard binding.wrappedValue == nil else {
      return
    }
    binding.wrappedValue = value
  }

  private func consumeDefaultFocusSeed(
    in context: ResolveContext
  ) -> (isFresh: Bool, ownerIdentity: Identity?) {
    guard
      let authoringContext = currentAuthoringContext(),
      let modifierOrdinal = authoringContext.ordinalTracker.claimOrdinal(),
      let viewNode = authoringContext.viewNode
    else {
      return (true, nil)
    }
    let ordinal = StateSlotOrdinals.defaultFocus(modifierOrdinal)

    let hasSeeded: Bool = viewNode.stateSlot(
      ordinal: ordinal,
      seed: false
    )
    guard !hasSeeded else {
      return (false, viewNode.identity)
    }
    viewNode.setStateSlot(ordinal: ordinal, value: true)
    return (true, viewNode.identity)
  }
}

/// Records a binding `.defaultFocus` whose fresh subtree resolved while
/// another control already held focus. The stale binding value deliberately
/// does not veto — a departed generation's value must not pin the arriving
/// shape's default; a live authored request does veto, at arm time.
/// Owner-backed positions gate on their seed slot (the caller); owner-less
/// positions (the outermost modifier of a chain never mints an authoring
/// node) dedupe on the resolve-context identity in the registry — without
/// one of those lifetimes, re-recording every resolve would re-steal focus
/// each frame.
@MainActor
private func recordArrivalDefault<Value: Equatable>(
  binding: FocusState<Value>.Binding,
  value: Value,
  ownerIdentity: Identity?,
  in context: ResolveContext
) {
  let lifetime = DefaultFocusArrivalLifetime(
    graph: context.viewGraph,
    ownerNodeID: currentAuthoringContext()?.viewNode?.viewNodeID,
    contextIdentity: context.identity)
  context.focusArrivalRegistry?.recordArrivalDefault(
    DefaultFocusArrivalSnapshot(
      bindingKey: binding.bindingKey,
      ownerIdentity: ownerIdentity,
      contextIdentity: context.identity,
      isLive: { lifetime.isLive() },
      armDefault: {
        guard !binding.hasPendingRequest else {
          return false
        }
        binding.wrappedValue = value
        return true
      }
    )
  )
}

/// An outermost modifier can run before its resolved owner is minted. Bind its
/// lifetime after resolve, then compare node IDs so reusing the same identity
/// after removal creates a fresh arrival. Weak graph storage avoids retaining
/// a graph through the registry's owner-less one-shot history.
@MainActor
private final class DefaultFocusArrivalLifetime {
  private weak var graph: ViewGraph?
  private let graphBacked: Bool
  private var ownerNodeID: ViewNodeID?
  private let contextIdentity: Identity

  init(graph: ViewGraph?, ownerNodeID: ViewNodeID?, contextIdentity: Identity) {
    self.graph = graph
    self.graphBacked = graph != nil
    self.ownerNodeID = ownerNodeID
    self.contextIdentity = contextIdentity
  }

  func isLive() -> Bool {
    guard graphBacked else { return true }
    guard let graph else { return false }
    if let ownerNodeID { return graph.nodeForViewNodeID(ownerNodeID) != nil }
    guard let owner = graph.nodeForIdentity(contextIdentity) else { return false }
    ownerNodeID = owner.viewNodeID
    return true
  }
}
