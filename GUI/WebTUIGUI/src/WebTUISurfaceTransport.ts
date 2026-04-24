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

export interface WebTUISurfaceFrame {
  version: 1;
  width: number;
  height: number;
  styles: Array<WebTUISurfaceStyle | null>;
  rows: WebTUISurfaceCell[][];
  images?: unknown[];
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
      Math.max(0, Math.floor(input.x)),
      Math.max(0, Math.floor(input.y)),
      input.button ?? "none",
      Math.round(input.deltaX ?? 0),
      Math.round(input.deltaY ?? 0),
      Math.max(0, Math.round(input.modifiers ?? 0)),
    ].join(":") + "\n"
  );
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
    && Array.isArray(frame.rows);
}
