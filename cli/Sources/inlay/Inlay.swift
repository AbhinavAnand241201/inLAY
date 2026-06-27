import ArgumentParser

@main
struct Inlay: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inlay",
        abstract: "Copy-paste UIKit components for iOS — shadcn/ui for iOS.",
        version: "0.1.1",
        subcommands: [Init.self, Add.self, List.self, Search.self, Diff.self,
                      Update.self, Remove.self, Doctor.self],
        defaultSubcommand: List.self)
}

/// Shared option: point any command at an alternate registry (path or URL).
struct RegistryOption: ParsableArguments {
    @Option(name: .customLong("registry"),
            help: "Path or URL to a registry.json (overrides the bundled one).")
    var registry: String?
}
