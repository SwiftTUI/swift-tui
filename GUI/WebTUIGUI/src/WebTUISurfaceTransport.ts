import {
  encodeWebTUITerminalRenderStyleBase64,
  type WebTUITerminalStyle,
} from "./WebTUITerminalStyle.ts";

export interface WebTUISurfaceStyle {
  fg?: string;
  bg?: string;
  em?: number;
  underline?: WebTUISurfaceLineStyle;
  strikethrough?: WebTUISurfaceLineStyle;
  opacity?: number;
}

export interface WebTUISurfaceLineStyle {
  pattern: "solid" | "dot" | "dash" | "dashDot" | "dashDotDot" | "double" | "curly";
  color?: string;
}

export type WebTUISurfaceCell = [
  x: number,
  text: string,
  span: number,
  styleIndex: number,
];

export type WebTUISurfaceRect = [
  x: number,
  y: number,
  width: number,
  height: number,
];

export type WebTUISurfaceSize = [
  width: number,
  height: number,
];

export type WebTUISurfaceImageFormat = "png" | "jpeg" | "gif";

export interface WebTUISurfaceImage {
  id: string;
  format: WebTUISurfaceImageFormat;
  bounds: WebTUISurfaceRect;
  visibleBounds: WebTUISurfaceRect;
  scalingMode: "stretch" | "fit" | "fill";
  pixelSize?: WebTUISurfaceSize;
  dataBase64?: string;
}

export interface WebTUISurfaceFrame {
  version: 1;
  width: number;
  height: number;
  styles: Array<WebTUISurfaceStyle | null>;
  rows: WebTUISurfaceCell[][];
  images?: WebTUISurfaceImage[];
}

export type WebTUIOutputRecord =
  | { type: "surface"; frame: WebTUISurfaceFrame }
  | { type: "text"; text: string };

export interface WebTUIKeyInput {
  key:
    | "return"
    | "space"
    | "tab"
    | "arrowLeft"
    | "arrowRight"
    | "arrowUp"
    | "arrowDown"
    | "backspace"
    | "escape"
    | "home"
    | "end"
    | "character";
  character?: string;
  modifiers?: number;
}

export interface WebTUIMouseInput {
  kind: "down" | "up" | "moved" | "dragged" | "scrolled";
  x: number;
  y: number;
  button?: "primary" | "middle" | "secondary";
  deltaX?: number;
  deltaY?: number;
  modifiers?: number;
}

const recordPrefix = "\u001E";
const textEncoder = new TextEncoder();

export class WebTUIOutputDecoder {
  private readonly textDecoder = new TextDecoder();
  private bufferedText = "";

  feed(
    chunk: Uint8Array
  ): WebTUIOutputRecord[] {
    this.bufferedText += this.textDecoder.decode(chunk, { stream: true });
    const records: WebTUIOutputRecord[] = [];

    while (true) {
      const newlineIndex = this.bufferedText.indexOf("\n");
      if (newlineIndex < 0) {
        break;
      }

      const line = this.bufferedText.slice(0, newlineIndex);
      this.bufferedText = this.bufferedText.slice(newlineIndex + 1);
      records.push(this.decodeLine(line));
    }

    if (this.bufferedText.length > 4096 && !this.bufferedText.startsWith(recordPrefix)) {
      records.push({ type: "text", text: this.bufferedText });
      this.bufferedText = "";
    }

    return records;
  }

  flush(): WebTUIOutputRecord[] {
    if (!this.bufferedText) {
      return [];
    }
    const text = this.bufferedText;
    this.bufferedText = "";
    return [this.decodeLine(text)];
  }

  private decodeLine(
    line: string
  ): WebTUIOutputRecord {
    if (!line.startsWith(`${recordPrefix}surface:`)) {
      return { type: "text", text: `${line}\n` };
    }

    try {
      const frame = JSON.parse(line.slice(`${recordPrefix}surface:`.length));
      if (isWebTUISurfaceFrame(frame)) {
        return { type: "surface", frame };
      }
    } catch {
      // Fall through to the text path below so malformed output remains visible.
    }

    return { type: "text", text: `${line}\n` };
  }
}

export function encodeResizeControlMessage(
  columns: number,
  rows: number,
  cellWidth?: number,
  cellHeight?: number
): Uint8Array {
  const normalizedColumns = Math.max(1, Math.round(columns));
  const normalizedRows = Math.max(1, Math.round(rows));
  if (cellWidth && cellHeight) {
    return textEncoder.encode(
      `${recordPrefix}resize:${normalizedColumns}:${normalizedRows}:${Math.max(1, Math.round(cellWidth))}:${Math.max(1, Math.round(cellHeight))}\n`
    );
  }

  return textEncoder.encode(`${recordPrefix}resize:${normalizedColumns}:${normalizedRows}\n`);
}

export function encodeRenderStyleControlMessage(
  style: WebTUITerminalStyle
): Uint8Array {
  const encoded = encodeWebTUITerminalRenderStyleBase64(style);
  return textEncoder.encode(`${recordPrefix}style:${encoded}\n`);
}

export function encodeKeyInputMessage(
  input: WebTUIKeyInput
): Uint8Array {
  const modifiers = Math.max(0, Math.round(input.modifiers ?? 0));
  if (input.key === "character") {
    return textEncoder.encode(
      `${recordPrefix}key:character:${encodeURIComponent(input.character ?? "")}:${modifiers}\n`
    );
  }
  return textEncoder.encode(`${recordPrefix}key:${input.key}:${modifiers}\n`);
}

export function encodePasteInputMessage(
  text: string
): Uint8Array {
  return textEncoder.encode(`${recordPrefix}paste:${encodeURIComponent(text)}\n`);
}

export function encodeMouseInputMessage(
  input: WebTUIMouseInput
): Uint8Array {
  return textEncoder.encode(
    recordPrefix + [
      "mouse",
      input.kind,
      formatCellCoordinate(input.x),
      formatCellCoordinate(input.y),
      input.button ?? "none",
      Math.round(input.deltaX ?? 0),
      Math.round(input.deltaY ?? 0),
      Math.max(0, Math.round(input.modifiers ?? 0)),
    ].join(":") + "\n"
  );
}

function formatCellCoordinate(
  value: number
): string {
  return Number.isFinite(value) ? String(value) : "0";
}

function isWebTUISurfaceFrame(
  value: unknown
): value is WebTUISurfaceFrame {
  if (!value || typeof value !== "object") {
    return false;
  }
  const frame = value as Partial<WebTUISurfaceFrame>;
  return frame.version === 1
    && typeof frame.width === "number"
    && typeof frame.height === "number"
    && Array.isArray(frame.styles)
    && Array.isArray(frame.rows)
    && (frame.images === undefined || isWebTUISurfaceImages(frame.images));
}

function isWebTUISurfaceImages(
  value: unknown
): value is WebTUISurfaceImage[] {
  return Array.isArray(value) && value.every(isWebTUISurfaceImage);
}

function isWebTUISurfaceImage(
  value: unknown
): value is WebTUISurfaceImage {
  if (!value || typeof value !== "object") {
    return false;
  }
  const image = value as Partial<WebTUISurfaceImage>;
  return typeof image.id === "string"
    && isWebTUISurfaceImageFormat(image.format)
    && isWebTUISurfaceRect(image.bounds)
    && isWebTUISurfaceRect(image.visibleBounds)
    && isWebTUISurfaceScalingMode(image.scalingMode)
    && (image.pixelSize === undefined || isWebTUISurfaceSize(image.pixelSize))
    && (image.dataBase64 === undefined || typeof image.dataBase64 === "string");
}

function isWebTUISurfaceImageFormat(
  value: unknown
): value is WebTUISurfaceImageFormat {
  return value === "png" || value === "jpeg" || value === "gif";
}

function isWebTUISurfaceRect(
  value: unknown
): value is WebTUISurfaceRect {
  return Array.isArray(value)
    && value.length === 4
    && value.every((entry) => typeof entry === "number");
}

function isWebTUISurfaceSize(
  value: unknown
): value is WebTUISurfaceSize {
  return Array.isArray(value)
    && value.length === 2
    && value.every((entry) => typeof entry === "number");
}

function isWebTUISurfaceScalingMode(
  value: unknown
): value is WebTUISurfaceImage["scalingMode"] {
  return value === "stretch" || value === "fit" || value === "fill";
}
