#!/usr/bin/env swift
//
//  build-registry.swift
//  Inlay — registry generator
//
//  Walks registry/<component>/manifest.json, reads each referenced Swift source,
//  validates the dependency graph (existence + resolvability + no cycles via a
//  topological sort), and emits registry.json — the single artifact the CLI and
//  website consume.
//
//  Usage:
//      swift scripts/build-registry.swift            # writes ./registry.json
//      swift scripts/build-registry.swift --check     # validate only, no write
//
//  Run from the repo root.
//

import Foundation

// MARK: - Manifest model (the hand-authored input)

struct ManifestFile: Codable {
    let from: String
    let to: String
}

struct Variant: Codable {
    let id: String
    let title: String
    let description: String?
    let config: [String: JSONValue]?
}

struct Manifest: Codable {
    let name: String
    let kind: String
    let title: String
    let description: String
    let category: String
    let minIOS: String
    let swiftVersion: String
    let files: [ManifestFile]
    let dependencies: [String]
    let variants: [Variant]?
    /// Optional 3-line usage snippet surfaced by `inlay add`.
    let usage: String?
}

// MARK: - Output model (the generated artifact)

struct RegistryFile: Codable {
    let to: String
    let source: String
}

struct RegistryComponent: Codable {
    let name: String
    let kind: String
    let title: String
    let description: String
    let category: String
    let minIOS: String
    let swiftVersion: String
    let dependencies: [String]
    let variants: [Variant]?
    let usage: String?
    let files: [RegistryFile]
}

struct Registry: Codable {
    let version: Int
    let generatedAt: String
    let components: [RegistryComponent]
}

// MARK: - A small JSON value type so arbitrary `config` maps round-trip cleanly.

enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        throw DecodingError.dataCorruptedError(
            in: c, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

// MARK: - Errors

struct BuildError: Error, CustomStringConvertible {
    let description: String
    init(_ m: String) { description = "✗ \(m)" }
}

// MARK: - Driver

let fm = FileManager.default
let root = fm.currentDirectoryPath
let registryDir = root + "/registry"
let checkOnly = CommandLine.arguments.contains("--check")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("✗ " + message + "\n").utf8))
    exit(1)
}

guard fm.fileExists(atPath: registryDir) else {
    fail("No registry/ directory found. Run from the repo root.")
}

// 1. Discover manifests: registry/<component>/manifest.json
let componentDirs = (try? fm.contentsOfDirectory(atPath: registryDir))?
    .sorted()
    .map { registryDir + "/" + $0 }
    .filter { var isDir: ObjCBool = false
              return fm.fileExists(atPath: $0, isDirectory: &isDir) && isDir.boolValue }
    ?? []

var manifests: [Manifest] = []
let decoder = JSONDecoder()

for dir in componentDirs {
    let manifestPath = dir + "/manifest.json"
    guard fm.fileExists(atPath: manifestPath) else {
        fail("Missing manifest.json in \(dir)")
    }
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
        let manifest = try decoder.decode(Manifest.self, from: data)
        let folder = (dir as NSString).lastPathComponent
        if manifest.name != folder {
            fail("Manifest name '\(manifest.name)' != folder '\(folder)' in \(manifestPath)")
        }
        manifests.append(manifest)
    } catch {
        fail("Failed to parse \(manifestPath): \(error)")
    }
}

guard !manifests.isEmpty else { fail("No components found under registry/") }

let byName = Dictionary(uniqueKeysWithValues: manifests.map { ($0.name, $0) })

// 2. Validate: every `from` file exists; every dependency resolves.
for m in manifests {
    for file in m.files {
        let path = root + "/" + file.from
        guard fm.fileExists(atPath: path) else {
            fail("Component '\(m.name)' references missing file: \(file.from)")
        }
    }
    for dep in m.dependencies where byName[dep] == nil {
        fail("Component '\(m.name)' depends on unknown component '\(dep)'")
    }
}

// 3. Topological sort — proves the dependency graph is acyclic.
//    States: 0 = unvisited, 1 = visiting (on stack), 2 = done.
var state: [String: Int] = [:]
var ordered: [String] = []

func visit(_ name: String, stack: [String]) {
    switch state[name] ?? 0 {
    case 2: return
    case 1:
        let cycle = (stack + [name]).joined(separator: " → ")
        fail("Dependency cycle detected: \(cycle)")
    default:
        state[name] = 1
        for dep in byName[name]!.dependencies {
            visit(dep, stack: stack + [name])
        }
        state[name] = 2
        ordered.append(name)
    }
}

for m in manifests.sorted(by: { $0.name < $1.name }) {
    visit(m.name, stack: [])
}

// 4. Build the output, embedding raw source text. `ordered` is dependency-first.
var components: [RegistryComponent] = []
for name in ordered {
    let m = byName[name]!
    var files: [RegistryFile] = []
    for file in m.files {
        let source = try String(contentsOfFile: root + "/" + file.from, encoding: .utf8)
        files.append(RegistryFile(to: file.to, source: source))
    }
    components.append(RegistryComponent(
        name: m.name, kind: m.kind, title: m.title, description: m.description,
        category: m.category, minIOS: m.minIOS, swiftVersion: m.swiftVersion,
        dependencies: m.dependencies, variants: m.variants, usage: m.usage,
        files: files))
}

// Stable timestamp source: honour SOURCE_DATE_EPOCH for reproducible builds,
// else now. Avoids spurious diffs in CI when nothing changed.
let generatedAt: String
let isoFormatter = ISO8601DateFormatter()
if let epoch = ProcessInfo.processInfo.environment["SOURCE_DATE_EPOCH"],
   let seconds = TimeInterval(epoch) {
    generatedAt = isoFormatter.string(from: Date(timeIntervalSince1970: seconds))
} else {
    generatedAt = isoFormatter.string(from: Date())
}

let registry = Registry(version: 1, generatedAt: generatedAt, components: components)

if checkOnly {
    print("✓ Registry valid: \(components.count) components, dependency graph acyclic.")
    for name in ordered {
        let m = byName[name]!
        let deps = m.dependencies.isEmpty ? "" : "  ← \(m.dependencies.joined(separator: ", "))"
        print("    • \(name)\(deps)")
    }
    exit(0)
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
let outData = try encoder.encode(registry)
let outPath = root + "/registry.json"
try outData.write(to: URL(fileURLWithPath: outPath))

print("✓ Wrote registry.json — \(components.count) components (\(outData.count) bytes)")
for name in ordered {
    let m = byName[name]!
    let deps = m.dependencies.isEmpty ? "" : "  ← \(m.dependencies.joined(separator: ", "))"
    print("    • \(name)\(deps)")
}
