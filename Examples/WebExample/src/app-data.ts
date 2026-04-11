import type { WebTUISceneManifest, WebTUITerminalStyle } from "webtuigui";

export const fallbackManifest: WebTUISceneManifest = {
  defaultSceneId: "main",
  scenes: [
    {
      id: "main",
      title: "Deploy Dashboard",
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
  fontSize: 15,
  fontFamily:
    '"BerkleyMono Nerd Font", "Berkley Mono", "SFMono-Regular", "SF Mono", "Menlo", "Monaco", "Consolas", "Liberation Mono", monospace',
  cursorBlink: false,
  backgroundOpacity: 0.94,
};

export const terminalAppManifestPath = "./TerminalApp/dist/scene-manifest.json";
export const terminalAppWasmPath = "./TerminalApp/dist/assets/app.wasm";
