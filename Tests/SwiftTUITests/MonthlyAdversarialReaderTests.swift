import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

// STUI-932, STUI-950 and STUI-951: stale capabilities, editing intent and
// request correlation must remain independent of display/review updates.
@MainActor
@Suite("Monthly adversarial terminal reader")
struct MonthlyAdversarialReaderTests {
  @Test func audit041SecureInsertThenDeleteIsIntentionalClear() {
    var reader = editing(field(secure: true))
    _ = reader.command("insert secret")
    _ = reader.command("select 0 6")
    _ = reader.command("delete")
    #expect(reader.command("save").request?.action == .setValue(.text("")))
  }

  @Test func audit042RejectedSecureInsertionDoesNotBecomeClear() {
    var reader = editing(field(secure: true))
    #expect(reader.command("insert \u{1B}[31m").request == nil)
    #expect(reader.command("save").request == nil)
    #expect(reader.editor == nil)
  }

  @Test func audit043SecureSelectionOnlyIsNotEditingIntent() {
    var reader = editing(field(secure: true))
    _ = reader.command("select 0 0")
    _ = reader.command("delete")
    #expect(reader.command("save").request == nil)
    #expect(reader.pendingRequest == nil)
  }

  @Test func audit044CanceledSecretDoesNotSurviveNewDraft() {
    var reader = editing(field(secure: true))
    _ = reader.command("replace secret")
    _ = reader.command("cancel")
    _ = reader.command("edit")
    #expect(reader.editor?.text == "")
    #expect(reader.command("save").request == nil)
  }

  @Test func audit045ProtectedReadsAndPendingMetadataNeverEchoDraft() throws {
    var reader = editing(field(secure: true))
    let secret = "private-👩🏽‍💻-value"
    #expect(!reader.command("replace \(secret)").output.contains(secret))
    #expect(!reader.command("read").output.contains(secret))
    let request = try #require(reader.command("save").request)
    #expect(request.action == .setValue(.text(secret)))
    #expect(reader.pendingRequest?.action == .focus)
    #expect(reader.editor == nil)
    #expect(!reader.command("history").output.contains(secret))
  }

  @Test func audit046ReverseGraphemeSelectionUsesUTF16OnSave() {
    var reader = editing(field(text: "a👩🏽‍💻🇺🇳z"))
    _ = reader.command("select 3 1")
    #expect(
      reader.command("save").request?.action
        == .selectText(
          .init(
            text: "a👩🏽‍💻🇺🇳z", anchor: "a👩🏽‍💻🇺🇳".utf16.count, head: 1)))
  }

  @Test func audit047CombiningDraftInsertionKeepsSelectionValid() {
    var reader = editing(field(text: "ex"))
    _ = reader.command("select 1 1")
    _ = reader.command("insert \u{301}")
    #expect(reader.editor?.text == "éx")
    #expect(reader.editor?.head == 1)
    #expect(
      reader.command("save").request?.action
        == .editText(
          .init(
            text: "e\u{301}x", anchor: 2, head: 2)))
  }

  @Test func audit048TargetReplacementDiscardsDraftDespiteEqualText() {
    var node = field(text: "old")
    var reader = editing(node)
    _ = reader.command("replace local")
    node.actionTarget = "replacement#2"
    _ = reader.model.update(frame(2, [node]))
    #expect(reader.command("save").request == nil)
    #expect(reader.editor == nil)
  }

  @Test func audit049RemovedControlDiscardsSecureDraft() {
    var reader = editing(field(secure: true))
    _ = reader.command("replace local-secret")
    _ = reader.model.update(frame(2, []))
    #expect(reader.command("save").request == nil)
    #expect(reader.editor == nil)
  }

  @Test func audit050ConcurrentValueChangeRejectsInsertBeforeSave() {
    var node = field(text: "before")
    var reader = editing(node)
    node.control = .init(actions: [.setValue, .editText, .selectText], value: .text("external"))
    _ = reader.model.update(frame(2, [node]))
    #expect(reader.command("insert stale").request == nil)
    #expect(reader.editor == nil)
    _ = reader.command("edit")
    #expect(reader.editor?.text == "external")
  }

  @Test func audit051DisabledAfterEditingCannotSubmit() {
    var node = field(text: "before")
    var reader = editing(node)
    _ = reader.command("replace after")
    node.isEnabled = false
    _ = reader.model.update(frame(2, [node]))
    #expect(reader.command("save").request == nil)
    #expect(reader.pendingRequest == nil)
  }

  @Test func audit052RevokedEditingActionCannotSubmit() {
    var node = field(text: "before")
    var reader = editing(node)
    _ = reader.command("replace after")
    node.control = .init(actions: [.selectText], value: .text("before"))
    _ = reader.model.update(frame(2, [node]))
    #expect(reader.command("save").request == nil)
    #expect(reader.pendingRequest == nil)
  }

  @Test func audit053SelectionWithNonnumericTokenIsRejectedAtomically() {
    var reader = editing(field(text: "abcd"))
    _ = reader.command("select 1 garbage 2")
    #expect(reader.editor?.anchor == 4)
    #expect(reader.editor?.head == 4)
  }

  @Test func audit054OverflowingSelectionTokenCannotPartiallyParse() {
    var reader = editing(field(text: "abcd"))
    _ = reader.command("select 1 \(String(repeating: "9", count: 80)) 2")
    #expect(reader.editor?.anchor == 4)
    #expect(reader.editor?.head == 4)
  }

  @Test func audit055NegativeSelectionDoesNotDamageFollowingEdit() {
    var reader = editing(field(text: "abcd"))
    _ = reader.command("select -1 2")
    _ = reader.command("insert !")
    #expect(
      reader.command("save").request?.action
        == .editText(
          .init(
            text: "abcd!", anchor: 5, head: 5)))
  }

  @Test func audit056WrongTargetAcknowledgmentCannotUnlockPendingAction() throws {
    var reader = editing(field(text: "before"))
    _ = reader.command("replace after")
    let request = try #require(reader.command("save").request)
    #expect(
      reader.acknowledge(.init(requestID: request.requestID!, target: "other#1", result: .accepted))
        == nil)
    #expect(reader.pendingRequest?.requestID == request.requestID)
    #expect(reader.command("set another").request == nil)
  }

  @Test func audit057WrongIDAcknowledgmentCannotUnlockPendingAction() throws {
    var reader = editing(field(text: "before"))
    _ = reader.command("replace after")
    let request = try #require(reader.command("save").request)
    #expect(
      reader.acknowledge(
        .init(requestID: request.requestID! - 1, target: request.target, result: .accepted)) == nil)
    #expect(reader.pendingRequest?.requestID == request.requestID)
  }

  @Test func audit058OldAcknowledgmentCannotClearNewRequest() throws {
    var reader = editing(field(text: "before"))
    _ = reader.command("replace first")
    let first = try #require(reader.command("save").request)
    let ack = AccessibilityActionResponse(
      requestID: first.requestID!, target: first.target, result: .accepted)
    #expect(reader.acknowledge(ack) != nil)
    let second = try #require(reader.command("set second").request)
    #expect(second.requestID != first.requestID)
    #expect(reader.acknowledge(ack) == nil)
    #expect(reader.pendingRequest?.requestID == second.requestID)
  }

  @Test func audit059RejectedRequestAcknowledgmentAllowsRetryWithNewID() throws {
    var reader = editing(field(text: "before"))
    _ = reader.command("replace first")
    let first = try #require(reader.command("save").request)
    #expect(
      reader.acknowledge(
        .init(requestID: first.requestID!, target: first.target, result: .invalidValue)) != nil)
    let retry = try #require(reader.command("set retry").request)
    #expect(retry.requestID! > first.requestID!)
    #expect(retry.action == .setValue(.text("retry")))
  }

  @Test func audit060UnchangedRepaintPreservesDraftAndReverseSelection() {
    let node = field(text: "a😀bc")
    var reader = editing(node)
    _ = reader.command("select 4 1")
    for sequence in UInt64(2)...5 { _ = reader.model.update(frame(sequence, [node])) }
    #expect(
      reader.command("save").request?.action
        == .selectText(
          .init(
            text: "a😀bc", anchor: 5, head: 1)))
  }

  private func field(text: String = "", secure: Bool = false) -> AccessibilityNode {
    var node = AccessibilityNode(
      identity: testIdentity("MonthlyReader", "field"),
      rect: .init(origin: .zero, size: .init(width: 20, height: 1)),
      role: secure ? .secureField : .textEditor, label: "Field")
    node.actionTarget = "field#1"
    node.control = .init(actions: [.setValue, .editText, .selectText], value: .text(text))
    return node
  }

  private func editing(_ node: AccessibilityNode) -> TerminalReaderCommands {
    var reader = TerminalReaderCommands()
    _ = reader.model.update(frame(1, [node]))
    _ = reader.command("edit")
    #expect(reader.editor != nil)
    return reader
  }

  private func frame(_ sequence: UInt64, _ nodes: [AccessibilityNode]) -> SemanticHostFrame {
    .init(
      sequence: sequence, raster: .init(size: .init(width: 20, height: 4), lines: []),
      semantics: .init(accessibilityNodes: nodes), focusedIdentity: nil)
  }
}
