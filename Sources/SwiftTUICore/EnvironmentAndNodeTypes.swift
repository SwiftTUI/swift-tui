private final class EnvironmentSnapshotStorage: Sendable {
  let debugSignature: String
  let values: [String: String]
  let style: StyleEnvironmentSnapshot

  init(
    debugSignature: String,
    values: [String: String],
    style: StyleEnvironmentSnapshot
  ) {
    self.debugSignature = debugSignature
    self.values = values
    self.style = style
  }
}

/// An immutable snapshot of environment values captured during resolve.
public struct EnvironmentSnapshot: Sendable {
  private var storage: EnvironmentSnapshotStorage

  public var debugSignature: String {
    get { storage.debugSignature }
    set {
      storage = .init(
        debugSignature: newValue,
        values: storage.values,
        style: storage.style
      )
    }
  }

  public var values: [String: String] {
    get { storage.values }
    set {
      storage = .init(
        debugSignature: storage.debugSignature,
        values: newValue,
        style: storage.style
      )
    }
  }

  public var style: StyleEnvironmentSnapshot {
    get { storage.style }
    set {
      storage = .init(
        debugSignature: storage.debugSignature,
        values: storage.values,
        style: newValue
      )
    }
  }

  public init(
    debugSignature: String = "",
    values: [String: String] = [:],
    style: StyleEnvironmentSnapshot = .init()
  ) {
    storage = .init(
      debugSignature: debugSignature,
      values: values,
      style: style
    )
  }
}

extension EnvironmentSnapshot: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    if lhs.storage === rhs.storage {
      return true
    }

    return lhs.debugSignature == rhs.debugSignature
      && lhs.values == rhs.values
      && lhs.style == rhs.style
  }
}

/// A transaction snapshot captured while resolving a frame.
public struct TransactionSnapshot: Equatable, Sendable {
  public var debugSignature: String
  package var animationRequest: AnimationRequest = .inherit
  /// Optional batch identifier used to associate every animation
  /// enqueued under the same ``withAnimation`` scope so the animation
  /// controller can fire a single completion closure once the whole
  /// batch has settled.
  package var animationBatchID: AnimationBatchID? = nil

  public init(debugSignature: String = "") {
    self.debugSignature = debugSignature
  }

  /// Returns `true` when two snapshots carry equivalent resolve-time intent.
  ///
  /// Unlike `==`, this ignores debug-only fields such as `debugSignature`
  /// that would otherwise defeat retained resolve reuse.
  package func isReuseEquivalent(to other: Self) -> Bool {
    animationRequest == other.animationRequest
      && animationBatchID == other.animationBatchID
  }
}

/// Identifies the high-level role of a node in the resolved tree.
package enum NodeKind: Equatable, Sendable {
  case root
  case scene(String)
  case view(String)
}

/// Canonical axes used by layout, scrolling, and charts.
public enum Axis: String, Equatable, Sendable {
  case horizontal
  case vertical
}

/// Visibility policy used for optional chrome such as separators.
public enum Visibility: String, Equatable, Sendable {
  case automatic
  case visible
  case hidden
}

/// Option set describing the top and bottom edges of a vertical region.
public struct VerticalEdgeSet: OptionSet, Equatable, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let top = Self(rawValue: 1 << 0)
  public static let bottom = Self(rawValue: 1 << 1)
  public static let all: Self = [.top, .bottom]
}

/// Option set describing horizontal and vertical participation.
public struct AxisSet: OptionSet, Equatable, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let horizontal = Self(rawValue: 1 << 0)
  public static let vertical = Self(rawValue: 1 << 1)
}
