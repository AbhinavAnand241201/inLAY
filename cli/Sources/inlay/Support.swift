import Foundation
import CryptoKit

// MARK: - Errors

enum InlayError: Error, CustomStringConvertible {
    case unknownComponent(String)
    case dependencyCycle(String)
    case registryUnavailable
    case registryDecode(String)
    case notInstalled(String)

    var description: String {
        switch self {
        case .unknownComponent(let n):
            return "Unknown component '\(n)'. Run `inlay list` to see what's available."
        case .dependencyCycle(let c):
            return "Dependency cycle: \(c)"
        case .registryUnavailable:
            return "Could not locate a registry. Pass --registry <path|url> or set INLAY_REGISTRY."
        case .registryDecode(let d):
            return "Failed to read registry: \(d)"
        case .notInstalled(let n):
            return "'\(n)' isn't installed here. Run `inlay add \(n)` first."
        }
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
