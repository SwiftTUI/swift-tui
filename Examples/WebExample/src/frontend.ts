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
import { createWasmSceneRuntimeFactory } from "./scene-runtime.ts";

const terminalAppManifestUrl = new URL(terminalAppManifestPath, location.href);
const terminalAppWasmUrl = new URL(terminalAppWasmPath, location.href);

await bootstrap();

async function bootstrap(): Promise<void> {
  const root = document.querySelector<HTMLDivElement>("#root");
  if (!root) {
    throw new Error("missing root element");
  }

  root.innerHTML = `
    <main class="app-shell">
      <section class="hero">
        <div class="hero__copy">
          <p class="eyebrow">WebExample</p>
          <h1>TerminalUI in the browser</h1>
          <p class="lede">
            This Bun app builds a tiny Swift <code>TerminalUI</code> executable,
            generates a scene manifest plus <code>app.wasm</code>, and mounts it
            through <code>WebTUIGUI</code>.
          </p>
        </div>
        <div class="hero__status">
          <span class="status-pill" data-status>Booting WebExampleApp…</span>
        </div>
      </section>

      <section class="layout">
        <aside class="panel panel--controls">
          <div class="panel__header">
            <h2>Scenes</h2>
            <p>Each scene is rendered from the Swift manifest emitted by TerminalApp.</p>
          </div>
          <div class="scene-list" data-scenes></div>

          <div class="panel__header panel__header--spaced">
            <h2>Style</h2>
            <p>These controls update the active WebTUIGUI terminal in place.</p>
          </div>
          <label class="field">
            <span>Font size</span>
            <input data-font-size type="range" min="12" max="22" step="1" />
          </label>
          <label class="field field--inline">
            <span>Cursor blink</span>
            <input data-cursor-blink type="checkbox" />
          </label>
          <label class="field">
            <span>Background opacity</span>
            <input data-opacity type="range" min="0.35" max="1" step="0.01" />
          </label>
        </aside>

        <section class="panel panel--terminal">
          <div class="panel__header">
            <h2>Terminal</h2>
            <p data-terminal-note>The embedded TerminalUI program mounts below.</p>
          </div>
          <div class="terminal-host" data-terminal-host></div>
        </section>
      </section>
    </main>
  `;

  const status = root.querySelector<HTMLElement>("[data-status]");
  const scenes = root.querySelector<HTMLElement>("[data-scenes]");
  const terminalHost = root.querySelector<HTMLElement>("[data-terminal-host]");
  const terminalNote = root.querySelector<HTMLElement>("[data-terminal-note]");
  const fontSizeInput = root.querySelector<HTMLInputElement>("[data-font-size]");
  const cursorBlinkInput = root.querySelector<HTMLInputElement>("[data-cursor-blink]");
  const opacityInput = root.querySelector<HTMLInputElement>("[data-opacity]");

  if (!status || !scenes || !terminalHost || !terminalNote || !fontSizeInput || !cursorBlinkInput || !opacityInput) {
    throw new Error("failed to mount WebExample controls");
  }

  const { controller, manifestSource } = await createController(terminalHost);
  renderSceneButtons(controller, scenes, status, terminalNote);
  bindStyleControls(controller, fontSizeInput, cursorBlinkInput, opacityInput);

  const defaultScene = controller.scenes.find((scene) => scene.isDefault)?.id ?? controller.selectedSceneId;
  await controller.switchScene(defaultScene);
  updateSceneSelection(controller, scenes);
  status.textContent = controller.scenes.length > 0
    ? `Loaded ${controller.scenes.length} scene${controller.scenes.length === 1 ? "" : "s"} from ${manifestSource}.`
    : "Loaded terminal host.";
  terminalNote.textContent = `Active scene: ${controller.selectedSceneId}`;
}

async function createController(
  mount: HTMLElement
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
        sceneRuntimeFactory: createWasmSceneRuntimeFactory(terminalAppWasmUrl),
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
  status: HTMLElement,
  terminalNote: HTMLElement
): void {
  container.replaceChildren();

  for (const scene of controller.scenes) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "scene-button";
    button.dataset.sceneId = scene.id;
    button.textContent = scene.title ?? scene.id;
    button.addEventListener("click", async () => {
      await controller.switchScene(scene.id);
      updateSceneSelection(controller, container);
      const label = scene.title ?? scene.id;
      status.textContent = `Switched to ${label}.`;
      terminalNote.textContent = `Active scene: ${label}`;
    });
    container.append(button);
  }

  updateSceneSelection(controller, container);
}

function updateSceneSelection(
  controller: WebTUIAppController,
  container: HTMLElement
): void {
  for (const button of container.querySelectorAll<HTMLButtonElement>(".scene-button")) {
    button.dataset.active = String(button.dataset.sceneId === controller.selectedSceneId);
  }
}

function bindStyleControls(
  controller: WebTUIAppController,
  fontSizeInput: HTMLInputElement,
  cursorBlinkInput: HTMLInputElement,
  opacityInput: HTMLInputElement
): void {
  fontSizeInput.value = String(defaultStyle.fontSize ?? 15);
  cursorBlinkInput.checked = Boolean(defaultStyle.cursorBlink);
  opacityInput.value = String(defaultStyle.backgroundOpacity ?? 1);

  const updateStyle = () => {
    controller.setStyle({
      fontSize: Number(fontSizeInput.value),
      cursorBlink: cursorBlinkInput.checked,
      backgroundOpacity: Number(opacityInput.value),
    });
  };

  fontSizeInput.addEventListener("input", updateStyle);
  cursorBlinkInput.addEventListener("change", updateStyle);
  opacityInput.addEventListener("input", updateStyle);
}
