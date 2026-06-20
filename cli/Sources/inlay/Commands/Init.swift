import ArgumentParser
import Foundation

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Set up Inlay in the current Xcode project.")

    @Flag(name: .long, help: "Don't fail or warn if no .xcodeproj is found.")
    var force = false

    func run() throws {
        let cwd = FileManager.default.currentDirectoryPath

        // 1. Detect the Xcode project.
        let project = XcodeProject.find(in: cwd)
        if project == nil && !force {
            print(Term.yellow("⚠ No .xcodeproj found in this directory."))
            print("  Run `inlay init` from your project root, or pass --force to set up anyway.")
            print("  Inlay will still write files; you'd add the Inlay/ folder to your target manually.")
        }

        // 2. Create the Inlay/ folder inside the synchronized source folder, so
        //    components land where Xcode auto-builds them.
        let base = project?.installBase ?? "."
        let inlayRel = Paths.join(base, "Inlay")
        try FileManager.default.createDirectory(
            atPath: cwd + "/" + inlayRel, withIntermediateDirectories: true)
        print("\(Term.green("✓")) Created \(Term.bold(inlayRel + "/"))")

        // 3. Write an empty lockfile if one doesn't exist.
        let lockPath = Lockfile.path(in: cwd)
        if !FileManager.default.fileExists(atPath: lockPath) {
            try Lockfile.empty.write(to: cwd)
            print("\(Term.green("✓")) Wrote \(Term.bold(Lockfile.fileName))")
        } else {
            print("\(Term.dim("•")) \(Lockfile.fileName) already exists — leaving it.")
        }

        // 4. Tell the user how their setup will behave.
        print("")
        if let project {
            print("Detected \(Term.cyan(project.name + ".xcodeproj")).")
            if project.usesBuildableFolders, let source = project.sourceFolder {
                print(Term.green("✓ This project uses Xcode 16 buildable folders."))
                print("  Components install into \(Term.bold(source + "/Inlay/")) — inside the folder")
                print("  Xcode already builds — so every `inlay add` compiles with no project edits.")
            } else if project.usesBuildableFolders {
                print(Term.green("✓ This project uses Xcode 16 buildable folders."))
                print("  Couldn't pinpoint the source folder, so files go in \(Term.bold("Inlay/")) at the root.")
                print("  Drag \(Term.bold("Inlay/")) into your target once; future adds need no edits.")
            } else {
                print(Term.yellow("⚠ This project doesn't appear to use buildable folders."))
                print("  Add the \(Term.bold("Inlay/")) folder to your app target once:")
                print("    Xcode → File → Add Files to \"\(project.name)\"… → select Inlay/ →")
                print("    check \"Create folder references\" and your app target.")
                print("  After that, future `inlay add` commands need no project edits.")
            }
        }
        print("")
        print("Next: \(Term.bold("inlay add floating-toolbar"))")
    }
}
