import Foundation

/// Offline DAG layout for `gitviz dag`.
///
/// Given a topologically ordered list of `(sha, parents)` rows (newest
/// first), `layout` assigns each commit a lane, a pre-rendered glyph
/// stream, and an optional connector row below the commit. Each glyph
/// carries the lane it belongs to so the renderer can color lanes
/// individually for visual tracing.
enum GraphLayout {
  /// Layout result. `bailed` is true when the graph required more lanes
  /// than `maxLanes` and rendering stopped early.
  struct Result: Sendable, Equatable {
    var commits: [GraphCommit]
    var bailed: Bool
  }

  /// Computes lanes and per-row glyph streams for the supplied commits.
  ///
  /// - Parameters:
  ///   - rows: `(sha, parents, subject)` triples in display order
  ///     (newest first).
  ///   - maxLanes: Bail out and stop laying out once a row would need
  ///     more than `maxLanes` simultaneous lanes. Defaults to 12.
  static func layout(
    rows: [(sha: String, parents: [String], subject: String)],
    maxLanes: Int = 12
  ) -> Result {
    var lanes: [String?] = []  // index → sha the lane is waiting for
    var result: [GraphCommit] = []
    var bailed = false

    for row in rows {
      // 1. Find or allocate the lane for this commit.
      let lane: Int
      if let existing = lanes.firstIndex(where: { $0 == row.sha }) {
        lane = existing
      } else if let freeLane = lanes.firstIndex(where: { $0 == nil }) {
        lane = freeLane
        lanes[freeLane] = row.sha
      } else {
        lane = lanes.count
        lanes.append(row.sha)
      }

      if lanes.count > maxLanes {
        bailed = true
        break
      }

      // 2. Render the commit's own glyph row.
      let commitGlyphs = renderGlyphRow(commitLane: lane, lanes: lanes)

      // 3. Process parents. The commit's lane is freed first; then each
      //    parent is either reused-in-place (if some lane already waits
      //    for it) or assigned to the commit's freed lane (first eligible
      //    parent only) or to a brand-new lane. Skipping already-waited
      //    parents avoids the duplicate-lane bug where two lanes would
      //    point at the same SHA.
      lanes[lane] = nil
      var newLanes: [Int] = []
      var commitLaneAssigned = false
      for parent in row.parents {
        if lanes.contains(parent) {
          continue
        }
        if !commitLaneAssigned {
          lanes[lane] = parent
          commitLaneAssigned = true
        } else if let freeLane = lanes.firstIndex(where: { $0 == nil }) {
          lanes[freeLane] = parent
          newLanes.append(freeLane)
        } else {
          lanes.append(parent)
          newLanes.append(lanes.count - 1)
        }
      }

      // 4. Decide whether to emit a connector row below this commit.
      let connectorGlyphs: [GraphGlyph]?
      if !newLanes.isEmpty {
        connectorGlyphs = renderFanOutConnector(
          commitLane: lane,
          newLanes: newLanes,
          lanes: lanes
        )
      } else if !commitLaneAssigned, !row.parents.isEmpty {
        connectorGlyphs = renderConvergenceConnector(
          fromLane: lane,
          lanes: lanes
        )
      } else {
        connectorGlyphs = nil
      }

      result.append(
        GraphCommit(
          sha: row.sha,
          parents: row.parents,
          subject: row.subject,
          lane: lane,
          glyphs: commitGlyphs,
          connectorGlyphs: connectorGlyphs
        )
      )

      // 5. Trim trailing nil lanes so the array stays compact.
      while let last = lanes.last, last == nil {
        lanes.removeLast()
      }
    }

    return Result(commits: result, bailed: bailed)
  }

  // MARK: - Glyph rendering

  /// Renders one commit row column-by-column. Lane columns sit at even
  /// positions (0, 2, 4, …); single-space separators sit between them.
  ///
  /// - The lane carrying the commit gets `●`.
  /// - Every other occupied lane gets `│`.
  /// - Empty lanes get a space.
  /// - Inter-lane separators get a space with `lane = nil` so the
  ///   renderer leaves them uncolored.
  private static func renderGlyphRow(
    commitLane: Int,
    lanes: [String?]
  ) -> [GraphGlyph] {
    var glyphs: [GraphGlyph] = []
    for index in 0..<lanes.count {
      if index == commitLane {
        glyphs.append(GraphGlyph(character: "●", lane: index))
      } else if lanes[index] != nil {
        glyphs.append(GraphGlyph(character: "│", lane: index))
      } else {
        glyphs.append(GraphGlyph(character: " ", lane: nil))
      }
      if index < lanes.count - 1 {
        glyphs.append(GraphGlyph(character: " ", lane: nil))
      }
    }
    return glyphs
  }

  /// Renders the fan-out connector below a merge commit. New parent lanes
  /// can land on either side of `commitLane` depending on which free slot
  /// the allocator picked (e.g., a left-side lane was vacated by an
  /// earlier convergence), so this routine generalizes over LEFT, RIGHT,
  /// or BOTH directions.
  ///
  /// Lane attribution for coloring:
  /// - Endpoint glyphs are tagged with the lane index of their column.
  /// - Crossings (`┼`) are tagged with the lane being crossed (i.e., the
  ///   pre-existing occupant of that column), so eye-tracing follows the
  ///   continuing lane through the crossing.
  /// - Horizontal connector glyphs (`─`) are tagged with a "moving" lane
  ///   — the lane being spawned — so the new branch's color visibly
  ///   leaves the commit toward its new column.
  private static func renderFanOutConnector(
    commitLane: Int,
    newLanes: [Int],
    lanes: [String?]
  ) -> [GraphGlyph] {
    let newLanesSet = Set(newLanes)
    let allLeft = newLanes.allSatisfy { $0 < commitLane }
    let allRight = newLanes.allSatisfy { $0 > commitLane }
    let commitGlyph: Character =
      allLeft ? "┤" : allRight ? "├" : "┼"

    let leftBound = min(commitLane, newLanes.min() ?? commitLane)
    let rightBound = max(commitLane, newLanes.max() ?? commitLane)
    let maxIndex = max(rightBound, lanes.count - 1)
    let movingLane = newLanes.first ?? commitLane
    var glyphs: [GraphGlyph] = []

    for col in 0...maxIndex {
      let glyph: GraphGlyph
      if col < leftBound || col > rightBound {
        // Outside the connector — pass the underlying lane through.
        if col < lanes.count, lanes[col] != nil {
          glyph = GraphGlyph(character: "│", lane: col)
        } else {
          glyph = GraphGlyph(character: " ", lane: nil)
        }
      } else if col == commitLane {
        glyph = GraphGlyph(character: commitGlyph, lane: commitLane)
      } else if newLanesSet.contains(col) {
        glyph = GraphGlyph(character: (col > commitLane) ? "╮" : "╭", lane: col)
      } else if col < lanes.count, lanes[col] != nil {
        glyph = GraphGlyph(character: "┼", lane: col)
      } else {
        glyph = GraphGlyph(character: "─", lane: movingLane)
      }
      glyphs.append(glyph)

      if col < maxIndex {
        let extends = (col >= leftBound && col < rightBound)
        if extends {
          glyphs.append(GraphGlyph(character: "─", lane: movingLane))
        } else {
          glyphs.append(GraphGlyph(character: " ", lane: nil))
        }
      }
    }
    return glyphs
  }

  /// Renders the convergence connector below a commit whose lane just
  /// disappeared (its only outstanding parent is already in another
  /// lane). The disappeared lane reaches LEFT or RIGHT into the surviving
  /// lane that holds the parent.
  ///
  /// Lane attribution mirrors `renderFanOutConnector`: endpoints get their
  /// column's lane, horizontal segments and crossings get the *dying*
  /// lane's color so the join is visible as the dying lane curving in to
  /// meet the survivor.
  private static func renderConvergenceConnector(
    fromLane: Int,
    lanes: [String?]
  ) -> [GraphGlyph] {
    var targetLane: Int? = nil
    for candidate in stride(from: fromLane - 1, through: 0, by: -1) {
      if candidate < lanes.count, lanes[candidate] != nil {
        targetLane = candidate
        break
      }
    }
    if targetLane == nil {
      for candidate in (fromLane + 1)..<lanes.count where lanes[candidate] != nil {
        targetLane = candidate
        break
      }
    }
    guard let target = targetLane else {
      return []
    }

    let leftEnd = min(target, fromLane)
    let rightEnd = max(target, fromLane)
    let maxIndex = max(rightEnd, lanes.count - 1)
    let dyingLane = fromLane
    var glyphs: [GraphGlyph] = []

    for col in 0...maxIndex {
      let glyph: GraphGlyph
      if col < leftEnd || col > rightEnd {
        if col < lanes.count, lanes[col] != nil {
          glyph = GraphGlyph(character: "│", lane: col)
        } else {
          glyph = GraphGlyph(character: " ", lane: nil)
        }
      } else if col == leftEnd {
        let ch: Character = (target < fromLane) ? "├" : "╰"
        glyph = GraphGlyph(character: ch, lane: col)
      } else if col == rightEnd {
        let ch: Character = (target < fromLane) ? "╯" : "┤"
        glyph = GraphGlyph(character: ch, lane: col)
      } else if col < lanes.count, lanes[col] != nil {
        glyph = GraphGlyph(character: "┼", lane: col)
      } else {
        glyph = GraphGlyph(character: "─", lane: dyingLane)
      }
      glyphs.append(glyph)

      if col < maxIndex {
        let extends = (col >= leftEnd && col < rightEnd)
        if extends {
          glyphs.append(GraphGlyph(character: "─", lane: dyingLane))
        } else {
          glyphs.append(GraphGlyph(character: " ", lane: nil))
        }
      }
    }
    return glyphs
  }
}
