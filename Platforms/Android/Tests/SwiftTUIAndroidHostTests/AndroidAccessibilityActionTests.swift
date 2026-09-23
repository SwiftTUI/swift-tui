#if !os(Windows)
  import Foundation
  import SwiftTUIAndroidHost
  @_spi(Testing) import SwiftTUICore
  @_spi(Runners) import SwiftTUIRuntime
  import Testing

  @MainActor
  @Test
  func android_accessibility_abi_routes_actions_and_returns_runtime_rejections() async throws {
    let host = try AndroidHostSceneHost(app: AndroidAccessibilityApp())
    let handle = AndroidHostHandleRegistry.register(host)
    defer { swift_tui_android_destroy(handle) }
    host.start()
    let initial = await host.surface.waitForFrame { !$0.semantics.accessibilityNodes.isEmpty }
    let target = try #require(
      initial.semantics.accessibilityNodes.first { $0.label == "Add" }?.actionTarget)
    let encodedTarget = try #require(
      target.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
    func send(_ command: String) -> Int32 {
      Array(command.utf8).withUnsafeBufferPointer {
        unsafe swift_tui_android_accessibility_action(handle, $0.baseAddress, Int32($0.count))
      }
    }
    try #require(send("\u{1E}accessibility:1:\(encodedTarget):activate\n") == 1)
    let accepted = await host.surface.waitForFrame {
      $0.semantics.accessibilityActionResponse?.requestID == 1
    }
    #expect(accepted.semantics.accessibilityActionResponse?.result == .accepted)
    #expect(accepted.raster.lines.joined().contains("Count 1"))
    try #require(send("\u{1E}accessibility:2:removed:activate\n") == 1)
    let refused = await host.surface.waitForFrame {
      $0.semantics.accessibilityActionResponse?.requestID == 2
    }
    #expect(refused.semantics.accessibilityActionResponse?.result == .staleTarget)
    #expect(refused.raster.lines.joined().contains("Count 1"))
    for invalid in [
      "x", "\u{1E}accessibility:x:activate", "\u{1E}accessibility:3:x:setValue:number:NaN\n",
      "\u{1E}accessibility:3:x:setValue:text:%FF\n", "\u{1E}accessibility:3:x:activate\nextra\n",
    ] {
      #expect(send(invalid) == 0)
    }
    #expect(swift_tui_android_accessibility_action(handle, nil, 1) == 0)
    #expect(swift_tui_android_accessibility_action(-1, nil, 0) == 0)
    let one: [UInt8] = [0]
    one.withUnsafeBufferPointer {
      #expect(unsafe swift_tui_android_accessibility_action(handle, $0.baseAddress, .max) == 0)
    }
  }

  @MainActor
  private struct AndroidAccessibilityApp: App {
    var body: some Scene { WindowGroup { AndroidAccessibilityControls() } }
  }
  @MainActor
  private struct AndroidAccessibilityControls: View {
    @State private var count = 0
    var body: some View {
      VStack {
        Text("Count \(count)")
        Button("Add") { count += 1 }
      }
    }
  }
#endif
