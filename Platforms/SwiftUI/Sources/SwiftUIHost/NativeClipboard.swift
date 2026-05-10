#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

enum NativeClipboard {
  @MainActor
  static func write(
    _ text: String
  ) -> Bool {
    #if canImport(AppKit)
      NSPasteboard.general.clearContents()
      return NSPasteboard.general.setString(text, forType: .string)
    #elseif canImport(UIKit)
      UIPasteboard.general.string = text
      return true
    #else
      return false
    #endif
  }
}
