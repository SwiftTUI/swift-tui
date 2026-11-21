import SwiftTUI
import TransitionConsumer

// A terminal app that plays one demonstration transition (STUI-1546).
//
// It draws an 80 by 24 screen. Space inserts and removes a bordered panel of
// text through the transition named on the command line, and `q` quits. The
// recordings of the demonstrations are made with this program, and the
// frame-cost measurements read the per-frame diagnostics the framework
// writes for it when `SWIFTTUI_DIAGNOSTICS=1` and `SWIFTTUI_DEBUG_DIR` are
// set.
//
//   transition-showcase iris
//   transition-showcase dissolve --spring
//   transition-showcase dissolve-cells --fill

/// The transitions the showcase can play.
enum Demonstration: String, CaseIterable, ExpressibleByArgument {
  case wipe
  case iris
  case blinds
  case dissolve
  /// The dissolve with one rectangle of the path for each cell.
  case dissolveCells = "dissolve-cells"
  case typewriter
  case rise
  /// The built-in fade, to compare the others with.
  case opacity

  /// The transition for a panel that is `size` cells.
  @MainActor
  func transition(for size: CellSize) -> AnyTransition {
    switch self {
    case .wipe:
      AnyTransition(SoftEdgeWipe(ink: ShowcasePanel.ink))
    case .iris:
      AnyTransition(Iris())
    case .blinds:
      AnyTransition(Blinds(slats: size.width / 6))
    case .dissolve:
      AnyTransition(CellDissolve(columns: size.width, rows: size.height, seed: 7))
    case .dissolveCells:
      AnyTransition(
        CellDissolve(columns: size.width, rows: size.height, seed: 7, mergesRuns: false))
    case .typewriter:
      AnyTransition(Typewriter(columns: size.width, rows: size.height))
    case .rise:
      .rise(rows: 4)
    case .opacity:
      .opacity
    }
  }
}

@main
struct TransitionShowcaseApp: App {
  nonisolated static let configuration = CommandConfiguration(
    commandName: "transition-showcase",
    abstract: "Plays one demonstration transition on a panel. Space toggles the panel.",
    subcommands: [CompletionsCommand.self]
  )

  @Argument(help: "The transition to play.")
  var demonstration: Demonstration

  @Flag(help: "Animate with a spring that passes its target.")
  var spring = false

  @Flag(help: "Let the panel fill the screen.")
  var fill = false

  @OptionGroup(title: "SwiftTUI Options") var swiftTUIOptions: SwiftTUIOptions

  var body: some Scene {
    WindowGroup {
      ShowcaseScreen(demonstration: demonstration, usesSpring: spring, fillsScreen: fill)
    }
    .exitOnKeys([KeyPress(.character("q")), KeyPress(.character("c"), modifiers: .ctrl)])
  }
}

/// The 80 by 24 screen: a title, the panel under the transition, and the
/// keys.
struct ShowcaseScreen: View {
  static let size = CellSize(width: 80, height: 24)

  let demonstration: Demonstration
  let usesSpring: Bool
  let fillsScreen: Bool

  @State private var isShown = false
  @FocusState private var hasFocus: Bool

  private var animation: Animation {
    usesSpring
      ? .spring(duration: .milliseconds(900), bounce: 0.45)
      : .linear(duration: .milliseconds(1200))
  }

  private var panelSize: CellSize {
    fillsScreen ? Self.size : CellSize(width: 60, height: 16)
  }

  var body: some View {
    VStack(spacing: 0) {
      if !fillsScreen {
        Text("Transition: \(demonstration.rawValue)   \(usesSpring ? "spring" : "linear 1.2 s")")
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      VStack(spacing: 0) {
        if isShown {
          ShowcasePanel(size: panelSize)
            .transition(demonstration.transition(for: panelSize))
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      if !fillsScreen {
        Text("space: insert or remove the panel   q: quit")
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(width: Self.size.width, height: Self.size.height)
    // The ink is set out here, above the transition. A foreground set on
    // the panel itself would be nearer to its text than the gradient of the
    // wipe, and the wipe would have a hard edge.
    .foregroundStyle(ShowcasePanel.ink)
    .focusable()
    .focused($hasFocus)
    .defaultFocus($hasFocus, true)
    .onKeyPress(.space) { _ in
      withAnimation(animation) {
        isShown.toggle()
      }
      return .handled
    }
  }
}

/// The panel the transitions play on: a border, a background and text.
///
/// The title sets its own color, which shows what a transition that works
/// through the inherited foreground cannot reach. The paragraphs are one
/// `Text`, as wide as the rule above them: a gradient is sampled in the
/// frame of each view that draws with it, so separate lines of different
/// widths would each fade at their own scale under the wipe.
struct ShowcasePanel: View {
  static let ink = Color(red: 0.92, green: 0.92, blue: 0.88)
  private static let paper = Color(red: 0.10, green: 0.13, blue: 0.22)
  private static let accent = Color(red: 0.98, green: 0.72, blue: 0.26)

  let size: CellSize

  private static let lines = [
    "A transition describes how a view arrives and how it",
    "leaves.",
    "",
    "On insertion the view appears through the willAppear",
    "body and moves to the identity body. On removal it",
    "leaves through the didDisappear body, drawn as it was",
    "last drawn.",
    "",
    "A shape that conforms to Animatable builds its path",
    "again for every frame. A modifier that conforms runs",
    "its body again for every frame.",
    "0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnop",
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("SwiftTUI transitions")
        .foregroundStyle(Self.accent)
      Text(String(repeating: "-", count: max(0, size.width - 6)))
      Text(Self.lines.joined(separator: "\n"))
    }
    .padding(.horizontal, 3)
    .padding(.vertical, 1)
    .frame(width: size.width, height: size.height, alignment: .topLeading)
    .background(Self.paper)
    .border(style: .rounded)
  }
}
