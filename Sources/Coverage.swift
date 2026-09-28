import Foundation

/// Declared, hard-coded coverage: every place the app knows a tool writes to. Discovery reads this
/// catalog; the Coverage settings tab shows it. Adding a writer means adding one entry here.
struct CoverageEntry: Identifiable, Hashable {
    enum Kind: String { case folder = "Folder", children = "Each child folder", projects = "Each project's build folders" }
    var id: String { relativePath }
    var writer: String
    var relativePath: String
    var kind: Kind
    var category: FolderCategory
    var writes: String
    func path(home: String) -> String { home + "/" + relativePath }
}

enum Coverage {
    static let projectSuffixes = ["android/app/.cxx", "android/app/build/intermediates", "build", "generated", "work"]
    static let entries: [CoverageEntry] = [
        CoverageEntry(writer: "Codex", relativePath: ".codex/sessions", kind: .folder, category: .history, writes: "Conversation transcripts and tool output for every Codex session."),
        CoverageEntry(writer: "Codex", relativePath: ".codex/backups", kind: .children, category: .backup, writes: "Recovery copies of worktrees taken before risky operations."),
        CoverageEntry(writer: "Codex", relativePath: ".codex/tasks", kind: .children, category: .workspace, writes: "Per-task scratch folders, downloads and generated files."),
        CoverageEntry(writer: "Codex", relativePath: ".codex/worktrees", kind: .projects, category: .workspace, writes: "Isolated Git checkouts; their build, generated and work folders are measured individually."),
        CoverageEntry(writer: "Codex", relativePath: "Documents/Codex", kind: .folder, category: .workspace, writes: "Task outputs, reports and files mentioned in conversations."),
        CoverageEntry(writer: "Codex", relativePath: "Library/Application Support/Codex", kind: .folder, category: .appData, writes: "App state, caches and local databases."),
        CoverageEntry(writer: "Claude", relativePath: "Library/Application Support/Claude", kind: .folder, category: .appData, writes: "App state, caches and local databases."),
        CoverageEntry(writer: "Your projects", relativePath: "GitHub", kind: .projects, category: .workspace, writes: "Build output, generated files and work folders inside each repository."),
        CoverageEntry(writer: "Xcode", relativePath: "Library/Developer/Xcode/DerivedData", kind: .folder, category: .buildOutput, writes: "Compiled intermediates, indexes and build products for every project you open."),
        CoverageEntry(writer: "Xcode", relativePath: "Library/Developer/Xcode/iOS DeviceSupport", kind: .children, category: .debugSymbols, writes: "Symbol files copied from each connected device and OS version."),
        CoverageEntry(writer: "Simulator", relativePath: "Library/Developer/CoreSimulator/Devices", kind: .children, category: .simulator, writes: "One folder per virtual device: installed apps, their data, saves and photos."),
        CoverageEntry(writer: "CoreDevice", relativePath: "Library/Containers/com.apple.CoreDevice.CoreDeviceService/Data/Library/Caches/AppInstallationBinaryDeltas", kind: .children, category: .installCache, writes: "Binary deltas cached when installing apps on physical iPhones and iPads."),
        CoverageEntry(writer: "npm", relativePath: ".npm/_cacache", kind: .folder, category: .packageCache, writes: "Downloaded package tarballs and metadata."),
        CoverageEntry(writer: "npm", relativePath: ".npm/_npx", kind: .folder, category: .packageCache, writes: "Temporary installs made by npx."),
        CoverageEntry(writer: "pip", relativePath: "Library/Caches/pip", kind: .folder, category: .packageCache, writes: "Downloaded wheels and HTTP cache."),
        CoverageEntry(writer: "uv", relativePath: ".cache/uv", kind: .folder, category: .packageCache, writes: "Python package archives and built wheels."),
        CoverageEntry(writer: "Gradle", relativePath: ".gradle/caches", kind: .folder, category: .packageCache, writes: "Dependency jars, transforms and build caches for Android projects."),
        CoverageEntry(writer: "Homebrew", relativePath: "Library/Caches/Homebrew", kind: .folder, category: .packageCache, writes: "Downloaded bottles and casks."),
        CoverageEntry(writer: "Yarn", relativePath: "Library/Caches/Yarn", kind: .folder, category: .packageCache, writes: "Downloaded package archives."),
        CoverageEntry(writer: "Playwright", relativePath: "Library/Caches/ms-playwright", kind: .folder, category: .packageCache, writes: "Downloaded browser builds for automated testing."),
        CoverageEntry(writer: "Hugging Face", relativePath: ".cache/huggingface", kind: .folder, category: .model, writes: "Downloaded models and datasets."),
        CoverageEntry(writer: "LM Studio", relativePath: ".cache/lm-studio", kind: .folder, category: .model, writes: "Downloaded language models."),
        CoverageEntry(writer: "Steam", relativePath: "Library/Application Support/Steam", kind: .folder, category: .appData, writes: "Installed games, shader caches and downloads."),
        CoverageEntry(writer: "CrossOver", relativePath: "Library/Application Support/CrossOver", kind: .folder, category: .appData, writes: "Windows bottles with their installed programs and saves."),
        CoverageEntry(writer: "OpenEmu", relativePath: "Library/Application Support/OpenEmu", kind: .folder, category: .appData, writes: "Game library, save states and screenshots."),
        CoverageEntry(writer: "You", relativePath: "Downloads", kind: .folder, category: .download, writes: "Installers, archives and documents saved by browsers and other apps."),
    ]
    /// What the app deliberately does not scan, stated so the boundary is explicit.
    static let notScanned: [String] = [
        "System files and the macOS installation (/System, /Library, /private).",
        "Other users' home folders.",
        "Photos, Mail, Messages and iCloud Drive libraries.",
        "Time Machine local snapshots and purgeable space managed by macOS.",
        "Any folder you exclude, and anything inside it.",
        "Symbolic links and other volumes reached through a parent folder.",
    ]
    static func presence(_ entry: CoverageEntry, home: String) -> Bool {
        var st = stat()
        return lstat(entry.path(home: home), &st) == 0
    }
}
