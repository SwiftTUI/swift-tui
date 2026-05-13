// frontend.ts
//
// The minimal embedding example: mounts a SwiftTUI WASI build into a
// browser canvas using the WebHost host, with a scene picker.
//
// This file is the reference for "how do I embed a SwiftTUI app in the browser?".
//
// Boot order:
//   1. mount WebHost against ../TerminalApp/dist/{scene-manifest.json, app.wasm}.
//   2. render the scene picker around a viewport-sized canvas.
//
// Cross-origin isolation (required for SharedArrayBuffer-backed stdin) is
// expected to come from the host's HTTP headers — see ../README.md and the
// COOP/COEP headers set by built-app-server.ts and the deploy host.

import {
  createWebHostApp,
  type WebHostAppController,
} from "webhost";
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
const backtabSequence = new TextEncoder().encode("[Z");

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
      class: "example-shell example-shell--error",
      children: [
        el("main", {
          class: "example-error",
          children: [
            el("p", { class: "example-eyebrow", text: "Startup error" }),
            el("h1", { text: "Could not boot the embedded SwiftTUI app." }),
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

  const shell = el("div", {
    class: "example-shell",
    children: [
      el("main", {
        class: "example-main",
        children: [
          el("div", {
            class: "terminal-shell",
            children: [
              el("div", {
                class: "terminal-topline",
                children: [
                  el("div", {
                    class: "terminal-topline-copy",
                    children: [
                      el("span", { class: "terminal-label", text: "Conway's Game of Life" }),
                      el("span", {
                        class: "terminal-caption",
                        text: "A SwiftTUI app. Running in the Platforms/Web host.",
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
            ],
          }),
        ],
      }),
    ],
  });
  root.append(shell);

  const sceneSizes = new Map<string, string>();
  const sceneRuntimes = new Map<string, WasmSceneRuntimeHandle>();
  let controller: WebHostAppController | undefined;
  const updateHostMetadata = () => {
    if (!controller) return;
    const activeScene = controller.scenes.find(
      (scene) => scene.id === controller?.selectedSceneId,
    );
    const activeLabel = activeScene?.title ?? activeScene?.id ?? controller.selectedSceneId;
    const sizeLabel = sceneSizes.get(controller.selectedSceneId);
    terminalHost.dataset.sceneId = controller.selectedSceneId;
    terminalHost.dataset.sceneTitle = activeLabel;
    terminalHost.dataset.size = sizeLabel ?? "";
  };

  controller = await createController(
    terminalHost,
    (event) => {
      sceneSizes.set(event.sceneId, `${event.columns}x${event.rows}`);
      updateHostMetadata();
    },
    (runtime) => {
      sceneRuntimes.set(runtime.descriptor.id, runtime);
    },
  );
  installShiftTabPassthrough(terminalHost, () => controller, sceneRuntimes);
  const defaultScene =
    controller.scenes.find((scene) => scene.isDefault)?.id ?? controller.selectedSceneId;
  await controller.switchScene(defaultScene);
  renderSceneButtons(controller, scenes, () => {
    updateHostMetadata();
  });
  updateHostMetadata();
}

// ---------------------------------------------------------------------------
// Controller wiring

async function createController(
  mount: HTMLElement,
  onSceneResize: (event: WasmSceneResizeEvent) => void,
  onRuntimeCreated: (runtime: WasmSceneRuntimeHandle) => void,
): Promise<WebHostAppController> {
  try {
    return await createWebHostApp({
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
    });
  } catch (error) {
    // eslint-disable-next-line no-console
    console.warn("Falling back to the local preview manifest:", error);
    return await createWebHostApp({
      mount,
      manifest: fallbackManifest,
      style: defaultStyle,
      initialSceneId: fallbackManifest.defaultSceneId,
    });
  }
}

function installShiftTabPassthrough(
  terminalHost: HTMLElement,
  getController: () => WebHostAppController | undefined,
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
  controller: WebHostAppController,
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
  controller: WebHostAppController,
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
