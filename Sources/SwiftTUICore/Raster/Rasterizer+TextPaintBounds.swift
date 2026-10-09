/// Skips text painting that cannot produce a visible terminal cell.
extension Rasterizer {
  /// Finds the part of a text block that could write to the destination surface.
  ///
  /// This is a conservative overlap check used before layout and color work.
  /// It does not resize the text: wrapping and gradient sampling still use the
  /// original command bounds. The final writer checks each character precisely.
  /// - Parameters:
  ///   - bounds: Original text position and size in absolute terminal cells.
  ///   - clip: Rectangular clip used by the writer, or `nil` for no extra clip.
  ///   - surfaceSize: Destination surface dimensions in terminal cells.
  /// - Returns: Possible write coverage, or `nil` when the entire block is excluded.
  internal func textPaintBounds(
    _ bounds: CellRect, clip: CellRect?, surfaceSize: CellSize
  ) -> CellRect? {
    // The preformatted painters can place a zero-width trailing character at
    // the block's right edge. The writer gives it one cell, so include that
    // extra column here rather than reject the block too early.
    var coverage = bounds
    if coverage.size.width < Int.max { coverage.size.width += 1 }
    // Text must overlap both the destination screen and any explicit clip.
    guard let surfaceCoverage = intersect(coverage, CellRect(origin: .zero, size: surfaceSize))
    else { return nil }
    if let clip { return intersect(surfaceCoverage, clip) }
    return surfaceCoverage
  }

  /// Selects the original text line indices that can reach the screen and clip.
  ///
  /// The returned range skips hidden lines without changing their positions or
  /// rebuilding the text layout. The caller still checks which visible rows
  /// actually need repainting.
  /// - Parameters:
  ///   - bounds: Original text bounds, including positions above the screen.
  ///   - lineCount: Number of lines in the complete text layout.
  ///   - clip: Rectangular clip used by the writer, or `nil` for no extra clip.
  ///   - surfaceSize: Destination surface dimensions in terminal cells.
  /// - Returns: Original line indices eligible for the caller's dirty-row check.
  internal func textPaintLineRange(
    bounds: CellRect, lineCount: Int, clip: CellRect?, surfaceSize: CellSize
  ) -> Range<Int> {
    let count = min(max(0, lineCount), max(0, bounds.size.height))
    // Find the visible screen rows where the surface and clip overlap.
    let top = max(0, clip?.origin.y ?? 0)
    let bottom = min(
      surfaceSize.height, clip.map { $0.origin.y + $0.size.height } ?? surfaceSize.height)
    // Convert screen rows back to indices in the original text. For example,
    // a block starting at y = -1000 shows its line 1000 at screen row zero.
    let lower = min(count, max(0, top - bounds.origin.y))
    let upper = min(count, max(0, bottom - bounds.origin.y))
    // A clip that misses the block must produce an empty, valid range.
    return lower..<max(lower, upper)
  }

  /// Checks whether the writer can accept a character before its style is computed.
  ///
  /// This follows the existing writer's rules: the first cell must be on the
  /// surface, while an explicit clip requires the character's entire width to fit.
  /// - Parameters:
  ///   - x: Absolute column of the character's first cell.
  ///   - y: Absolute row of the character.
  ///   - width: Character width in cells; the writer uses at least one cell.
  ///   - clip: Rectangular clip used by the writer, or `nil` for no extra clip.
  ///   - surfaceSize: Destination surface dimensions in terminal cells.
  /// - Returns: Whether the character passes the writer's screen and clip checks.
  internal func textGlyphCanWrite(
    atX x: Int, y: Int, width: Int, clip: CellRect?, surfaceSize: CellSize
  ) -> Bool {
    // A wide character may start in the screen's last column, as the writer
    // already allows. Only its first cell must fit when there is no extra clip.
    guard x >= 0, x < surfaceSize.width, y >= 0, y < surfaceSize.height else { return false }
    guard let clip else { return true }
    // An explicit clip is stricter: the full character must fit inside it.
    // Zero-width characters still need one destination cell.
    return x >= clip.origin.x && x + max(1, width) <= clip.origin.x + clip.size.width
      && y >= clip.origin.y && y < clip.origin.y + clip.size.height
  }
}
