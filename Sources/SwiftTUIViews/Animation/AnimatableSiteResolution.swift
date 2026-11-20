import SwiftTUICore

// Custom `Animatable` views, view modifiers and shapes.
//
// The animation controller interpolates a fixed list of values on resolved
// nodes. A view or a modifier that conforms to `Animatable` asks for more:
// its body has to run again with interpolated `animatableData` on every tick.
// The pieces here find those conformers where a body is about to be
// evaluated and ask the controller, through `AnimatableValueSink`, for the
// data to evaluate it with. The controller owns everything about the
// animation; this file only finds the site and writes the data into the
// working copy the body consumes. The value the author wrote stays the
// reuse and memo witness.

/// How a view type takes part in value animation.
package enum AnimatableSiteKind: Sendable {
  /// The type has no `animatableData` to animate.
  case none
  /// The view itself conforms to `Animatable`. For a `ModifiedContent` that
  /// means its content and its modifier both do, and the whole value is one
  /// site.
  case view
  /// A `ModifiedContent` whose modifier conforms to `Animatable` while the
  /// whole does not: the modifier is the site.
  case modifier
}

/// A view that carries a modifier the resolver may have to animate.
/// `ModifiedContent` is the only conformer.
@MainActor
package protocol AnimatableModifierForwarding {
  static var forwardedModifierType: Any.Type { get }

  /// Replaces the modifier by what `transform` makes of it, when the modifier
  /// conforms to `Animatable`.
  mutating func replaceForwardedAnimatableModifier(
    _ transform: (any Animatable) -> any Animatable
  )
}

/// The per-type answer to "does this view take part in value animation?".
///
/// Every body evaluation asks, so the answer is one dictionary lookup after
/// the first resolve of a type. A type whose data is `EmptyAnimatableData`
/// has nothing to animate and counts as a non-conformer.
@MainActor
package enum AnimatableSiteDetection {
  private static var kinds: [ObjectIdentifier: AnimatableSiteKind] = [:]
  private static var animatableDataTypes: [ObjectIdentifier: Bool] = [:]

  package static func kind<V: View>(of type: V.Type) -> AnimatableSiteKind {
    let key = ObjectIdentifier(type)
    if let known = kinds[key] {
      return known
    }
    let kind: AnimatableSiteKind
    if hasAnimatableData(type) {
      kind = .view
    } else if let forwarding = type as? any AnimatableModifierForwarding.Type,
      hasAnimatableData(forwarding.forwardedModifierType)
    {
      kind = .modifier
    } else {
      kind = .none
    }
    kinds[key] = kind
    return kind
  }

  /// Whether `type` conforms to `Animatable` with data that can change.
  package static func hasAnimatableData(_ type: Any.Type) -> Bool {
    let key = ObjectIdentifier(type)
    if let known = animatableDataTypes[key] {
      return known
    }
    let result = (type as? any Animatable.Type).map { dataCanChange($0) } ?? false
    animatableDataTypes[key] = result
    return result
  }

  private static func dataCanChange<A: Animatable>(_: A.Type) -> Bool {
    A.AnimatableData.self != EmptyAnimatableData.self
  }
}

/// Resolves one `Animatable` site: names it, and asks the bound sink for the
/// data its body evaluates with.
@MainActor
package enum AnimatableSiteResolver {
  /// Returns `view` with the `animatableData` to present, and the context
  /// its body resolves in.
  ///
  /// The site is the context's identity and the next site position there.
  /// The returned context has that position taken, so a site further in at
  /// the same identity gets the next one. This holds with or without a
  /// sink, so a scratch evaluation of a view names its sites as the live one
  /// does. Without a sink the view is returned as written.
  package static func presenting<V: View>(
    _ view: V,
    kind: AnimatableSiteKind,
    in context: ResolveContext
  ) -> (view: V, bodyContext: ResolveContext) {
    if case .none = kind {
      return (view, context)
    }
    var bodyContext = context
    bodyContext.animatableSiteOrdinalCursor = context.animatableSiteOrdinalCursor + 1
    guard let sink = AnimatableValueStorage.effectiveSink else {
      return (view, bodyContext)
    }
    let request = Request(
      sink: sink,
      site: AnimatableValueSite(
        identity: context.identity,
        ordinal: context.animatableSiteOrdinalCursor
      ),
      ownerNodeID: ownerNodeID(in: context),
      transaction: context.transaction,
      reducesMotion: context.environmentValues.renderingReduceMotion
    )
    switch kind {
    case .none:
      return (view, bodyContext)
    case .view:
      guard let animatable = view as? any Animatable,
        let presented = request.presenting(animatable) as? V
      else {
        return (view, bodyContext)
      }
      return (presented, bodyContext)
    case .modifier:
      guard var forwarding = view as? any AnimatableModifierForwarding else {
        return (view, bodyContext)
      }
      forwarding.replaceForwardedAnimatableModifier { request.presenting($0) }
      return ((forwarding as? V) ?? view, bodyContext)
    }
  }

  /// The node that evaluates the site resolving in `context`: the node
  /// being evaluated when it belongs to the context's graph, else the node
  /// at the identity. `nil` outside a graph.
  private static func ownerNodeID(in context: ResolveContext) -> ViewNodeID? {
    guard let viewGraph = context.viewGraph else {
      return nil
    }
    if let current = ViewNodeContext.current, current.ownerGraph === viewGraph {
      return current.viewNodeID
    }
    return viewGraph.nodeForIdentity(context.identity)?.viewNodeID
  }

  private struct Request {
    var sink: any AnimatableValueSink
    var site: AnimatableValueSite
    var ownerNodeID: ViewNodeID?
    var transaction: TransactionSnapshot
    var reducesMotion: Bool

    @MainActor
    func presenting<A: Animatable>(_ value: A) -> A {
      let target = value.animatableData
      let data = sink.presentedAnimatableData(
        for: target,
        at: site,
        ownerNodeID: ownerNodeID,
        transaction: transaction,
        reducesMotion: reducesMotion
      )
      // At rest the body gets the value exactly as written: a setter that
      // does not round-trip its getter never runs.
      guard data != target else {
        return value
      }
      var presented = value
      presented.animatableData = data
      return presented
    }
  }
}

extension ModifiedContent: AnimatableModifierForwarding
where Content: View, Modifier: ViewModifier {
  package static var forwardedModifierType: Any.Type {
    Modifier.self
  }

  package mutating func replaceForwardedAnimatableModifier(
    _ transform: (any Animatable) -> any Animatable
  ) {
    guard let animatable = modifier as? any Animatable,
      let replaced = transform(animatable) as? Modifier
    else {
      return
    }
    modifier = replaced
  }
}

// MARK: - Shapes

/// A shape that draws with another shape it wraps: a trim or an inset.
///
/// The wrappers are main-actor types that store a base which need not be
/// `Sendable`, so they cannot conform to `Animatable` themselves: a
/// nonisolated `animatableData` cannot reach the base. They forward instead.
/// A wrapper around a shape that conforms to `Animatable` animates as that
/// shape does, by rebuilding itself around each sample of the base.
///
/// The protocol does not refine `Sendable`. The wrappers are `Sendable`
/// already, as main-actor types, and a conformance here that restated it
/// would change how their public `Sendable` conformance is declared.
@MainActor
package protocol AnimatableShapeForwarding {
  static var forwardedShapeType: Any.Type { get }

  /// The shape this one wraps.
  var forwardedShape: any Shape { get }

  /// This shape around `shape` in place of the one it wraps, or `nil` when
  /// `shape` is of another type.
  func replacingForwardedShape(_ shape: any Shape) -> (any Shape)?
}

extension AnimatableSiteDetection {
  private static var animatableShapeTypes: [ObjectIdentifier: Bool] = [:]

  /// Whether a shape of `type` has data to animate: its own, or that of a
  /// shape it wraps, through any depth of trims and insets.
  package static func isAnimatableShape(_ type: Any.Type) -> Bool {
    let key = ObjectIdentifier(type)
    if let known = animatableShapeTypes[key] {
      return known
    }
    let result: Bool
    if hasAnimatableData(type) {
      result = true
    } else if let forwarding = type as? any AnimatableShapeForwarding.Type {
      result = isAnimatableShape(forwarding.forwardedShapeType)
    } else {
      result = false
    }
    animatableShapeTypes[key] = result
    return result
  }
}

extension Shape {
  /// The data and the way back to geometry that a fill, a stroke or a clip of
  /// this shape records when the shape conforms to `Animatable`, or wraps one
  /// that does; `nil` for every other shape.
  ///
  /// `Shape` does not refine `Animatable`, so the conformance is looked up
  /// here, once per type. The geometry closure copies the shape, sets its
  /// data and reads the same geometry the modifier read: `fillGeometry` for a
  /// fill or a clip, `geometry` for a stroke. For a shape that implements
  /// `path(in:)` that evaluates the path in the unit rectangle.
  package func animatableShapeProvider(fills: Bool) -> AnimatableShapeProvider? {
    guard AnimatableSiteDetection.isAnimatableShape(Self.self),
      let source = AnimatableShapeSource(self)
    else {
      return nil
    }
    return source.provider(shapeType: ObjectIdentifier(Self.self), fills: fills)
  }
}

/// An `Animatable` shape and the wrappers between it and the shape a
/// modifier was applied to, outermost first.
@MainActor
private struct AnimatableShapeSource {
  var animatable: any Animatable
  var wrappers: [any AnimatableShapeForwarding] = []

  init?(_ shape: any Shape) {
    var current = shape
    var wrappers: [any AnimatableShapeForwarding] = []
    while true {
      if AnimatableSiteDetection.hasAnimatableData(type(of: current)),
        let animatable = current as? any Animatable
      {
        self.animatable = animatable
        self.wrappers = wrappers
        return
      }
      guard let wrapper = current as? any AnimatableShapeForwarding else {
        return nil
      }
      wrappers.append(wrapper)
      current = wrapper.forwardedShape
    }
  }

  /// `shapeType` is the type the modifier was applied to, wrappers included.
  func provider(shapeType: ObjectIdentifier, fills: Bool) -> AnimatableShapeProvider {
    makeAnimatableShapeProvider(
      animatable, wrappers: wrappers, shapeType: shapeType, fills: fills)
  }
}

@MainActor
private func makeAnimatableShapeProvider<A: Animatable>(
  _ shape: A,
  wrappers: [any AnimatableShapeForwarding],
  shapeType: ObjectIdentifier,
  fills: Bool
) -> AnimatableShapeProvider {
  AnimatableShapeProvider(
    AnimatableShapeData(
      data: shape.animatableData,
      shapeType: shapeType,
      geometry: { data in
        var sampled = shape
        sampled.animatableData = data
        // `A` is a shape's own type, and each wrapper is rebuilt around the
        // type it wrapped, so neither cast can fail.
        guard var sampledShape = sampled as? any Shape else {
          return .rectangle
        }
        for wrapper in wrappers.reversed() {
          guard let wrapped = wrapper.replacingForwardedShape(sampledShape) else {
            return .rectangle
          }
          sampledShape = wrapped
        }
        return fills ? sampledShape.fillGeometry : sampledShape.geometry
      }
    )
  )
}
