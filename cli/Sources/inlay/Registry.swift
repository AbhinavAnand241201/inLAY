import Foundation

// MARK: - Registry model (mirrors registry.json — the generated artifact)

struct Variant: Codable {
    let id: String
    let title: String
    let description: String?
}

struct RegistryFile: Codable {
    let to: String
    let source: String
}

struct Component: Codable {
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
    let generatedAt: String?
    let components: [Component]

    private var index: [String: Component] {
        Dictionary(uniqueKeysWithValues: components.map { ($0.name, $0) })
    }

    func component(named name: String) -> Component? { index[name] }

    var names: [String] { components.map(\.name) }

    /// Direct dependents: installed-or-not components that list `name` as a dep.
    func directDependents(of name: String) -> [String] {
        components.filter { $0.dependencies.contains(name) }.map(\.name)
    }

    /// Throws `.unknownComponentDidYouMean` with fuzzy suggestions when possible,
    /// else `.unknownComponent`.
    func requireComponent(_ name: String) throws -> Component {
        if let c = index[name] { return c }
        let suggestions = Fuzzy.nearest(name, in: names)
        throw suggestions.isEmpty
            ? InlayError.unknownComponent(name)
            : InlayError.unknownComponentDidYouMean(name, suggestions)
    }

    /// Transitive dependencies of `name`, dependency-first, deduplicated,
    /// with `name` itself last. Throws on an unknown name (cycles can't occur:
    /// the registry is generated from an acyclic graph).
    func resolve(_ name: String) throws -> [Component] {
        let idx = index
        guard idx[name] != nil else { throw InlayError.unknownComponent(name) }
        var ordered: [Component] = []
        var seen = Set<String>()

        func walk(_ n: String, _ stack: [String]) throws {
            guard let comp = idx[n] else { throw InlayError.unknownComponent(n) }
            if stack.contains(n) {
                throw InlayError.dependencyCycle((stack + [n]).joined(separator: " → "))
            }
            if seen.contains(n) { return }
            for dep in comp.dependencies { try walk(dep, stack + [n]) }
            seen.insert(n)
            ordered.append(comp)
        }
        try walk(name, [])
        return ordered
    }
}

// MARK: - Loading

enum RegistrySource {
    /// Resolution order: explicit override → env var → bundled resource.
    static func load(override: String?) throws -> Registry {
        if let override { return try loadFrom(string: override) }
        if let env = ProcessInfo.processInfo.environment["INLAY_REGISTRY"] {
            return try loadFrom(string: env)
        }
        guard let url = Bundle.module.url(forResource: "registry", withExtension: "json") else {
            throw InlayError.registryUnavailable
        }
        return try decode(Data(contentsOf: url))
    }

    /// A `--registry` value may be a local path or an http(s) URL.
    private static func loadFrom(string: String) throws -> Registry {
        if string.hasPrefix("http://") || string.hasPrefix("https://"),
           let url = URL(string: string) {
            return try decode(Data(contentsOf: url))
        }
        return try decode(Data(contentsOf: URL(fileURLWithPath: string)))
    }

    private static func decode(_ data: Data) throws -> Registry {
        do { return try JSONDecoder().decode(Registry.self, from: data) }
        catch { throw InlayError.registryDecode(String(describing: error)) }
    }
}
