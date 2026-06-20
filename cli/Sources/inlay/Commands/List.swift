import ArgumentParser
import Foundation

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List available components, grouped by category.")

    @OptionGroup var registryOption: RegistryOption

    func run() throws {
        let cwd = FileManager.default.currentDirectoryPath
        let registry = try RegistrySource.load(override: registryOption.registry)
        let lock = (try? Lockfile.load(in: cwd)) ?? .empty

        let grouped = Dictionary(grouping: registry.components, by: \.category)
        let categories = grouped.keys.sorted()

        print("")
        for category in categories {
            print(Term.bold(category.capitalized))
            let comps = grouped[category]!.sorted { $0.name < $1.name }
            let width = comps.map { $0.name.count }.max() ?? 0
            for c in comps {
                let installed = lock.isInstalled(c.name)
                let mark = installed ? Term.green("●") : Term.dim("○")
                let padded = c.name.padding(toLength: width, withPad: " ", startingAt: 0)
                var line = "  \(mark) \(Term.cyan(padded))  \(Term.dim(c.description))"
                if installed {
                    if let v = lock.entry(c.name)?.variant {
                        line += Term.green("  [installed · \(v)]")
                    } else {
                        line += Term.green("  [installed]")
                    }
                }
                print(line)
            }
            print("")
        }
        print(Term.dim("● installed   ○ available     Add one with ") +
              Term.bold("inlay add <name>"))
    }
}
