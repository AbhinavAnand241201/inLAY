import ArgumentParser
import Foundation

struct Search: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Fuzzy-search components by name, title, description, or category.")

    @Argument(help: "Search query.")
    var query: String

    @OptionGroup var registryOption: RegistryOption

    func run() throws {
        let registry = try RegistrySource.load(override: registryOption.registry)
        let q = query.lowercased()

        // Score each component: lower is better. Name hits rank highest.
        struct Hit { let component: Component; let score: Int }
        var hits: [Hit] = []
        for c in registry.components where c.kind != "primitive" {
            let haystacks = [c.name, c.title, c.description, c.category].map { $0.lowercased() }
            let contains = haystacks.contains { $0.contains(q) }
            let nameDistance = Fuzzy.distance(q, c.name.lowercased())
            if contains {
                hits.append(Hit(component: c, score: c.name.lowercased().contains(q) ? 0 : 1))
            } else if nameDistance <= 3 {
                hits.append(Hit(component: c, score: 2 + nameDistance))
            }
        }
        hits.sort { $0.score < $1.score || ($0.score == $1.score && $0.component.name < $1.component.name) }

        print("")
        if hits.isEmpty {
            print(Term.dim("No components match “\(query)”. Try `inlay list`."))
            return
        }
        let width = hits.map { $0.component.name.count }.max() ?? 0
        for hit in hits {
            let c = hit.component
            let padded = c.name.padding(toLength: width, withPad: " ", startingAt: 0)
            print("  \(Term.cyan(padded))  \(Term.dim(c.description))")
        }
        print("")
        print(Term.dim("\(hits.count) result\(hits.count == 1 ? "" : "s"). Install with ") +
              Term.bold("inlay add <name>"))
    }
}
