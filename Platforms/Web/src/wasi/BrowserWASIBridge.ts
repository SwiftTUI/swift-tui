import { StdIOPipe } from "./StdIOPipe.ts";
import {
  encodeWebHostTerminalRenderStyleBase64,
  type WebHostTerminalStyle,
} from "../WebHostTerminalStyle.ts";
import {
  WebHostOutputDecoder,
  encodeRenderStyleControlMessage,
  encodeResizeControlMessage,
  type WebHostSurfaceFrame,
} from "../WebHostSurfaceTransport.ts";

export interface BrowserWASIBridgeOptions {
  sceneId: string;
  columns: number;
  rows: number;
  environment?: Record<string, string>;
  renderStyle?: WebHostTerminalStyle;
}

export interface BrowserWASIOutputSink {
  presentSurface(frame: WebHostSurfaceFrame): void;
  writeOutput?(text: string): void;
  writeError?(text: string): void;
}

export class BrowserWASIBridge {
  readonly stdin = new StdIOPipe();
  readonly stdout = new StdIOPipe();
  readonly stderr = new StdIOPipe();
  readonly environment: Record<string, string>;

  private detachStdout?: () => void;
  private detachStderr?: () => void;
  private readonly resizeListeners = new Set<(
    columns: number,
    rows: number,
    cellWidth?: number,
    cellHeight?: number
  ) => void>();
  private latestResize: {
    columns: number;
    rows: number;
    cellWidth?: number;
    cellHeight?: number;
  };

  constructor(options: BrowserWASIBridgeOptions) {
    this.environment = {
      TUIGUI_MODE: "browser",
      TUIGUI_TRANSPORT: "surface",
      TUIGUI_SCENE: options.sceneId,
      TUIGUI_COLUMNS: String(Math.max(1, options.columns)),
      TUIGUI_ROWS: String(Math.max(1, options.rows)),
      ...options.environment,
      ...(options.renderStyle
        ? {
            TUIGUI_RENDER_STYLE: encodeWebHostTerminalRenderStyleBase64(
              options.renderStyle
            ),
          }
        : {}),
    };
    this.latestResize = {
      columns: Math.max(1, options.columns),
      rows: Math.max(1, options.rows),
    };
  }

  bindOutput(
    sink: BrowserWASIOutputSink
  ): void {
    this.detachStdout?.();
    this.detachStderr?.();
    const decoder = new WebHostOutputDecoder();
    this.detachStdout = this.stdout.subscribe((chunk) => {
      for (const record of decoder.feed(chunk)) {
        switch (record.type) {
        case "surface":
          sink.presentSurface(record.frame);
          break;
        case "text":
          sink.writeOutput?.(record.text);
          break;
        }
      }
    });
    this.detachStderr = this.stderr.subscribe((chunk) => {
      sink.writeError?.(new TextDecoder().decode(chunk));
    });
  }

  resize(
    columns: number,
    rows: number,
    cellWidth?: number,
    cellHeight?: number
  ): void {
    const normalizedColumns = Math.max(1, columns);
    const normalizedRows = Math.max(1, rows);
    this.environment.TUIGUI_COLUMNS = String(normalizedColumns);
    this.environment.TUIGUI_ROWS = String(normalizedRows);
    this.latestResize = {
      columns: normalizedColumns,
      rows: normalizedRows,
      cellWidth,
      cellHeight,
    };
    this.stdin.write(encodeResizeControlMessage(columns, rows, cellWidth, cellHeight));
    for (const listener of this.resizeListeners) {
      listener(normalizedColumns, normalizedRows, cellWidth, cellHeight);
    }
  }

  updateRenderStyle(
    style: WebHostTerminalStyle
  ): void {
    this.environment.TUIGUI_RENDER_STYLE = encodeWebHostTerminalRenderStyleBase64(style);
    this.stdin.write(encodeRenderStyleControlMessage(style));
  }

  sendInput(
    chunk: Uint8Array
  ): void {
    this.stdin.write(chunk);
  }

  subscribeResize(
    listener: (
      columns: number,
      rows: number,
      cellWidth?: number,
      cellHeight?: number
    ) => void
  ): () => void {
    this.resizeListeners.add(listener);
    listener(
      this.latestResize.columns,
      this.latestResize.rows,
      this.latestResize.cellWidth,
      this.latestResize.cellHeight
    );
    return () => {
      this.resizeListeners.delete(listener);
    };
  }

  dispose(): void {
    this.detachStdout?.();
    this.detachStderr?.();
    this.resizeListeners.clear();
    this.stdin.close();
    this.stdout.close();
    this.stderr.close();
  }
}

export {
  encodeRenderStyleControlMessage,
  encodeResizeControlMessage,
};
