package import Core

// MARK: - Public Coordinator Types

/// A logical family of presentations that should share ordering and
/// exclusivity policy.
public struct PresentationFamilyID: RawRepresentable, Hashable, Sendable,
  ExpressibleByStringLiteral, CustomStringConvertible
{
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: StringLiteralType) {
    rawValue = value
  }

  public var description: String {
    rawValue
  }
}

extension PresentationFamilyID {
  public static let alert: Self = "alert"
  public static let commandPalette: Self = "commandPalette"
  public static let confirmationDialog: Self = "confirmationDialog"
  public static let sheet: Self = "sheet"
  public static let toast: Self = "toast"
}

/// A hosted presentation stratum. Families in the same lane share visibility
/// and base-interaction policy.
public struct PresentationLaneID: RawRepresentable, Hashable, Sendable,
  ExpressibleByStringLiteral, CustomStringConvertible
{
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: StringLiteralType) {
    rawValue = value
  }

  public var description: String {
    rawValue
  }
}

extension PresentationLaneID {
  public static let `default`: Self = "default"
  public static let modal: Self = "modal"
  public static let notification: Self = "notification"
}

/// Controls which instances survive within a presentation family.
public enum PresentationFamilySelectionPolicy: Equatable, Sendable {
  case all
  case latest(Int)
  case highestPriority(Int)
}

/// Controls how requests inside a lane are ranked when more than one candidate
/// may be visible.
public enum PresentationLaneOrdering: Equatable, Sendable {
  case highestPriorityThenMostRecent
  case mostRecentThenHighestPriority
}

/// Controls which requests survive within a lane after family-level selection.
public enum PresentationLaneVisibilityPolicy: Equatable, Sendable {
  case all(order: PresentationLaneOrdering = .highestPriorityThenMostRecent)
  case single(order: PresentationLaneOrdering = .highestPriorityThenMostRecent)
  case limit(Int, order: PresentationLaneOrdering = .highestPriorityThenMostRecent)
}

/// Controls whether visible requests in a lane suppress background interaction.
public enum PresentationBackgroundInteraction: Equatable, Sendable {
  case passthrough
  case disableBase
}

/// Coordinator policy applied to a presentation family.
public struct PresentationFamilyPolicy: Equatable, Sendable {
  public var lane: PresentationLaneID
  public var priority: Int
  public var selection: PresentationFamilySelectionPolicy

  public init(
    lane: PresentationLaneID = .default,
    priority: Int = 0,
    selection: PresentationFamilySelectionPolicy = .all
  ) {
    self.lane = lane
    self.priority = priority
    self.selection = selection
  }
}

/// Coordinator policy applied to a presentation lane.
public struct PresentationLanePolicy: Equatable, Sendable {
  public var zIndex: Int
  public var visibility: PresentationLaneVisibilityPolicy
  public var backgroundInteraction: PresentationBackgroundInteraction

  public init(
    zIndex: Int = 0,
    visibility: PresentationLaneVisibilityPolicy = .all(),
    backgroundInteraction: PresentationBackgroundInteraction = .passthrough
  ) {
    self.zIndex = zIndex
    self.visibility = visibility
    self.backgroundInteraction = backgroundInteraction
  }
}

/// Global configuration for the shared presentation coordinator.
public struct PresentationCoordinatorConfiguration: Equatable, Sendable {
  public var familyPolicies: [PresentationFamilyID: PresentationFamilyPolicy]
  public var lanePolicies: [PresentationLaneID: PresentationLanePolicy]
  public var defaultFamilyPolicy: PresentationFamilyPolicy?
  public var defaultLanePolicy: PresentationLanePolicy?

  public init(
    familyPolicies: [PresentationFamilyID: PresentationFamilyPolicy] = [:],
    lanePolicies: [PresentationLaneID: PresentationLanePolicy] = [:],
    defaultFamilyPolicy: PresentationFamilyPolicy? = nil,
    defaultLanePolicy: PresentationLanePolicy? = nil
  ) {
    self.familyPolicies = familyPolicies
    self.lanePolicies = lanePolicies
    self.defaultFamilyPolicy = defaultFamilyPolicy
    self.defaultLanePolicy = defaultLanePolicy
  }

  public static var standard: Self {
    var configuration = Self(
      defaultFamilyPolicy: .init(
        lane: .default,
        priority: 0,
        selection: .all
      ),
      defaultLanePolicy: .init(
        zIndex: 0,
        visibility: .all(),
        backgroundInteraction: .passthrough
      )
    )
    configuration.familyPolicies = [
      .commandPalette: .init(
        lane: .modal,
        priority: 300,
        selection: .latest(1)
      ),
      .alert: .init(
        lane: .modal,
        priority: 260,
        selection: .latest(1)
      ),
      .confirmationDialog: .init(
        lane: .modal,
        priority: 240,
        selection: .latest(1)
      ),
      .sheet: .init(
        lane: .modal,
        priority: 200,
        selection: .latest(1)
      ),
      .toast: .init(
        lane: .notification,
        priority: 100,
        selection: .all
      ),
    ]
    configuration.lanePolicies = [
      .modal: .init(
        zIndex: 200,
        visibility: .single(),
        backgroundInteraction: .disableBase
      ),
      .notification: .init(
        zIndex: 100,
        visibility: .all(),
        backgroundInteraction: .passthrough
      ),
      .default: .init(
        zIndex: 0,
        visibility: .all(),
        backgroundInteraction: .passthrough
      ),
    ]
    return configuration
  }

  public func settingFamilyPolicy(
    _ family: PresentationFamilyID,
    lane: PresentationLaneID,
    priority: Int = 0,
    selection: PresentationFamilySelectionPolicy = .all
  ) -> Self {
    var copy = self
    copy.familyPolicies[family] = .init(
      lane: lane,
      priority: priority,
      selection: selection
    )
    return copy
  }

  public func settingLanePolicy(
    _ lane: PresentationLaneID,
    zIndex: Int = 0,
    visibility: PresentationLaneVisibilityPolicy = .all(),
    backgroundInteraction: PresentationBackgroundInteraction = .passthrough
  ) -> Self {
    var copy = self
    copy.lanePolicies[lane] = .init(
      zIndex: zIndex,
      visibility: visibility,
      backgroundInteraction: backgroundInteraction
    )
    return copy
  }

  public func settingDefaultFamilyPolicy(
    lane: PresentationLaneID,
    priority: Int = 0,
    selection: PresentationFamilySelectionPolicy = .all
  ) -> Self {
    var copy = self
    copy.defaultFamilyPolicy = .init(
      lane: lane,
      priority: priority,
      selection: selection
    )
    return copy
  }

  public func settingDefaultLanePolicy(
    zIndex: Int = 0,
    visibility: PresentationLaneVisibilityPolicy = .all(),
    backgroundInteraction: PresentationBackgroundInteraction = .passthrough
  ) -> Self {
    var copy = self
    copy.defaultLanePolicy = .init(
      zIndex: zIndex,
      visibility: visibility,
      backgroundInteraction: backgroundInteraction
    )
    return copy
  }

  public func merging(
    _ overrides: Self
  ) -> Self {
    var merged = self
    merged.familyPolicies.merge(overrides.familyPolicies) { _, new in new }
    merged.lanePolicies.merge(overrides.lanePolicies) { _, new in new }
    merged.defaultFamilyPolicy = overrides.defaultFamilyPolicy ?? merged.defaultFamilyPolicy
    merged.defaultLanePolicy = overrides.defaultLanePolicy ?? merged.defaultLanePolicy
    return merged
  }

  package func resolvedFamilyPolicy(
    for family: PresentationFamilyID
  ) -> PresentationFamilyPolicy {
    familyPolicies[family]
      ?? defaultFamilyPolicy
      ?? .init()
  }

  package func resolvedLanePolicy(
    for lane: PresentationLaneID
  ) -> PresentationLanePolicy {
    lanePolicies[lane]
      ?? defaultLanePolicy
      ?? .init()
  }
}

/// Placement metadata for the hosted presentation currently being resolved.
public struct PresentationPlacementContext: Equatable, Sendable {
  public var laneIndex: Int
  public var laneCount: Int
  public var familyIndex: Int
  public var familyCount: Int
  public var isTopmostInLane: Bool
  public var isTopmostInFamily: Bool

  public init(
    laneIndex: Int = 0,
    laneCount: Int = 1,
    familyIndex: Int = 0,
    familyCount: Int = 1,
    isTopmostInLane: Bool = true,
    isTopmostInFamily: Bool = true
  ) {
    self.laneIndex = laneIndex
    self.laneCount = laneCount
    self.familyIndex = familyIndex
    self.familyCount = familyCount
    self.isTopmostInLane = isTopmostInLane
    self.isTopmostInFamily = isTopmostInFamily
  }
}

private enum PresentationPlacementContextKey: EnvironmentKey {
  static let defaultValue = PresentationPlacementContext()
}

extension EnvironmentValues {
  public var presentationPlacementContext: PresentationPlacementContext {
    get { self[PresentationPlacementContextKey.self] }
    set { self[PresentationPlacementContextKey.self] = newValue }
  }
}

// MARK: - Public Modifiers

extension View {
  /// Applies coordinator policy overrides to the nearest shared presentation
  /// host above this subtree.
  public func presentationCoordinator(
    _ configuration: PresentationCoordinatorConfiguration
  ) -> some View {
    PresentationCoordinatorConfigurationModifier(
      content: self,
      configuration: configuration
    )
  }

  /// Hoists authored presentation content through the shared presentation
  /// coordinator.
  public func presentation<Presented: View>(
    _ family: PresentationFamilyID,
    id: String? = nil,
    isPresented: Binding<Bool>,
    priority: Int = 0,
    @ViewBuilder content presentedContent: () -> Presented
  ) -> some View {
    PresentationEmitterModifier(
      content: self,
      family: family,
      requestToken: id ?? family.rawValue,
      isPresented: isPresented,
      priority: priority,
      presentedContent: presentedContent()
    )
  }
}

// MARK: - Shared Preference Plumbing

package struct PresentationRequestID: Hashable, Sendable, CustomStringConvertible {
  package var attachmentIdentity: Identity
  package var family: PresentationFamilyID
  package var token: String

  package var description: String {
    "\(attachmentIdentity.path)#\(family.rawValue)#\(token)"
  }
}

package struct PresentationRequest: Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  package var requestID: PresentationRequestID
  package var attachmentIdentity: Identity
  package var family: PresentationFamilyID
  package var priority: Int
  package var surfacePayload: DeferredViewPayload

  package var description: String {
    debugDescription
  }

  package var debugDescription: String {
    "PresentationRequest(id: \(requestID.description), priority: \(priority))"
  }
}

package struct PresentationCoordinatorPreferenceValue: Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  package var requests: [PresentationRequest] = []
  package var configuration = PresentationCoordinatorConfiguration()

  package var description: String {
    debugDescription
  }

  package var debugDescription: String {
    let requestSummary = requests.map(\.debugDescription).joined(separator: ", ")
    return
      "PresentationCoordinatorPreferenceValue(requests: [\(requestSummary)], familyPolicies: \(configuration.familyPolicies.count), lanePolicies: \(configuration.lanePolicies.count))"
  }
}

package enum PresentationCoordinatorPreferenceKey: PreferenceKey {
  package static let defaultValue = PresentationCoordinatorPreferenceValue()

  package static func reduce(
    value: inout PresentationCoordinatorPreferenceValue,
    nextValue: () -> PresentationCoordinatorPreferenceValue
  ) {
    let next = nextValue()
    value.requests.append(contentsOf: next.requests)
    value.configuration = value.configuration.merging(next.configuration)
  }
}

package struct PresentationHostingRoot<Content: View>: View, ResolvableView {
  package var content: Content
  package var coordinatorState: PresentationCoordinatorState

  package init(
    content: Content,
    coordinatorState: PresentationCoordinatorState
  ) {
    self.content = content
    self.coordinatorState = coordinatorState
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var baseNode = normalizeResolvedElements(
      resolveViewElements(content, in: context),
      in: context
    )
    let preferenceValue = baseNode.preferenceValues[PresentationCoordinatorPreferenceKey.self]
    let configuration = PresentationCoordinatorConfiguration.standard.merging(
      preferenceValue.configuration
    )
    let visibleRequests = PresentationCoordinator.visibleRequests(
      from: preferenceValue.requests,
      configuration: configuration,
      state: coordinatorState
    )

    guard !visibleRequests.isEmpty else {
      return [baseNode]
    }

    let hostContext = context.child(component: .named("PresentationHost"))
    let baseContext = hostContext.child(component: .named("base"))
    baseNode = normalizeResolvedElements(
      resolveViewElements(content, in: baseContext),
      in: baseContext
    )
    if visibleRequests.contains(where: {
      $0.lanePolicy.backgroundInteraction == .disableBase
    }) {
      baseNode.setEnabledRecursively(false)
    }
    let overlayNode = PresentationOverlayHost(requests: visibleRequests).resolve(
      in: hostContext.child(component: .named("overlay"))
    )

    return [
      ResolvedNode(
        identity: hostContext.identity,
        kind: .view("PresentationHost"),
        children: [baseNode, overlayNode],
        environmentSnapshot: hostContext.environment,
        transactionSnapshot: hostContext.transaction,
        layoutBehavior: .overlay(alignment: .topLeading)
      )
    ]
  }
}

@MainActor
package final class PresentationCoordinatorState: @unchecked Sendable {
  private var activationOrdinals: [PresentationRequestID: Int] = [:]
  private var activeRequestIDs: Set<PresentationRequestID> = []
  private var nextActivationOrdinal = 0

  package init() {}

  package func activationOrdinalMap(
    for requests: [PresentationRequest]
  ) -> [PresentationRequestID: Int] {
    let currentRequestIDs = Set(requests.map(\.requestID))

    for requestID in activeRequestIDs.subtracting(currentRequestIDs) {
      activationOrdinals.removeValue(forKey: requestID)
    }

    let newlyActive =
      currentRequestIDs
      .subtracting(activeRequestIDs)
      .sorted { lhs, rhs in
        lhs.description < rhs.description
      }
    for requestID in newlyActive {
      nextActivationOrdinal += 1
      activationOrdinals[requestID] = nextActivationOrdinal
    }

    activeRequestIDs = currentRequestIDs
    return activationOrdinals
  }
}

package struct HostedPresentationRequest: Sendable {
  package var request: PresentationRequest
  package var familyPolicy: PresentationFamilyPolicy
  package var lanePolicy: PresentationLanePolicy
  package var activationOrdinal: Int
  package var placementContext: PresentationPlacementContext
}

@MainActor
private enum PresentationCoordinator {
  static func visibleRequests(
    from requests: [PresentationRequest],
    configuration: PresentationCoordinatorConfiguration,
    state: PresentationCoordinatorState
  ) -> [HostedPresentationRequest] {
    let deduplicatedRequests = deduplicateRequests(requests)
    let activationOrdinals = state.activationOrdinalMap(for: deduplicatedRequests)
    let stagedRequests = deduplicatedRequests.map { request in
      let familyPolicy = configuration.resolvedFamilyPolicy(for: request.family)
      let lanePolicy = configuration.resolvedLanePolicy(for: familyPolicy.lane)
      return HostedPresentationRequest(
        request: request,
        familyPolicy: familyPolicy,
        lanePolicy: lanePolicy,
        activationOrdinal: activationOrdinals[request.requestID] ?? 0,
        placementContext: .init()
      )
    }

    let familySelectedRequests = selectFamilies(stagedRequests)
    let laneSelectedRequests = selectLanes(familySelectedRequests)
    return applyPlacementContexts(
      to: laneSelectedRequests
    )
  }

  private static func deduplicateRequests(
    _ requests: [PresentationRequest]
  ) -> [PresentationRequest] {
    var indicesByRequestID: [PresentationRequestID: Int] = [:]
    var deduplicated: [PresentationRequest] = []
    for request in requests {
      if let existingIndex = indicesByRequestID[request.requestID] {
        deduplicated[existingIndex] = request
      } else {
        indicesByRequestID[request.requestID] = deduplicated.count
        deduplicated.append(request)
      }
    }
    return deduplicated
  }

  private static func selectFamilies(
    _ requests: [HostedPresentationRequest]
  ) -> [HostedPresentationRequest] {
    let groupedRequests = Dictionary(grouping: requests, by: \.request.family)
    return groupedRequests.keys.sorted(by: {
      $0.rawValue < $1.rawValue
    }).flatMap { family in
      let familyRequests = groupedRequests[family] ?? []
      guard let familyPolicy = familyRequests.first?.familyPolicy else {
        return [HostedPresentationRequest]()
      }

      let selected: [HostedPresentationRequest]
      switch familyPolicy.selection {
      case .all:
        selected = familyRequests
      case .latest(let limit):
        selected =
          familyRequests
          .sorted(by: latestFamilyComparator)
          .prefix(max(0, limit))
          .map { $0 }
      case .highestPriority(let limit):
        selected =
          familyRequests
          .sorted(by: highestPriorityFamilyComparator)
          .prefix(max(0, limit))
          .map { $0 }
      }
      return selected
    }
  }

  private static func selectLanes(
    _ requests: [HostedPresentationRequest]
  ) -> [HostedPresentationRequest] {
    let groupedRequests = Dictionary(grouping: requests, by: \.familyPolicy.lane)
    return groupedRequests.keys.sorted(by: { lhs, rhs in
      let lhsPolicy = requests.first(where: { $0.familyPolicy.lane == lhs })?.lanePolicy
      let rhsPolicy = requests.first(where: { $0.familyPolicy.lane == rhs })?.lanePolicy
      let lhsZIndex = lhsPolicy?.zIndex ?? 0
      let rhsZIndex = rhsPolicy?.zIndex ?? 0
      if lhsZIndex != rhsZIndex {
        return lhsZIndex < rhsZIndex
      }
      return lhs.rawValue < rhs.rawValue
    }).flatMap { lane in
      let laneRequests = groupedRequests[lane] ?? []
      guard let lanePolicy = laneRequests.first?.lanePolicy else {
        return [HostedPresentationRequest]()
      }
      let topFirstComparator = laneComparator(
        order: laneOrdering(from: lanePolicy.visibility)
      )
      let selectedTopFirst: [HostedPresentationRequest]
      switch lanePolicy.visibility {
      case .all:
        selectedTopFirst = laneRequests.sorted(by: topFirstComparator)
      case .single:
        selectedTopFirst = Array(laneRequests.sorted(by: topFirstComparator).prefix(1))
      case .limit(let limit, _):
        selectedTopFirst = Array(
          laneRequests.sorted(by: topFirstComparator).prefix(max(0, limit))
        )
      }
      return selectedTopFirst.sorted(by: reverseComparator(topFirstComparator))
    }
  }

  private static func applyPlacementContexts(
    to requests: [HostedPresentationRequest]
  ) -> [HostedPresentationRequest] {
    let laneGroups = Dictionary(
      grouping: requests.enumerated(),
      by: {
        $0.element.familyPolicy.lane
      })
    var laneIndexesByRequestID: [PresentationRequestID: Int] = [:]
    var laneCountsByRequestID: [PresentationRequestID: Int] = [:]
    var familyIndexesByRequestID: [PresentationRequestID: Int] = [:]
    var familyCountsByRequestID: [PresentationRequestID: Int] = [:]

    for laneEntries in laneGroups.values {
      let laneRequests = laneEntries.map(\.element)
      let laneCount = laneRequests.count
      let familyCounts = Dictionary(
        grouping: laneRequests,
        by: \.request.family
      ).mapValues(\.count)
      var familyIndexes: [PresentationFamilyID: Int] = [:]

      for (laneIndex, request) in laneRequests.enumerated() {
        let familyIndex = familyIndexes[request.request.family] ?? 0
        familyIndexes[request.request.family] = familyIndex + 1
        laneIndexesByRequestID[request.request.requestID] = laneIndex
        laneCountsByRequestID[request.request.requestID] = laneCount
        familyIndexesByRequestID[request.request.requestID] = familyIndex
        familyCountsByRequestID[request.request.requestID] =
          familyCounts[request.request.family] ?? 1
      }
    }

    return requests.map { request in
      let requestID = request.request.requestID
      let laneIndex = laneIndexesByRequestID[requestID] ?? 0
      let laneCount = laneCountsByRequestID[requestID] ?? 1
      let familyIndex = familyIndexesByRequestID[requestID] ?? 0
      let familyCount = familyCountsByRequestID[requestID] ?? 1
      var updatedRequest = request
      updatedRequest.placementContext = .init(
        laneIndex: laneIndex,
        laneCount: laneCount,
        familyIndex: familyIndex,
        familyCount: familyCount,
        isTopmostInLane: laneIndex == laneCount - 1,
        isTopmostInFamily: familyIndex == familyCount - 1
      )
      return updatedRequest
    }
  }

  private static func latestFamilyComparator(
    lhs: HostedPresentationRequest,
    rhs: HostedPresentationRequest
  ) -> Bool {
    if lhs.activationOrdinal != rhs.activationOrdinal {
      return lhs.activationOrdinal > rhs.activationOrdinal
    }
    if lhs.request.priority != rhs.request.priority {
      return lhs.request.priority > rhs.request.priority
    }
    return lhs.request.requestID.description < rhs.request.requestID.description
  }

  private static func highestPriorityFamilyComparator(
    lhs: HostedPresentationRequest,
    rhs: HostedPresentationRequest
  ) -> Bool {
    if lhs.request.priority != rhs.request.priority {
      return lhs.request.priority > rhs.request.priority
    }
    if lhs.activationOrdinal != rhs.activationOrdinal {
      return lhs.activationOrdinal > rhs.activationOrdinal
    }
    return lhs.request.requestID.description < rhs.request.requestID.description
  }

  private static func laneOrdering(
    from visibility: PresentationLaneVisibilityPolicy
  ) -> PresentationLaneOrdering {
    switch visibility {
    case .all(let order), .single(let order), .limit(_, let order):
      return order
    }
  }

  private static func laneComparator(
    order: PresentationLaneOrdering
  ) -> (HostedPresentationRequest, HostedPresentationRequest) -> Bool {
    { lhs, rhs in
      if lhs.familyPolicy.priority != rhs.familyPolicy.priority {
        return lhs.familyPolicy.priority > rhs.familyPolicy.priority
      }
      switch order {
      case .highestPriorityThenMostRecent:
        if lhs.request.priority != rhs.request.priority {
          return lhs.request.priority > rhs.request.priority
        }
        if lhs.activationOrdinal != rhs.activationOrdinal {
          return lhs.activationOrdinal > rhs.activationOrdinal
        }
      case .mostRecentThenHighestPriority:
        if lhs.activationOrdinal != rhs.activationOrdinal {
          return lhs.activationOrdinal > rhs.activationOrdinal
        }
        if lhs.request.priority != rhs.request.priority {
          return lhs.request.priority > rhs.request.priority
        }
      }
      if lhs.lanePolicy.zIndex != rhs.lanePolicy.zIndex {
        return lhs.lanePolicy.zIndex > rhs.lanePolicy.zIndex
      }
      return lhs.request.requestID.description < rhs.request.requestID.description
    }
  }

  private static func reverseComparator(
    _ comparator: @escaping (HostedPresentationRequest, HostedPresentationRequest) -> Bool
  ) -> (HostedPresentationRequest, HostedPresentationRequest) -> Bool {
    { lhs, rhs in
      if comparator(lhs, rhs) {
        return false
      }
      if comparator(rhs, lhs) {
        return true
      }
      return lhs.request.requestID.description < rhs.request.requestID.description
    }
  }
}

private struct PresentationOverlayHost: View {
  var requests: [HostedPresentationRequest]

  var body: some View {
    ZStack(alignment: .topLeading) {
      ForEach(requests.indices, id: \.self) { index in
        HostedPresentationPayloadView(
          payload: requests[index].request.surfacePayload,
          placementContext: requests[index].placementContext
        )
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct HostedPresentationPayloadView: View {
  var payload: DeferredViewPayload
  var placementContext: PresentationPlacementContext

  var body: some View {
    DeferredPayloadView(payload: payload)
      .environment(\.presentationPlacementContext, placementContext)
  }
}

package struct PresentationEmitterModifier<Content: View, Presented: View>: View,
  ResolvableView
{
  package var content: Content
  package var family: PresentationFamilyID
  package var requestToken: String
  package var isPresented: Binding<Bool>
  package var priority: Int
  package var presentedContent: Presented

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    guard isPresented.wrappedValue else {
      return [node]
    }

    node.preferenceValues.merge(
      PresentationCoordinatorPreferenceKey.self,
      value: .init(
        requests: [
          .init(
            requestID: .init(
              attachmentIdentity: node.identity,
              family: family,
              token: requestToken
            ),
            attachmentIdentity: node.identity,
            family: family,
            priority: priority,
            surfacePayload: DeferredViewPayload {
              presentedContent
            }
          )
        ]
      )
    )
    return [node]
  }
}

private struct PresentationCoordinatorConfigurationModifier<Content: View>: View,
  ResolvableView
{
  var content: Content
  var configuration: PresentationCoordinatorConfiguration

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.preferenceValues.merge(
      PresentationCoordinatorPreferenceKey.self,
      value: .init(
        configuration: configuration
      )
    )
    return [node]
  }
}
