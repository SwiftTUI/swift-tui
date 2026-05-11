import SwiftTUI
public import SwiftUI

public struct SwiftUIHostAppView<A: SwiftTUI.App>: SwiftUI.View {
  private let state: SwiftUIHostAppState<A>

  public init(state: SwiftUIHostAppState<A>) {
    self.state = state
  }

  public var body: some SwiftUI.View {
    VStack(spacing: 0) {
      if state.scenes.count > 1 {
        SceneSwitcherBar(
          scenes: state.scenes,
          selectedSceneID: state.selectedSceneID
        ) { sceneID in
          state.selectScene(sceneID)
        }
      }
      SceneTerminalSurface(host: state.currentSceneHost)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .ignoresSafeArea(.container, edges: .bottom)
    .task {
      state.start()
    }
    .onDisappear {
      state.stop()
    }
  }
}

@available(macOS 14.0, iOS 17.0, macCatalyst 17.0, *)
private struct TerminalSurfaceHost: SwiftUI.View {
  let host: SwiftUIHostSceneHost

  var body: some SwiftUI.View {
    TerminalSurfaceRepresentable(host: host)
      .background(.clear)
  }
}

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  @available(macOS 14.0, *)
  private struct TerminalSurfaceRepresentable: NSViewRepresentable {
    let host: SwiftUIHostSceneHost

    func makeNSView(context _: Context) -> NativeTerminalSurfaceView {
      let view = NativeTerminalSurfaceView(frame: .zero)
      configure(view)
      return view
    }

    func updateNSView(_ view: NativeTerminalSurfaceView, context _: Context) {
      configure(view)
    }

    private func configure(_ view: NativeTerminalSurfaceView) {
      view.surface = host.latestSurface
      view.style = host.style
      view.focusPresentation = host.focusPresentation
      view.allowsTextInput =
        host.focusPresentation.prefersTextInput || host.manualKeyboardPresentationRequested
      view.onResize = { [weak host] size, cellPixelSize in
        host?.resize(to: size, cellPixelSize: cellPixelSize)
      }
      view.onInputEvent = { [weak host] event in
        host?.send(event)
      }
    }
  }
#elseif canImport(UIKit)
  @available(iOS 17.0, macCatalyst 17.0, *)
  private struct TerminalSurfaceRepresentable: UIViewRepresentable {
    let host: SwiftUIHostSceneHost

    func makeUIView(context _: Context) -> NativeTerminalSurfaceView {
      let view = NativeTerminalSurfaceView(frame: .zero)
      configure(view)
      return view
    }

    func updateUIView(_ view: NativeTerminalSurfaceView, context _: Context) {
      configure(view)
    }

    private func configure(_ view: NativeTerminalSurfaceView) {
      view.surface = host.latestSurface
      view.style = host.style
      view.focusPresentation = host.focusPresentation
      view.allowsTextInput =
        host.focusPresentation.prefersTextInput || host.manualKeyboardPresentationRequested
      view.onResize = { [weak host] size, cellPixelSize in
        host?.resize(to: size, cellPixelSize: cellPixelSize)
      }
      view.onInputEvent = { [weak host] event in
        host?.send(event)
      }
    }
  }
#endif

private struct SceneSwitcherBar: SwiftUI.View {
  let scenes: [SwiftUIHostSceneDescriptor]
  let selectedSceneID: WindowIdentifier
  let onSelect: (WindowIdentifier) -> Void

  var body: some SwiftUI.View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 0) {
        ForEach(scenes) { scene in
          Button {
            onSelect(scene.id)
          } label: {
            let isSelected = scene.id == selectedSceneID

            Text(scene.title ?? scene.id.rawValue)
              .lineLimit(1)
              .monospaced()
              .fontWeight(isSelected ? .semibold : .regular)
              .foregroundStyle(isSelected ? SwiftUI.Color.accentColor : SwiftUI.Color.primary)
              .padding(.horizontal, 6)
              .padding(.vertical, 3)
              .background {
                Rectangle()
                  .fill(
                    isSelected
                      ? SwiftUI.Color.accentColor.opacity(0.18)
                      : SwiftUI.Color.clear
                  )
              }
          }
          .buttonStyle(.plain)
          .accessibilityLabel(scene.title ?? scene.id.rawValue)
        }
      }
      .padding(.top, 10)
    }
  }
}

private struct SceneTerminalSurface: SwiftUI.View {
  let host: SwiftUIHostSceneHost?

  var body: some SwiftUI.View {
    Group {
      if let host {
        TerminalSurfaceHost(host: host)
          .accessibilityHidden(true)
          .overlay(alignment: .topLeading) {
            HostedAccessibilityOverlay(
              semanticSnapshot: host.latestSemanticSnapshot,
              focusedIdentity: host.focusedAccessibilityIdentity,
              cellSize: NativeTerminalMetrics(style: host.style).cellSize
            )
          }
          .id(host.descriptor.id)
          #if canImport(UIKit) && !targetEnvironment(macCatalyst)
            .overlay(alignment: .topTrailing) {
              if host.focusPresentation.prefersTextInput == false {
                KeyboardToggleButton(
                  isPresented: host.manualKeyboardPresentationRequested,
                  action: host.toggleManualKeyboardPresentation
                )
                .padding(12)
              }
            }
          #endif
          .task {
            host.start()
          }
      } else {
        VStack(spacing: 8) {
          Text("No scene selected")
            .font(.headline)
          Text("The app did not produce a visible scene.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }
}

#if canImport(UIKit) && !targetEnvironment(macCatalyst)
  @available(iOS 17.0, *)
  private struct KeyboardToggleButton: SwiftUI.View {
    let isPresented: Bool
    let action: () -> Void

    var body: some SwiftUI.View {
      Button(action: action) {
        Image(systemName: isPresented ? "keyboard.chevron.compact.down" : "keyboard")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.primary)
          .frame(width: 36, height: 36)
          .background(.regularMaterial, in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isPresented ? "Hide keyboard" : "Show keyboard")
    }
  }
#endif
