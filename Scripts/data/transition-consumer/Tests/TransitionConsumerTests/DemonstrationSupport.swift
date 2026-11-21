import SwiftTUI
import Testing
import TransitionConsumer

// What the demonstration tests share: the panel they render, the reading of
// a frame into the set of panel cells that show a glyph, and the six
// demonstrations with the cells each one shows at a given progress.
//
// Everything here uses public API of `SwiftTUI` and of the consumer library.
// Frames come from `DefaultRenderer.render(_:context:proposal:frameInstant:)`,
// whose `frameInstant` is the clock of the frame: a test names the instant
// of every frame it renders, and nothing waits.

/// One cell of the panel: a column and a row counted from its top-left
/// corner.
struct PanelCell: Hashable, Comparable, CustomStringConvertible {
  var column: Int
  var row: Int

  var description: String { "(\(column),\(row))" }

  static func < (lhs: PanelCell, rhs: PanelCell) -> Bool {
    (lhs.row, lhs.column) < (rhs.row, rhs.column)
  }
}

/// The panel under test: 40 by 10 cells, with a glyph in every cell that
/// tells where the cell is.
enum Panel {
  static let columns = 40
  static let rows = 10
  /// The ink of the wipe. The panel sets no foreground of its own: a view
  /// that does is out of the reach of a transition that fades the ink.
  static let ink = Color.white

  static var allCells: Set<PanelCell> {
    cells { _ in true }
  }

  static func cells(where isIncluded: (PanelCell) -> Bool) -> Set<PanelCell> {
    var result: Set<PanelCell> = []
    for row in 0..<rows {
      for column in 0..<columns {
        let cell = PanelCell(column: column, row: row)
        if isIncluded(cell) {
          result.insert(cell)
        }
      }
    }
    return result
  }

  /// The glyph of a cell: the alphabet, moved three letters for each row,
  /// so no two neighbours hold the same letter.
  static func glyph(column: Int, row: Int) -> Character {
    Character(UnicodeScalar(UInt8(65 + (column + 3 * row) % 26)))
  }

  static func line(_ row: Int) -> String {
    String((0..<columns).map { glyph(column: $0, row: row) })
  }
}

struct PanelView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(0..<Panel.rows, id: \.self) { row in
        Text(Panel.line(row))
      }
    }
  }
}

/// What a frame shows of the panel.
struct PanelReading {
  /// The cells of the panel that show a glyph.
  var visible: Set<PanelCell> = []
  /// Everything that must not be in a frame: a glyph outside the panel, or
  /// a glyph other than the one of its cell.
  var problems: [String] = []
  /// The foreground color of each visible cell.
  var inks: [PanelCell: Color] = [:]
}

extension RenderSnapshot {
  /// Reads the panel whose top-left cell is at `origin`. `rowsDown` is how
  /// many rows below its place the panel's content is drawn. Rows above
  /// `origin` are not the panel's and are not read.
  func panel(origin: CellPoint = .zero, rowsDown: Int = 0) -> PanelReading {
    var reading = PanelReading()
    var styles: [CellPoint: ResolvedTextStyle] = [:]
    for run in rasterSurface.styleRuns {
      for x in run.x..<(run.x + run.length) {
        styles[CellPoint(x: x, y: run.y)] = run.style
      }
    }
    for (y, line) in rasterSurface.cells.enumerated() where y >= origin.y {
      for (x, cell) in line.enumerated() where cell.character != " " {
        let column = x - origin.x
        let row = y - origin.y
        guard (0..<Panel.columns).contains(column), (0..<Panel.rows).contains(row) else {
          reading.problems.append("\"\(cell.character)\" outside the panel at (\(x),\(y))")
          continue
        }
        guard row >= rowsDown else {
          reading.problems.append("\"\(cell.character)\" at (\(column),\(row)), above the content")
          continue
        }
        let expected = Panel.glyph(column: column, row: row - rowsDown)
        guard cell.character == expected else {
          reading.problems.append(
            "\"\(cell.character)\" at (\(column),\(row)), where \"\(expected)\" belongs")
          continue
        }
        let place = PanelCell(column: column, row: row)
        reading.visible.insert(place)
        reading.inks[place] = styles[CellPoint(x: x, y: y)]?.foregroundColor
      }
    }
    return reading
  }

  /// The runtime issues of the frame, as text.
  var issues: [String] {
    diagnostics.runtime.issues.map(\.description)
  }
}

/// The six demonstrations.
enum Demonstration: String, CaseIterable, CustomTestStringConvertible {
  case wipe, iris, blinds, dissolve, typewriter, rise

  static let slats = 10
  static let seed: UInt64 = 1
  static let softness = 0.2
  static let riseRows = 4

  var testDescription: String { rawValue }

  /// The demonstration as a transition.
  @MainActor
  var transition: AnyTransition {
    switch self {
    case .wipe:
      AnyTransition(SoftEdgeWipe(ink: Panel.ink, softness: Self.softness))
    case .iris:
      AnyTransition(Iris())
    case .blinds:
      AnyTransition(Blinds(slats: Self.slats))
    case .dissolve:
      AnyTransition(CellDissolve(columns: Panel.columns, rows: Panel.rows, seed: Self.seed))
    case .typewriter:
      AnyTransition(Typewriter(columns: Panel.columns, rows: Panel.rows))
    case .rise:
      .rise(rows: Self.riseRows)
    }
  }

  /// The panel under the demonstration's modifier or shape at `progress`,
  /// with no transition and no animation.
  @MainActor
  @ViewBuilder
  func panel(at progress: Double) -> some View {
    switch self {
    case .wipe:
      PanelView().modifier(
        SoftEdgeWipeEffect(progress: progress, ink: Panel.ink, softness: Self.softness))
    case .iris:
      PanelView().clipShape(IrisShape(open: progress))
    case .blinds:
      PanelView().clipShape(BlindsShape(open: progress, slats: Self.slats))
    case .dissolve:
      PanelView().clipShape(
        CellDissolveShape(
          progress: progress, columns: Panel.columns, rows: Panel.rows, seed: Self.seed))
    case .typewriter:
      PanelView().clipShape(
        TypewriterShape(progress: progress, columns: Panel.columns, rows: Panel.rows))
    case .rise:
      PanelView().modifier(Rise(progress: progress, rows: Self.riseRows))
    }
  }

  /// How many rows below its place the panel is drawn at `progress`.
  func rowsDown(at progress: Double) -> Int {
    switch self {
    case .rise:
      // Four rows at 0, one row less for each quarter.
      Int((Double(Self.riseRows) * (1 - progress)).rounded())
    default:
      0
    }
  }

  /// The cells the demonstration shows at `progress`, worked out from its
  /// description and not from its code. `must` are the cells that have to
  /// show; `may` are those allowed to. The two are the same set for every
  /// demonstration but the iris.
  func cells(at progress: Double) -> (must: Set<PanelCell>, may: Set<PanelCell>) {
    switch self {
    case .wipe:
      // The front is at `progress * (1 + softness)` of the width: with a
      // softness of 0.2 and 40 columns, 48 columns for each unit of
      // progress. Every tested value puts it between two cells.
      let front = progress * (1 + Self.softness) * Double(Panel.columns)
      return same(Panel.cells { Double($0.column) + 0.5 < front })
    case .iris:
      return (Self.ellipse(at: progress, margin: -0.4), Self.ellipse(at: progress, margin: 0.1))
    case .blinds:
      // Ten slats of four columns. A slat shows its leading `progress`:
      // one column for each quarter.
      let width = Panel.columns / Self.slats
      return same(Panel.cells { Double($0.column % width) + 0.5 < progress * Double(width) })
    case .dissolve:
      return same(
        Panel.cells { cell in
          Self.splitMix(Self.seed, index: cell.row * Panel.columns + cell.column) < progress
        })
    case .typewriter:
      // 400 cells in reading order: 100 for each quarter.
      let revealed = Int((progress * Double(Panel.columns * Panel.rows)).rounded())
      return same(Panel.cells { $0.row * Panel.columns + $0.column < revealed })
    case .rise:
      // Transparent at 0. Above that, every row of the panel that is still
      // inside it after the move down.
      let down = rowsDown(at: progress)
      return same(progress <= 0 ? [] : Panel.cells { $0.row >= down })
    }
  }

  private func same(_ cells: Set<PanelCell>) -> (must: Set<PanelCell>, may: Set<PanelCell>) {
    (cells, cells)
  }

  /// The cells an ellipse round the centre of the panel covers, when its
  /// radius on each axis is `0.75 * progress` of the panel's extent.
  ///
  /// A cell is two subcells wide and four tall, and a clip draws a cell
  /// when the outline holds the centre of one of the eight. That rule is
  /// the framework's, read from its rasterizer, and the outline it tests is
  /// a polygon near the ellipse. `margin` moves the outline by that many
  /// subcells: a negative margin gives the cells that are inside for
  /// certain, a positive one the cells that can be.
  private static func ellipse(at progress: Double, margin: Double) -> Set<PanelCell> {
    let radiusX = 0.75 * progress * Double(2 * Panel.columns) + margin
    let radiusY = 0.75 * progress * Double(4 * Panel.rows) + margin
    guard radiusX > 0, radiusY > 0 else {
      return []
    }
    return Panel.cells { cell in
      for subcolumn in 0..<2 {
        for subrow in 0..<4 {
          let x = (Double(2 * cell.column + subcolumn) + 0.5 - Double(Panel.columns)) / radiusX
          let y = (Double(4 * cell.row + subrow) + 0.5 - Double(2 * Panel.rows)) / radiusY
          if x * x + y * y < 1 {
            return true
          }
        }
      }
      return false
    }
  }

  /// SplitMix64 for the seed and the cell's index, as a fraction: the
  /// threshold the dissolve documents. Written here a second time, so the
  /// test does not ask the library what the library does.
  static func splitMix(_ seed: UInt64, index: Int) -> Double {
    var value = seed &+ UInt64(index + 1) &* 0x9E37_79B9_7F4A_7C15
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    value ^= value >> 31
    return Double(value >> 11) / 9_007_199_254_740_992
  }
}

/// A header, and below it the panel under a transition when `isShown`. The
/// frame is wider and taller than the panel, so a glyph drawn outside the
/// panel shows.
struct TransitionHost: View {
  static let size = CellSize(width: Panel.columns + 4, height: Panel.rows + 4)
  static let panelOrigin = CellPoint(x: 0, y: 1)

  var isShown: Bool
  var transition: AnyTransition

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("HEADER")
      if isShown {
        PanelView().transition(transition)
      }
    }
    .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
  }
}

/// One renderer and the frames a test asks of it, each at an instant the
/// test names.
@MainActor
final class Stage {
  private let renderer = DefaultRenderer()
  private let start = MonotonicInstant(offset: .seconds(100))
  private let transition: AnyTransition
  private let identity: Identity

  /// The transition plays under `animation`, attached with
  /// `AnyTransition.animation(_:)`, so a change of `isShown` needs no
  /// animation scope round it.
  init(_ demonstration: Demonstration, animation: Animation) {
    transition = demonstration.transition.animation(animation)
    identity = Identity(components: ["demonstration", demonstration.rawValue])
  }

  /// Renders the host at `milliseconds` on the stage's clock.
  func frame(shown: Bool, at milliseconds: Int) -> RenderSnapshot {
    renderer.render(
      TransitionHost(isShown: shown, transition: transition),
      context: ResolveContext(identity: identity),
      proposal: ProposedSize(width: TransitionHost.size.width, height: TransitionHost.size.height),
      frameInstant: start.advanced(by: .milliseconds(milliseconds)))
  }
}
