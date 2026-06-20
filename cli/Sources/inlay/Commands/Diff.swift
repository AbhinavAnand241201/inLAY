import ArgumentParser
import Foundation

struct Diff: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show how your installed copy differs from the registry source.")

    @Argument(help: "Component name to diff.")
    var name: String

    @OptionGroup var registryOption: RegistryOption

    func run() throws {
        let cwd = FileManager.default.currentDirectoryPath
        let registry = try RegistrySource.load(override: registryOption.registry)
        let lock = try Lockfile.load(in: cwd)

        guard let entry = lock.entry(name) else { throw InlayError.notInstalled(name) }
        guard let component = registry.component(named: name) else {
            throw InlayError.unknownComponent(name)
        }

        // Pair each registry file with where it actually landed on disk (the
        // lockfile records the real path, which may be inside a source folder).
        let installedPaths = entry.files.count == component.files.count
            ? entry.files
            : component.files.map { $0.to }

        var anyChange = false
        for (file, relPath) in zip(component.files, installedPaths) {
            let installedPath = cwd + "/" + relPath
            guard FileManager.default.fileExists(atPath: installedPath) else {
                print(Term.yellow("⚠ \(file.to) is in the lockfile but missing on disk."))
                anyChange = true
                continue
            }
            let onDisk = try String(contentsOfFile: installedPath, encoding: .utf8)
            if Hash.string(onDisk) == Hash.string(file.source) {
                print("\(Term.green("✓")) \(file.to) — \(Term.dim("unchanged"))")
                continue
            }
            anyChange = true
            print("\(Term.yellow("≠")) \(Term.bold(file.to)) — \(Term.yellow("modified"))")
            printDiff(registrySource: file.source, installedPath: installedPath, label: file.to)
        }

        print("")
        if anyChange {
            print(Term.dim("Lines you changed are shown above. ") +
                  "Re-running `inlay add \(name)` would overwrite them — back up first.")
        } else {
            print(Term.green("Your copy matches the registry exactly."))
        }
    }

    /// Unified diff (registry → your copy) via /usr/bin/diff against a temp file.
    private func printDiff(registrySource: String, installedPath: String, label: String) {
        let tmp = NSTemporaryDirectory() + "inlay-" + Hash.string(label).prefix(12) + ".swift"
        do {
            try registrySource.write(toFile: tmp, atomically: true, encoding: .utf8)
        } catch {
            print(Term.red("  (couldn't prepare diff: \(error))"))
            return
        }
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/diff")
        process.arguments = [
            "-u",
            "--label", "registry/\(label)",
            "--label", "your copy/\(label)",
            tmp, installedPath,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                print("  " + colorize(String(line)))
            }
        } catch {
            print(Term.red("  (diff failed: \(error))"))
        }
    }

    private func colorize(_ line: String) -> String {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return Term.green(line) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return Term.red(line) }
        if line.hasPrefix("@@") { return Term.cyan(line) }
        return Term.dim(line)
    }
}
