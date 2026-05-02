// frontend.ts
//
// The minimal embedding example: mounts a TerminalUI WASI build into a
// browser canvas using the WebTUIGUI host, with a scene picker, a status
// line, and a resize handle.
//
// This file is the shipped reference for "how do I embed TerminalUI in
// a Bun-served browser app?" — it deliberately stays small.
//
// Boot order:
//   1. mount WebTUIGUI against ../TerminalApp/dist/{scene-manifest.json, app.wasm}.
//   2. render the scene picker + status + resize handle around the canvas.
//
// Cross-origin isolation (required for SharedArrayBuffer-backed stdin) is
// expected to come from the host's HTTP headers — see ../README.md and the
// COOP/COEP headers set by built-app-server.ts and the deploy host.
//
// All shell DOM is constructed via document.createElement / .append rather
// than via innerHTML. There is no untrusted-input path into this page;
// the structured DOM construction is for clarity, not sandboxing.

import {
  createWebTUIApp,
  type WebTUIAppController,
} from "webtuigui";
import "./index.css";
import {
  defaultStyle,
  fallbackManifest,
  terminalAppManifestPath,
  terminalAppWasmPath,
} from "./app-data.ts";
import {
  createWasmSceneRuntimeFactory,
  type WasmSceneRuntimeHandle,
  type WasmSceneResizeEvent,
} from "./scene-runtime.ts";

const terminalAppManifestUrl = new URL(terminalAppManifestPath, import.meta.url);
const terminalAppWasmUrl = new URL(terminalAppWasmPath, import.meta.url);
const minimumFrameWidth = 320;
const minimumFrameHeight = 240;
const backtabSequence = new TextEncoder().encode("[Z");
const readmeUrl =
  "https://github.com/GoodHatsLLC/swift-terminal-ui/blob/main/Examples/WebExample/README.md";

try {
  await bootstrap();
} catch (error: unknown) {
  renderStartupError(error);
  // eslint-disable-next-line no-console
  console.error("Failed to start WebExample:", error);
}

// ---------------------------------------------------------------------------
// Bootstrap

function rootEl(): HTMLDivElement {
  const root = document.querySelector<HTMLDivElement>("#root");
  if (!root) throw new Error("missing root element");
  return root;
}

function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  init?: {
    class?: string;
    text?: string;
    attrs?: Record<string, string>;
    dataset?: Record<string, string>;
    children?: ReadonlyArray<Node>;
  },
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  if (init?.class) node.className = init.class;
  if (init?.text !== undefined) node.textContent = init.text;
  for (const [k, v] of Object.entries(init?.attrs ?? {})) node.setAttribute(k, v);
  for (const [k, v] of Object.entries(init?.dataset ?? {})) node.dataset[k] = v;
  for (const child of init?.children ?? []) node.append(child);
  return node;
}

function renderStartupError(error: unknown): void {
  const root = document.querySelector<HTMLDivElement>("#root");
  if (!root) return;
  root.replaceChildren();

  const message = error instanceof Error ? error.message : String(error);
  const stack = error instanceof Error && error.stack ? `\n\n${error.stack}` : "";

  const codeBlock = el("pre", {
    class: "example-code-block",
    children: [el("code", { text: `${message}${stack}` })],
  });

  root.append(
    el("div", {
      class: "example-shell",
      children: [
        el("main", {
          class: "example-error",
          children: [
            el("p", { class: "example-eyebrow", text: "Startup error" }),
            el("h1", { text: "Could not boot the embedded TerminalUI app." }),
            el("p", {
              text:
                "The browser runtime did not start. The error is below; reload to retry.",
            }),
            codeBlock,
          ],
        }),
      ],
    }),
  );
}

async function bootstrap(): Promise<void> {
  const root = rootEl();
  root.replaceChildren();

  // Static shell. A host page that adopts this pattern can render whatever
  // chrome it wants around the .terminal-shell element — only the
  // .terminal-shell + its data-* hooks are load-bearing.
  const status = el("span", {
    class: "status-item",
    text: "Booting the browser demo…",
    attrs: { "aria-live": "polite" },
    dataset: { status: "true" },
  });
  const scenes = el("div", {
    class: "scene-select",
    attrs: { "aria-label": "Scene selector" },
    dataset: { scenes: "true" },
  });
  const terminalHost = el("div", {
    class: "terminal-host",
    dataset: { terminalHost: "true" },
  });
  const terminalFrame = el("div", {
    class: "terminal-frame",
    dataset: { terminalFrame: "true" },
    children: [terminalHost],
  });
  const resizeHandle = el("button", {
    class: "terminal-resize-handle",
    attrs: {
      type: "button",
      "aria-label": "Resize terminal demo",
      title: "Resize terminal demo",
    },
    dataset: { resizeHandle: "true" },
  });

  const readmeLink = el("a", {
    text: "README",
    attrs: {
      href: readmeUrl,
      target: "_blank",
      rel: "noreferrer",
    },
  });

  const lede = el("p", { class: "example-lede" });
  lede.append(
    document.createTextNode(
      "The component gallery below is a real TerminalUI ",
    ),
    el("code", { text: "App" }),
    document.createTextNode(
      " built for WASI and mounted onto a canvas via the ",
    ),
    el("code", { text: "WebTUIGUI" }),
    document.createTextNode(
      " host. There is no terminal-emulator dependency — the browser draws raster surface output directly. See the ",
    ),
    readmeLink,
    document.createTextNode(" for the embedding pattern."),
  );

  const shell = el("div", {
    class: "example-shell",
    children: [
      el("main", {
        class: "example-main",
        children: [
          el("header", {
            class: "example-header",
            children: [
              el("p", {
                class: "example-eyebrow",
                text: "TerminalUI · WebTUIGUI embedding example",
              }),
              el("h1", { text: "The same authored app, rendered in the browser." }),
              lede,
            ],
          }),
          el("div", {
            class: "terminal-shell",
            children: [
              el("div", {
                class: "terminal-topline",
                children: [
                  el("div", {
                    class: "terminal-topline-copy",
                    children: [
                      el("span", { class: "terminal-label", text: "WebExample" }),
                      el("span", {
                        class: "terminal-caption",
                        text: "TerminalUI running through WebTUIGUI",
                      }),
                    ],
                  }),
                  scenes,
                ],
              }),
              el("div", {
                class: "terminal-frame-shell",
                children: [terminalFrame],
              }),
              el("div", {
                class: "terminal-resize-bar",
                children: [
                  el("div", {
                    class: "terminal-status",
                    children: [
                      el("span", { class: "status-label", text: "Live canvas" }),
                      status,
                    ],
                  }),
                  resizeHandle,
                ],
              }),
            ],
          }),
        ],
      }),
    ],
  });
  root.append(shell);

  installResizeHandle(terminalFrame, resizeHandle);

  const sceneSizes = new Map<string, string>();
  const sceneRuntimes = new Map<string, WasmSceneRuntimeHandle>();
  let controller: WebTUIAppController | undefined;
  let manifestSource = "";
  const renderStatus = () => {
    if (!controller) return;
    const activeScene = controller.scenes.find(
      (scene) => scene.id === controller?.selectedSceneId,
    );
    const activeLabel = activeScene?.title ?? activeScene?.id ?? controller.selectedSceneId;
    const sizeLabel = sceneSizes.get(controller.selectedSceneId);
    terminalHost.dataset.sceneId = controller.selectedSceneId;
    terminalHost.dataset.size = sizeLabel ?? "";
    status.textContent = sizeLabel
      ? `${activeLabel} · ${sizeLabel}`
      : `${activeLabel} · loaded from ${manifestSource}`;
  };

  ({
    controller,
    manifestSource,
  } = await createController(
    terminalHost,
    (event) => {
      sceneSizes.set(event.sceneId, `${event.columns}x${event.rows}`);
      renderStatus();
    },
    (runtime) => {
      sceneRuntimes.set(runtime.descriptor.id, runtime);
    },
  ));
  installShiftTabPassthrough(terminalHost, () => controller, sceneRuntimes);
  const defaultScene =
    controller.scenes.find((scene) => scene.isDefault)?.id ?? controller.selectedSceneId;
  await controller.switchScene(defaultScene);
  renderSceneButtons(controller, scenes, () => {
    renderStatus();
  });

  if (controller.scenes.length > 0) {
    renderStatus();
  } else {
    status.textContent = "Terminal host loaded.";
  }
}

// ---------------------------------------------------------------------------
// Controller wiring

async function createController(
  mount: HTMLElement,
  onSceneResize: (event: WasmSceneResizeEvent) => void,
  onRuntimeCreated: (runtime: WasmSceneRuntimeHandle) => void,
): Promise<{ controller: WebTUIAppController; manifestSource: string }> {
  try {
    return {
      controller: await createWebTUIApp({
        mount,
        manifestUrl: terminalAppManifestUrl,
        style: defaultStyle,
        initialSceneId: "main",
        environment: {
          TUIGUI_APP_NAME: "Examples/WebExample",
        },
        sceneRuntimeFactory: createWasmSceneRuntimeFactory(terminalAppWasmUrl, {
          onSceneResize,
          onRuntimeCreated,
        }),
      }),
      manifestSource: "TerminalApp",
    };
  } catch (error) {
    // eslint-disable-next-line no-console
    console.warn("Falling back to the local preview manifest:", error);
    return {
      controller: await createWebTUIApp({
        mount,
        manifest: fallbackManifest,
        style: defaultStyle,
        initialSceneId: fallbackManifest.defaultSceneId,
      }),
      manifestSource: "fallback preview",
    };
  }
}

function installShiftTabPassthrough(
  terminalHost: HTMLElement,
  getController: () => WebTUIAppController | undefined,
  sceneRuntimes: ReadonlyMap<string, WasmSceneRuntimeHandle>,
): void {
  terminalHost.addEventListener(
    "keydown",
    (event) => {
      if (
        event.key !== "Tab" ||
        !event.shiftKey ||
        event.altKey ||
        event.ctrlKey ||
        event.metaKey ||
        event.defaultPrevented
      ) {
        return;
      }

      const path = typeof event.composedPath === "function" ? event.composedPath() : [];
      const eventOriginatedInTerminal =
        path.includes(terminalHost) ||
        (event.target instanceof Node && terminalHost.contains(event.target));
      if (!eventOriginatedInTerminal) return;

      const controller = getController();
      if (!controller) return;

      const runtime = sceneRuntimes.get(controller.selectedSceneId);
      if (!runtime) return;

      event.preventDefault();
      event.stopPropagation();
      runtime.sendInput(backtabSequence);
    },
    { capture: true },
  );
}

// ---------------------------------------------------------------------------
// Scene picker

function renderSceneButtons(
  controller: WebTUIAppController,
  container: HTMLElement,
  onSelectionChanged: () => void,
): void {
  container.replaceChildren();
  if (controller.scenes.length === 0) return;

  const activeLabel = () => {
    const active = controller.scenes.find((s) => s.id === controller.selectedSceneId);
    return active?.title ?? active?.id ?? controller.selectedSceneId;
  };

  const sceneValueSpan = el("span", {
    text: activeLabel(),
    dataset: { sceneValue: "true" },
  });
  const trigger = el("button", {
    class: "scene-select-trigger",
    attrs: {
      type: "button",
      "aria-haspopup": "listbox",
      "aria-expanded": "false",
    },
    children: [
      el("span", { class: "scene-select-label", text: "Scene:" }),
      document.createTextNode(" "),
      sceneValueSpan,
      document.createTextNode(" "),
      el("span", { class: "scene-select-chevron" }),
    ],
  });

  const menu = el("div", {
    class: "scene-select-menu",
    attrs: { role: "listbox" },
    dataset: { open: "false" },
  });

  for (const scene of controller.scenes) {
    const option = el("button", {
      class: "scene-select-option",
      attrs: { type: "button", role: "option" },
      dataset: { sceneId: scene.id },
      text: scene.title ?? scene.id,
    });
    option.addEventListener("click", async () => {
      await controller.switchScene(scene.id);
      updateSceneSelection(controller, container);
      onSelectionChanged();
      closeMenu();
    });
    menu.append(option);
  }

  const closeMenu = () => {
    trigger.setAttribute("aria-expanded", "false");
    menu.dataset.open = "false";
  };

  trigger.addEventListener("click", () => {
    const isOpen = trigger.getAttribute("aria-expanded") === "true";
    trigger.setAttribute("aria-expanded", String(!isOpen));
    menu.dataset.open = String(!isOpen);
  });

  document.addEventListener("click", (event) => {
    if (!container.contains(event.target as Node)) closeMenu();
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && menu.dataset.open === "true") {
      closeMenu();
      trigger.focus();
    }
  });

  container.append(trigger, menu);
  updateSceneSelection(controller, container);
}

function updateSceneSelection(
  controller: WebTUIAppController,
  container: HTMLElement,
): void {
  const valueEl = container.querySelector<HTMLElement>("[data-scene-value]");
  if (valueEl) {
    const active = controller.scenes.find((s) => s.id === controller.selectedSceneId);
    valueEl.textContent = active?.title ?? active?.id ?? controller.selectedSceneId;
  }

  for (const option of container.querySelectorAll<HTMLButtonElement>(".scene-select-option")) {
    const isActive = option.dataset.sceneId === controller.selectedSceneId;
    option.setAttribute("aria-selected", String(isActive));
  }
}

// ---------------------------------------------------------------------------
// Resize handle

function installResizeHandle(frame: HTMLElement, handle: HTMLButtonElement): void {
  let drag:
    | {
        pointerId: number;
        startX: number;
        startY: number;
        startWidth: number;
        startHeight: number;
      }
    | undefined;

  const stopDrag = (pointerId?: number) => {
    if (!drag || (pointerId !== undefined && drag.pointerId !== pointerId)) return;
    drag = undefined;
    document.body.classList.remove("is-resizing-terminal");
  };

  const resizeToPointer = (event: PointerEvent) => {
    if (!drag || drag.pointerId !== event.pointerId) return;
    const width = Math.max(
      minimumFrameWidth,
      Math.round(drag.startWidth + event.clientX - drag.startX),
    );
    const height = Math.max(
      minimumFrameHeight,
      Math.round(drag.startHeight + event.clientY - drag.startY),
    );
    frame.style.width = `${width}px`;
    frame.style.height = `${height}px`;
  };

  handle.addEventListener("pointerdown", (event) => {
    if (event.button !== 0) return;
    event.preventDefault();
    const rect = frame.getBoundingClientRect();
    drag = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      startWidth: rect.width,
      startHeight: rect.height,
    };
    document.body.classList.add("is-resizing-terminal");
    handle.setPointerCapture(event.pointerId);
  });

  handle.addEventListener("pointermove", resizeToPointer);
  handle.addEventListener("pointerup", (event) => {
    resizeToPointer(event);
    stopDrag(event.pointerId);
  });
  handle.addEventListener("pointercancel", (event) => {
    stopDrag(event.pointerId);
  });
  window.addEventListener("blur", () => {
    stopDrag();
  });
}
