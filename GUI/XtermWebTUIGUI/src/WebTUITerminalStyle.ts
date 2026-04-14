import type { ITheme } from "./vendor/xterm.ts";

export type WebTUITerminalCursorStyle = "block" | "bar" | "underline";

export interface WebTUIANSIColors {
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

export interface WebTUITerminalPalette {
  foreground?: string;
  background?: string;
  cursor?: string;
  selectionBackground?: string;
  selectionForeground?: string;
  ansi?: WebTUIANSIColors;
}

export interface WebTUITerminalTheme {
  foreground?: string;
  background?: string;
  tint?: string;
  separator?: string;
  selection?: string;
  placeholder?: string;
  link?: string;
  fill?: string;
  windowBackground?: string;
  success?: string;
  warning?: string;
  danger?: string;
  info?: string;
  muted?: string;
}

export interface WebTUITerminalStyle {
  fontSize?: number;
  fontFamily?: string;
  cursorStyle?: WebTUITerminalCursorStyle;
  cursorBlink?: boolean;
  backgroundOpacity?: number;
  palette?: WebTUITerminalPalette;
  theme?: WebTUITerminalTheme;
}

export interface ResolvedWebTUITerminalPalette {
  foreground: string;
  background: string;
  cursor: string;
  selectionBackground: string;
  selectionForeground: string;
  ansi: Required<WebTUIANSIColors>;
}

export interface ResolvedWebTUITerminalStyle {
  fontSize: number;
  fontFamily: string;
  cursorStyle: WebTUITerminalCursorStyle;
  cursorBlink: boolean;
  backgroundOpacity: number;
  palette: ResolvedWebTUITerminalPalette;
  theme: Required<WebTUITerminalTheme>;
}

export interface WebTUITerminalRenderStyle {
  appearance: WebTUITerminalAppearance;
  theme?: WebTUITerminalTheme;
}

export interface WebTUITerminalAppearance {
  foregroundColor: string;
  backgroundColor: string;
  tintColor: string;
  palette: Record<string, string>;
  colorSchemeContrast: "standard" | "increased";
  source: "activeQuery" | "environmentHeuristics" | "fallback" | "override";
}

const defaultFontFamily =
  '"SFMono-Regular", "SF Mono", "Menlo", "Monaco", "Consolas", "Liberation Mono", monospace';

const defaultANSI: Required<WebTUIANSIColors> = {
  black: "#20242c",
  red: "#e05757",
  green: "#61c67b",
  yellow: "#ebb33c",
  blue: "#5ba3ff",
  magenta: "#b46eff",
  cyan: "#56b6c2",
  white: "#eceff4",
  brightBlack: "#8c92ac",
  brightRed: "#ff7b72",
  brightGreen: "#7ee787",
  brightYellow: "#f2cc60",
  brightBlue: "#79c0ff",
  brightMagenta: "#d2a8ff",
  brightCyan: "#7de2d1",
  brightWhite: "#ffffff",
};

const defaultPalette: ResolvedWebTUITerminalPalette = {
  foreground: "#eceff4",
  background: "#1e222a",
  cursor: "#56b6c2",
  selectionBackground: "#2e3440",
  selectionForeground: "#eceff4",
  ansi: defaultANSI,
};

const defaultTheme: Required<WebTUITerminalTheme> = {
  foreground: "#eceff4",
  background: "#1e222a",
  tint: "#56b6c2",
  separator: "#4c566a",
  selection: "#2e3440",
  placeholder: "#8c92ac",
  link: "#5ba3ff",
  fill: "#2b303b",
  windowBackground: "#15181e",
  success: "#61c67b",
  warning: "#ebb33c",
  danger: "#e05757",
  info: "#56b6c2",
  muted: "#8c92ac",
};

export function normalizeWebTUITerminalStyle(
  style: WebTUITerminalStyle = {}
): ResolvedWebTUITerminalStyle {
  const palette = normalizePalette(style.palette, defaultPalette);
  const theme = normalizeTheme(style.theme, palette, defaultTheme);
  return {
    fontSize: normalizeFontSize(style.fontSize ?? 14),
    fontFamily: style.fontFamily ?? defaultFontFamily,
    cursorStyle: style.cursorStyle ?? "block",
    cursorBlink: style.cursorBlink ?? false,
    backgroundOpacity: normalizeOpacity(style.backgroundOpacity ?? 1),
    palette,
    theme,
  };
}

export function mergeWebTUITerminalStyle(
  base: WebTUITerminalStyle,
  patch: WebTUITerminalStyle
): ResolvedWebTUITerminalStyle {
  const resolvedBase = normalizeWebTUITerminalStyle(base);
  return normalizeWebTUITerminalStyle({
    ...resolvedBase,
    ...patch,
    palette: mergePalette(resolvedBase.palette, patch.palette),
    theme: patch.theme ? { ...resolvedBase.theme, ...patch.theme } : resolvedBase.theme,
  });
}

export function resolveWebTUITerminalRenderStyle(
  style: WebTUITerminalStyle
): WebTUITerminalRenderStyle {
  const normalized = normalizeWebTUITerminalStyle(style);
  return {
    appearance: {
      foregroundColor: normalized.theme.foreground,
      backgroundColor: normalized.theme.background,
      tintColor: normalized.theme.tint,
      palette: paletteToIndexedMap(normalized.palette.ansi),
      colorSchemeContrast: contrastRatio(normalized.theme.foreground, normalized.theme.background) >= 7
        ? "increased"
        : "standard",
      source: "override",
    },
    theme: { ...normalized.theme },
  };
}

export function encodeWebTUITerminalRenderStyleBase64(
  style: WebTUITerminalStyle
): string {
  return encodeBase64(JSON.stringify(resolveWebTUITerminalRenderStyle(style)));
}

export function decodeWebTUITerminalRenderStyleBase64(
  encoded: string
): WebTUITerminalRenderStyle | undefined {
  const json = decodeBase64(encoded);
  if (!json) {
    return undefined;
  }

  try {
    return JSON.parse(json) as WebTUITerminalRenderStyle;
  } catch {
    return undefined;
  }
}

export function xtermThemeForStyle(
  style: WebTUITerminalStyle
): ITheme {
  const normalized = normalizeWebTUITerminalStyle(style);
  return {
    foreground: normalized.palette.foreground,
    background: webTUITerminalBackgroundColor(normalized),
    cursor: normalized.palette.cursor,
    cursorAccent: normalized.palette.background,
    selectionBackground: normalized.palette.selectionBackground,
    selectionForeground: normalized.palette.selectionForeground,
    black: normalized.palette.ansi.black,
    red: normalized.palette.ansi.red,
    green: normalized.palette.ansi.green,
    yellow: normalized.palette.ansi.yellow,
    blue: normalized.palette.ansi.blue,
    magenta: normalized.palette.ansi.magenta,
    cyan: normalized.palette.ansi.cyan,
    white: normalized.palette.ansi.white,
    brightBlack: normalized.palette.ansi.brightBlack,
    brightRed: normalized.palette.ansi.brightRed,
    brightGreen: normalized.palette.ansi.brightGreen,
    brightYellow: normalized.palette.ansi.brightYellow,
    brightBlue: normalized.palette.ansi.brightBlue,
    brightMagenta: normalized.palette.ansi.brightMagenta,
    brightCyan: normalized.palette.ansi.brightCyan,
    brightWhite: normalized.palette.ansi.brightWhite,
  };
}

export function webTUITerminalBackgroundColor(
  style: WebTUITerminalStyle
): string {
  const normalized = normalizeWebTUITerminalStyle(style);
  return hexToRgba(normalized.theme.background, normalized.backgroundOpacity);
}

export function applyWebTUITerminalStyle(
  element: HTMLElement,
  style: WebTUITerminalStyle
): void {
  const normalized = normalizeWebTUITerminalStyle(style);
  element.style.fontFamily = normalized.fontFamily;
  element.style.fontSize = `${normalized.fontSize}px`;
  element.style.background = hexToRgba(normalized.theme.background, normalized.backgroundOpacity);
  element.style.color = normalized.theme.foreground;
}

function normalizePalette(
  input: WebTUITerminalPalette | undefined,
  defaults: ResolvedWebTUITerminalPalette
): ResolvedWebTUITerminalPalette {
  return {
    foreground: normalizeHexColor(input?.foreground ?? defaults.foreground),
    background: normalizeHexColor(input?.background ?? defaults.background),
    cursor: normalizeHexColor(input?.cursor ?? defaults.cursor),
    selectionBackground: normalizeHexColor(
      input?.selectionBackground ?? defaults.selectionBackground
    ),
    selectionForeground: normalizeHexColor(
      input?.selectionForeground ?? defaults.selectionForeground
    ),
    ansi: normalizeANSI(input?.ansi, defaults.ansi),
  };
}

function mergePalette(
  base: ResolvedWebTUITerminalPalette,
  patch: WebTUITerminalPalette | undefined
): WebTUITerminalPalette {
  if (!patch) {
    return base;
  }

  return {
    ...base,
    ...patch,
    ansi: patch.ansi ? { ...base.ansi, ...patch.ansi } : base.ansi,
  };
}

function normalizeANSI(
  input: WebTUIANSIColors | undefined,
  defaults: Required<WebTUIANSIColors>
): Required<WebTUIANSIColors> {
  return {
    black: normalizeHexColor(input?.black ?? defaults.black),
    red: normalizeHexColor(input?.red ?? defaults.red),
    green: normalizeHexColor(input?.green ?? defaults.green),
    yellow: normalizeHexColor(input?.yellow ?? defaults.yellow),
    blue: normalizeHexColor(input?.blue ?? defaults.blue),
    magenta: normalizeHexColor(input?.magenta ?? defaults.magenta),
    cyan: normalizeHexColor(input?.cyan ?? defaults.cyan),
    white: normalizeHexColor(input?.white ?? defaults.white),
    brightBlack: normalizeHexColor(input?.brightBlack ?? defaults.brightBlack),
    brightRed: normalizeHexColor(input?.brightRed ?? defaults.brightRed),
    brightGreen: normalizeHexColor(input?.brightGreen ?? defaults.brightGreen),
    brightYellow: normalizeHexColor(input?.brightYellow ?? defaults.brightYellow),
    brightBlue: normalizeHexColor(input?.brightBlue ?? defaults.brightBlue),
    brightMagenta: normalizeHexColor(input?.brightMagenta ?? defaults.brightMagenta),
    brightCyan: normalizeHexColor(input?.brightCyan ?? defaults.brightCyan),
    brightWhite: normalizeHexColor(input?.brightWhite ?? defaults.brightWhite),
  };
}

function normalizeTheme(
  input: WebTUITerminalTheme | undefined,
  palette: ResolvedWebTUITerminalPalette,
  defaults: Required<WebTUITerminalTheme>
): Required<WebTUITerminalTheme> {
  const derived = themeFromPalette(palette, defaults);
  return {
    foreground: normalizeHexColor(input?.foreground ?? derived.foreground),
    background: normalizeHexColor(input?.background ?? derived.background),
    tint: normalizeHexColor(input?.tint ?? derived.tint),
    separator: normalizeHexColor(input?.separator ?? derived.separator),
    selection: normalizeHexColor(input?.selection ?? derived.selection),
    placeholder: normalizeHexColor(input?.placeholder ?? derived.placeholder),
    link: normalizeHexColor(input?.link ?? derived.link),
    fill: normalizeHexColor(input?.fill ?? derived.fill),
    windowBackground: normalizeHexColor(input?.windowBackground ?? derived.windowBackground),
    success: normalizeHexColor(input?.success ?? derived.success),
    warning: normalizeHexColor(input?.warning ?? derived.warning),
    danger: normalizeHexColor(input?.danger ?? derived.danger),
    info: normalizeHexColor(input?.info ?? derived.info),
    muted: normalizeHexColor(input?.muted ?? derived.muted),
  };
}

function themeFromPalette(
  palette: ResolvedWebTUITerminalPalette,
  defaults: Required<WebTUITerminalTheme>
): Required<WebTUITerminalTheme> {
  return {
    foreground: palette.foreground,
    background: palette.background,
    tint: palette.cursor,
    separator: palette.ansi.brightBlack,
    selection: palette.selectionBackground,
    placeholder: palette.ansi.brightBlack,
    link: palette.ansi.blue,
    fill: defaults.fill,
    windowBackground: palette.background,
    success: palette.ansi.green,
    warning: palette.ansi.yellow,
    danger: palette.ansi.red,
    info: palette.ansi.cyan,
    muted: palette.ansi.brightBlack,
  };
}

function paletteToIndexedMap(
  ansi: Required<WebTUIANSIColors>
): Record<string, string> {
  return {
    0: ansi.black,
    1: ansi.red,
    2: ansi.green,
    3: ansi.yellow,
    4: ansi.blue,
    5: ansi.magenta,
    6: ansi.cyan,
    7: ansi.white,
    8: ansi.brightBlack,
    9: ansi.brightRed,
    10: ansi.brightGreen,
    11: ansi.brightYellow,
    12: ansi.brightBlue,
    13: ansi.brightMagenta,
    14: ansi.brightCyan,
    15: ansi.brightWhite,
  };
}

function normalizeFontSize(fontSize: number): number {
  return Number.isFinite(fontSize) && fontSize > 0 ? fontSize : 14;
}

function normalizeOpacity(opacity: number): number {
  if (!Number.isFinite(opacity)) {
    return 1;
  }

  return Math.min(1, Math.max(0, opacity));
}

function normalizeHexColor(value: string): string {
  const trimmed = value.trim();
  const normalized = trimmed.startsWith("#") ? trimmed : `#${trimmed}`;
  if (!/^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(normalized)) {
    throw new Error(`Invalid hex color: ${value}`);
  }

  return normalized.toLowerCase();
}

function hexToRgba(
  color: string,
  opacity: number
): string {
  const normalized = normalizeHexColor(color);
  const alpha = normalizeOpacity(opacity);
  const channels = parseHexColor(normalized);
  if (!channels) {
    return normalized;
  }

  const finalAlpha = Math.round(channels.alpha * alpha * 1000) / 1000;
  return `rgba(${channels.red}, ${channels.green}, ${channels.blue}, ${finalAlpha})`;
}

function parseHexColor(
  color: string
): {
  red: number;
  green: number;
  blue: number;
  alpha: number;
} | undefined {
  const hex = color.startsWith("#") ? color.slice(1) : color;
  const normalized = hex.length === 3 || hex.length === 4
    ? hex.split("").map((ch) => ch + ch).join("")
    : hex;

  if (normalized.length !== 6 && normalized.length !== 8) {
    return undefined;
  }

  const red = Number.parseInt(normalized.slice(0, 2), 16);
  const green = Number.parseInt(normalized.slice(2, 4), 16);
  const blue = Number.parseInt(normalized.slice(4, 6), 16);
  const alpha = normalized.length === 8
    ? Number.parseInt(normalized.slice(6, 8), 16) / 255
    : 1;
  return { red, green, blue, alpha };
}

function contrastRatio(
  foreground: string,
  background: string
): number {
  const fg = relativeLuminance(foreground);
  const bg = relativeLuminance(background);
  const lighter = Math.max(fg, bg);
  const darker = Math.min(fg, bg);
  return (lighter + 0.05) / (darker + 0.05);
}

function relativeLuminance(color: string): number {
  const channels = parseHexColor(normalizeHexColor(color));
  if (!channels) {
    return 0;
  }

  const toLinear = (channel: number) => {
    const value = channel / 255;
    return value <= 0.03928
      ? value / 12.92
      : ((value + 0.055) / 1.055) ** 2.4;
  };

  return 0.2126 * toLinear(channels.red) + 0.7152 * toLinear(channels.green)
    + 0.0722 * toLinear(channels.blue);
}

function encodeBase64(value: string): string {
  if (typeof btoa === "function") {
    const bytes = new TextEncoder().encode(value);
    let binary = "";
    for (const byte of bytes) {
      binary += String.fromCharCode(byte);
    }
    return btoa(binary);
  }

  return Buffer.from(value, "utf8").toString("base64");
}

function decodeBase64(value: string): string | undefined {
  try {
    if (typeof atob === "function") {
      const binary = atob(value);
      const bytes = new Uint8Array(binary.length);
      for (let index = 0; index < binary.length; index += 1) {
        bytes[index] = binary.charCodeAt(index);
      }
      return new TextDecoder().decode(bytes);
    }

    return Buffer.from(value, "base64").toString("utf8");
  } catch {
    return undefined;
  }
}
