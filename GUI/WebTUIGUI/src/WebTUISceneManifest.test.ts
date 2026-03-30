import { expect, test } from "bun:test";

import {
  normalizeWebTUISceneManifest,
  webTUISceneManifestToJSON,
} from "./WebTUISceneManifest.ts";

test("scene manifests preserve declaration order and default scene", () => {
  const manifest = normalizeWebTUISceneManifest([
    { id: "dashboard", title: "Dashboard", isDefault: true },
    { id: "controls", title: "Controls", isDefault: false },
  ]);

  expect(manifest.defaultSceneId).toBe("dashboard");
  expect(manifest.scenes.map((scene) => scene.id)).toEqual([
    "dashboard",
    "controls",
  ]);
  expect(webTUISceneManifestToJSON(manifest)).toBe(
    JSON.stringify({
      defaultSceneId: "dashboard",
      scenes: [
        { id: "dashboard", title: "Dashboard", isDefault: true },
        { id: "controls", title: "Controls", isDefault: false },
      ],
    })
  );
});

test("scene manifests infer a default scene when one is not marked", () => {
  const manifest = normalizeWebTUISceneManifest([
    { id: "primary", title: "Primary", isDefault: false },
    { id: "secondary", title: "Secondary", isDefault: false },
  ]);

  expect(manifest.defaultSceneId).toBe("primary");
  expect(manifest.scenes[0]?.isDefault).toBe(true);
});
