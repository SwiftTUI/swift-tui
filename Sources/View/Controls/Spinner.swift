import Core

public struct Spinner: View {

  public init(_ set: SpinnerSet = .brailleLoop, stage: Stage = .active) {
    self.set = set
    self.stage = stage
  }
  let set: SpinnerSet
  let stage: Stage
  @State var iteration: Int = 0

  public var body: some View {
    GeometryReader { proxy in
      if proxy.size.width == 1 {
        switch stage {
        case .active:
          Text(set.body[iteration])
        case .finished:
          Text(set.tail)
        case .inactive:
          Text(set.head)
        }
      } else {
        HStack(spacing: 0) {
          ForEach(Array(0..<proxy.size.width), id: \.self) { cell in
            switch stage {
            case .active:
              let safe = cell % set.body.count
              let char: String = set.body[safe: safe] ?? set.body.last ?? set.tail
              Text(char)
            case .finished:
              Text(set.tail)
            case .inactive:
              Text(set.head)
            }
          }
        }
      }
    }
    .frame(minWidth: 1, idealWidth: 1, maxWidth: 1, minHeight: 1, idealHeight: 1, maxHeight: 1)
    .task(id: Pair(a: set, b: stage)) {
      switch stage {
      case .active:
        while !Task.isCancelled {
          Standard.Error().write("\(set)\(stage)")
          try? await Task.sleep(for: .milliseconds(16))
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

  public struct SpinnerSet: Hashable, Sendable, View, CustomStringConvertible {
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

extension Array {
  subscript(safe safe: Int) -> Element? {
    if safe < self.count {
      self[safe]
    } else {
      nil
    }
  }
}
