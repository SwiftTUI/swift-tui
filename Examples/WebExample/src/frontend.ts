import {
  createWebTUIApp,
  type WebTUIAppController,
} from "../../../GUI/WebTUIGUI/src/WebTUIApp.ts";
import "./index.css";
import {
  defaultStyle,
  fallbackManifest,
  terminalAppManifestPath,
  terminalAppWasmPath,
} from "./app-data.ts";
import {
  createWasmSceneRuntimeFactory,
  type WasmSceneResizeEvent,
} from "./scene-runtime.ts";

const terminalAppManifestUrl = new URL(terminalAppManifestPath, location.href);
const terminalAppWasmUrl = new URL(terminalAppWasmPath, location.href);
const minimumFrameWidth = 320;
const minimumFrameHeight = 240;

await bootstrap();

async function bootstrap(): Promise<void> {
  const root = document.querySelector<HTMLDivElement>("#root");
  if (!root) {
    throw new Error("missing root element");
  }

  root.innerHTML = `
    <main>
      <div class="tabs" data-scenes></div>
      <p data-status>Booting WebExampleApp…</p>
      <p>Drag the resize handle under the terminal to change its size.</p>
      <div class="terminal-shell">
        <div class="terminal-frame" data-terminal-frame>
          <div class="terminal-host" data-terminal-host></div>
        </div>
        <div class="terminal-resize-bar">
          <button type="button" class="terminal-resize-handle" data-resize-handle>Resize</button>
        </div>
      </div>
    </main>
  `;

  const status = root.querySelector<HTMLElement>("[data-status]");
  const scenes = root.querySelector<HTMLElement>("[data-scenes]");
  const terminalFrame = root.querySelector<HTMLElement>("[data-terminal-frame]");
  const terminalHost = root.querySelector<HTMLElement>("[data-terminal-host]");
  const resizeHandle = root.querySelector<HTMLButtonElement>("[data-resize-handle]");

  if (!status || !scenes || !terminalFrame || !terminalHost || !resizeHandle) {
    throw new Error("failed to mount WebExample");
  }

  installResizeHandle(terminalFrame, resizeHandle);

  const sceneSizes = new Map<string, string>();
  let controller: WebTUIAppController | undefined;
  let manifestSource = "";
  const renderStatus = () => {
    if (!controller) {
      return;
    }

    const activeScene = controller.scenes.find((scene) => scene.id === controller?.selectedSceneId);
    const activeLabel = activeScene?.title ?? activeScene?.id ?? controller.selectedSceneId;
    const sizeLabel = sceneSizes.get(controller.selectedSceneId);
    terminalHost.dataset.sceneId = controller.selectedSceneId;
    terminalHost.dataset.size = sizeLabel ?? "";
    status.textContent = sizeLabel
      ? `Loaded ${activeLabel} from ${manifestSource} at ${sizeLabel}.`
      : `Loaded ${activeLabel} from ${manifestSource}.`;
  };

  ({ controller, manifestSource } = await createController(terminalHost, (event) => {
    sceneSizes.set(event.sceneId, `${event.columns}x${event.rows}`);
    renderStatus();
  }));
  const defaultScene = controller.scenes.find((scene) => scene.isDefault)?.id ?? controller.selectedSceneId;
  await controller.switchScene(defaultScene);
  renderSceneButtons(controller, scenes, () => {
    renderStatus();
  });

  if (controller.scenes.length > 0) {
    renderStatus();
  } else {
    status.textContent = "Loaded terminal host.";
  }
}

async function createController(
  mount: HTMLElement,
  onSceneResize: (event: WasmSceneResizeEvent) => void
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
        }),
      }),
      manifestSource: "TerminalApp",
    };
  } catch (error) {
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

function renderSceneButtons(
  controller: WebTUIAppController,
  container: HTMLElement,
  onSelectionChanged: () => void
): void {
  container.replaceChildren();

  for (const scene of controller.scenes) {
    const button = document.createElement("button");
    button.type = "button";
    button.dataset.sceneId = scene.id;
    button.textContent = scene.title ?? scene.id;
    button.addEventListener("click", async () => {
      await controller.switchScene(scene.id);
      updateSceneSelection(controller, container);
      onSelectionChanged();
    });
    container.append(button);
  }

  updateSceneSelection(controller, container);
}

function updateSceneSelection(
  controller: WebTUIAppController,
  container: HTMLElement
): void {
  for (const button of container.querySelectorAll<HTMLButtonElement>("button")) {
    const isActive = button.dataset.sceneId === controller.selectedSceneId;
    button.disabled = isActive;
    button.setAttribute("aria-pressed", String(isActive));
  }
}

function installResizeHandle(
  frame: HTMLElement,
  handle: HTMLButtonElement
): void {
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
    if (!drag || (pointerId !== undefined && drag.pointerId !== pointerId)) {
      return;
    }

    drag = undefined;
    document.body.classList.remove("is-resizing-terminal");
  };

  const resizeToPointer = (event: PointerEvent) => {
    if (!drag || drag.pointerId !== event.pointerId) {
      return;
    }

    const width = Math.max(
      minimumFrameWidth,
      Math.round(drag.startWidth + event.clientX - drag.startX)
    );
    const height = Math.max(
      minimumFrameHeight,
      Math.round(drag.startHeight + event.clientY - drag.startY)
    );

    frame.style.width = `${width}px`;
    frame.style.height = `${height}px`;
  };

  handle.addEventListener("pointerdown", (event) => {
    if (event.button !== 0) {
      return;
    }

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
