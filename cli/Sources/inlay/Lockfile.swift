import Foundation

// MARK: - inlay.lock.json — records what's installed so deps install once.

struct InstalledComponent: Codable {
    let name: String
    var files: [String]
    var variant: String?
    /// Content hash of the installed sources, so `add`/`diff` can tell whether
    /// the registry version differs from what's on disk.
    var hash: String?
}

struct Lockfile: Codable {
    var version: Int
    var installed: [InstalledComponent]

    static let fileName = "inlay.lock.json"
    static let empty = Lockfile(version: 1, installed: [])

    func isInstalled(_ name: String) -> Bool {
        installed.contains { $0.name == name }
    }

    func entry(_ name: String) -> InstalledComponent? {
        installed.first { $0.name == name }
    }

    mutating func upsert(_ entry: InstalledComponent) {
        if let i = installed.firstIndex(where: { $0.name == entry.name }) {
            installed[i] = entry
        } else {
            installed.append(entry)
        }
    }

    // MARK: Disk

    static func path(in directory: String) -> String {
        directory + "/" + fileName
    }

    static func load(in directory: String) throws -> Lockfile {
        let p = path(in: directory)
        guard FileManager.default.fileExists(atPath: p) else { return .empty }
        let data = try Data(contentsOf: URL(fileURLWithPath: p))
        return try JSONDecoder().decode(Lockfile.self, from: data)
    }

    func write(to directory: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        try data.write(to: URL(fileURLWithPath: Lockfile.path(in: directory)))
    }
}
