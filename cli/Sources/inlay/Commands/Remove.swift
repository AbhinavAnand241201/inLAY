import ArgumentParser
import Foundation

struct Remove: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Delete a component's files and update the lockfile (with safety checks).")

    @Argument(help: "Component name to remove.")
    var name: String

    @Flag(name: .long, help: "Remove even if other installed components depend on it, or you edited it.")
    var force = false

    @Flag(name: .long, help: "Print what would be removed without deleting anything.")
    var dryRun = false

    @OptionGroup var registryOption: RegistryOption

    func run() throws {
        let cwd = FileManager.default.currentDirectoryPath
        var lock = try Lockfile.load(in: cwd)
        guard let entry = lock.entry(name) else { throw InlayError.notInstalled(name) }

        let registry = try? RegistrySource.load(override: registryOption.registry)

        // Refcount safety: is another INSTALLED component depending on this one?
        if let registry, !force {
            let dependents = registry.directDependents(of: name)
                .filter { lock.isInstalled($0) && $0 != name }
            if !dependents.isEmpty {
                throw InlayError.operationBlocked(
                    "Can't remove '\(name)' — still needed by: \(dependents.joined(separator: ", ")).\n"
                    + "Remove those first, or pass --force.")
            }
        }

        // Edit safety: warn if the user modified a file we're about to delete.
        if let registry, let comp = registry.component(named: name), !force {
            let bySuffix = Dictionary(grouping: comp.files, by: { ($0.to as NSString).lastPathComponent })
            for file in entry.files {
                let onDiskPath = cwd + "/" + file
                guard let onDisk = try? String(contentsOfFile: onDiskPath, encoding: .utf8) else { continue }
                let leaf = (file as NSString).lastPathComponent
                if let source = bySuffix[leaf]?.first?.source,
                   Hash.string(onDisk) != Hash.string(source) {
                    throw InlayError.operationBlocked(
                        "'\(file)' has local edits. Pass --force to delete it anyway "
                        + "(back it up first if you want to keep your changes).")
                }
            }
        }

        if dryRun {
            print("")
            print(Term.bold("Dry run") + Term.dim(" — nothing was deleted."))
            print("Would remove \(Term.cyan(name)):")
            for file in entry.files { print("  \(Term.dim("✗")) \(file)") }
            return
        }

        // Delete files, prune now-empty Inlay directories, update the lockfile.
        let fm = FileManager.default
        var removed: [String] = []
        for file in entry.files {
            let path = cwd + "/" + file
            if fm.fileExists(atPath: path) {
                try fm.removeItem(atPath: path)
                removed.append(file)
            }
        }
        pruneEmptyDirs(for: entry.files, root: cwd)
        lock.installed.removeAll { $0.name == name }
        try lock.write(to: cwd)

        print("")
        print("\(Term.green("✓")) Removed \(Term.bold(name))")
        for f in removed { print("    \(Term.dim("✗")) \(f)") }

        // Surface dependencies that may now be orphaned (we don't auto-remove).
        if let registry, let comp = registry.component(named: name) {
            let orphans = comp.dependencies.filter { dep in
                lock.isInstalled(dep)
                    && registry.directDependents(of: dep).allSatisfy { !lock.isInstalled($0) }
            }
            if !orphans.isEmpty {
                print(Term.dim("No longer required (remove manually if you like): "
                               + orphans.joined(separator: ", ")))
            }
        }
    }

    /// Remove `Inlay/Components` then `Inlay` if they became empty.
    private func pruneEmptyDirs(for files: [String], root: String) {
        let fm = FileManager.default
        var dirs = Set<String>()
        for file in files {
            var dir = (file as NSString).deletingLastPathComponent
            while !dir.isEmpty && dir != "." {
                dirs.insert(dir)
                dir = (dir as NSString).deletingLastPathComponent
            }
        }
        // Deepest first.
        for dir in dirs.sorted(by: { $0.count > $1.count }) {
            let abs = root + "/" + dir
            if let contents = try? fm.contentsOfDirectory(atPath: abs), contents.isEmpty {
                try? fm.removeItem(atPath: abs)
            }
        }
    }
}
