import Foundation

/// Declared, hard-coded coverage: every place the app knows a tool writes to. Discovery reads this
/// catalog; the Coverage settings tab shows it. Adding a writer means adding one entry here.
struct CoverageEntry: Identifiable, Hashable {
    enum Kind: String {
        case folder = "Folder", children = "Each child folder", projects = "Each project's build folders"
        /// Each child folder whole, plus the build, generated and work folders of the repository in it.
        case workspaces = "Each folder, and its build and work folders"
    }
    var id: String { relativePath }
    var writer: String
    /// Under your home folder, or an absolute path such as your temporary folder.
    var relativePath: String
    var kind: Kind
    var category: FolderCategory
    var writes: String
    /// Short label shown after the app name, e.g. "Codex · Conversations".
    var name: String
    var group: CoverageGroup
    func path(home: String) -> String { relativePath.hasPrefix("/") ? relativePath : home + "/" + relativePath }
    /// The path as you'd type it: ~/.codex/worktrees, or the full path outside your home folder.
    var shownPath: String { relativePath.hasPrefix("/") ? relativePath : "~/" + relativePath }
}

enum CoverageGroup: String, CaseIterable, Identifiable {
    case ai = "AI tools", developer = "Developer tools", virtual = "Virtual machines", games = "Games & emulators", downloads = "Downloads"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .ai: return "sparkles"
        case .developer: return "hammer"
        case .virtual: return "desktopcomputer"
        case .games: return "gamecontroller"
        case .downloads: return "arrow.down.circle"
        }
    }
}

enum CoveragePresence {
    case present, missing, unavailable
    var label: String {
        switch self { case .present: return "Present"; case .missing: return "Not on this Mac"; case .unavailable: return "Could not check" }
    }
}

enum Coverage {
    static let projectSuffixes = ["android/app/.cxx", "android/app/build/intermediates", "build", "generated", "work"]
    /// Your own temporary folder (\$TMPDIR), where apps and command-line tools leave work files. Resolved, without symbolic links.
    static let temporaryFolder: String? = {
#if DEMO
        if let demo = ProcessInfo.processInfo.environment["CC_DEMO_HOME"] { return demo + "/TemporaryItems" }
#endif
        guard let real = realpath(NSTemporaryDirectory(), nil) else { return nil }
        defer { free(real) }
        return String(cString: real)
    }()
    static let entries: [CoverageEntry] = [
        CoverageEntry(writer: "Codex", relativePath: ".codex/sessions", kind: .folder, category: .history, writes: "Conversation transcripts and tool output for every Codex session.", name: "Conversations", group: .ai),
        CoverageEntry(writer: "Codex", relativePath: ".codex/backups", kind: .children, category: .backup, writes: "Recovery copies of worktrees taken before risky operations.", name: "Recovery copies", group: .ai),
        CoverageEntry(writer: "Codex", relativePath: ".codex/tasks", kind: .workspaces, category: .workspace, writes: "Per-task scratch folders, downloads and generated files.", name: "Task folders", group: .ai),
        CoverageEntry(writer: "Codex", relativePath: ".codex/worktrees", kind: .workspaces, category: .workspace, writes: "Isolated Git checkouts, one per task, measured whole and with their build, generated and work folders.", name: "Worktrees", group: .ai),
        CoverageEntry(writer: "Codex", relativePath: ".codex/scratch", kind: .children, category: .workspace, writes: "Scratch space Codex tasks leave behind: builds, downloads, logs, test copies and device backups.", name: "Scratch", group: .ai),
        CoverageEntry(writer: "Codex", relativePath: "Documents/Codex", kind: .children, category: .workspace, writes: "Task outputs, reports and files mentioned in conversations.", name: "Task outputs", group: .ai),
        CoverageEntry(writer: "Codex", relativePath: "Library/Application Support/Codex", kind: .folder, category: .appData, writes: "App state, caches and local databases.", name: "App data", group: .ai),
        CoverageEntry(writer: "Claude", relativePath: "Library/Application Support/Claude", kind: .folder, category: .appData, writes: "App state, caches and local databases.", name: "App data", group: .ai),
        CoverageEntry(writer: "Your projects", relativePath: "GitHub", kind: .projects, category: .workspace, writes: "Build output, generated files and work folders inside each repository.", name: "Build folders", group: .developer),
        CoverageEntry(writer: "Xcode", relativePath: "Library/Developer/Xcode/DerivedData", kind: .folder, category: .buildOutput, writes: "Compiled intermediates, indexes and build products for every project you open.", name: "Build data", group: .developer),
        CoverageEntry(writer: "Xcode", relativePath: "Library/Developer/Xcode/iOS DeviceSupport", kind: .children, category: .debugSymbols, writes: "Symbol files copied from each connected device and OS version.", name: "Device support files", group: .developer),
        CoverageEntry(writer: "Simulator", relativePath: "Library/Developer/CoreSimulator/Devices", kind: .children, category: .simulator, writes: "One folder per virtual device: installed apps, their data, saves and photos.", name: "Test devices", group: .developer),
        CoverageEntry(writer: "CoreDevice", relativePath: "Library/Containers/com.apple.CoreDevice.CoreDeviceService/Data/Library/Caches/AppInstallationBinaryDeltas", kind: .children, category: .installCache, writes: "Binary deltas cached when installing apps on physical iPhones and iPads.", name: "Install cache", group: .developer),
        CoverageEntry(writer: "npm", relativePath: ".npm/_cacache", kind: .folder, category: .packageCache, writes: "Downloaded package tarballs and metadata.", name: "Package cache", group: .developer),
        CoverageEntry(writer: "Parallels", relativePath: "Parallels", kind: .children, category: .virtualMachine, writes: "Virtual machines: each .pvm holds a whole computer's disk and snapshots.", name: "Virtual machines", group: .virtual),
        CoverageEntry(writer: "Docker", relativePath: "Library/Containers/com.docker.docker/Data/vms", kind: .folder, category: .virtualMachine, writes: "The disk image holding Docker images, containers and volumes.", name: "Docker disk", group: .virtual),
        CoverageEntry(writer: "UTM", relativePath: "Library/Containers/com.utmapp.UTM/Data/Documents", kind: .children, category: .virtualMachine, writes: "Virtual machines created in UTM.", name: "Virtual machines", group: .virtual),
        CoverageEntry(writer: "npm", relativePath: ".npm/_npx", kind: .folder, category: .packageCache, writes: "Temporary installs made by npx.", name: "npx installs", group: .developer),
        CoverageEntry(writer: "pip", relativePath: "Library/Caches/pip", kind: .folder, category: .packageCache, writes: "Downloaded wheels and HTTP cache.", name: "Package cache", group: .developer),
        CoverageEntry(writer: "uv", relativePath: ".cache/uv", kind: .folder, category: .packageCache, writes: "Python package archives and built wheels.", name: "Package cache", group: .developer),
        CoverageEntry(writer: "Gradle", relativePath: ".gradle/caches", kind: .folder, category: .packageCache, writes: "Dependency jars, transforms and build caches for Android projects.", name: "Build cache", group: .developer),
        CoverageEntry(writer: "Homebrew", relativePath: "Library/Caches/Homebrew", kind: .folder, category: .packageCache, writes: "Downloaded bottles and casks.", name: "Downloads", group: .developer),
        CoverageEntry(writer: "Yarn", relativePath: "Library/Caches/Yarn", kind: .folder, category: .packageCache, writes: "Downloaded package archives.", name: "Package cache", group: .developer),
        CoverageEntry(writer: "Playwright", relativePath: "Library/Caches/ms-playwright", kind: .folder, category: .packageCache, writes: "Downloaded browser builds for automated testing.", name: "Browsers", group: .developer),
        CoverageEntry(writer: "Hugging Face", relativePath: ".cache/huggingface", kind: .folder, category: .model, writes: "Downloaded models and datasets.", name: "Models & datasets", group: .ai),
        CoverageEntry(writer: "Ollama", relativePath: ".ollama/models", kind: .folder, category: .model, writes: "Downloaded language models.", name: "Models", group: .ai),
        CoverageEntry(writer: "DiffusionBee", relativePath: ".diffusionbee", kind: .folder, category: .model, writes: "Image models and the pictures it made.", name: "Models & images", group: .ai),
        CoverageEntry(writer: "Android Emulator", relativePath: ".android/avd", kind: .children, category: .virtualMachine, writes: "Virtual Android devices: each holds a system disk, app data and snapshots.", name: "Virtual devices", group: .virtual),
        CoverageEntry(writer: "LM Studio", relativePath: ".cache/lm-studio", kind: .folder, category: .model, writes: "Downloaded language models.", name: "Models", group: .ai),
        CoverageEntry(writer: "Steam", relativePath: "Library/Application Support/Steam", kind: .folder, category: .appData, writes: "Installed games, shader caches and downloads.", name: "Games & downloads", group: .games),
        CoverageEntry(writer: "CrossOver", relativePath: "Library/Application Support/CrossOver", kind: .folder, category: .appData, writes: "Windows bottles with their installed programs and saves.", name: "Windows bottles", group: .games),
        CoverageEntry(writer: "OpenEmu", relativePath: "Library/Application Support/OpenEmu", kind: .folder, category: .appData, writes: "Game library, save states and screenshots.", name: "Game library", group: .games),
        CoverageEntry(writer: "You", relativePath: "Downloads", kind: .folder, category: .download, writes: "Installers, archives and documents saved by browsers and other apps.", name: "Downloads folder", group: .downloads),
    ] + (temporaryFolder.map { [CoverageEntry(writer: "Apps and tools", relativePath: $0, kind: .folder, category: .temporary, writes: "Work files apps and command-line tools leave behind: build trees, traces, unpacked downloads. macOS clears what nothing has used for 3 days, but not always.", name: "Temporary files", group: .developer)] } ?? [])
    /// What the app deliberately does not scan, stated so the boundary is explicit.
    static let notScanned: [String] = [
        "System files and the macOS installation (/System, /Library, /private).",
        "Other users' home folders.",
        "Photos, Mail, Messages and iCloud Drive libraries.",
        "Time Machine local snapshots and purgeable space managed by macOS.",
        "Any folder you exclude, and anything inside it.",
        "Symbolic links and other volumes reached through a parent folder.",
    ]
    static func presence(_ entry: CoverageEntry, home: String) -> CoveragePresence {
        var st = stat()
        if lstat(entry.path(home: home), &st) == 0 { return .present }
        return errno == ENOENT || errno == ENOTDIR ? .missing : .unavailable
    }
}
