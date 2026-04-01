import type { ITheme } from "./vendor/ghostty-web.ts";

export type WebTUIColorScheme = "light" | "dark";
export type WebTUIColorSchemeMode = WebTUIColorScheme | "system";

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

export interface WebTUITerminalThemeColors {
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

export interface WebTUITerminalThemeVariant {
  palette?: WebTUITerminalPalette;
  theme?: WebTUITerminalThemeColors;
}

export interface WebTUITerminalStyle {
  fontSize?: number;
  fontFamily?: string;
  cursorStyle?: WebTUITerminalCursorStyle;
  cursorBlink?: boolean;
  backgroundOpacity?: number;
  colorSchemeMode?: WebTUIColorSchemeMode;
  light?: WebTUITerminalThemeVariant;
  dark?: WebTUITerminalThemeVariant;
  lightPalette?: WebTUITerminalPalette;
  darkPalette?: WebTUITerminalPalette;
  lightTheme?: WebTUITerminalThemeColors;
  darkTheme?: WebTUITerminalThemeColors;
}

export interface ResolvedWebTUITerminalThemeVariant {
  palette: Required<WebTUITerminalPalette>;
  theme: Required<WebTUITerminalThemeColors>;
}

export interface ResolvedWebTUITerminalStyle {
  fontSize: number;
  fontFamily: string;
  cursorStyle: WebTUITerminalCursorStyle;
  cursorBlink: boolean;
  backgroundOpacity: number;
  colorSchemeMode: WebTUIColorSchemeMode;
  light: ResolvedWebTUITerminalThemeVariant;
  dark: ResolvedWebTUITerminalThemeVariant;
}

export interface WebTUITerminalRenderStyle {
  appearance: WebTUITerminalAppearance;
  theme?: WebTUITerminalThemeColors;
}

export interface WebTUITerminalAppearance {
  foregroundColor: string;
  backgroundColor: string;
  tintColor: string;
  palette: Record<string, string>;
  colorScheme: WebTUIColorScheme;
  colorSchemeContrast: "standard" | "increased";
  source: "activeQuery" | "environmentHeuristics" | "fallback" | "override";
}

const defaultFontFamily =
  '"SFMono-Regular", "SF Mono", "Menlo", "Monaco", "Consolas", "Liberation Mono", monospace';

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

const defaultDarkTheme: Required<WebTUITerminalThemeColors> = {
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

const defaultLightTheme: Required<WebTUITerminalThemeColors> = {
  foreground: "#1f2328",
  background: "#ffffff",
  tint: "#0969da",
  separator: "#d0d7de",
  selection: "#c8ddff",
  placeholder: "#6e7781",
  link: "#0969da",
  fill: "#f6f8fa",
  windowBackground: "#ffffff",
  success: "#1a7f37",
  warning: "#9a6700",
  danger: "#cf222e",
  info: "#1b7c83",
  muted: "#57606a",
};

const defaultStyle: Omit<ResolvedWebTUITerminalStyle, "light" | "dark"> = {
  fontSize: 14,
  fontFamily: defaultFontFamily,
  cursorStyle: "block",
  cursorBlink: false,
  backgroundOpacity: 1,
  colorSchemeMode: "dark",
};

export function normalizeWebTUITerminalStyle(
  style: WebTUITerminalStyle = {}
): ResolvedWebTUITerminalStyle {
  return {
    ...defaultStyle,
    fontSize: normalizeFontSize(style.fontSize ?? defaultStyle.fontSize),
    fontFamily: style.fontFamily ?? defaultStyle.fontFamily,
    cursorStyle: style.cursorStyle ?? defaultStyle.cursorStyle,
    cursorBlink: style.cursorBlink ?? defaultStyle.cursorBlink,
    backgroundOpacity: normalizeOpacity(style.backgroundOpacity ?? defaultStyle.backgroundOpacity),
    colorSchemeMode: style.colorSchemeMode ?? defaultStyle.colorSchemeMode,
    light: resolveThemeVariant(
      style.light ?? {
        palette: style.lightPalette,
        theme: style.lightTheme,
      },
      defaultLightPalette,
      defaultLightTheme
    ),
    dark: resolveThemeVariant(
      style.dark ?? {
        palette: style.darkPalette,
        theme: style.darkTheme,
      },
      defaultDarkPalette,
      defaultDarkTheme
    ),
  };
}

export function mergeWebTUITerminalStyle(
  base: WebTUITerminalStyle,
  patch: WebTUITerminalStyle
): ResolvedWebTUITerminalStyle {
  return normalizeWebTUITerminalStyle({
    ...normalizeWebTUITerminalStyle(base),
    ...patch,
    light: mergeThemeVariant(
      normalizeWebTUITerminalStyle(base).light,
      patch.light ?? {
        palette: patch.lightPalette,
        theme: patch.lightTheme,
      }
    ),
    dark: mergeThemeVariant(
      normalizeWebTUITerminalStyle(base).dark,
      patch.dark ?? {
        palette: patch.darkPalette,
        theme: patch.darkTheme,
      }
    ),
  });
}

export function resolveWebTUIColorScheme(
  style: WebTUITerminalStyle,
  systemScheme: WebTUIColorScheme = "dark"
): WebTUIColorScheme {
  const normalized = normalizeWebTUITerminalStyle(style);
  return normalized.colorSchemeMode === "system"
    ? systemScheme
    : normalized.colorSchemeMode;
}

export function resolveWebTUITerminalRenderStyle(
  style: WebTUITerminalStyle,
  colorScheme: WebTUIColorScheme = "dark"
): WebTUITerminalRenderStyle {
  const normalized = normalizeWebTUITerminalStyle(style);
  const variant = resolveVariantForScheme(normalized, colorScheme);
  return {
    appearance: {
      foregroundColor: variant.theme.foreground,
      backgroundColor: variant.theme.background,
      tintColor: variant.theme.tint,
      palette: paletteToIndexedMap(variant.palette),
      colorScheme,
      colorSchemeContrast: contrastRatio(variant.theme.foreground, variant.theme.background) >= 7
        ? "increased"
        : "standard",
      source: "override",
    },
    theme: { ...variant.theme },
  };
}

export function encodeWebTUITerminalRenderStyleBase64(
  style: WebTUITerminalStyle,
  colorScheme: WebTUIColorScheme = "dark"
): string {
  const encoded = JSON.stringify(resolveWebTUITerminalRenderStyle(style, colorScheme));
  return encodeBase64(encoded);
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

export function ghosttyThemeForStyle(
  style: WebTUITerminalStyle,
  colorScheme: WebTUIColorScheme = "dark"
): ITheme {
  const normalized = normalizeWebTUITerminalStyle(style);
  const variant = resolveVariantForScheme(normalized, colorScheme);
  return {
    foreground: variant.palette.foreground,
    background: variant.palette.background,
    cursor: variant.palette.cursor,
    selectionBackground: variant.palette.selectionBackground,
    selectionForeground: variant.palette.selectionForeground,
    black: variant.palette.black,
    red: variant.palette.red,
    green: variant.palette.green,
    yellow: variant.palette.yellow,
    blue: variant.palette.blue,
    magenta: variant.palette.magenta,
    cyan: variant.palette.cyan,
    white: variant.palette.white,
    brightBlack: variant.palette.brightBlack,
    brightRed: variant.palette.brightRed,
    brightGreen: variant.palette.brightGreen,
    brightYellow: variant.palette.brightYellow,
    brightBlue: variant.palette.brightBlue,
    brightMagenta: variant.palette.brightMagenta,
    brightCyan: variant.palette.brightCyan,
    brightWhite: variant.palette.brightWhite,
  };
}

export function webTUITerminalBackgroundColor(
  style: WebTUITerminalStyle,
  colorScheme: WebTUIColorScheme = "dark"
): string {
  const normalized = normalizeWebTUITerminalStyle(style);
  const variant = resolveVariantForScheme(normalized, colorScheme);
  return hexToRgba(variant.theme.background, normalized.backgroundOpacity);
}

export function applyWebTUITerminalStyle(
  element: HTMLElement,
  style: WebTUITerminalStyle,
  colorScheme: WebTUIColorScheme = "dark"
): void {
  const normalized = normalizeWebTUITerminalStyle(style);
  const variant = resolveVariantForScheme(normalized, colorScheme);
  element.style.fontFamily = normalized.fontFamily;
  element.style.fontSize = `${normalized.fontSize}px`;
  element.style.background = hexToRgba(variant.theme.background, normalized.backgroundOpacity);
  element.style.color = variant.theme.foreground;
}

function resolveVariantForScheme(
  style: ResolvedWebTUITerminalStyle,
  colorScheme: WebTUIColorScheme
): ResolvedWebTUITerminalThemeVariant {
  return colorScheme === "light" ? style.light : style.dark;
}

function resolveThemeVariant(
  input: WebTUITerminalThemeVariant | undefined,
  defaultPalette: Required<WebTUITerminalPalette>,
  defaultTheme: Required<WebTUITerminalThemeColors>
): ResolvedWebTUITerminalThemeVariant {
  const palette = normalizePalette(input?.palette, defaultPalette);
  const theme = normalizeTheme(input?.theme, palette, defaultTheme);
  return { palette, theme };
}

function mergeThemeVariant(
  base: ResolvedWebTUITerminalThemeVariant,
  patch: WebTUITerminalThemeVariant | undefined
): ResolvedWebTUITerminalThemeVariant {
  if (!patch) {
    return base;
  }

  return resolveThemeVariant(
    {
      palette: patch.palette ?? base.palette,
      theme: patch.theme ?? base.theme,
    },
    base.palette,
    base.theme
  );
}

function normalizePalette(
  input: WebTUITerminalPalette | undefined,
  defaults: Required<WebTUITerminalPalette>
): Required<WebTUITerminalPalette> {
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
  input: WebTUITerminalThemeColors | undefined,
  palette: Required<WebTUITerminalPalette>,
  defaults: Required<WebTUITerminalThemeColors>
): Required<WebTUITerminalThemeColors> {
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
  palette: Required<WebTUITerminalPalette>,
  defaults: Required<WebTUITerminalThemeColors>
): Required<WebTUITerminalThemeColors> {
  return {
    foreground: palette.foreground,
    background: palette.background,
    tint: palette.cyan,
    separator: palette.brightBlack,
    selection: palette.selectionBackground,
    placeholder: palette.brightBlack,
    link: palette.blue,
    fill: defaults.fill,
    windowBackground: palette.background,
    success: palette.green,
    warning: palette.yellow,
    danger: palette.red,
    info: palette.cyan,
    muted: palette.brightBlack,
  };
}

function paletteToIndexedMap(
  palette: Required<WebTUITerminalPalette>
): Record<string, string> {
  return {
    0: palette.black,
    1: palette.red,
    2: palette.green,
    3: palette.yellow,
    4: palette.blue,
    5: palette.magenta,
    6: palette.cyan,
    7: palette.white,
    8: palette.brightBlack,
    9: palette.brightRed,
    10: palette.brightGreen,
    11: palette.brightYellow,
    12: palette.brightBlue,
    13: palette.brightMagenta,
    14: palette.brightCyan,
    15: palette.brightWhite,
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

  return 0.2126 * toLinear(channels.red) + 0.7152 * toLinear(channels.green) + 0.0722 * toLinear(channels.blue);
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
