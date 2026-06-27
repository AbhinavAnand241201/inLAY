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
    /// Global fallbacks (tagged, immutable) used when no local registry is found
    /// — e.g. a bare binary with no resource bundle. jsDelivr first (edge-cached
    /// worldwide), then GitHub raw (always available, no cache warming).
    static let remoteFallbacks = [
        "https://cdn.jsdelivr.net/gh/AbhinavAnand241201/inLAY@v0.1.0/registry.json",
        "https://raw.githubusercontent.com/AbhinavAnand241201/inLAY/v0.1.0/registry.json",
    ]

    /// Resolution order: explicit override → env var → local resource (bundle or
    /// next to the executable) → global CDN. We locate the local resource by hand
    /// rather than via `Bundle.module`, whose generated accessor *crashes* when
    /// the bundle is absent (e.g. a copied binary).
    static func load(override: String?) throws -> Registry {
        if let override { return try loadFrom(string: override) }
        if let env = ProcessInfo.processInfo.environment["INLAY_REGISTRY"] {
            return try loadFrom(string: env)
        }
        for url in localCandidates() {
            if let data = try? Data(contentsOf: url) { return try decode(data) }
        }
        // Global fallback so `inlay` works even if the resource didn't travel.
        for remote in remoteFallbacks {
            if let url = URL(string: remote), let data = try? Data(contentsOf: url) {
                return try decode(data)
            }
        }
        throw InlayError.registryUnavailable
    }

    /// Places a real install may keep `registry.json`: the app resource dir, the
    /// SwiftPM resource bundle next to the binary, the binary's own dir, and a
    /// sibling `libexec` (Homebrew layout). Symlinks are resolved first.
    private static func localCandidates() -> [URL] {
        var urls: [URL] = []
        if let res = Bundle.main.resourceURL {
            urls.append(res.appendingPathComponent("registry.json"))
            urls.append(res.appendingPathComponent("inlay_inlay.bundle/registry.json"))
        }
        if let exe = Bundle.main.executablePath ?? CommandLine.arguments.first {
            let real = (exe as NSString).resolvingSymlinksInPath
            let dir = (real as NSString).deletingLastPathComponent
            for rel in ["inlay_inlay.bundle/registry.json", "registry.json",
                        "../libexec/inlay_inlay.bundle/registry.json"] {
                urls.append(URL(fileURLWithPath: (dir as NSString).appendingPathComponent(rel)))
            }
        }
        return urls
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
