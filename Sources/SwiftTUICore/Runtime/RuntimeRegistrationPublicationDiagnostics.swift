#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#elseif canImport(WASILibc)
  import WASILibc
#endif

package struct RuntimeRegistrationPublicationDiagnostics: Equatable, Sendable {
  package var publicationMode: String
  package var dirtyPlanResult: String
  package var subtreeRootCount: Int
  package var restoredNodeCount: Int?
  package var invalidatedIdentityCount: Int
  package var unmappedInvalidatedIdentityCount: Int
  package var unmappedInvalidatedIdentitySample: [Identity]
  package var selectiveEvaluationDisabledReasons: [String]
  package var presentationPortalRootQueued: Bool?
  package var presentationPortalEscalated: Bool?
  package var graphCheckpointBaselineNodeCount: Int?
  package var graphCheckpointPreparedNodeCount: Int?
  package var graphCheckpointDirtySubtreeCandidateNodeCount: Int?
  package var graphCheckpointStrategy: String?
  package var graphDeltaCheckpointNodeCount: Int?
  package var graphDeltaCheckpointCreatedNodeCount: Int?
  package var graphDeltaCheckpointRemovedNodeCount: Int?
  package var graphDeltaCheckpointEpochDelta: UInt64?
  package var graphCheckpointRestoreStrategy: String?
  package var graphCheckpointRestoreFallbackReason: String?
  package var graphCheckpointDeltaRestoreCount: Int
  package var graphCheckpointFallbackRestoreCount: Int
  package var nonGraphCheckpointPresent: Bool?

  package init(
    publicationMode: String = "-",
    dirtyPlanResult: String = "-",
    subtreeRootCount: Int = 0,
    restoredNodeCount: Int? = nil,
    invalidatedIdentityCount: Int = 0,
    unmappedInvalidatedIdentityCount: Int = 0,
    unmappedInvalidatedIdentitySample: [Identity] = [],
    selectiveEvaluationDisabledReasons: [String] = [],
    presentationPortalRootQueued: Bool? = nil,
    presentationPortalEscalated: Bool? = nil,
    graphCheckpointBaselineNodeCount: Int? = nil,
    graphCheckpointPreparedNodeCount: Int? = nil,
    graphCheckpointDirtySubtreeCandidateNodeCount: Int? = nil,
    graphCheckpointStrategy: String? = nil,
    graphDeltaCheckpointNodeCount: Int? = nil,
    graphDeltaCheckpointCreatedNodeCount: Int? = nil,
    graphDeltaCheckpointRemovedNodeCount: Int? = nil,
    graphDeltaCheckpointEpochDelta: UInt64? = nil,
    graphCheckpointRestoreStrategy: String? = nil,
    graphCheckpointRestoreFallbackReason: String? = nil,
    graphCheckpointDeltaRestoreCount: Int = 0,
    graphCheckpointFallbackRestoreCount: Int = 0,
    nonGraphCheckpointPresent: Bool? = nil
  ) {
    self.publicationMode = publicationMode
    self.dirtyPlanResult = dirtyPlanResult
    self.subtreeRootCount = subtreeRootCount
    self.restoredNodeCount = restoredNodeCount
    self.invalidatedIdentityCount = invalidatedIdentityCount
    self.unmappedInvalidatedIdentityCount = unmappedInvalidatedIdentityCount
    self.unmappedInvalidatedIdentitySample = unmappedInvalidatedIdentitySample
    self.selectiveEvaluationDisabledReasons = selectiveEvaluationDisabledReasons
    self.presentationPortalRootQueued = presentationPortalRootQueued
    self.presentationPortalEscalated = presentationPortalEscalated
    self.graphCheckpointBaselineNodeCount = graphCheckpointBaselineNodeCount
    self.graphCheckpointPreparedNodeCount = graphCheckpointPreparedNodeCount
    self.graphCheckpointDirtySubtreeCandidateNodeCount =
      graphCheckpointDirtySubtreeCandidateNodeCount
    self.graphCheckpointStrategy = graphCheckpointStrategy
    self.graphDeltaCheckpointNodeCount = graphDeltaCheckpointNodeCount
    self.graphDeltaCheckpointCreatedNodeCount = graphDeltaCheckpointCreatedNodeCount
    self.graphDeltaCheckpointRemovedNodeCount = graphDeltaCheckpointRemovedNodeCount
    self.graphDeltaCheckpointEpochDelta = graphDeltaCheckpointEpochDelta
    self.graphCheckpointRestoreStrategy = graphCheckpointRestoreStrategy
    self.graphCheckpointRestoreFallbackReason = graphCheckpointRestoreFallbackReason
    self.graphCheckpointDeltaRestoreCount = graphCheckpointDeltaRestoreCount
    self.graphCheckpointFallbackRestoreCount = graphCheckpointFallbackRestoreCount
    self.nonGraphCheckpointPresent = nonGraphCheckpointPresent
  }
}

@MainActor
package enum RuntimeRegistrationPublicationDiagnosticsConfiguration {
  package static let environmentVariableName = "SWIFTTUI_PUBLICATION_DIAGNOSTICS"
  package static var isEnabled: Bool = environmentDefault()

  private static func environmentDefault() -> Bool {
    guard let rawValue = environmentValue(named: environmentVariableName) else {
      return false
    }
    switch rawValue.lowercased() {
    case "1", "true", "yes", "on":
      return true
    default:
      return false
    }
  }

  private static func environmentValue(named name: String) -> String? {
    unsafe name.withCString { cName in
      guard let rawValue = unsafe getenv(cName) else {
        return nil
      }
      return unsafe String(cString: rawValue)
    }
  }
}
