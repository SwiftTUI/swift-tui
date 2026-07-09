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
