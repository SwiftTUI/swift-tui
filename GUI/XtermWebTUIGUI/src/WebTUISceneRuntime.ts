import {
  FitAddon,
  Terminal,
  init,
  type ITerminalOptions,
} from "./vendor/xterm.ts";
import {
  applyWebTUITerminalStyle,
  normalizeWebTUITerminalStyle,
  xtermThemeForStyle,
  type ResolvedWebTUITerminalStyle,
  type WebTUITerminalStyle,
} from "./WebTUITerminalStyle.ts";
import { BrowserWASIBridge, encodeResizeControlMessage } from "./wasi/BrowserWASIBridge.ts";
import type { WebTUISceneDescriptor } from "./WebTUISceneManifest.ts";

export interface WebTUISceneRuntimeOptions {
  mount: HTMLElement;
  descriptor: WebTUISceneDescriptor;
  style: WebTUITerminalStyle;
  bridge?: BrowserWASIBridge;
  onInput(chunk: Uint8Array): void;
}

export class WebTUISceneRuntime {
  readonly descriptor: WebTUISceneDescriptor;
  readonly element: HTMLElement;
  readonly terminalMount: HTMLElement;

  private terminal?: Terminal;
  private fitAddon?: FitAddon;
  private resizeObserver?: ResizeObserver;
  private readonly bridge?: BrowserWASIBridge;
  private readonly onInput: (chunk: Uint8Array) => void;
  private currentStyle: ResolvedWebTUITerminalStyle;
  private readonly inputEncoder = new TextEncoder();
  private isVisible = false;

  constructor(options: WebTUISceneRuntimeOptions) {
    this.descriptor = options.descriptor;
    this.currentStyle = normalizeWebTUITerminalStyle(options.style);
    this.bridge = options.bridge;
    this.onInput = options.onInput;
    this.element = document.createElement("section");
    this.element.className = "webtuigui-scene";
    this.element.dataset.sceneId = options.descriptor.id;
    this.element.hidden = true;

    const header = document.createElement("div");
    header.className = "webtuigui-scene__header";
    header.textContent = options.descriptor.title ?? options.descriptor.id;

    this.terminalMount = document.createElement("div");
    this.terminalMount.className = "webtuigui-scene__terminal";

    this.element.append(header, this.terminalMount);
    options.mount.appendChild(this.element);
    this.applyVisibility();
  }

  async mount(): Promise<void> {
    if (this.terminal) {
      return;
    }

    await init();

    const terminal = new Terminal(this.terminalOptionsForStyle(this.currentStyle));
    const fitAddon = new FitAddon();
    terminal.loadAddon(fitAddon);

    terminal.onData((data) => {
      this.onInput(this.inputEncoder.encode(data));
    });

    terminal.onResize((size) => {
      if (this.bridge) {
        this.bridge.resize(size.cols, size.rows);
      } else {
        this.onInput(encodeResizeControlMessage(size.cols, size.rows));
      }
    });

    this.bridge?.bindOutput({
      writeOutput: (text) => terminal.write(text),
      writeError: (text) => terminal.write(text),
      resize: (columns, rows) => {
        terminal.resize(columns, rows);
      },
    });

    terminal.open(this.terminalMount);

    this.terminal = terminal;
    this.fitAddon = fitAddon;
    this.applyStyle(this.currentStyle);
    this.observeResize();
    this.fitToContainer();
  }

  setVisible(
    visible: boolean
  ): void {
    this.isVisible = visible;
    this.applyVisibility();
    if (visible) {
      this.fitToContainer();
      this.terminal?.focus();
    }
  }

  setStyle(
    style: WebTUITerminalStyle
  ): void {
    this.currentStyle = normalizeWebTUITerminalStyle(style);
    const terminalOptions = this.terminal?.options;
    if (terminalOptions) {
      terminalOptions.fontSize = this.currentStyle.fontSize;
      terminalOptions.fontFamily = this.currentStyle.fontFamily;
      terminalOptions.cursorBlink = this.currentStyle.cursorBlink;
      terminalOptions.cursorStyle = this.currentStyle.cursorStyle;
      terminalOptions.theme = xtermThemeForStyle(this.currentStyle);
    }
    this.applyStyle(this.currentStyle);
    this.bridge?.updateRenderStyle(this.currentStyle);
    this.fitToContainer();
  }

  resize(
    columns: number,
    rows: number
  ): void {
    this.terminal?.resize(columns, rows);
  }

  writeOutput(
    text: string
  ): void {
    this.terminal?.write(text);
  }

  sendInput(
    chunk: Uint8Array
  ): void {
    this.onInput(chunk);
  }

  dispose(): void {
    this.resizeObserver?.disconnect();
    this.resizeObserver = undefined;
    this.fitAddon?.dispose();
    this.fitAddon = undefined;
    this.terminal?.dispose();
    this.terminal = undefined;
    this.element.remove();
  }

  private terminalOptionsForStyle(
    style: WebTUITerminalStyle
  ): ITerminalOptions {
    const normalized = normalizeWebTUITerminalStyle(style);
    return {
      cursorBlink: normalized.cursorBlink,
      cursorStyle: normalized.cursorStyle,
      fontFamily: normalized.fontFamily,
      fontSize: normalized.fontSize,
      theme: xtermThemeForStyle(normalized),
      allowTransparency: normalized.backgroundOpacity < 1,
    };
  }

  private applyStyle(
    style: WebTUITerminalStyle
  ): void {
    applyWebTUITerminalStyle(this.element, style);
    this.element.style.padding = "0.75rem";
    this.element.style.borderRadius = "16px";
    this.element.style.boxShadow = "0 20px 50px rgba(0, 0, 0, 0.28)";
    this.element.style.overflow = "hidden";
    this.element.style.gap = "0.5rem";
    this.element.style.gridTemplateRows = "auto 1fr";
  }

  private applyVisibility(): void {
    this.element.hidden = !this.isVisible;
    this.element.style.setProperty(
      "display",
      this.isVisible ? "grid" : "none",
      "important"
    );
  }

  private observeResize(): void {
    this.resizeObserver?.disconnect();
    if (typeof ResizeObserver === "undefined") {
      return;
    }

    this.resizeObserver = new ResizeObserver(() => {
      this.fitToContainer();
    });
    this.resizeObserver.observe(this.terminalMount);
  }

  private fitToContainer(): void {
    if (!this.isVisible) {
      return;
    }
    this.fitAddon?.fit();
  }
}
