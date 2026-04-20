import Foundation
import SwiftTerm
import TerminalUI

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

@MainActor
final class SwiftTermSceneBridge {
  enum BridgeError: Error, Equatable {
    case missingSession
  }

  let descriptor: SwiftTermTUISceneDescriptor
  let terminalView: TerminalView

  private var style: SwiftTermTUITerminalStyle
  private var session: (any HostedSceneSessionHandling)?
  private var focusPresentation: FocusPresentation = .none
  private var manualKeyboardPresentationRequested = false
  private(set) var lastViewportSize: Size?

  init(
    descriptor: SwiftTermTUISceneDescriptor,
    style: SwiftTermTUITerminalStyle
  ) {
    self.descriptor = descriptor
    self.style = style
    terminalView = Self.makeTerminalView(style: style)
    terminalView.terminalDelegate = self
    apply(style: style, to: terminalView)
    terminalView.resize(cols: 80, rows: 24)
  }

  func attach(session: any HostedSceneSessionHandling) {
    self.session = session
    syncSessionStyle()
  }

  func startSession() async throws -> RunLoopExitReason {
    guard let session else {
      throw BridgeError.missingSession
    }
    return try await session.start()
  }

  func stopSession() {
    session?.stop()
  }

  func apply(style: SwiftTermTUITerminalStyle) {
    self.style = style
    apply(style: style, to: terminalView)
    syncSessionStyle()
  }

  func updateKeyboardPresentation(
    focusPresentation: FocusPresentation,
    manualKeyboardPresentationRequested: Bool
  ) {
    self.focusPresentation = focusPresentation
    self.manualKeyboardPresentationRequested = manualKeyboardPresentationRequested
    syncKeyboardPresentation()
  }

  func receiveOutput(_ output: String) {
    terminalView.feed(text: output)
  }

  func handleSurfaceResize(
    columns: Int,
    rows: Int
  ) {
    let size = Size(width: columns, height: rows)
    guard size != lastViewportSize else {
      return
    }

    lastViewportSize = size
    session?.resize(to: size)
  }

  func handleTerminalInput(_ data: ArraySlice<UInt8>) {
    session?.sendInput(Array(data))
  }

  func handleOpenLink(_ link: String) {
    guard let url = URL(string: link) else {
      return
    }

    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
      NSWorkspace.shared.open(url)
    #elseif canImport(UIKit)
      UIApplication.shared.open(url)
    #endif
  }

  func handleBell() {
    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
      NSSound.beep()
    #endif
  }

  func handleClipboardCopy(_ content: Data) {
    let string = String(decoding: content, as: UTF8.self)

    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(string, forType: .string)
    #elseif canImport(UIKit)
      UIPasteboard.general.string = string
    #endif
  }

  private func syncSessionStyle() {
    guard let session else {
      return
    }

    session.updateStyle(style.renderStyle)
  }

  private var allowsExpandedKeyboardPresentation: Bool {
    focusPresentation.prefersTextInput || manualKeyboardPresentationRequested
  }

  private func syncKeyboardPresentation() {
    #if canImport(UIKit) && !targetEnvironment(macCatalyst)
      if allowsExpandedKeyboardPresentation {
        SwiftTermKeyboardPresentationController.presentExpandedKeyboard(for: terminalView)
      } else {
        SwiftTermKeyboardPresentationController.suppressExpandedKeyboard(for: terminalView)
      }
    #endif
  }

  private func apply(
    style: SwiftTermTUITerminalStyle,
    to view: TerminalView
  ) {
    let configuration = style.swiftTermConfiguration

    view.font = style.nativeFont
    view.nativeForegroundColor = configuration.foreground.nativeColor
    view.nativeBackgroundColor = configuration.background.nativeColor
    view.caretColor = configuration.caret.nativeColor
    view.caretTextColor = configuration.caretText.nativeColor
    view.selectedTextBackgroundColor = configuration.selectionBackground.nativeColor
    view.installColors(configuration.ansiColors)
    view.getTerminal().setCursorStyle(configuration.cursorStyle)
  }

  private static func makeTerminalView(
    style: SwiftTermTUITerminalStyle
  ) -> TerminalView {
    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
      TerminalView(frame: .zero, font: style.nativeFont)
    #elseif canImport(UIKit)
      let view = TerminalView(frame: .zero)
      view.font = style.nativeFont
      return view
    #endif
  }

  var focusPresentationForTesting: FocusPresentation {
    focusPresentation
  }

  var allowsExpandedKeyboardPresentationForTesting: Bool {
    allowsExpandedKeyboardPresentation
  }
}

@MainActor
protocol HostedSceneSessionHandling: AnyObject {
  func start() async throws -> RunLoopExitReason
  func sendInput(_ bytes: [UInt8])
  func resize(to size: Size)
  func updateStyle(_ style: TerminalRenderStyle)
  func stop()
}

extension HostedSceneSession: HostedSceneSessionHandling {}

extension SwiftTermSceneBridge: TerminalViewDelegate {
  nonisolated func sizeChanged(
    source _: TerminalView,
    newCols: Int,
    newRows: Int
  ) {
    Task { @MainActor [weak self] in
      self?.handleSurfaceResize(columns: newCols, rows: newRows)
    }
  }

  nonisolated func setTerminalTitle(
    source _: TerminalView,
    title _: String
  ) {}

  nonisolated func hostCurrentDirectoryUpdate(
    source _: TerminalView,
    directory _: String?
  ) {}

  nonisolated func send(
    source _: TerminalView,
    data: ArraySlice<UInt8>
  ) {
    Task { @MainActor [weak self] in
      self?.handleTerminalInput(data)
    }
  }

  nonisolated func scrolled(
    source _: TerminalView,
    position _: Double
  ) {}

  nonisolated func requestOpenLink(
    source _: TerminalView,
    link: String,
    params _: [String: String]
  ) {
    Task { @MainActor [weak self] in
      self?.handleOpenLink(link)
    }
  }

  nonisolated func bell(source _: TerminalView) {
    Task { @MainActor [weak self] in
      self?.handleBell()
    }
  }

  nonisolated func clipboardCopy(
    source _: TerminalView,
    content: Data
  ) {
    Task { @MainActor [weak self] in
      self?.handleClipboardCopy(content)
    }
  }

  nonisolated func iTermContent(
    source _: TerminalView,
    content _: ArraySlice<UInt8>
  ) {}

  nonisolated func rangeChanged(
    source _: TerminalView,
    startY _: Int,
    endY _: Int
  ) {}
}
