import ArgumentParser
import Foundation

struct Add: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add a component (and its dependencies) to your project.")

    @Argument(help: "Component name, e.g. floating-toolbar.")
    var name: String

    @Option(name: .long, help: "Variant id to install (see the component's page).")
    var variant: String?

    @Flag(name: .long, help: "Print the source + paste instructions instead of writing files.")
    var manual = false

    @OptionGroup var registryOption: RegistryOption

    func run() throws {
        let cwd = FileManager.default.currentDirectoryPath
        let registry = try RegistrySource.load(override: registryOption.registry)

        // Resolve the target + all transitive deps, dependency-first.
        let resolved = try registry.resolve(name)

        // --manual: don't touch disk, just print everything to paste.
        if manual {
            printManual(resolved)
            return
        }

        // Write components into the synchronized source folder Xcode auto-builds,
        // so no manual "add folder to target" / `mv` step is needed.
        let project = XcodeProject.find(in: cwd)
        let base = project?.installBase ?? "."

        var lock = try Lockfile.load(in: cwd)
        var wrote: [(component: Component, paths: [String])] = []
        var skipped: [String] = []

        for component in resolved {
            let hash = Hash.component(component.files)
            if let existing = lock.entry(component.name), existing.hash == hash {
                skipped.append(component.name)
                continue
            }

            var paths: [String] = []
            for file in component.files {
                let rel = Paths.join(base, file.to)
                _ = try Files.write(file.source, to: rel, root: cwd)
                paths.append(rel)
            }
            // Only the explicitly requested component records the variant.
            let chosenVariant = component.name == name ? variant : nil
            lock.upsert(InstalledComponent(
                name: component.name, files: paths,
                variant: chosenVariant, hash: hash))
            wrote.append((component, paths))
        }

        try lock.write(to: cwd)
        report(target: name, wrote: wrote, skipped: skipped,
               registry: registry, project: project, base: base)
    }

    // MARK: - Output

    private func report(
        target: String,
        wrote: [(component: Component, paths: [String])],
        skipped: [String],
        registry: Registry,
        project: XcodeProject?,
        base: String
    ) {
        print("")
        if !wrote.isEmpty {
            if let project, base != ".", project.usesBuildableFolders {
                print(Term.dim("Placed inside the synchronized folder ") +
                      Term.bold(base + "/") +
                      Term.dim(" — Xcode builds it automatically, no project edits."))
            } else if base == "." {
                print(Term.yellow("⚠ Wrote to the project root. ") +
                      "Add the \(Term.bold("Inlay/")) folder to your target once (see `inlay init`).")
            }
        }
        if wrote.isEmpty {
            print(Term.green("✓") + " Nothing to do — \(Term.bold(target)) and its dependencies are already installed.")
        } else {
            for (component, paths) in wrote {
                let tag = component.name == target
                    ? Term.cyan("component")
                    : Term.dim("dependency")
                print("\(Term.green("✓")) \(Term.bold(component.name)) \(tag)")
                for p in paths { print("    \(Term.dim("→")) \(p)") }
            }
        }

        let deps = wrote.map(\.component).filter { $0.name != target }
        if !deps.isEmpty {
            print("")
            print(Term.dim("Pulled in dependencies: ") + deps.map(\.name).joined(separator: ", "))
        }
        if !skipped.isEmpty {
            print(Term.dim("Already installed (skipped): " + skipped.joined(separator: ", ")))
        }

        if let chosen = variant {
            print(Term.dim("Variant: ") + chosen +
                  Term.dim(" — apply its config in your Configuration (see usage below)."))
        }

        if let component = registry.component(named: target) {
            printUsage(component)
        }
    }

    private func printUsage(_ component: Component) {
        print("")
        print(Term.bold("Usage"))
        let snippet = component.usage ?? defaultUsageSnippet(for: component)
        for line in snippet.split(separator: "\n", omittingEmptySubsequences: false) {
            print("  " + line)
        }
    }

    private func printManual(_ resolved: [Component]) {
        print(Term.bold("Manual install — paste these files into your project:"))
        for component in resolved {
            for file in component.files {
                print("")
                print(Term.cyan("// ===== \(file.to) =====  (\(component.name))"))
                print(file.source)
            }
        }
        print("")
        print(Term.dim("Add each file to your app target. Order doesn't matter; Swift resolves it."))
    }

    private func defaultUsageSnippet(for component: Component) -> String {
        """
        // See \(component.files.first?.to ?? component.name) — the header comment has a
        // runnable snippet. Customize via \(component.title.replacingOccurrences(of: " ", with: "")).Configuration.
        """
    }
}
