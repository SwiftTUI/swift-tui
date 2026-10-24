import Foundation
import SwiftTUIViews
import Testing

@MainActor
final class SetDControlModel {
  struct Snapshot: Equatable {
    var number: Int
    var flag: Bool
    var text: String
    var mutations: Int
  }
  var mutations = 0
  var number = 0 { didSet { mutations += 1 } }
  var flag = false { didSet { mutations += 1 } }
  var text = "seed" { didSet { mutations += 1 } }
  var disabled = false
  var snapshot: Snapshot { .init(number: number, flag: flag, text: text, mutations: mutations) }
  var numberBinding: Binding<Int> { .init(get: { self.number }, set: { self.number = $0 }) }
  var flagBinding: Binding<Bool> { .init(get: { self.flag }, set: { self.flag = $0 }) }
  var textBinding: Binding<String> { .init(get: { self.text }, set: { self.text = $0 }) }
}

struct SetDControlForm: View {
  let kind: Int
  let number: Binding<Int>
  let flag: Binding<Bool>
  let text: Binding<String>
  let wide: Bool
  init(kind: Int, model: SetDControlModel, wide: Bool = false) {
    self.init(
      kind: kind, number: model.numberBinding, flag: model.flagBinding,
      text: model.textBinding, wide: wide)
  }
  init(
    kind: Int, number: Binding<Int>, flag: Binding<Bool>, text: Binding<String>, wide: Bool = false
  ) {
    self.kind = kind
    self.number = number
    self.flag = flag
    self.text = text
    self.wide = wide
  }
  var body: some View {
    let label = wide ? "界Target" : "Target"
    switch kind {
    case 1: Button(label) { number.wrappedValue += 1 }
    case 2: Toggle(label, isOn: flag)
    case 3: Stepper(label, value: number, in: 0...5)
    case 4: Slider(label, value: number, in: 0...5)
    case 5:
      Picker(label, selection: number) {
        Text(wide ? "界0" : "Zero").tag(0)
        Text(wide ? "界1" : "One").tag(1)
        Text(wide ? "界2" : "Two").tag(2)
      }
    case 6:
      Picker(label, selection: number) {
        Text(wide ? "界0" : "Zero").tag(0)
        Text(wide ? "界1" : "One").tag(1)
        Text(wide ? "界2" : "Two").tag(2)
      }.pickerStyle(.segmented)
    case 7: TextField(label, text: text)
    case 8: SecureField(label, text: text)
    case 9: TextEditor(text: text).frame(width: 25, height: 3)
    default:
      DisclosureGroup(label, isExpanded: flag) { Text(wide ? "内容" : "expanded body") }
    }
  }
}

@MainActor
func setDKnown(_ comment: Comment, _ body: () -> Void) {
  if ProcessInfo.processInfo.environment["SWIFTTUI_SETD_UNMARKED"] == "1" {
    body()
  } else {
    withKnownIssue(comment) { body() }
  }
}
