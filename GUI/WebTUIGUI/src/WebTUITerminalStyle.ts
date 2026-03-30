import type { ITheme } from "./vendor/ghostty-web.ts";

export type WebTUITerminalCursorStyle = "block" | "bar" | "underline";

export interface WebTUITerminalPalette {
  foreground?: string;
  background?: string;
  cursor?: string;
  selectionBackground?: string;
  selectionForeground?: string;
  black?: string;
  red?: string;
  green?: string;
  yellow?: string;
  blue?: string;
  magenta?: string;
  cyan?: string;
  white?: string;
  brightBlack?: string;
  brightRed?: string;
  brightGreen?: string;
  brightYellow?: string;
  brightBlue?: string;
  brightMagenta?: string;
  brightCyan?: string;
  brightWhite?: string;
}

export interface WebTUITerminalStyle {
  fontSize?: number;
  fontFamily?: string;
  cursorStyle?: WebTUITerminalCursorStyle;
  cursorBlink?: boolean;
  backgroundOpacity?: number;
  lightPalette?: WebTUITerminalPalette;
  darkPalette?: WebTUITerminalPalette;
}

const defaultDarkPalette: Required<WebTUITerminalPalette> = {
  foreground: "#d4d4d4",
  background: "#1e1e1e",
  cursor: "#ffffff",
  selectionBackground: "#264f78",
  selectionForeground: "#ffffff",
  black: "#000000",
  red: "#cd3131",
  green: "#0dbc79",
  yellow: "#e5e510",
  blue: "#2472c8",
  magenta: "#bc3fbc",
  cyan: "#11a8cd",
  white: "#e5e5e5",
  brightBlack: "#666666",
  brightRed: "#f14c4c",
  brightGreen: "#23d18b",
  brightYellow: "#f5f543",
  brightBlue: "#3b8eea",
  brightMagenta: "#d670d6",
  brightCyan: "#29b8db",
  brightWhite: "#e5e5e5",
};

const defaultLightPalette: Required<WebTUITerminalPalette> = {
  foreground: "#1f2328",
  background: "#ffffff",
  cursor: "#1f2328",
  selectionBackground: "#c8ddff",
  selectionForeground: "#1f2328",
  black: "#1f2328",
  red: "#cf222e",
  green: "#1a7f37",
  yellow: "#9a6700",
  blue: "#0969da",
  magenta: "#8250df",
  cyan: "#1b7c83",
  white: "#6e7781",
  brightBlack: "#57606a",
  brightRed: "#a40e26",
  brightGreen: "#116329",
  brightYellow: "#633c01",
  brightBlue: "#0550ae",
  brightMagenta: "#8250df",
  brightCyan: "#116b74",
  brightWhite: "#24292f",
};

const defaultStyle: Required<Omit<WebTUITerminalStyle, "lightPalette" | "darkPalette">> = {
  fontSize: 14,
  fontFamily:
    '"SFMono-Regular", "SF Mono", "Menlo", "Monaco", "Consolas", "Liberation Mono", monospace',
  cursorStyle: "block",
  cursorBlink: false,
  backgroundOpacity: 1,
};

export function normalizeWebTUITerminalStyle(
  style: WebTUITerminalStyle = {}
): Required<WebTUITerminalStyle> {
  return {
    ...defaultStyle,
    ...style,
    lightPalette: {
      ...defaultLightPalette,
      ...style.lightPalette,
    },
    darkPalette: {
      ...defaultDarkPalette,
      ...style.darkPalette,
    },
  };
}

export function mergeWebTUITerminalStyle(
  base: WebTUITerminalStyle,
  patch: WebTUITerminalStyle
): Required<WebTUITerminalStyle> {
  return normalizeWebTUITerminalStyle({
    ...base,
    ...patch,
    lightPalette: {
      ...base.lightPalette,
      ...patch.lightPalette,
    },
    darkPalette: {
      ...base.darkPalette,
      ...patch.darkPalette,
    },
  });
}

export function ghosttyThemeForStyle(
  style: WebTUITerminalStyle,
  variant: "light" | "dark" = "dark"
): ITheme {
  const normalized = normalizeWebTUITerminalStyle(style);
  const palette = variant === "light" ? normalized.lightPalette : normalized.darkPalette;
  return {
    foreground: palette.foreground,
    background: palette.background,
    cursor: palette.cursor,
    selectionBackground: palette.selectionBackground,
    selectionForeground: palette.selectionForeground,
    black: palette.black,
    red: palette.red,
    green: palette.green,
    yellow: palette.yellow,
    blue: palette.blue,
    magenta: palette.magenta,
    cyan: palette.cyan,
    white: palette.white,
    brightBlack: palette.brightBlack,
    brightRed: palette.brightRed,
    brightGreen: palette.brightGreen,
    brightYellow: palette.brightYellow,
    brightBlue: palette.brightBlue,
    brightMagenta: palette.brightMagenta,
    brightCyan: palette.brightCyan,
    brightWhite: palette.brightWhite,
  };
}

export function webTUITerminalBackgroundColor(
  style: WebTUITerminalStyle,
  variant: "light" | "dark" = "dark"
): string {
  const normalized = normalizeWebTUITerminalStyle(style);
  const palette = variant === "light" ? normalized.lightPalette : normalized.darkPalette;
  return hexToRgba(palette.background ?? defaultDarkPalette.background, normalized.backgroundOpacity);
}

export function applyWebTUITerminalStyle(
  element: HTMLElement,
  style: WebTUITerminalStyle,
  variant: "light" | "dark" = "dark"
): void {
  const normalized = normalizeWebTUITerminalStyle(style);
  element.style.fontFamily = normalized.fontFamily;
  element.style.fontSize = `${normalized.fontSize}px`;
  element.style.background = webTUITerminalBackgroundColor(normalized, variant);
  element.style.color =
    (variant === "light" ? normalized.lightPalette : normalized.darkPalette).foreground ??
    defaultDarkPalette.foreground;
}

function hexToRgba(
  color: string,
  opacity: number
): string {
  const alpha = Number.isFinite(opacity) ? Math.min(1, Math.max(0, opacity)) : 1;
  const hex = color.trim();
  if (!hex.startsWith("#")) {
    return hex;
  }

  const normalizedHex =
    hex.length === 4
      ? `#${hex[1]}${hex[1]}${hex[2]}${hex[2]}${hex[3]}${hex[3]}`
      : hex;
  const value = Number.parseInt(normalizedHex.slice(1), 16);
  if (Number.isNaN(value)) {
    return hex;
  }

  const red = (value >> 16) & 0xff;
  const green = (value >> 8) & 0xff;
  const blue = value & 0xff;
  return `rgba(${red}, ${green}, ${blue}, ${alpha})`;
}
