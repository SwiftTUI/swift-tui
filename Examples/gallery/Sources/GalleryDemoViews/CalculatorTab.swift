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

  func apply(_ lhs: Double, _ rhs: Double) -> Double {
    switch self {
    case .add: lhs + rhs
    case .sub: lhs - rhs
    case .mul: lhs * rhs
    case .div:
      lhs / rhs
    }
  }
}

struct CalculatorTab: View {

  @State private var display: String?
  @State private var accumulator: Double?
  @State private var pendingOp: CalculatorOp?
  private var isError: Bool {
    accumulator?.isFinite == false || displayValue.isFinite == false
  }

  var body: some View {
    VStack(spacing: 1) {
      Rectangle().fill(Color.clear).overlay(alignment: .bottomTrailing) {
        VStack {
          Text(
            "\(display == nil ? "" : accumulator.map { formatted($0) } ?? "")\(pendingOp?.glyph ?? "")"
          )
          .foregroundStyle(Color.gray)
          ViewThatFits {
            let text = isError ? "Error" : display ?? accumulator.map { formatted($0) } ?? " "
            TextFigure(text, font: .future)
            Text(text)
          }.foregroundStyle(isError ? Color.red : Color.black)
        }
      }
      .frame(height: 4)
      .padding(1)
      .frame(maxWidth: .infinity, alignment: .trailing)
      .border(.black)
      buttonGrid
    }
    .fixedSize()
    .padding(2)
    .background(Color.white)
    .background {
      Rectangle()
        .fill(Color.gray)
        .offset(x: 2, y: 1)
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(1)
    .animation(.easeInOut, value: display)
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
        CalculatorButton("=", type: .submit) { evaluate() }
      }
    }
    .focusSection()
  }

  // MARK: - State machine

  private func enterDigit(_ d: String) {
    if display == "0" {
      display = d
      return
    }
    display = Double("\(display ?? "")\(d)").map(formatted)
  }

  private func enterDot() {
    if isError || display == nil {
      display = "0."
      return
    }
    if display?.contains(".") != true {
      display = "\(display ?? "0")."
    }
  }

  var displayValue: Double {
    var d: String = display ?? "0"
    if d.last == "." {
      d.removeLast()
    }
    return Double(d) ?? 0.0
  }

  private func setOp(_ op: CalculatorOp) {
    if let lhs = accumulator, let pending = pendingOp {
      let result = pending.apply(lhs, displayValue)
      accumulator = result
      display = nil
    } else {
      accumulator = displayValue
      display = nil
    }
    pendingOp = op
  }

  private func evaluate() {
    guard let lhs = accumulator, let pending = pendingOp else {
      return
    }
    let result = pending.apply(lhs, displayValue)
    display = formatted(result)
    accumulator = nil
    pendingOp = nil
  }

  private func clearAll() {
    display = "0"
    accumulator = nil
    pendingOp = nil
  }

  private func negate() {
    guard !isError else { return }
    var d = display ?? "0"
    if d.hasPrefix("-") {
      d.removeFirst()
    } else if d != "0" {
      d = "-\(d)"
    }
    display = d
  }

  private func percent() {
    guard let value = Double(display ?? "0") else { return }
    display = formatted(value / 100)
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
        .frame(minWidth: 6, maxWidth: type == .submit ? .infinity : 6, alignment: .center)
        .foregroundStyle(type.fg)
        .background {
          Rectangle().fill(type.bg)
        }
    }
    .buttonStyle(.plain)
    .disabled(type.features.contains(.disabled))
  }
}
