import SwiftTUICore

public struct Spinner: View {

  public init(
    _ set: SpinnerSet = .brailleLoop,
    stage: Stage = .active,
    interval: Duration = .milliseconds(64)
  ) {
    precondition(
      interval > .zero,
      "Spinner interval must be > 0 milliseconds"
    )
    self.set = set
    self.stage = stage
    self.interval = interval
  }
  let set: SpinnerSet
  let stage: Stage
  let interval: Duration
  @State var iteration: Int = 0

  public var body: some View {
    EnvironmentReader(\.accessibilityReduceMotion) { accessibilityReduceMotion in
      spinnerBody(accessibilityReduceMotion: accessibilityReduceMotion)
    }
  }

  @ViewBuilder
  private func spinnerBody(accessibilityReduceMotion: Bool) -> some View {
    if accessibilityReduceMotion {
      spinnerText(accessibilityReduceMotion: true)
    } else {
      spinnerText(accessibilityReduceMotion: false)
        .task(id: SpinnerTaskKey(set: set, stage: stage, interval: interval)) {
          switch stage {
          case .active:
            while !Task.isCancelled {
              try? await Task.sleep(for: interval)
              let max = set.body.count
              var newIteration = iteration + 1
              newIteration %= max
              iteration = newIteration
            }
          case .finished, .inactive:
            break
          }
        }
    }
  }

  @ViewBuilder
  private func spinnerText(accessibilityReduceMotion: Bool) -> some View {
    Group {
      switch stage {
      case .active:
        if accessibilityReduceMotion {
          Text(set.body.first ?? set.head)
        } else {
          Text(set.body[iteration])
        }
      case .finished:
        Text(set.tail)
      case .inactive:
        Text(set.head)
      }
    }
  }

  public enum Stage: Hashable, Sendable, CustomStringConvertible {
    case inactive
    case active
    case finished
    public var description: String {
      switch self {
      case .inactive: "inactive"
      case .active: "active"
      case .finished: "finished"
      }
    }
  }

  public struct SpinnerSet: Hashable, Sendable, CustomStringConvertible {
    public enum Progression {
      case bounce
      case `repeat`
    }
    public init(
      progression: Progression = .repeat, head: String = " ", _ body: String..., tail: String = " "
    ) {
      self.head = head
      self.body = body
      self.tail = tail
    }

    nonisolated public var description: String { body.first! }
    public static let circleOrbit = Self("◡", "◟", "◜", "◠", "◝", "◞", tail: "○")
    public static let brailleRingFilled = Self("⣾", "⣷", "⣯", "⣟", "⡿", "⢿", "⣽", "⣻", tail: "⣿")
    public static let brailleBlockFill = Self("⠉", "⠛", "⠿", "⣿", tail: "⣿")
    public static let barRise = Self("▁", "▂", "▃", "▄", "▅", "▆", "▇", "█", tail: "█")
    public static let circleFill = Self("○", "◔", "◑", "◕", "●", tail: "●")
    public static let brailleSweep = Self("⠉", "⠘", "⠰", "⢠", "⣀", "⡄", "⠆", "⠃")
    public static let diamondPulse = Self("◇", "◈", "◆", "◈", tail: "◆")
    public static let brailleDotOrbit = Self("⠁", "⠈", "⠐", "⠠", "⢀", "⡀", "⠄", "⠂")
    public static let brailleLoopFilled = Self(
      "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏", tail: "⣶")
    public static let quadrantOrbit = Self("▖", "▘", "▝", "▗")
    public static let clockFace = Self("◷", "◶", "◵", "◴")
    public static let halfCircle = Self("◓", "◑", "◒", "◐")
    public static let triangleCompass = Self("▲", "▶", "▼", "◀")
    public static let brailleRamp = Self("⣀", "⣤", "⣶", "⣾", "⣿", "⣾", "⣶", "⣤", tail: "⣿")
    public static let brailleLinePulse = Self("⠉", "⠒", "⣀", "⠒")
    public static let diceRoll = Self("⚀", "⚁", "⚂", "⚃", "⚄", "⚅")
    public static let boxCornerOrbit = Self("┌", "┐", "┘", "└")
    public static let brailleDotFade = Self("⠈", "⠐", "⠠", "⠄", "⠂", "⠁")
    public static let brailleLineSweep = Self("⠘", "⠰", "⠤", "⠆", "⠃", "⠉")
    public static let brailleRing = Self("⣾", "⣷", "⣯", "⣟", "⡿", "⢿", "⣽", "⣻")
    public static let arcOrbit = Self("◜", "◝", "◞", "◟")
    public static let brailleLoop = Self("⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏")
    public static let shadeFade = Self("█", "▓", "▒", "░", tail: "█")
    public static let dotChase = Self("∙∙∙", "●∙∙", "∙●∙", "∙∙●", tail: "●●●")
    public static let globe = Self("🌍", "🌎", "🌏")
    public static let moonPhase = Self("🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘", tail: "🌕")
    public static let segmentedBar = Self(
      "▱▱▱", "▰▱▱", "▰▰▱", "▰▰▰", "▰▰▱", "▰▱▱", "▱▱▱", tail: "▰▰▰")
    public static let arrowCompass = Self("←", "↖", "↑", "↗", "→", "↘", "↓", "↙")
    public static let glyphPulse = Self("ᔐ", "ᯇ", "ᔑ", "ᯇ", tail: "ᦟ")
    public static let blockCorners = Self("▙", "▛", "▜", "▟", tail: "█")
    public static let horizontalBarFill = Self("▏", "▎", "▍", "▌", "▋", "▊", "▉", "█", tail: "█")
    public static let quadrantCorners = Self("▝", "▗", "▖", "▘", tail: "█")
    public static let verticalBarFill = Self("▁", "▂", "▃", "▄", "▅", "▆", "▇", "█", tail: "█")
    public static let heavyArrowCompass = Self("⇑", "⇗", "⇒", "⇘", "⇓", "⇙", "⇐", "⇖")
    public static let lineCompass = Self("│", "╱", "─", "╲", tail: "┼")
    public static let asciiLineCompass = Self("|", "/", "-", "\\", tail: "X")
    /// Compact 4-glyph cycle used by Claude Code's terminal "working"
    /// header: asterisk, middle dot, plus, division sign.  All four
    /// glyphs are single-cell-wide ASCII so the spinner stays at a
    /// constant width as it rotates.
    public static let asteriskCycle = Self("*", "·", "+", "÷")
    public static let oghamPulse = Self(
      " ", "ᚁ", "ᚂ", "ᚃ", "ᚄ", "ᚅ", "ᚄ", "ᚃ", "ᚂ", "ᚁ", " ", "ᚆ", "ᚇ", "ᚈ", "ᚉ", "ᚊ", "ᚉ", "ᚈ", "ᚇ",
      "ᚆ", tail: "ᚔ")
    var head: String
    var body: [String]
    var tail: String
  }
}

struct Pair<A, B> {
  var a: A
  var b: B
}
extension Pair: Equatable where A: Equatable, B: Equatable {}
extension Pair: Hashable where A: Hashable, B: Hashable {}
extension Pair: Sendable where A: Sendable, B: Sendable {}

/// Composite key used to drive the spinner's `.task(id:)` cancellation.
/// Changing any of the three observed fields cleanly cancels the
/// previous tick loop so a fresh one starts at the new rate.
private struct SpinnerTaskKey: Hashable, Sendable {
  let set: Spinner.SpinnerSet
  let stage: Spinner.Stage
  let interval: Duration
}

extension Array {
  subscript(safe safe: Int) -> Element? {
    if safe < self.count {
      self[safe]
    } else {
      nil
    }
  }
}
