import TerminalUI

enum CalculatorOp: Hashable {
  case add
  case sub
  case mul
  case div

  var glyph: String {
    switch self {
    case .add: "+"
    case .sub: "−"
    case .mul: "×"
    case .div: "÷"
    }
  }

  func apply(_ lhs: Double, _ rhs: Double) -> Double? {
    switch self {
    case .add: lhs + rhs
    case .sub: lhs - rhs
    case .mul: lhs * rhs
    case .div:
      if rhs == 0 { nil } else { lhs / rhs }
    }
  }
}

struct CalculatorTab: View {
  @State private var display: String = "0"
  @State private var accumulator: Double? = nil
  @State private var pendingOp: CalculatorOp? = nil
  @State private var clearOnNextDigit: Bool = false
  @State private var isError: Bool = false

  var body: some View {
    VStack(alignment: .center, spacing: 1) {
      displayRow
      Spacer(minLength: 1)
      buttonGrid
      Spacer(minLength: 0)
    }
    .padding(1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var displayRow: some View {
    Text(display)
      .bold()
      .frame(maxWidth: .infinity, alignment: .trailing)
      .padding(.horizontal, 1)
  }

  private var buttonGrid: some View {
    VStack(alignment: .center, spacing: 0) {
      HStack(spacing: 0) {
        calcButton("AC") { clearAll() }
        calcButton("+/−") { negate() }
        calcButton("%") { percent() }
        calcButton(CalculatorOp.div.glyph) { setOp(.div) }
      }
      HStack(spacing: 0) {
        calcButton("7") { enterDigit("7") }
        calcButton("8") { enterDigit("8") }
        calcButton("9") { enterDigit("9") }
        calcButton(CalculatorOp.mul.glyph) { setOp(.mul) }
      }
      HStack(spacing: 0) {
        calcButton("4") { enterDigit("4") }
        calcButton("5") { enterDigit("5") }
        calcButton("6") { enterDigit("6") }
        calcButton(CalculatorOp.sub.glyph) { setOp(.sub) }
      }
      HStack(spacing: 0) {
        calcButton("1") { enterDigit("1") }
        calcButton("2") { enterDigit("2") }
        calcButton("3") { enterDigit("3") }
        calcButton(CalculatorOp.add.glyph) { setOp(.add) }
      }
      HStack(spacing: 0) {
        calcButton("0") { enterDigit("0") }
        calcButton(".") { enterDot() }
        calcButton("=") { evaluate() }
        Rectangle().fill(Color.clear).frame(width: 6, height: 3)
      }
    }
  }

  private func calcButton(
    _ label: String,
    action: @escaping @MainActor @Sendable () -> Void
  ) -> some View {
    Button(label, action: action)
      .frame(width: 6, height: 3)
  }

  // MARK: - State machine

  private func enterDigit(_ d: String) {
    if isError || clearOnNextDigit || display == "0" {
      display = d
      clearOnNextDigit = false
      isError = false
      return
    }
    display += d
  }

  private func enterDot() {
    if isError || clearOnNextDigit {
      display = "0."
      clearOnNextDigit = false
      isError = false
      return
    }
    if !display.contains(".") {
      display += "."
    }
  }

  private func setOp(_ op: CalculatorOp) {
    if let lhs = accumulator, let pending = pendingOp, !clearOnNextDigit {
      let rhs = Double(display) ?? 0
      if let result = pending.apply(lhs, rhs) {
        accumulator = result
        display = formatted(result)
      } else {
        showError()
      }
    } else {
      accumulator = Double(display) ?? 0
    }
    pendingOp = op
    clearOnNextDigit = true
  }

  private func evaluate() {
    guard let lhs = accumulator, let pending = pendingOp else {
      return
    }
    let rhs = Double(display) ?? 0
    if let result = pending.apply(lhs, rhs) {
      display = formatted(result)
      accumulator = result
    } else {
      showError()
    }
    pendingOp = nil
    clearOnNextDigit = true
  }

  private func clearAll() {
    display = "0"
    accumulator = nil
    pendingOp = nil
    clearOnNextDigit = false
    isError = false
  }

  private func negate() {
    guard !isError else { return }
    if display.hasPrefix("-") {
      display.removeFirst()
    } else if display != "0" {
      display = "-" + display
    }
  }

  private func percent() {
    guard let value = Double(display) else { return }
    display = formatted(value / 100)
  }

  private func showError() {
    display = "Error"
    accumulator = nil
    pendingOp = nil
    clearOnNextDigit = true
    isError = true
  }

  private func formatted(_ value: Double) -> String {
    if value.rounded() == value, abs(value) < 1e15 {
      return String(Int64(value))
    }
    return String(value)
  }
}
