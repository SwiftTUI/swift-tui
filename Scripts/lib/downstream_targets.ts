// Prints every SwiftPM target downstream of the given module (the module
// itself excluded), one per line, derived from `swift package describe
// --type json` on stdin. Used by Scripts/purge_downstream_build_products.sh.
//
// Usage: swift package describe --type json | bun run Scripts/lib/downstream_targets.ts <module>
//        swift package describe --type json | bun run Scripts/lib/downstream_targets.ts --all
//
// `--all` prints every target of the described package (a sibling package
// whose targets all consume swift-tui by path).

interface DescribedTarget {
  name: string;
  target_dependencies?: string[];
}

interface DescribedPackage {
  targets: DescribedTarget[];
}

const module = process.argv[2];
if (!module) {
  console.error("usage: downstream_targets.ts <module>");
  process.exit(2);
}

const input = await Bun.stdin.text();
const described = JSON.parse(input) as DescribedPackage;
const names = new Set(described.targets.map((target) => target.name));
if (module === "--all") {
  for (const name of [...names].sort()) {
    console.log(name);
  }
  process.exit(0);
}
if (!names.has(module)) {
  console.error(`unknown target: ${module}`);
  process.exit(2);
}

// Reverse edges: dependency -> the targets that depend on it directly.
const dependents = new Map<string, string[]>();
for (const target of described.targets) {
  for (const dependency of target.target_dependencies ?? []) {
    const list = dependents.get(dependency) ?? [];
    list.push(target.name);
    dependents.set(dependency, list);
  }
}

const downstream = new Set<string>();
const queue = [module];
while (queue.length > 0) {
  const current = queue.shift()!;
  for (const dependent of dependents.get(current) ?? []) {
    if (!downstream.has(dependent)) {
      downstream.add(dependent);
      queue.push(dependent);
    }
  }
}

for (const name of [...downstream].sort()) {
  console.log(name);
}
