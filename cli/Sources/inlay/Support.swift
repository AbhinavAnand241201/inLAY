import Foundation
import CryptoKit

// MARK: - Errors

enum InlayError: Error, CustomStringConvertible {
    case unknownComponent(String)
    case unknownComponentDidYouMean(String, [String])
    case dependencyCycle(String)
    case registryUnavailable
    case registryDecode(String)
    case notInstalled(String)
    case unsafePath(String)
    case operationBlocked(String)

    var description: String {
        switch self {
        case .unknownComponent(let n):
            return "Unknown component '\(n)'. Run `inlay list` to see what's available."
        case .unknownComponentDidYouMean(let n, let suggestions):
            let hints = suggestions.map { "  • \($0)" }.joined(separator: "\n")
            return "Unknown component '\(n)'. Did you mean:\n\(hints)"
        case .dependencyCycle(let c):
            return "Dependency cycle: \(c)"
        case .registryUnavailable:
            return "Could not locate a registry. Pass --registry <path|url> or set INLAY_REGISTRY."
        case .registryDecode(let d):
            return "Failed to read registry: \(d)"
        case .notInstalled(let n):
            return "'\(n)' isn't installed here. Run `inlay add \(n)` first."
        case .unsafePath(let p):
            return "Refusing to write unsafe path '\(p)' (absolute or escapes the project)."
        case .operationBlocked(let why):
            return why
        }
    }
}

// MARK: - Path safety (manifest paths are untrusted input)

enum SafePath {
    /// Validates a manifest `to` path is relative with no `..`/`~`/absolute
    /// segment, then returns the cwd-relative path to write. With no `..` and no
    /// leading `/`, a relative path provably cannot escape `root`, so an explicit
    /// filesystem containment check (fragile for not-yet-existing paths) is
    /// unnecessary — and `base` is CLI-derived, not from the manifest.
    static func validate(_ to: String, base: String, root: String) throws -> String {
        if to.hasPrefix("/") || to.hasPrefix("~") { throw InlayError.unsafePath(to) }
        let segments = to.split(separator: "/").map(String.init)
        if segments.contains("..") || segments.contains(".") || segments.contains("~") {
            throw InlayError.unsafePath(to)
        }
        return Paths.join(base, to)
    }
}

// MARK: - Fuzzy matching (git-style "did you mean")

enum Fuzzy {
    static func distance(_ a: String, _ b: String) -> Int {
        let s = Array(a), t = Array(b)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        var prev = Array(0...t.count)
        var curr = [Int](repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            curr[0] = i
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[t.count]
    }

    /// Nearest names to `query`: close edit distance OR substring containment.
    static func nearest(_ query: String, in names: [String], limit: Int = 3) -> [String] {
        let q = query.lowercased()
        return names
            .map { ($0, distance(q, $0.lowercased()), $0.lowercased().contains(q)) }
            .filter { $0.1 <= 4 || $0.2 }
            .sorted { ($0.2 ? -1 : $0.1) < ($1.2 ? -1 : $1.1) }
            .prefix(limit)
            .map { $0.0 }
    }
}

// MARK: - System introspection (for `doctor`)

enum SystemInfo {
    /// Runs `xcodebuild -version` and returns e.g. "16.2", or nil if unavailable.
    static func xcodeVersion() -> String? {
        guard let out = run("/usr/bin/xcodebuild", ["-version"]) else { return nil }
        // First line: "Xcode 16.2"
        for line in out.split(separator: "\n") where line.hasPrefix("Xcode ") {
            return line.replacingOccurrences(of: "Xcode ", with: "").trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Best-effort IPHONEOS_DEPLOYMENT_TARGET from a pbxproj.
    static func deploymentTarget(pbxprojAt path: String) -> String? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        guard let re = try? NSRegularExpression(
            pattern: #"IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);"#) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private static func run(_ launchPath: String, _ args: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: launchPath) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        } catch { return nil }
    }
}

// MARK: - Version comparison ("16.0" vs "16.2")

enum SemVerLite {
    /// true if `a` >= `b` for dotted numeric versions.
    static func gte(_ a: String, _ b: String) -> Bool {
        let av = a.split(separator: ".").map { Int($0) ?? 0 }
        let bv = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return true
    }
}

// MARK: - Hashing

enum Hash {
    /// Stable hash of a component's files (path + content), order-independent.
    static func component(_ files: [RegistryFile]) -> String {
        var hasher = SHA256()
        for file in files.sorted(by: { $0.to < $1.to }) {
            hasher.update(data: Data(file.to.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: Data(file.source.utf8))
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func string(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Terminal styling (no-ops when not a TTY or NO_COLOR is set)

enum Term {
    static let isTTY = isatty(fileno(stdout)) == 1
        && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    static func style(_ s: String, _ code: String) -> String {
        isTTY ? "\u{001B}[\(code)m\(s)\u{001B}[0m" : s
    }
    static func bold(_ s: String) -> String { style(s, "1") }
    static func dim(_ s: String) -> String { style(s, "2") }
    static func green(_ s: String) -> String { style(s, "32") }
    static func cyan(_ s: String) -> String { style(s, "36") }
    static func yellow(_ s: String) -> String { style(s, "33") }
    static func red(_ s: String) -> String { style(s, "31") }
}

// MARK: - Xcode project detection

struct XcodeProject {
    let path: String          // …/Foo.xcodeproj
    let directory: String     // the folder containing the .xcodeproj (== cwd)
    let usesBuildableFolders: Bool
    /// The synchronized source folder Xcode auto-builds, relative to `directory`
    /// (e.g. "TestApp1"). nil for classic projects without buildable folders.
    let sourceFolder: String?

    /// Finds the first *.xcodeproj in `directory`, if any.
    static func find(in directory: String) -> XcodeProject? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: directory) else { return nil }
        guard let proj = entries.sorted().first(where: { $0.hasSuffix(".xcodeproj") }) else {
            return nil
        }
        let path = directory + "/" + proj
        let name = proj.replacingOccurrences(of: ".xcodeproj", with: "")
        // Xcode 16 "buildable folders" appear in the pbxproj as
        // PBXFileSystemSynchronizedRootGroup — their contents auto-build.
        let pbxprojText = (try? String(contentsOfFile: path + "/project.pbxproj",
                                       encoding: .utf8)) ?? ""
        let usesBuildable = pbxprojText.contains("PBXFileSystemSynchronizedRootGroup")
        let roots = synchronizedRoots(in: pbxprojText)
        let source = chooseSourceFolder(roots, projectName: name, directory: directory)
        return XcodeProject(path: path, directory: directory,
                            usesBuildableFolders: usesBuildable, sourceFolder: source)
    }

    var name: String {
        (path as NSString).lastPathComponent.replacingOccurrences(of: ".xcodeproj", with: "")
    }

    /// Directory (relative to the project root) under which component `to` paths
    /// are written. Components land inside the synchronized source folder so they
    /// build with no further Xcode steps; "." falls back to the project root.
    var installBase: String { sourceFolder ?? "." }

    // MARK: pbxproj parsing

    /// Extracts the `path` of every PBXFileSystemSynchronizedRootGroup.
    private static func synchronizedRoots(in pbxproj: String) -> [String] {
        guard let blockRe = try? NSRegularExpression(
                pattern: #"\{[^{}]*?isa = PBXFileSystemSynchronizedRootGroup;[^{}]*?\}"#),
              let pathRe = try? NSRegularExpression(
                pattern: #"path = (?:"([^"]*)"|([^;\n]+));"#)
        else { return [] }

        let ns = pbxproj as NSString
        var out: [String] = []
        for m in blockRe.matches(in: pbxproj, range: NSRange(location: 0, length: ns.length)) {
            let block = ns.substring(with: m.range)
            let bns = block as NSString
            guard let pm = pathRe.firstMatch(
                in: block, range: NSRange(location: 0, length: bns.length)) else { continue }
            let quoted = pm.range(at: 1), bare = pm.range(at: 2)
            if quoted.location != NSNotFound {
                out.append(bns.substring(with: quoted))
            } else if bare.location != NSNotFound {
                out.append(bns.substring(with: bare).trimmingCharacters(in: .whitespaces))
            }
        }
        return out
    }

    /// Picks the app's main source folder from the synchronized roots: prefer the
    /// one named after the project, else the first non-test folder that exists.
    private static func chooseSourceFolder(
        _ roots: [String], projectName: String, directory: String
    ) -> String? {
        let fm = FileManager.default
        func isDir(_ rel: String) -> Bool {
            var d: ObjCBool = false
            return fm.fileExists(atPath: directory + "/" + rel, isDirectory: &d) && d.boolValue
        }
        let existing = roots.filter(isDir)
        if let exact = existing.first(where: { $0 == projectName }) { return exact }
        if let nonTest = existing.first(where: { !$0.lowercased().contains("test") }) {
            return nonTest
        }
        return existing.first
    }
}

// MARK: - Relative path joining

enum Paths {
    /// Joins an install base (relative to cwd; "." for the project root) with a
    /// component's `to` path into a clean, cwd-relative path.
    static func join(_ base: String, _ to: String) -> String {
        (base == "." || base.isEmpty) ? to : base + "/" + to
    }
}

// MARK: - File helpers

enum Files {
    @discardableResult
    static func write(_ content: String, to relativePath: String, root: String) throws -> String {
        let full = root + "/" + relativePath
        let dir = (full as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        try content.write(toFile: full, atomically: true, encoding: .utf8)
        return full
    }
}
