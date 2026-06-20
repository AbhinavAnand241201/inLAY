import registry from "@/data/registry.json";

export type Variant = { id: string; title: string; description?: string };
export type RegistryFile = { to: string; source: string };
export type Component = {
  name: string;
  kind: string;
  title: string;
  description: string;
  category: string;
  minIOS: string;
  swiftVersion: string;
  dependencies: string[];
  variants?: Variant[];
  usage?: string;
  files: RegistryFile[];
};
export type Registry = { version: number; generatedAt?: string; components: Component[] };

export const registryData = registry as unknown as Registry;

/** Components users actually install (primitives are pulled in automatically). */
export const components = registryData.components.filter((c) => c.kind !== "primitive");

export const allComponents = registryData.components;

export function getComponent(name: string): Component | undefined {
  return registryData.components.find((c) => c.name === name);
}

export function groupedByCategory(): [string, Component[]][] {
  const map = new Map<string, Component[]>();
  for (const c of components) {
    const list = map.get(c.category) ?? [];
    list.push(c);
    map.set(c.category, list);
  }
  return [...map.entries()].sort(([a], [b]) => a.localeCompare(b));
}

/** A configuration knob parsed from a component's `struct Configuration`. */
export type Knob = { name: string; type: string; def: string };

/** Pulls `var name: Type = default` lines out of `struct Configuration`. */
export function parseConfiguration(source: string): Knob[] {
  const start = source.indexOf("struct Configuration");
  if (start === -1) return [];
  let i = source.indexOf("{", start);
  if (i === -1) return [];
  let depth = 0;
  let end = -1;
  for (let j = i; j < source.length; j++) {
    if (source[j] === "{") depth++;
    else if (source[j] === "}") {
      depth--;
      if (depth === 0) {
        end = j;
        break;
      }
    }
  }
  const body = source.slice(i + 1, end === -1 ? source.length : end);
  const knobs: Knob[] = [];
  const re = /(?:^|\n)\s*var\s+(\w+)\s*:\s*([^=\n]+?)\s*=\s*([^\n]+)/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(body))) {
    knobs.push({ name: m[1], type: m[2].trim(), def: m[3].trim() });
  }
  return knobs;
}
