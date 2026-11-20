@_spi(Testing) import SwiftTUICore
import SwiftTUIViews

/// The value sink of a transition body that is evaluated outside the graph.
///
/// A view or a modifier of a body that conforms to `Animatable` asks the
/// bound sink for the `animatableData` to evaluate with. In the live tree
/// that sink is the animation controller, which records what each site asks
/// with and owns the animation toward it. A phase of a body that is not on
/// screen is evaluated in a scratch scope, and its sites have the names the
/// live sites have. The controller must learn nothing from such an
/// evaluation: a scratch pull would replace the target the live site
/// recorded.
///
/// This sink stands between the two. It records the data each site of the
/// phase was written with, which is the data the phase ends at, and answers
/// each site from values its owner supplies:
///
/// - an insertion supplies nothing, and reads what the `.willAppear` phase
///   wrote for each site: where the site's animation starts;
/// - a removal supplies what each site shows on the frame being drawn: the
///   data on screen when it plans, and the sample of the site's animation on
///   each later frame.
///
/// A site with no supplied value evaluates with the data the phase wrote.
@MainActor
final class TransitionBodyValueSink: AnimatableValueSink {
  private let answer: (AnimationKey) -> AnyAnimatable?
  /// The sites the phase evaluated, in the order they resolved.
  private(set) var sites: [AnimationKey] = []
  /// The data the phase wrote for each site, boxed as the controller boxes
  /// the data of a live site.
  private(set) var phaseData: [AnimationKey: AnyAnimatable] = [:]

  /// A sink that answers each site with what `answer` returns for it, and
  /// with the data the phase wrote when that is `nil`.
  init(answering answer: @escaping (AnimationKey) -> AnyAnimatable? = { _ in nil }) {
    self.answer = answer
  }

  /// A sink that answers from a table of values by site.
  convenience init(answers: [AnimationKey: AnyAnimatable]) {
    self.init(answering: { answers[$0] })
  }

  func presentedAnimatableData<Data: VectorArithmetic>(
    for target: Data,
    at site: AnimatableValueSite,
    ownerNodeID: ViewNodeID?,
    transaction: TransactionSnapshot,
    reducesMotion: Bool
  ) -> Data {
    let key = AnimationKey(site: site)
    let written = AnimationController.boxedAnimatableData(target)
    if phaseData.updateValue(written, forKey: key) == nil {
      sites.append(key)
    }
    // A value of another type belongs to a different view that used to
    // resolve at this site. The phase's own data stands.
    return answer(key)?.unwrap(as: AnimatableDataBox<Data>.self)?.animatableData ?? target
  }
}
