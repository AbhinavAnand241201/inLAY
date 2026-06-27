import ArgumentParser
import Foundation

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Diagnose the project setup: Xcode, buildable folders, install base, registry, lockfile.")

    @OptionGroup var registryOption: RegistryOption

    func run() throws {
        let cwd = FileManager.default.currentDirectoryPath
        var problems = 0

        func ok(_ m: String)   { print("\(Term.green("✓")) \(m)") }
        func warn(_ m: String) { problems += 1; print("\(Term.yellow("⚠")) \(m)") }
        func info(_ m: String) { print("\(Term.dim("•")) \(m)") }

        print("")
        print(Term.bold("Inlay doctor"))
        print(Term.dim("Working dir: \(cwd)"))
        print("")

        // 1. Xcode toolchain.
        if let xcode = SystemInfo.xcodeVersion() {
            ok("Xcode \(xcode) detected.")
        } else {
            warn("Couldn't run xcodebuild — is Xcode / Command Line Tools installed?")
        }

        // 2. Project + install base.
        let project = XcodeProject.find(in: cwd)
        if let project {
            ok("Found \(project.name).xcodeproj")
            if project.usesBuildableFolders, let source = project.sourceFolder {
                ok("Buildable folders in use — components install into \(Term.bold(source + "/Inlay/")) and auto-build.")
            } else if project.usesBuildableFolders {
                warn("Buildable folders present, but the source folder couldn't be pinpointed; files go to Inlay/ at the root (add it to your target once).")
            } else {
                warn("No buildable folders — add the Inlay/ folder to your target once (see `inlay init`).")
            }

            // 3. Deployment target vs installed components' minIOS.
            let pbxproj = project.path + "/project.pbxproj"
            if let target = SystemInfo.deploymentTarget(pbxprojAt: pbxproj) {
                info("Deployment target: iOS \(target)")
                if let registry = try? RegistrySource.load(override: registryOption.registry),
                   let lock = try? Lockfile.load(in: cwd) {
                    for entry in lock.installed {
                        guard let comp = registry.component(named: entry.name) else { continue }
                        if !SemVerLite.gte(target, comp.minIOS) {
                            warn("\(entry.name) needs iOS \(comp.minIOS) but your target is iOS \(target).")
                        }
                    }
                }
            } else {
                info("Couldn't read the deployment target from the project.")
            }
        } else {
            warn("No .xcodeproj here — run from your project root, or components write to Inlay/ at the root.")
        }

        // 4. Registry reachability.
        if let registry = try? RegistrySource.load(override: registryOption.registry) {
            ok("Registry OK — \(registry.components.count) components available.")
        } else {
            warn("Registry unavailable — pass --registry or set INLAY_REGISTRY.")
        }

        // 5. Lockfile + installed-file integrity.
        let lockPath = Lockfile.path(in: cwd)
        if FileManager.default.fileExists(atPath: lockPath) {
            let lock = (try? Lockfile.load(in: cwd)) ?? .empty
            ok("\(Lockfile.fileName): \(lock.installed.count) component(s) installed.")
            var missing = 0
            for entry in lock.installed {
                for file in entry.files where !FileManager.default.fileExists(atPath: cwd + "/" + file) {
                    missing += 1
                    warn("Missing on disk: \(file) (from \(entry.name)).")
                }
            }
            if missing == 0, !lock.installed.isEmpty { ok("All installed files present on disk.") }
        } else {
            info("No \(Lockfile.fileName) yet — run `inlay init` or `inlay add <name>`.")
        }

        print("")
        if problems == 0 {
            print(Term.green("Everything looks good."))
        } else {
            print(Term.yellow("\(problems) thing\(problems == 1 ? "" : "s") to look at above."))
        }
    }
}
