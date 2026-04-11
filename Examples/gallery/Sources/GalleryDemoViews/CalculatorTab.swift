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
      TextFigure(display, font: .future)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .foregroundStyle(Color.black)
      buttonGrid
    }
    .animation(.easeInOut, value: display)
    .fixedSize()
    .padding(2)
    .background(Color.white)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
  }

  private var buttonGrid: some View {
    VStack(alignment: .center, spacing: 1) {
      HStack(spacing: 1) {
        CalculatorButton("AC", type: .destroy) { clearAll() }
        CalculatorButton("+/−", type: .op) { negate() }
        CalculatorButton("%", type: .op) { percent() }
        CalculatorButton(CalculatorOp.div.glyph, type: .op) { setOp(.div) }
      }
      HStack(spacing: 1) {
        CalculatorButton("7") { enterDigit("7") }
        CalculatorButton("8") { enterDigit("8") }
        CalculatorButton("9") { enterDigit("9") }
        CalculatorButton(CalculatorOp.mul.glyph, type: .op) { setOp(.mul) }
      }
      HStack(spacing: 1) {
        CalculatorButton("4") { enterDigit("4") }
        CalculatorButton("5") { enterDigit("5") }
        CalculatorButton("6") { enterDigit("6") }
        CalculatorButton(CalculatorOp.sub.glyph, type: .op) { setOp(.sub) }
      }
      HStack(spacing: 1) {
        CalculatorButton("1") { enterDigit("1") }
        CalculatorButton("2") { enterDigit("2") }
        CalculatorButton("3") { enterDigit("3") }
        CalculatorButton(CalculatorOp.add.glyph, type: .op) { setOp(.add) }
      }
      HStack(spacing: 1) {
        CalculatorButton("0") { enterDigit("0") }
        CalculatorButton(".", type: .num) { enterDot() }
        Spacer()
        CalculatorButton("=", type: .submit) { evaluate() }
      }
    }
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

struct CalculatorButton: View {
  enum ButtonType {
    case destroy
    case submit
    case num
    case op

    enum Features: Hashable {
      case fg(Color)
      case bg(Color)
      case bold
      case italic
      case disabled
      case underline
      case strikethrough
    }

    var features: [Features] {
      switch self {
      case .destroy:
        [.fg(.white), .bg(Color.red), .bold]
      case .submit:
        [.fg(.white), .bg(Color.green), .bold]
      case .num:
        [.fg(.black), .bg(Color.gray)]
      case .op:
        [.fg(.white), .bg(Color.blue), .italic]
      }
    }

    var fg: Color {
      features.compactMap({
        if case .fg(let c) = $0 { c } else { nil }
      }).first ?? Color.magenta
    }

    var bg: Color {
      features.compactMap({
        if case .bg(let c) = $0 { c } else { nil }
      }).first ?? Color.magenta
    }
  }
  init(_ text: String, type: ButtonType = .num, action: @escaping @MainActor @Sendable () -> Void) {
    self.action = action
    self.type = type
    self.text = text
  }
  var text: String
  var type: ButtonType
  var action: @MainActor () -> Void
  var body: some View {
    Button(action: action) {
      Text(text)
        .bold(type.features.contains(.bold))
        .underline(type.features.contains(.underline))
        .italic(type.features.contains(.italic))
        .strikethrough(type.features.contains(.strikethrough))
    }
    .buttonStyle(.plain)
    .frame(minWidth: 5, maxWidth: type == .submit ? .infinity : 5, alignment: .center)
    .foregroundStyle(type.fg)
    .background {
      Rectangle().fill(
        type.bg
      )
    }
    .disabled(type.features.contains(.disabled))
  }
}
