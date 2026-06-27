import ArgumentParser
import Foundation

struct Update: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Re-apply the registry version of installed components; never silently overwrites edits.")

    @Argument(help: "Component to update. Omit to check all installed components.")
    var name: String?

    @Flag(name: .long, help: "Apply changes (overwrite). Without this, update only reports diffs.")
    var yes = false

    @OptionGroup var registryOption: RegistryOption

    func run() throws {
        let cwd = FileManager.default.currentDirectoryPath
        var lock = try Lockfile.load(in: cwd)
        let registry = try RegistrySource.load(override: registryOption.registry)

        let targets: [InstalledComponent]
        if let name {
            guard let entry = lock.entry(name) else { throw InlayError.notInstalled(name) }
            targets = [entry]
        } else {
            targets = lock.installed
        }
        if targets.isEmpty {
            print(Term.dim("Nothing installed here. `inlay add <name>` first.")); return
        }

        var changedCount = 0
        var applied = 0

        for entry in targets {
            guard let comp = registry.component(named: entry.name) else {
                print("\(Term.yellow("⚠")) \(entry.name) — no longer in the registry; skipping.")
                continue
            }
            // Pair installed paths with registry sources by file leaf name.
            let regByLeaf = Dictionary(grouping: comp.files,
                                       by: { ($0.to as NSString).lastPathComponent })
            var diffs: [(path: String, source: String)] = []
            for path in entry.files {
                let leaf = (path as NSString).lastPathComponent
                guard let source = regByLeaf[leaf]?.first?.source else { continue }
                let onDiskPath = cwd + "/" + path
                let onDisk = (try? String(contentsOfFile: onDiskPath, encoding: .utf8)) ?? ""
                if Hash.string(onDisk) != Hash.string(source) {
                    diffs.append((path, source))
                }
            }

            if diffs.isEmpty {
                print("\(Term.green("✓")) \(entry.name) — \(Term.dim("up to date"))")
                continue
            }

            changedCount += 1
            print("\(Term.yellow("≠")) \(Term.bold(entry.name)) — \(diffs.count) file(s) differ:")
            for d in diffs {
                print("    \(Term.dim("·")) \(d.path)")
                showDiff(registrySource: d.source, installedPath: cwd + "/" + d.path, label: d.path)
            }

            if yes {
                for d in diffs {
                    _ = try Files.write(d.source, to: d.path, root: cwd)
                }
                lock.upsert(InstalledComponent(
                    name: entry.name, files: entry.files,
                    variant: entry.variant, hash: Hash.component(comp.files)))
                applied += 1
                print("    \(Term.green("✓")) updated.")
            }
        }

        if yes && applied > 0 { try lock.write(to: cwd) }

        print("")
        if changedCount == 0 {
            print(Term.green("Everything is up to date."))
        } else if yes {
            print(Term.green("Applied updates to \(applied) component(s)."))
        } else {
            print(Term.dim("These would overwrite the differences above. ")
                  + "Re-run with " + Term.bold("--yes") + " to apply (back up local edits first).")
        }
    }

    /// Compact unified diff (registry → your copy) via /usr/bin/diff.
    private func showDiff(registrySource: String, installedPath: String, label: String) {
        let tmp = NSTemporaryDirectory() + "inlay-upd-" + Hash.string(label).prefix(10) + ".swift"
        guard (try? registrySource.write(toFile: tmp, atomically: true, encoding: .utf8)) != nil
        else { return }
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/diff")
        p.arguments = ["-u", "--label", "registry", "--label", "your copy", tmp, installedPath]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        // Show only the first ~14 diff lines to keep it scannable.
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).prefix(14)
        for line in lines {
            let s = String(line)
            let colored: String
            if s.hasPrefix("+") && !s.hasPrefix("+++") { colored = Term.green(s) }
            else if s.hasPrefix("-") && !s.hasPrefix("---") { colored = Term.red(s) }
            else if s.hasPrefix("@@") { colored = Term.cyan(s) }
            else { colored = Term.dim(s) }
            print("      " + colored)
        }
    }
}
