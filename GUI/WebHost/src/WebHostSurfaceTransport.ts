import {
  encodeWebHostTerminalRenderStyleBase64,
  type WebHostTerminalStyle,
} from "./WebHostTerminalStyle.ts";

export interface WebHostSurfaceStyle {
  fg?: string;
  bg?: string;
  em?: number;
  underline?: WebHostSurfaceLineStyle;
  strikethrough?: WebHostSurfaceLineStyle;
  opacity?: number;
}

export interface WebHostSurfaceLineStyle {
  pattern: "solid" | "dot" | "dash" | "dashDot" | "dashDotDot" | "double" | "curly";
  color?: string;
}

export type WebHostSurfaceCell = [
  x: number,
  text: string,
  span: number,
  styleIndex: number,
];

export type WebHostSurfaceRect = [
  x: number,
  y: number,
  width: number,
  height: number,
];

export type WebHostSurfaceSize = [
  width: number,
  height: number,
];

export type WebHostSurfaceImageFormat = "png" | "jpeg" | "gif";

export interface WebHostSurfaceImage {
  id: string;
  format: WebHostSurfaceImageFormat;
  bounds: WebHostSurfaceRect;
  visibleBounds: WebHostSurfaceRect;
  scalingMode: "stretch" | "fit" | "fill";
  pixelSize?: WebHostSurfaceSize;
  dataBase64?: string;
}

export interface WebHostSurfaceFrame {
  version: 1;
  width: number;
  height: number;
  styles: Array<WebHostSurfaceStyle | null>;
  rows: WebHostSurfaceCell[][];
  images?: WebHostSurfaceImage[];
}

export type WebHostOutputRecord =
  | { type: "surface"; frame: WebHostSurfaceFrame }
  | { type: "text"; text: string };

export interface WebHostKeyInput {
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

export interface WebHostMouseInput {
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

export class WebHostOutputDecoder {
  private readonly textDecoder = new TextDecoder();
  private bufferedText = "";

  feed(
    chunk: Uint8Array
  ): WebHostOutputRecord[] {
    this.bufferedText += this.textDecoder.decode(chunk, { stream: true });
    const records: WebHostOutputRecord[] = [];

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

  flush(): WebHostOutputRecord[] {
    if (!this.bufferedText) {
      return [];
    }
    const text = this.bufferedText;
    this.bufferedText = "";
    return [this.decodeLine(text)];
  }

  private decodeLine(
    line: string
  ): WebHostOutputRecord {
    if (!line.startsWith(`${recordPrefix}surface:`)) {
      return { type: "text", text: `${line}\n` };
    }

    try {
      const frame = JSON.parse(line.slice(`${recordPrefix}surface:`.length));
      if (isWebHostSurfaceFrame(frame)) {
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
  style: WebHostTerminalStyle
): Uint8Array {
  const encoded = encodeWebHostTerminalRenderStyleBase64(style);
  return textEncoder.encode(`${recordPrefix}style:${encoded}\n`);
}

export function encodeKeyInputMessage(
  input: WebHostKeyInput
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
  input: WebHostMouseInput
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

function isWebHostSurfaceFrame(
  value: unknown
): value is WebHostSurfaceFrame {
  if (!value || typeof value !== "object") {
    return false;
  }
  const frame = value as Partial<WebHostSurfaceFrame>;
  return frame.version === 1
    && typeof frame.width === "number"
    && typeof frame.height === "number"
    && Array.isArray(frame.styles)
    && Array.isArray(frame.rows)
    && (frame.images === undefined || isWebHostSurfaceImages(frame.images));
}

function isWebHostSurfaceImages(
  value: unknown
): value is WebHostSurfaceImage[] {
  return Array.isArray(value) && value.every(isWebHostSurfaceImage);
}

function isWebHostSurfaceImage(
  value: unknown
): value is WebHostSurfaceImage {
  if (!value || typeof value !== "object") {
    return false;
  }
  const image = value as Partial<WebHostSurfaceImage>;
  return typeof image.id === "string"
    && isWebHostSurfaceImageFormat(image.format)
    && isWebHostSurfaceRect(image.bounds)
    && isWebHostSurfaceRect(image.visibleBounds)
    && isWebHostSurfaceScalingMode(image.scalingMode)
    && (image.pixelSize === undefined || isWebHostSurfaceSize(image.pixelSize))
    && (image.dataBase64 === undefined || typeof image.dataBase64 === "string");
}

function isWebHostSurfaceImageFormat(
  value: unknown
): value is WebHostSurfaceImageFormat {
  return value === "png" || value === "jpeg" || value === "gif";
}

function isWebHostSurfaceRect(
  value: unknown
): value is WebHostSurfaceRect {
  return Array.isArray(value)
    && value.length === 4
    && value.every((entry) => typeof entry === "number");
}

function isWebHostSurfaceSize(
  value: unknown
): value is WebHostSurfaceSize {
  return Array.isArray(value)
    && value.length === 2
    && value.every((entry) => typeof entry === "number");
}

function isWebHostSurfaceScalingMode(
  value: unknown
): value is WebHostSurfaceImage["scalingMode"] {
  return value === "stretch" || value === "fit" || value === "fill";
}
