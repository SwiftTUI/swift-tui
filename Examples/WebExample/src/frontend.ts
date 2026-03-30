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
    <main>
      <div class="tabs" data-scenes></div>
      <p data-status>Booting WebExampleApp…</p>
      <p>Drag the lower-right corner of the terminal box to resize it.</p>
      <div class="terminal-frame">
        <div class="terminal-host" data-terminal-host></div>
      </div>
    </main>
  `;

  const status = root.querySelector<HTMLElement>("[data-status]");
  const scenes = root.querySelector<HTMLElement>("[data-scenes]");
  const terminalHost = root.querySelector<HTMLElement>("[data-terminal-host]");

  if (!status || !scenes || !terminalHost) {
    throw new Error("failed to mount WebExample");
  }

  const { controller, manifestSource } = await createController(terminalHost);
  const defaultScene = controller.scenes.find((scene) => scene.isDefault)?.id ?? controller.selectedSceneId;
  await controller.switchScene(defaultScene);
  renderSceneButtons(controller, scenes, status, manifestSource);
  status.textContent = controller.scenes.length > 0
    ? `Loaded ${controller.scenes.length} scene${controller.scenes.length === 1 ? "" : "s"} from ${manifestSource}.`
    : "Loaded terminal host.";
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
  manifestSource: string
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
      const label = scene.title ?? scene.id;
      status.textContent = `Loaded ${label} from ${manifestSource}.`;
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
