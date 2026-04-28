extension PNG {

  /// Adam7 interlace pass geometry: starting offsets and step sizes per
  /// pass (RFC 2083 §8.2). The seven passes scan disjoint sub-grids of
  /// the image, in order of increasing fidelity.
  ///
  /// Pass 1: top-left of each 8×8 block, etc. The pattern repeats every
  /// 8 pixels horizontally and every 8 pixels vertically:
  ///
  /// ```
  ///   1 6 4 6 2 6 4 6
  ///   7 7 7 7 7 7 7 7
  ///   5 6 5 6 5 6 5 6
  ///   7 7 7 7 7 7 7 7
  ///   3 6 4 6 3 6 4 6
  ///   7 7 7 7 7 7 7 7
  ///   5 6 5 6 5 6 5 6
  ///   7 7 7 7 7 7 7 7
  /// ```
  struct Pass {
    let xStart: Int
    let yStart: Int
    let xStep: Int
    let yStep: Int
  }

  /// The seven Adam7 passes, in transmission order.
  static let adam7Passes: [Pass] = [
    Pass(xStart: 0, yStart: 0, xStep: 8, yStep: 8),
    Pass(xStart: 4, yStart: 0, xStep: 8, yStep: 8),
    Pass(xStart: 0, yStart: 4, xStep: 4, yStep: 8),
    Pass(xStart: 2, yStart: 0, xStep: 4, yStep: 4),
    Pass(xStart: 0, yStart: 2, xStep: 2, yStep: 4),
    Pass(xStart: 1, yStart: 0, xStep: 2, yStep: 2),
    Pass(xStart: 0, yStart: 1, xStep: 1, yStep: 2),
  ]

  /// Width (in pixels) of pass `pass` for an image of width `imageWidth`.
  static func passWidth(_ pass: Pass, imageWidth: Int) -> Int {
    if imageWidth <= pass.xStart { return 0 }
    return (imageWidth - pass.xStart + pass.xStep - 1) / pass.xStep
  }

  /// Height (in scanlines) of pass `pass` for an image of height
  /// `imageHeight`.
  static func passHeight(_ pass: Pass, imageHeight: Int) -> Int {
    if imageHeight <= pass.yStart { return 0 }
    return (imageHeight - pass.yStart + pass.yStep - 1) / pass.yStep
  }
}
