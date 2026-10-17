/// Shared integer ellipse boundary arithmetic for both drawing grids.
package enum EllipseRasterization {
  package static func halfSpan(radiusX: Int, radiusY: Int, offsetY: Int) -> Int {
    guard radiusX > 0 else { return 0 }
    guard radiusY > 0 else { return radiusX }
    let dy = abs(offsetY)
    guard dy <= radiusY else { return 0 }
    let ry = Double(radiusY)
    let estimate = Double(radiusX) * ((ry - Double(dy)) * (ry + Double(dy))).squareRoot() / ry
    var span = estimate >= Double(radiusX) ? radiusX : Int(max(0, estimate))
    // Test the candidate against the implicit integer equation. A rounded
    // square root can land just below an exact integer boundary (3-4-5,
    // for example). The equation decides membership without an epsilon.
    func inside(_ x: Int) -> Bool {
      if UInt64(radiusX) <= UInt64(UInt32.max), UInt64(radiusY) <= UInt64(UInt32.max) {
        let rx2 = UInt128(radiusX) * UInt128(radiusX)
        let ry2 = UInt128(radiusY) * UInt128(radiusY)
        return UInt128(x) * UInt128(x) * ry2 <= rx2 * (ry2 - UInt128(dy) * UInt128(dy))
      }
      let nx = Double(x) / Double(radiusX)
      let ny = Double(dy) / ry
      return nx * nx + ny * ny <= 1
    }
    while span < radiusX, inside(span + 1) { span += 1 }
    while span > 0, !inside(span) { span -= 1 }
    return span
  }
}
