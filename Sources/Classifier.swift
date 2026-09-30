import Foundation
import Darwin

struct Classifier {
    static func profile(path: String, home: String, readMetadata: Bool = true, preferences: Preferences = Preferences()) -> FolderProfile {
        let path = normalized(path), home = normalized(home)
        let url = URL(fileURLWithPath: path)
        var p = FolderProfile(path: path, name: url.lastPathComponent, category: .unknown, project: nil,
            associatedApp: "Unknown", explanation: "No specific classification is established for this location.",
            consequence: "Contents may be unique. Inspect before making any decision outside Context Cleaner.", evidence: [])
        /// The recognized folder a path sits in, when the path is below it. Subfolders are named for themselves:
        /// "project_dex_archive in Android build intermediates", never just their parent's name.
        var recognizedRoot: String?
        func assign(_ category: FolderCategory, _ name: String, _ app: String, _ explanation: String, _ consequence: String) {
            var name = name
            if let root = recognizedRoot, root != path, path.hasPrefix(root + "/") {
                name = String(path.dropFirst(root.count + 1)).split(separator: "/").joined(separator: " › ") + " in " + name
            }
            p.category = category; p.name = name; p.associatedApp = app; p.explanation = explanation; p.consequence = consequence
            p.evidence.append(Evidence(label: "Association", value: app, level: .inferred, source: "Matched known directory structure; not proof of the historical writer."))
        }
        if path.contains("/AppInstallationBinaryDeltas/") {
            assign(.installCache, url.lastPathComponent + " install cache", "Apple CoreDevice", "Mac-side app installation cache. The final path component identifies the target app, not the tool that initiated installation.", "Future device installations can recreate cached data. Stop device installs before manual review.")
            p.evidence.append(Evidence(label: "Target bundle identifier", value: url.lastPathComponent, level: .inferred, source: "Installation-cache directory name"))
        } else if path.contains("/CoreSimulator/Devices/") || path.hasSuffix("/CoreSimulator/Devices") {
            assign(.simulator, "Simulator data", "Apple CoreSimulator", "Simulator applications, app data, saves and test fixtures can be stored here.", "May contain unique saves or test fixtures. Review named devices and manage devices in Xcode; do not treat the parent as a cache.")
            let devicePath = SimulatorLocations.deviceRoot(path) ?? path
            let plist = URL(fileURLWithPath: devicePath).appendingPathComponent("device.plist")
            if readMetadata, let data = MetadataReader.data(plist.path, preferences: preferences), let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                if let name = info["name"] as? String { p.name = path == devicePath ? name : name + " · " + url.lastPathComponent; p.evidence.append(Evidence(label: "Device name", value: name, level: .observed, source: plist.path)) }
                if let runtime = info["runtime"] as? String { p.evidence.append(Evidence(label: "Runtime", value: runtime, level: .observed, source: plist.path)) }
                if let state = info["state"] { p.evidence.append(Evidence(label: "Stored device state", value: String(describing: state), level: .observed, source: "device.plist; not a live boot-state check")) }
            }
        } else if path.contains("/iOS DeviceSupport/") {
            assign(.debugSymbols, url.lastPathComponent, "Xcode", "Debugging support for the device and OS version named by this directory.", "Old crash reports may need these symbols. A newer folder does not prove this version is unused.")
        } else if containsPath(home + "/.codex/backups", path) {
            assign(.backup, url.lastPathComponent + " recovery backup", "Codex workspace", "Recovery copy associated with Codex. Its contents and creation process have not been independently verified.", "Preserve unless another complete recovery copy has been verified. Uncommitted source and device saves may be unique.")
        } else if containsPath(home + "/.codex/scratch", path) && path != home + "/.codex/scratch" {
            if url.lastPathComponent.lowercased().contains("backup") {
                assign(.backup, url.lastPathComponent, "Codex scratch", "A backup a Codex task saved, such as app data copied off a device.", "It may be the only copy. Check you have these files elsewhere first.")
            } else {
                assign(.workspace, url.lastPathComponent, "Codex scratch", "Left behind by a Codex task: builds, downloads, logs or test copies.", "Codex doesn't clean these up. Look for files you made by hand before removing it.")
            }
        } else if containsPath(home + "/.ollama/models", path) {
            assign(.model, "Ollama models", "Ollama", "Language models downloaded with Ollama.", "Removing a model means downloading it again to use it.")
        } else if containsPath(home + "/.diffusionbee", path) {
            assign(.model, "DiffusionBee models & images", "DiffusionBee", "Image models downloaded by DiffusionBee, and the pictures it made.", "Models can be downloaded again; pictures you made may be your only copy.")
        } else if containsPath(home + "/.android/avd", path) && path != home + "/.android/avd" {
            let device = url.lastPathComponent.replacingOccurrences(of: ".avd", with: "").replacingOccurrences(of: "_", with: " ")
            assign(.virtualMachine, device + " emulator", "Android Emulator", "A virtual Android device: its system disk, installed apps, data and snapshots.", "Removing it deletes the apps and data inside. Delete it in Android Studio's Device Manager.")
        } else if containsPath(home + "/.codex/sessions", path) {
            assign(.history, "Codex conversation history", "Codex", "Persistent conversation records; not a disposable compilation cache.", "Removing these records loses conversation history.")
        } else if path.contains("/.cache/huggingface") || path.contains("/.cache/lm-studio") {
            let app = path.contains("huggingface") ? "Hugging Face ecosystem" : "LM Studio"
            assign(.model, app + " downloads", app, "Models, datasets or runtime assets may be downloaded here.", "Review individual models and offline needs. Downloads may be large or unavailable later.")
        } else if path.hasSuffix("/android/app/.cxx") || path.contains("/android/app/.cxx/") {
            recognizedRoot = String(path[..<path.range(of: "/android/app/.cxx")!.upperBound])
            assign(.buildOutput, "Android native compiler cache", "Gradle / CMake", "Generated native compilation output in an Android project.", "Recompilation may be expensive. Wait for builds to finish; folder structure alone does not prove inactivity.")
        } else if path.hasSuffix("/android/app/build/intermediates") || path.contains("/android/app/build/intermediates/") {
            recognizedRoot = String(path[..<path.range(of: "/android/app/build/intermediates")!.upperBound])
            assign(.buildOutput, "Android build intermediates", "Android Gradle tooling", "Intermediate compilation and packaging data, separate from normal project source.", "Subsequent builds recreate intermediate output. Preserve any deliberately saved diagnostics you still need.")
        } else if containsPath(home + "/Library/Developer/Xcode/DerivedData", path) {
            recognizedRoot = home + "/Library/Developer/Xcode/DerivedData"
            assign(.buildOutput, "Xcode DerivedData", "Xcode", "Compiler output, indexes and test results.", "Rebuilds and reindexing take time; test results may be evidence worth retaining.")
        } else {
            let cacheRules: [(String,String,String)] = [
                (".cache/uv", "Python uv cache", "uv"), (".npm/_cacache", "npm download cache", "npm"),
                (".npm/_npx", "npx tool installations", "npm / npx"), (".gradle/caches", "Gradle cache", "Gradle"),
                ("Library/Caches/pip", "pip download cache", "pip"), ("Library/Caches/Homebrew", "Homebrew downloads", "Homebrew"),
                ("Library/Caches/Yarn", "Yarn download cache", "Yarn"), ("Library/Caches/ms-playwright", "Playwright browsers", "Playwright")]
            if let rule = cacheRules.first(where: { containsPath(home + "/" + $0.0, path) }) {
                recognizedRoot = home + "/" + rule.0
                assign(.packageCache, rule.1, rule.2, "Downloaded dependencies or generated package assets in a recognized tool cache.", "Future commands may require fresh downloads or rebuilds. Avoid manual changes while the tool is running.")
            } else if containsPath(home + "/Downloads", path) {
                assign(.download, "Downloads · " + url.lastPathComponent, "Multiple applications", "Downloaded files may include installers, documents and unique user data.", "Review each item; being in Downloads does not establish that another copy exists.")
            } else if containsPath(home + "/Parallels", path) {
                assign(.virtualMachine, url.deletingPathExtension().lastPathComponent + " virtual machine", "Parallels Desktop", "A whole virtual computer: its disk, memory image and snapshots.", "Removing it deletes everything inside the virtual machine. Use Parallels Desktop to reclaim space or remove it.")
            } else if containsPath(home + "/Library/Containers/com.docker.docker/Data/vms", path) {
                assign(.virtualMachine, "Docker Desktop disk", "Docker Desktop", "The disk image that holds every Docker image, container and volume.", "Removing it deletes all containers, images and volumes. Clean up inside Docker Desktop instead.")
            } else if containsPath(home + "/Library/Containers/com.utmapp.UTM/Data/Documents", path) {
                assign(.virtualMachine, url.deletingPathExtension().lastPathComponent + " virtual machine", "UTM", "A whole virtual computer and its disks.", "Removing it deletes everything inside the virtual machine. Remove it inside UTM.")
            } else if path.contains("/Library/Application Support/") {
                let app = String(path.components(separatedBy: "/Library/Application Support/")[1].split(separator: "/").first ?? "Unknown")
                assign(.appData, app + " data", app, "Data stored beneath the application's support directory. May include preferences, libraries, databases and saves.", "Preserve by default. Use the application's content management where appropriate.")
            } else if containsPath(home + "/.codex", path) || containsPath(home + "/GitHub", path) || containsPath(home + "/Documents/Codex", path) {
                assign(.workspace, url.lastPathComponent, path.contains("/.codex/") || path.contains("/Documents/Codex") ? "Codex workspace" : "Development tools", "Mixed working directory. Build output, patches, private inputs and diagnostics can coexist here.", "Inspect child folders and provenance. Never treat an entire workspace as disposable based on its name.")
            }
        }
        for root in [home + "/.codex/worktrees", home + "/GitHub"] where containsPath(root, path) && path != root {
            let relative = String(path.dropFirst(root.count + 1))
            let projectFolder = String(relative.split(separator: "/").first ?? "")
            guard !projectFolder.isEmpty else { continue }
            p.project = projectFolder
            let gitFile = URL(fileURLWithPath: root + "/" + projectFolder + "/.git")
            if readMetadata, let data = MetadataReader.data(gitFile.path, preferences: preferences), let text = String(data: data, encoding: .utf8), text.hasPrefix("gitdir:"), let boundary = text.range(of: "/.git/worktrees/") {
                let repoPath = String(text[..<boundary.lowerBound]).replacingOccurrences(of: "gitdir:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                // A worktree is named for its own folder; the repository it came from is evidence.
                p.evidence.append(Evidence(label: "Repository", value: repoPath, level: .observed, source: gitFile.path))
            }
            p.evidence.append(Evidence(label: "Workspace", value: projectFolder, level: .observed, source: "Path component; not proof of the process that wrote its contents"))
            if p.category == .buildOutput { p.name = (p.project ?? projectFolder) + " · " + p.name }
        }
        if readMetadata, let container = SimulatorLocations.containerRoot(path) {
            let metadata = container.path + "/.com.apple.mobile_container_manager.metadata.plist"
            if let data = MetadataReader.data(metadata, preferences: preferences),
               let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let identifier = info["MCMMetadataIdentifier"] as? String, !identifier.isEmpty {
                p.name = identifier + " · " + container.kind
                if path != container.path { p.name += " / " + URL(fileURLWithPath: path).lastPathComponent }
                p.associatedApp = identifier
                p.explanation = "Simulator \(container.kind) identified by local container metadata. App data and shared groups can hold saves, databases and test fixtures. An identifier does not establish the historical writer."
                p.evidence.append(Evidence(label: "Container identifier", value: identifier, level: .observed, source: metadata))
                p.evidence.append(Evidence(label: "Container role", value: container.kind, level: .inferred, source: "CoreSimulator container directory structure"))
            }
        }
        p.evidence.append(Evidence(label: "Historical writer", value: "Not recorded", level: .unknown, source: "Path classification and open handles cannot establish past writes."))
        return p
    }
}

// Read only small, known metadata files. Never follow a symlink or read excluded metadata.
struct MetadataReader {
    static func hasNoSymlinkComponents(_ path: String) -> Bool {
        var current = ""
        for component in normalized(path).split(separator: "/") {
            current += "/" + component
            var st = stat()
            guard lstat(current, &st) == 0, (st.st_mode & S_IFMT) != S_IFLNK else { return false }
        }
        return true
    }
    static func data(_ path: String, preferences: Preferences) -> Data? {
        guard !preferences.excluded(path) else { return nil }
        guard hasNoSymlinkComponents(path) else { return nil }
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var st = stat()
        guard fstat(descriptor, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_size <= 1_048_576 else { return nil }
        var bytes = [UInt8](repeating: 0, count: 1_048_577), used = 0
        while used < bytes.count {
            let remaining = bytes.count - used
            let count = bytes.withUnsafeMutableBytes { read(descriptor, $0.baseAddress!.advanced(by: used), remaining) }
            if count == 0 { break }; if count < 0 { return nil }; used += count
        }
        guard used <= 1_048_576 else { return nil }
        return Data(bytes.prefix(used))
    }
}
