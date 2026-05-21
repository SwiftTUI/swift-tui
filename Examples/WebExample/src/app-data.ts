import type { WebHostSceneManifest, WebHostTerminalStyle } from "@swifttui/web";

export const fallbackManifest: WebHostSceneManifest = {
  defaultSceneId: "main",
  scenes: [
    {
      id: "main",
      title: "Component Gallery",
      isDefault: true,
    },
    {
      id: "details",
      title: "Details",
      isDefault: false,
    },
  ],
};

export const defaultStyle: WebHostTerminalStyle = {
  fontSize: 15,
  fontFamily:
    '"BerkleyMono Nerd Font", "Berkley Mono", "SFMono-Regular", "SF Mono", "Menlo", "Monaco", "Consolas", "Liberation Mono", monospace',
  cursorBlink: false,
  backgroundOpacity: 0.94,
};

// Palette tuned to the marketing Website (Website/src/styles/site.css):
// neutral near-black surface, zinc text ramp, emerald accent, amber warn.
// Used only by the `?embed=marketing` iframe; the standalone WebExample
// keeps `defaultStyle` and its own Nothing-palette chrome.
export const marketingStyle: WebHostTerminalStyle = {
  ...defaultStyle,
  backgroundOpacity: 1,
  palette: {
    foreground: "#ededed",
    background: "#0a0a0a",
    cursor: "#34d399",
    selectionBackground: "#122e24",
    selectionForeground: "#ededed",
    ansi: {
      black: "#0a0a0a",
      red: "#f43f5e",
      green: "#34d399",
      yellow: "#f59e0b",
      blue: "#60a5fa",
      magenta: "#c084fc",
      cyan: "#22d3ee",
      white: "#ededed",
      brightBlack: "#71717a",
      brightRed: "#fb7185",
      brightGreen: "#6ee7b7",
      brightYellow: "#fbbf24",
      brightBlue: "#93c5fd",
      brightMagenta: "#d8b4fe",
      brightCyan: "#67e8f9",
      brightWhite: "#ffffff",
    },
  },
  theme: {
    foreground: "#ededed",
    background: "#0a0a0a",
    tint: "#34d399",
    separator: "#1e1e1e",
    selection: "#122e24",
    placeholder: "#71717a",
    link: "#34d399",
    fill: "#161616",
    windowBackground: "#0a0a0a",
    success: "#34d399",
    warning: "#f59e0b",
    danger: "#f43f5e",
    info: "#a1a1aa",
    muted: "#71717a",
  },
};

export const terminalAppManifestPath = "./TerminalApp/dist/scene-manifest.json";
export const terminalAppWasmPath = "./TerminalApp/dist/assets/app.wasm";
