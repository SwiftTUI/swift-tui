import type { WebTUISceneManifest } from "../../../GUI/WebTUIGUI/src/WebTUISceneManifest.ts";
import type { WebTUITerminalStyle } from "../../../GUI/WebTUIGUI/src/WebTUITerminalStyle.ts";

export const fallbackManifest: WebTUISceneManifest = {
  defaultSceneId: "main",
  scenes: [
    {
      id: "main",
      title: "Overview",
      isDefault: true,
    },
    {
      id: "details",
      title: "Details",
      isDefault: false,
    },
  ],
};

export const defaultStyle: WebTUITerminalStyle = {
  fontSize: 13,
  fontFamily:
    '"BerkleyMono Nerd Font", "Berkley Mono", "SFMono-Regular", "SF Mono", "Menlo", "Monaco", "Consolas", "Liberation Mono", monospace',
  cursorBlink: false,
  backgroundOpacity: 1.0,
};

export const terminalAppManifestPath = "/TerminalApp/dist/scene-manifest.json";
export const terminalAppWasmPath = "/TerminalApp/dist/assets/app.wasm";
