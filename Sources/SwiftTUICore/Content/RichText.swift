/// A typed link destination that stays Foundation-free in Core and View.
public struct LinkDestination: Equatable, Hashable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible, ExpressibleByStringLiteral
{
  public var rawValue: String

  public init(
    _ rawValue: String
  ) {
    self.rawValue = rawValue
  }

  public init(
    stringLiteral value: String
  ) {
    rawValue = value
  }
  public var description: String {
    rawValue
  }

  public var debugDescription: String {
    rawValue
  }

  public var isEmpty: Bool {
    rawValue.isEmpty
  }
}

/// A single inline run within a rich text payload.
public struct RichTextRun: Equatable, Sendable {
  public var text: String
  public var style: TextStyle
  public var destination: LinkDestination?
  package var linkIdentifier: String?

  public init(
    text: String,
    style: TextStyle = .init(),
    destination: LinkDestination? = nil,
    linkIdentifier: String? = nil
  ) {
    self.text = text
    self.style = style
    self.destination = destination
    self.linkIdentifier = linkIdentifier
  }

  package var isVisible: Bool {
    !text.isEmpty
  }
}

/// Ordered inline runs that share a single wrapping and truncation layout.
public struct RichTextPayload: Equatable, Sendable {
  public var runs: [RichTextRun]

  public init(runs: [RichTextRun]) {
    self.runs = Self.normalizedRuns(from: runs)
  }

  public var visibleText: String {
    runs.map(\.text).joined()
  }

  package var linkCount: Int {
    Set(
      runs.compactMap(\.linkIdentifier)
    ).count
  }

  private static func normalizedRuns(
    from runs: [RichTextRun]
  ) -> [RichTextRun] {
    var normalized: [RichTextRun] = []

    for run in runs where run.isVisible {
      if var previous = normalized.last,
        previous.style == run.style,
        previous.destination == run.destination,
        previous.linkIdentifier == run.linkIdentifier
      {
        previous.text += run.text
        normalized[normalized.count - 1] = previous
      } else {
        normalized.append(run)
      }
    }

    return normalized
  }
}

extension TextStyle {
  public func merging(
    _ other: Self
  ) -> Self {
    var merged = self
    merged.baseStyle = baseStyle.merging(other.baseStyle)
    return merged
  }
}

package func inlineLinkIdentity(
  parent: Identity,
  identifier: String
) -> Identity {
  parent.child(identifier)
}
