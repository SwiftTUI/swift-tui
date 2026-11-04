extension RuntimeIssue {
  /// An extensible host-facing diagnostic identifier.
  public struct Code: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral,
    CustomStringConvertible
  {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(rawValue: value) }
    public var description: String { rawValue }

    // Preserve the two spellings already published to hosts on the string seam.
    init(wireValue: String) {
      switch wireValue {
      case "companion-client-outdated": self = .Companion.clientOutdated
      case "windows.stack-floor-lean-profile": self = .Windows.stackFloorLeanProfile
      default: self.init(rawValue: wireValue)
      }
    }

    var wireValue: String {
      switch self {
      case .Companion.clientOutdated: "companion-client-outdated"
      case .Windows.stackFloorLeanProfile: "windows.stack-floor-lean-profile"
      default: rawValue
      }
    }

    public enum Collection {
      public static let ambiguousSelectionTag = Code(rawValue: "collection.ambiguousSelectionTag")
      public static let eagerLargeCollection = Code(rawValue: "collection.eagerLargeCollection")
      public static let incompatibleSelectionTag = Code(
        rawValue: "collection.incompatibleSelectionTag")
      public static let missingSelectionTag = Code(rawValue: "collection.missingSelectionTag")
      public static let unboundedRealization = Code(rawValue: "collection.unboundedRealization")
    }

    public enum Companion {
      public static let clientOutdated = Code(rawValue: "companion.clientOutdated")
    }

    public enum ForEach {
      public static let staleElementBindingWrite = Code(
        rawValue: "forEach.staleElementBindingWrite")
    }

    public enum Host {
      public static let geometryStalepointer = Code(rawValue: "host.geometry.stalePointer")
    }

    public enum Identity {
      public static let duplicateEntity = Code(rawValue: "identity.duplicateEntity")
    }

    public enum Image {
      public static let unresolvedSource = Code(rawValue: "image.unresolvedSource")
    }

    public enum KeyCommand {
      public static let modifierlessIgnored = Code(rawValue: "keyCommand.modifierlessIgnored")
      public static let requiresEnhancedKeyboard = Code(
        rawValue: "keyCommand.requiresEnhancedKeyboard")
    }

    public enum LatePreference {
      public static let reconciliationLimitExceeded = Code(
        rawValue: "latePreference.reconciliationLimitExceeded")
    }

    public enum Layout {
      public static let customLayoutDepthLimitExceeded = Code(
        rawValue: "layout.customLayoutDepthLimitExceeded")
      public static let insetBorderOccludesContent = Code(
        rawValue: "layout.insetBorderOccludesContent")
      public static let persistedCacheDivergence = Code(rawValue: "layout.persistedCacheDivergence")
      public static let placementChildMismatch = Code(rawValue: "layout.placementChildMismatch")
    }

    public enum Lifecycle {
      public static let appearHandlerSkipped = Code(rawValue: "lifecycle.appearHandlerSkipped")
      public static let changeHandlerSkipped = Code(rawValue: "lifecycle.changeHandlerSkipped")
      public static let disappearHandlerSkipped = Code(
        rawValue: "lifecycle.disappearHandlerSkipped")
      public static let taskStartSkipped = Code(rawValue: "lifecycle.taskStartSkipped")
      public static let userExitUnsupported = Code(rawValue: "lifecycle.userExitUnsupported")
    }

    public enum Navigation {
      public static let depthLimitExceeded = Code(rawValue: "navigation.depthLimitExceeded")
      public static let missingValueDestination = Code(
        rawValue: "navigation.missingValueDestination")
      public static let multipleActiveDestinations = Code(
        rawValue: "navigation.multipleActiveDestinations")
    }

    public enum Picker {
      public static let unrepresentableOptionContent = Code(
        rawValue: "picker.unrepresentableOptionContent")
    }

    public enum Presentation {
      public static let mutationDuringViewUpdate = Code(
        rawValue: "presentation.mutationDuringViewUpdate")
    }

    public enum State {
      public static let duplicateSlotClaim = Code(rawValue: "state.duplicateSlotClaim")
      public static let imperativeSeedFallback = Code(rawValue: "state.imperativeSeedFallback")
    }

    public enum Structure {
      public static let declaredChildTraversalMismatch = Code(
        rawValue: "structure.declaredChildTraversalMismatch")
    }

    public enum Style {
      public static let duplicateContent = Code(rawValue: "style.duplicateContent")
      public static let duplicateRoute = Code(rawValue: "style.duplicateRoute")
      public static let invalidPresentation = Code(rawValue: "style.invalidPresentation")
      public static let missingRequiredRoute = Code(rawValue: "style.missingRequiredRoute")
    }

    public enum Tab {
      public static let dormantStateUnsupportedValue = Code(
        rawValue: "tab.dormantStateUnsupportedValue")
      public static let duplicateTag = Code(rawValue: "tab.duplicateTag")
      public static let missingStructuralTag = Code(rawValue: "tab.missingStructuralTag")
    }

    public enum Toolbar {
      public static let unhostedItems = Code(rawValue: "toolbar.unhostedItems")
    }

    public enum Windows {
      public static let stackFloorLeanProfile = Code(rawValue: "windows.stackFloorLeanProfile")
    }

    package static func soundness(_ kind: SoundnessViolationKind) -> Self {
      Self(rawValue: "soundness.\(kind.issueName)")
    }
  }
}
