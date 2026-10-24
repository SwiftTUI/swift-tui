@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite("Campaign F5 animation properties", .serialized)
struct AdversarialSetGAnimationTests {
  @Test(arguments: Array(76...90))
  func animation(id: Int) {
    setGCheck(id, setGNumbers) { n in
      let t = Double(n[0] % 99 + 1) / 100
      let later = min(1, t + Double(n[1] % 10) / 100)
      let duration = Double(n[2] % 10 + 1) / 10
      let velocity = Double(n[3] % 21 - 10)
      let bounce = Double(n[1] % 9 - 4) / 10
      let solver = SpringSolver(duration: duration, bounce: bounce, initialVelocity: velocity)
      switch id {
      case 76: return setGNear(BezierSolver.linear.progress(for: t), t) ? nil : "linear identity"
      case 77, 78:
        let curve = id == 77 ? BezierSolver.easeIn : BezierSolver.easeOut
        return curve.progress(for: t) <= curve.progress(for: later) && curve.progress(for: 0) == 0
          && curve.progress(for: 1) == 1 ? nil : "ease monotonicity/endpoints"
      case 79:
        return setGNear(
          BezierSolver.easeInOut.progress(for: t) + BezierSolver.easeInOut.progress(for: 1 - t), 1)
          ? nil : "ease symmetry"
      case 80:
        let curve = [BezierSolver.linear, .easeIn, .easeOut, .easeInOut][n[1] % 4]
        let h = 1e-5
        let numerical = (curve.progress(for: t + h) - curve.progress(for: t - h)) / (2 * h)
        return setGNear(curve.slope(at: t), numerical, tolerance: 1e-4) ? nil : "Bezier slope"
      case 81:
        let speed = Double(n[1] % 4 + 1)
        let base = Animation.linear(duration: .seconds(1))
        let elapsed = t / speed
        guard let a = base.speed(speed).evaluate(elapsed: .seconds(elapsed)),
          let b = base.evaluate(elapsed: .seconds(elapsed * speed))
        else { return "missing speed-scaled value" }
        return setGNear(a, b) ? nil : "animation speed"
      case 82:
        let base = Animation.linear(duration: .seconds(1))
        guard let a = base.delay(.seconds(1)).evaluate(elapsed: .seconds(1 + t)),
          let b = base.evaluate(elapsed: .seconds(t))
        else { return "missing delayed value" }
        return setGNear(a, b) ? nil : "animation delay"
      case 83:
        let base = Animation.linear(duration: .seconds(1)).repeatCount(2, autoreverses: true)
        guard let a = base.evaluate(elapsed: .seconds(t)),
          let b = base.evaluate(elapsed: .seconds(1 + t))
        else { return "missing repeat value" }
        return setGNear(a + b, 1) ? nil : "autoreverse"
      case 84:
        let count = n[0] % 4 + 1
        let base = Animation.linear(duration: .seconds(1)).repeatCount(count, autoreverses: false)
        return base.evaluate(elapsed: .seconds(count)) == nil ? nil : "repeat completion"
      case 85: return setGNear(solver.displacement(at: 0), 1) ? nil : "spring initial displacement"
      case 86: return setGNear(solver.velocity(at: 0), -velocity) ? nil : "spring initial velocity"
      case 87:
        let h = 1e-6
        let numerical = (solver.displacement(at: t + h) - solver.displacement(at: t - h)) / (2 * h)
        return setGNear(solver.velocity(at: t), numerical, tolerance: 1e-4)
          ? nil : "spring derivative"
      case 88:
        let critical = SpringSolver(duration: duration, bounce: 0)
        return critical.displacement(at: t) >= critical.displacement(at: later)
          ? nil : "critical monotonicity"
      case 89:
        guard let completion = solver.completionDuration, completion.isFinite else {
          return "missing finite completion"
        }
        return solver.value(at: completion) == nil ? nil : "reported completion still active"
      default:
        return SpringSolver(mass: 1, stiffness: Double(n[0] + 1), damping: 0).completionDuration
          == nil ? nil : "undamped finite completion"
      }
    }
  }
}
