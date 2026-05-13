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

export type WebHostAccessibilityPoint = [
  x: number,
  y: number,
];

export type WebHostAccessibilityLiveRegion = "off" | "polite" | "assertive";

export interface WebHostAccessibilityNode {
  id: string;
  parentId?: string;
  rect: WebHostSurfaceRect;
  role: string;
  label?: string;
  hint?: string;
  liveRegion?: WebHostAccessibilityLiveRegion;
  cursorAnchor?: WebHostAccessibilityPoint;
  isFocused?: boolean;
}

export interface WebHostAccessibilityAnnouncement {
  message: string;
  politeness: WebHostAccessibilityLiveRegion;
}

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

export type WebHostSurfaceDamageRange = [
  start: number,
  end: number,
];

export type WebHostSurfaceDamageTextRow = [
  row: number,
  ranges: WebHostSurfaceDamageRange[],
];

export interface WebHostSurfaceDamage {
  textRows: WebHostSurfaceDamageTextRow[];
  requiresFullTextRepaint: boolean;
  requiresFullGraphicsReplay: boolean;
}

export interface WebHostSurfaceFrame {
  version: 1 | 2;
  width: number;
  height: number;
  styles: Array<WebHostSurfaceStyle | null>;
  rows: WebHostSurfaceCell[][];
  images?: WebHostSurfaceImage[];
  damage?: WebHostSurfaceDamage;
  accessibilityTree?: WebHostAccessibilityNode[];
  accessibilityAnnouncements?: WebHostAccessibilityAnnouncement[];
}

export interface WebHostRuntimeIssue {
  severity: "warning" | "error";
  code: string;
  message: string;
  description: string;
  identity?: string;
  source?: string;
}

export type WebHostOutputRecord =
  | { type: "surface"; frame: WebHostSurfaceFrame }
  | { type: "clipboard"; text: string }
  | { type: "runtimeIssue"; issue: WebHostRuntimeIssue }
  | { type: "text"; text: string };

export interface WebHostOutputSink {
  presentSurface(frame: WebHostSurfaceFrame): void;
  writeClipboard?(text: string): void | Promise<void>;
  notifyRuntimeIssue?(issue: WebHostRuntimeIssue): void;
  writeOutput?(text: string): void;
  writeError?(text: string): void;
}

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
    if (line.startsWith(`${recordPrefix}clipboard:`)) {
      try {
        const record = JSON.parse(line.slice(`${recordPrefix}clipboard:`.length));
        if (isWebHostClipboardRecord(record)) {
          return { type: "clipboard", text: record.text };
        }
      } catch {
        // Fall through to the text path below so malformed output remains visible.
      }

      return { type: "text", text: `${line}\n` };
    }

    if (line.startsWith(`${recordPrefix}runtimeIssue:`)) {
      try {
        const record = JSON.parse(line.slice(`${recordPrefix}runtimeIssue:`.length));
        if (isWebHostRuntimeIssue(record)) {
          return { type: "runtimeIssue", issue: record };
        }
      } catch {
        // Fall through to the text path below so malformed output remains visible.
      }

      return { type: "text", text: `${line}\n` };
    }

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

function isWebHostClipboardRecord(
  value: unknown
): value is { text: string } {
  return !!value && typeof value === "object" && typeof (value as { text?: unknown }).text === "string";
}

function isWebHostRuntimeIssue(
  value: unknown
): value is WebHostRuntimeIssue {
  if (!value || typeof value !== "object") {
    return false;
  }
  const record = value as Partial<WebHostRuntimeIssue>;
  return (record.severity === "warning" || record.severity === "error")
    && typeof record.code === "string"
    && typeof record.message === "string"
    && typeof record.description === "string"
    && (record.identity === undefined || typeof record.identity === "string")
    && (record.source === undefined || typeof record.source === "string");
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
  return (frame.version === 1 || frame.version === 2)
    && typeof frame.width === "number"
    && typeof frame.height === "number"
    && Array.isArray(frame.styles)
    && Array.isArray(frame.rows)
    && (frame.images === undefined || isWebHostSurfaceImages(frame.images))
    && (frame.damage === undefined || isWebHostSurfaceDamage(frame.damage))
    && (
      frame.accessibilityTree === undefined
        || isWebHostAccessibilityNodes(frame.accessibilityTree)
    )
    && (
      frame.accessibilityAnnouncements === undefined
        || isWebHostAccessibilityAnnouncements(frame.accessibilityAnnouncements)
    );
}

function isWebHostAccessibilityNodes(
  value: unknown
): value is WebHostAccessibilityNode[] {
  return Array.isArray(value) && value.every(isWebHostAccessibilityNode);
}

function isWebHostAccessibilityNode(
  value: unknown
): value is WebHostAccessibilityNode {
  if (!value || typeof value !== "object") {
    return false;
  }
  const node = value as Partial<WebHostAccessibilityNode>;
  return typeof node.id === "string"
    && (node.parentId === undefined || typeof node.parentId === "string")
    && isWebHostSurfaceRect(node.rect)
    && typeof node.role === "string"
    && (node.label === undefined || typeof node.label === "string")
    && (node.hint === undefined || typeof node.hint === "string")
    && (
      node.liveRegion === undefined
        || node.liveRegion === "off"
        || node.liveRegion === "polite"
        || node.liveRegion === "assertive"
    )
    && (node.cursorAnchor === undefined || isWebHostAccessibilityPoint(node.cursorAnchor))
    && (node.isFocused === undefined || typeof node.isFocused === "boolean");
}

function isWebHostAccessibilityPoint(
  value: unknown
): value is WebHostAccessibilityPoint {
  return Array.isArray(value)
    && value.length === 2
    && value.every((entry) => typeof entry === "number");
}

function isWebHostAccessibilityAnnouncements(
  value: unknown
): value is WebHostAccessibilityAnnouncement[] {
  return Array.isArray(value) && value.every(isWebHostAccessibilityAnnouncement);
}

function isWebHostAccessibilityAnnouncement(
  value: unknown
): value is WebHostAccessibilityAnnouncement {
  if (!value || typeof value !== "object") {
    return false;
  }
  const announcement = value as Partial<WebHostAccessibilityAnnouncement>;
  return typeof announcement.message === "string"
    && (
      announcement.politeness === "off"
        || announcement.politeness === "polite"
        || announcement.politeness === "assertive"
    );
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

function isWebHostSurfaceDamage(
  value: unknown
): value is WebHostSurfaceDamage {
  if (!value || typeof value !== "object") {
    return false;
  }
  const damage = value as Partial<WebHostSurfaceDamage>;
  return Array.isArray(damage.textRows)
    && damage.textRows.every(isWebHostSurfaceDamageTextRow)
    && typeof damage.requiresFullTextRepaint === "boolean"
    && typeof damage.requiresFullGraphicsReplay === "boolean";
}

function isWebHostSurfaceDamageTextRow(
  value: unknown
): value is WebHostSurfaceDamageTextRow {
  return Array.isArray(value)
    && value.length === 2
    && typeof value[0] === "number"
    && Array.isArray(value[1])
    && value[1].every(isWebHostSurfaceDamageRange);
}

function isWebHostSurfaceDamageRange(
  value: unknown
): value is WebHostSurfaceDamageRange {
  return Array.isArray(value)
    && value.length === 2
    && typeof value[0] === "number"
    && typeof value[1] === "number";
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
