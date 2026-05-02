export interface WebHostSceneDescriptor {
  id: string;
  title?: string;
  isDefault: boolean;
}

export interface WebHostSceneManifest {
  defaultSceneId: string;
  scenes: WebHostSceneDescriptor[];
}

export type WebHostSceneManifestSource =
  | WebHostSceneManifest
  | WebHostSceneDescriptor[]
  | string
  | URL
  | Request
  | Response;

export function normalizeWebHostSceneManifest(
  source: unknown
): WebHostSceneManifest {
  const scenes = normalizeSceneDescriptors(source);
  if (scenes.length === 0) {
    throw new Error("scene manifest must contain at least one scene");
  }

  const defaultScene = scenes.find((scene) => scene.isDefault) ?? scenes[0];
  return {
    defaultSceneId: defaultScene.id,
    scenes: scenes.map((scene, index) => ({
      ...scene,
      isDefault: scene.id === defaultScene.id || (index === 0 && !scenes.some((entry) => entry.isDefault)),
    })),
  };
}

export function webTUISceneManifestToJSON(
  manifest: WebHostSceneManifest
): string {
  return JSON.stringify({
    defaultSceneId: manifest.defaultSceneId,
    scenes: manifest.scenes.map((scene) => ({
      id: scene.id,
      ...(scene.title ? { title: scene.title } : {}),
      isDefault: scene.isDefault,
    })),
  });
}

export function webTUISceneManifestFromDescriptors(
  descriptors: WebHostSceneDescriptor[]
): WebHostSceneManifest {
  return normalizeWebHostSceneManifest(descriptors);
}

export async function loadWebHostSceneManifest(
  source: WebHostSceneManifestSource
): Promise<WebHostSceneManifest> {
  if (Array.isArray(source) || isSceneManifest(source)) {
    return normalizeWebHostSceneManifest(source);
  }

  if (source instanceof URL) {
    return loadWebHostSceneManifestFromResponse(await fetch(source));
  }

  if (source instanceof Request) {
    return loadWebHostSceneManifestFromResponse(await fetch(source));
  }

  if (source instanceof Response) {
    return loadWebHostSceneManifestFromResponse(source);
  }

  if (typeof source === "string") {
    const trimmed = source.trim();
    if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
      return normalizeWebHostSceneManifest(JSON.parse(trimmed));
    }

    return loadWebHostSceneManifest(new URL(source, import.meta.url));
  }

  return normalizeWebHostSceneManifest(source);
}

function normalizeSceneDescriptors(
  source: unknown
): WebHostSceneDescriptor[] {
  if (Array.isArray(source)) {
    return source.map(normalizeDescriptor);
  }

  if (isSceneManifest(source)) {
    return source.scenes.map(normalizeDescriptor);
  }

  if (isObject(source) && Array.isArray((source as { scenes?: unknown }).scenes)) {
    return ((source as { scenes: unknown[] }).scenes ?? []).map(normalizeDescriptor);
  }

  throw new Error("scene manifest must be an array or an object with scenes");
}

function normalizeDescriptor(
  value: unknown,
  index?: number
): WebHostSceneDescriptor {
  if (!isObject(value)) {
    throw new Error(`scene descriptor at index ${index ?? 0} must be an object`);
  }

  const id = String((value as { id?: unknown }).id ?? "").trim();
  if (!id) {
    throw new Error(`scene descriptor at index ${index ?? 0} is missing an id`);
  }

  const titleValue = (value as { title?: unknown }).title;
  const isDefaultValue = Boolean((value as { isDefault?: unknown }).isDefault);

  return {
    id,
    title:
      typeof titleValue === "string" && titleValue.trim().length > 0
        ? titleValue.trim()
        : undefined,
    isDefault: isDefaultValue,
  };
}

function isSceneManifest(
  value: unknown
): value is WebHostSceneManifest {
  return (
    isObject(value) &&
    typeof (value as { defaultSceneId?: unknown }).defaultSceneId === "string" &&
    Array.isArray((value as { scenes?: unknown }).scenes)
  );
}

function isObject(
  value: unknown
): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

async function loadWebHostSceneManifestFromResponse(
  response: Response
): Promise<WebHostSceneManifest> {
  if (!response.ok) {
    throw new Error(`failed to load scene manifest: ${response.status} ${response.statusText}`);
  }

  return normalizeWebHostSceneManifest(await response.json());
}
