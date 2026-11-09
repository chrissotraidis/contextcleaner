# Context Cleaner for Windows: scanning, answers and the Recycle Bin plan.
# Reads sizes and dates only. Nothing here deletes, moves or changes a file.
# Runs on Windows PowerShell 5.1, which every Windows 10 and 11 has, and on PowerShell 7.

$script:CCVersion = '0.1.0'
$script:CCHome = [Environment]::GetFolderPath('UserProfile')
$script:CCLocal = [Environment]::GetFolderPath('LocalApplicationData')
$script:CCRoaming = [Environment]::GetFolderPath('ApplicationData')
$script:CCTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
# Scans, plans, settings and History. CONTEXT_CLEANER_DATA points tests at a throwaway folder.
$script:CCData = if ($env:CONTEXT_CLEANER_DATA) { $env:CONTEXT_CLEANER_DATA } else { Join-Path $script:CCLocal 'Context Cleaner' }
$script:CCDrive = [IO.Path]::GetPathRoot($script:CCHome)
$script:CCApp = $PSScriptRoot
$script:NL = [Environment]::NewLine

$script:Answers = @{
    Safe = 'Safe to remove'; Rebuildable = 'Rebuildable'; Review = 'Review first'
    Keep = 'Not for the Recycle Bin'; Other = 'Everything else'
}
$script:AnswerOrder = @('Safe to remove', 'Rebuildable', 'Review first', 'Not for the Recycle Bin', 'Everything else')

# Places Context Cleaner knows, in groups you can turn off in Settings.
$script:Coverage = [ordered]@{
    codex     = @('Codex', 'Conversations, task folders, worktrees, old runtimes and the app''s data')
    claude    = @('Claude', 'Claude and Claude Code data and history')
    models    = @('AI models', 'Hugging Face, Ollama and LM Studio downloads')
    projects  = @('Project build folders', 'Build output and worktrees in folders that hold git repositories')
    caches    = @('Package caches', 'npm, pnpm, Yarn, Bun, pip, uv, NuGet, Gradle, Cargo, Go, Playwright, Electron')
    android   = @('Android SDK', 'Emulator system images, NDKs and virtual devices')
    temp      = @('Temporary files', 'Big items in your Temp folder')
    gpu       = @('Shader caches', 'DirectX, NVIDIA and AMD shader caches')
    crash     = @('Crash dumps', 'Crash dumps and error reports programs leave behind')
    downloads = @('Downloads', 'Big items in your Downloads folder')
    vms       = @('WSL and Docker', 'Linux distributions and Docker Desktop disks')
    games     = @('Steam games', 'Every game in every Steam library')
    windows   = @('Windows', 'Page and hibernation files, Windows Update downloads, Windows.old')
}

$CCSource = @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace ContextCleaner {
    public sealed class Measurement {
        public string Path; public bool Exists; public bool Link;
        public long Bytes; public long SharedBytes; public long Files; public long CloudOnly; public long Unreadable;
        public DateTime? Latest;
    }

    // Sizes and dates only. Written for .NET Framework 4.8 (Windows PowerShell 5.1) and .NET 8+ (PowerShell 7).
    public static class Disk {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct FindData {
            public uint Attributes;
            public uint CreatedLow, CreatedHigh, AccessedLow, AccessedHigh, WrittenLow, WrittenHigh;
            public uint SizeHigh, SizeLow, Reserved0, Reserved1;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string Name;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 14)] public string ShortName;
            public uint FileType, CreatorType; public ushort FinderFlags;
        }
        [StructLayout(LayoutKind.Sequential)]
        struct HandleInfo {
            public uint Attributes;
            public uint CreatedLow, CreatedHigh, AccessedLow, AccessedHigh, WrittenLow, WrittenHigh;
            public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
        }
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern IntPtr FindFirstFileExW(string name, int infoLevel, out FindData data, int searchOp, IntPtr filter, int flags);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern bool FindNextFileW(IntPtr handle, out FindData data);
        [DllImport("kernel32.dll")] static extern bool FindClose(IntPtr handle);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern uint GetCompressedFileSizeW(string name, out uint high);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern IntPtr CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetFileInformationByHandle(IntPtr handle, out HandleInfo info);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern uint GetLongPathNameW(string shortPath, StringBuilder longPath, uint size);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern uint GetFileAttributesW(string name);

        const uint Directory = 0x10, Reparse = 0x400, Compressed = 0x800, Sparse = 0x200;
        // Offline, RecallOnOpen and RecallOnDataAccess: kept only in the cloud, so it takes no space here.
        const uint CloudOnly = 0x1000 | 0x40000 | 0x400000;
        const uint TagSymlink = 0xA000000C, TagMountPoint = 0xA0000003;
        static readonly IntPtr Invalid = new IntPtr(-1);
        // A hardlinked file is freed only when its last name goes. Only big files are checked; opening every file is slow.
        const long LinkCheckMinimum = 8L * 1024 * 1024;

        public static long FilesRead;
        public static volatile bool Cancel;

        static string Long(string path) { return path.StartsWith(@"\\") ? path : @"\\?\" + path; }
        static long Ticks(uint low, uint high) { return DateTime.FromFileTimeUtc(((long)high << 32) | low).Ticks; }

        static long OnDisk(string full, uint attributes, long length) {
            if ((attributes & (Compressed | Sparse | Reparse)) == 0) return length;
            uint high; uint low = GetCompressedFileSizeW(Long(full), out high);
            if (low == 0xFFFFFFFF && Marshal.GetLastWin32Error() != 0) return length;
            return ((long)high << 32) | low;
        }
        static uint Links(string full) {
            IntPtr handle = CreateFileW(Long(full), 0, 7, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero);
            if (handle == Invalid) return 1;
            try { HandleInfo info; return GetFileInformationByHandle(handle, out info) ? info.Links : 1; }
            finally { CloseHandle(handle); }
        }

        public static Measurement Measure(string path, ISet<string> skip) {
            var m = new Measurement { Path = path };
            uint rootAttributes = GetFileAttributesW(Long(path));
            if (rootAttributes == 0xFFFFFFFF) return m;
            m.Exists = true;
            if ((rootAttributes & Reparse) != 0 && (rootAttributes & Directory) != 0) { m.Link = true; return m; }
            if ((rootAttributes & Directory) == 0) {
                FindData single; IntPtr h = FindFirstFileExW(Long(path), 1, out single, 0, IntPtr.Zero, 0);
                if (h == Invalid) { m.Unreadable++; return m; }
                FindClose(h);
                if ((single.Attributes & Reparse) != 0 && (single.Reserved0 == TagSymlink || single.Reserved0 == TagMountPoint)) { m.Link = true; return m; }
                long size = OnDisk(path, single.Attributes, ((long)single.SizeHigh << 32) | single.SizeLow);
                if (size >= LinkCheckMinimum && Links(path) > 1) m.SharedBytes = size; else m.Bytes = size;
                m.Files = 1;
                m.Latest = new DateTime(Math.Max(Ticks(single.WrittenLow, single.WrittenHigh), Ticks(single.CreatedLow, single.CreatedHigh)), DateTimeKind.Utc);
                return m;
            }
            // The folder's own date counts too, so an empty folder still has one.
            long latest = 0;
            try { latest = Math.Max(System.IO.Directory.GetLastWriteTimeUtc(path).Ticks, System.IO.Directory.GetCreationTimeUtc(path).Ticks); } catch { }
            var stack = new Stack<string>();
            stack.Push(path.TrimEnd('\\'));
            while (stack.Count > 0) {
                if (Cancel) break;
                string dir = stack.Pop();
                FindData data;
                // FindExInfoBasic, FIND_FIRST_EX_LARGE_FETCH
                IntPtr handle = FindFirstFileExW(Long(dir) + @"\*", 1, out data, 0, IntPtr.Zero, 2);
                if (handle == Invalid) { m.Unreadable++; continue; }
                try {
                    do {
                        string name = data.Name;
                        if (name == "." || name == "..") continue;
                        string full = dir + "\\" + name;
                        uint a = data.Attributes;
                        long changed = Math.Max(Ticks(data.WrittenLow, data.WrittenHigh), Ticks(data.CreatedLow, data.CreatedHigh));
                        if ((a & Directory) != 0) {
                            if ((a & Reparse) != 0) continue;
                            if (skip != null && skip.Contains(full)) continue;
                            if (changed > latest) latest = changed;
                            stack.Push(full);
                        } else {
                            if (skip != null && skip.Contains(full)) continue;
                            if ((a & CloudOnly) != 0) { m.CloudOnly++; continue; }
                            if ((a & Reparse) != 0 && (data.Reserved0 == TagSymlink || data.Reserved0 == TagMountPoint)) continue;
                            long size = OnDisk(full, a, ((long)data.SizeHigh << 32) | data.SizeLow);
                            if (size >= LinkCheckMinimum && Links(full) > 1) m.SharedBytes += size; else m.Bytes += size;
                            m.Files++;
                            if (changed > latest) latest = changed;
                            Interlocked.Increment(ref FilesRead);
                        }
                    } while (FindNextFileW(handle, out data));
                } finally { FindClose(handle); }
            }
            if (latest > 0) m.Latest = new DateTime(latest, DateTimeKind.Utc);
            return m;
        }

        public static Measurement[] MeasureAll(string[] paths, string[] skip) {
            var set = new HashSet<string>(skip ?? new string[0], StringComparer.OrdinalIgnoreCase);
            var results = new Measurement[paths.Length];
            Parallel.For(0, paths.Length, new ParallelOptions { MaxDegreeOfParallelism = 8 }, i => { results[i] = Measure(paths[i], set); });
            return results;
        }

        // The full, long form of a path: C:\Users\you\DOCUME~1 becomes C:\Users\you\Documents.
        public static string LongPath(string path) {
            var buffer = new StringBuilder(32768);
            uint length = GetLongPathNameW(path, buffer, (uint)buffer.Capacity);
            return length > 0 && length < buffer.Capacity ? buffer.ToString() : path;
        }
        // True when the path or any folder above it is a link or junction, so the path may lead somewhere else.
        public static bool ThroughLink(string path) {
            string current = path.TrimEnd('\\');
            while (current.Length > 3) {
                uint a = GetFileAttributesW(Long(current));
                if (a != 0xFFFFFFFF && (a & Reparse) != 0) return true;
                int slash = current.LastIndexOf('\\');
                if (slash < 3) break;
                current = current.Substring(0, slash);
            }
            return false;
        }
    }

    public static class RecycleBin {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct FileOp {
            public IntPtr hwnd; public uint wFunc; public string pFrom; public string pTo; public ushort fFlags;
            [MarshalAs(UnmanagedType.Bool)] public bool fAnyOperationsAborted; public IntPtr hNameMappings; public string lpszProgressTitle;
        }
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern int SHFileOperationW(ref FileOp op);
        // Move to the Recycle Bin (FOF_ALLOWUNDO) without the "are you sure" prompt, with Windows' own warning when
        // something is too big for the bin and would be deleted for good (FOF_WANTNUKEWARNING).
        public static int Send(string path) {
            var op = new FileOp { wFunc = 3, pFrom = path + "\0\0", fFlags = 0x0040 | 0x0010 | 0x4000 | 0x0004 };
            int result = SHFileOperationW(ref op);
            return result != 0 ? result : (op.fAnyOperationsAborted ? -1 : 0);
        }
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern int SHQueryRecycleBinW(string root, IntPtr info);
        // What the Recycle Bin on this drive holds now, or -1 when Windows can't say. The struct is packed
        // differently in 32- and 64-bit processes, so it is read by offset.
        public static long Bytes(string root) {
            bool wide = IntPtr.Size == 8; IntPtr info = Marshal.AllocHGlobal(24);
            try {
                Marshal.WriteInt32(info, 0, wide ? 24 : 20);
                return SHQueryRecycleBinW(root, info) == 0 ? Marshal.ReadInt64(info, wide ? 8 : 4) : -1;
            } finally { Marshal.FreeHGlobal(info); }
        }
    }

    public static class Shell {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern int SetCurrentProcessExplicitAppUserModelID(string id);
        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
        [StructLayout(LayoutKind.Sequential)] struct Margins { public int Left, Right, Top, Bottom; }
        [DllImport("dwmapi.dll")] static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref Margins margins);
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int command);
        public static void AppId(string id) { SetCurrentProcessExplicitAppUserModelID(id); }
        // Dark or light title bar (Windows 10 2004+). Returns true when Windows accepted it.
        public static bool DarkTitle(IntPtr hwnd, bool dark) { int v = dark ? 1 : 0; return DwmSetWindowAttribute(hwnd, 20, ref v, 4) == 0; }
        // Mica behind the window (Windows 11 22H2+). Returns true when Windows accepted it.
        public static bool Mica(IntPtr hwnd) {
            var margins = new Margins { Left = -1, Right = -1, Top = -1, Bottom = -1 };
            DwmExtendFrameIntoClientArea(hwnd, ref margins);
            int v = 2; return DwmSetWindowAttribute(hwnd, 38, ref v, 4) == 0;
        }
    }

    // The Vista-style folder picker. WPF on .NET Framework has none of its own.
    public static class FolderPicker {
        [ComImport, Guid("DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7")] class FileOpenDialogCom { }
        [ComImport, Guid("42f85136-db7e-439c-85f1-e4075d135fc8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IFileOpenDialog {
            [PreserveSig] int Show(IntPtr parent);
            void SetFileTypes(); void SetFileTypeIndex(); void GetFileTypeIndex(); void Advise(); void Unadvise();
            void SetOptions(uint options); void GetOptions(out uint options);
            void SetDefaultFolder(IShellItem item); void SetFolder(IShellItem item); void GetFolder(); void GetCurrentSelection();
            void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string name); void GetFileName();
            void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string title);
            void SetOkButtonLabel(); void SetFileNameLabel(); void GetResult(out IShellItem item);
        }
        [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IShellItem {
            void BindToHandler(); void GetParent();
            void GetDisplayName(uint type, [MarshalAs(UnmanagedType.LPWStr)] out string name);
            void GetAttributes(); void Compare();
        }
        public static string Pick(IntPtr owner, string title) {
            var dialog = (IFileOpenDialog)new FileOpenDialogCom();
            uint options; dialog.GetOptions(out options);
            dialog.SetOptions(options | 0x20 | 0x40); // FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM
            dialog.SetTitle(title);
            if (dialog.Show(owner) != 0) return null;
            IShellItem item; dialog.GetResult(out item);
            string path; item.GetDisplayName(0x80058000, out path); // SIGDN_FILESYSPATH
            return path;
        }
    }

    public sealed class Item : INotifyPropertyChanged {
        public string Path { get; set; }
        public string Name { get; set; }
        public string App { get; set; }
        public string Group { get; set; }
        public string Category { get; set; }
        public string Coverage { get; set; }
        public string Rule { get; set; }
        public string Answer { get; set; }
        public string Reason { get; set; }
        public string Explanation { get; set; }
        public string Consequence { get; set; }
        public string HowTo { get; set; }
        public string Evidence { get; set; }
        public string LookInside { get; set; }
        public string Action { get; set; }
        public string InUse { get; set; }
        public long Bytes { get; set; }
        public long SharedBytes { get; set; }
        public long Files { get; set; }
        public long Unreadable { get; set; }
        public long? Growth { get; set; }
        // When the scan Growth is measured against was taken, for example "Nov 7".
        public string GrowthSince { get; set; }
        public DateTime? Latest { get; set; }
        public bool Removable { get; set; }
        // Set when an item must never go in a command whatever its answer, such as a worktree git can't vouch for.
        public bool Withheld { get; set; }
        public double IdleDays { get { return Latest.HasValue ? (DateTime.UtcNow - Latest.Value).TotalDays : -1; } }
        public string SizeText { get { return Format.Bytes(Bytes); } }
        public string LatestText { get { return Format.Ago(Latest); } }
        // Growth you said is normal is not called growing.
        public bool Expected { get; set; }
        public bool Growing { get { return !Expected && Growth.HasValue && Growth.Value > Math.Max(256L * 1024 * 1024, (Bytes - Growth.Value) / 20); } }
        // Remind Me Tomorrow: not suggested until this time.
        public DateTime? Snoozed { get; set; }
        public bool IsSnoozed { get { return Snoozed.HasValue && Snoozed.Value > DateTime.UtcNow; } }
        string note;
        public string Note { get { return note; } set { if (note != value) { note = value; Changed("Note"); } } }
        // Changes under 1 MB are noise from logs and caches, so they aren't shown.
        public string GrowthText { get { return Growth.HasValue && Math.Abs(Growth.Value) >= 1048576 ? Format.Signed(Growth.Value) + " since " + (string.IsNullOrEmpty(GrowthSince) ? "the last scan" : GrowthSince) : ""; } }
        // The same change without the date, for narrow columns.
        public string GrowthShort { get { return Growth.HasValue && Math.Abs(Growth.Value) >= 1048576 ? Format.Signed(Growth.Value) : ""; } }
        public string AnswerKey {
            get {
                switch (Answer) {
                    case "Safe to remove": return "safe"; case "Rebuildable": return "rebuild"; case "Review first": return "review";
                    case "Not for the Recycle Bin": return "keep"; default: return "other";
                }
            }
        }
        // Second line under the name: what wrote it and what kind of thing it is.
        public string SubLine { get { return App == Category || string.IsNullOrEmpty(Category) ? App : App + " · " + Category; } }
        public string UntouchedText {
            get {
                if (!Latest.HasValue) return "last change unknown";
                double d = IdleDays;
                if (d < 1) return "changed today";
                if (d < 2) return "untouched 1 day";
                return "untouched " + ((int)d) + " days";
            }
        }
        bool selected, watched, ignored;
        public bool Selected { get { return selected; } set { if (selected != value) { selected = value; Changed("Selected"); } } }
        public bool Watched { get { return watched; } set { if (watched != value) { watched = value; Changed("Watched"); } } }
        public bool Ignored { get { return ignored; } set { if (ignored != value) { ignored = value; Changed("Ignored"); } } }
        public event PropertyChangedEventHandler PropertyChanged;
        void Changed(string name) { var handler = PropertyChanged; if (handler != null) handler(this, new PropertyChangedEventArgs(name)); }
    }

    // A group of items with one tick box for all of them, in Free Up Space's By kind view.
    public sealed class Group : INotifyPropertyChanged {
        public string Name { get; set; }
        public string Hint { get; set; }
        public bool ShowHeader { get; set; }
        public List<Item> Items { get; private set; }
        public Group(string name, IEnumerable<Item> items, bool showHeader) {
            Name = name; ShowHeader = showHeader; Items = new List<Item>(items);
            bool lossless = true;
            foreach (var item in Items) {
                if (item.Answer == "Review first") lossless = false;
                item.PropertyChanged += (s, e) => { if (e.PropertyName == "Selected") { Changed("Ticked"); Changed("Summary"); } };
            }
            Hint = lossless ? "nothing lost" : "review first";
        }
        public long Bytes { get { long sum = 0; foreach (var i in Items) sum += i.Bytes; return sum; } }
        public string Summary { get { return Items.Count + " · " + Format.Bytes(Bytes); } }
        public bool? Ticked {
            get {
                int on = 0; foreach (var i in Items) if (i.Selected) on++;
                return on == 0 ? (bool?)false : on == Items.Count ? (bool?)true : null;
            }
            set { bool v = value == true; foreach (var i in Items) i.Selected = v; Changed("Ticked"); }
        }
        public event PropertyChangedEventHandler PropertyChanged;
        void Changed(string name) { var handler = PropertyChanged; if (handler != null) handler(this, new PropertyChangedEventArgs(name)); }
    }

    public static class Format {
        public static string Bytes(long bytes) {
            string[] units = { "B", "KB", "MB", "GB", "TB" };
            double amount = bytes; int index = 0;
            while (Math.Abs(amount) >= 1024 && index < units.Length - 1) { amount /= 1024; index++; }
            return (index == 0 ? amount.ToString("0") : amount.ToString(Math.Abs(amount) >= 100 ? "0" : "0.0")) + " " + units[index];
        }
        public static string Signed(long bytes) { return (bytes > 0 ? "+" : bytes < 0 ? "\u2212" : "") + Bytes(Math.Abs(bytes)); }
        public static string Ago(DateTime? when) {
            if (!when.HasValue) return "Not recorded";
            var span = DateTime.UtcNow - when.Value; double days = span.TotalDays;
            if (span.TotalMinutes < 2) return "Just now";
            if (span.TotalHours < 1) return ((int)span.TotalMinutes) + " minutes ago";
            if (days < 1) return ((int)span.TotalHours) + (span.TotalHours < 2 ? " hour ago" : " hours ago");
            if (days < 2) return "Yesterday";
            if (days < 14) return ((int)days) + " days ago";
            if (days < 60) return ((int)(days / 7)) + " weeks ago";
            if (days < 730) return ((int)(days / 30)) + " months ago";
            return ((int)(days / 365)) + " years ago";
        }
    }
}
'@
# Compiling the helper takes most of a second, so the compiled copy is kept and reused until the source changes.
if (-not ('ContextCleaner.Disk' -as [type])) {
    $hash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($CCSource))).Replace('-', '').Substring(0, 16)
    # Always in your own AppData, even when tests point the data folder elsewhere: a loaded DLL can't be deleted.
    $cache = Join-Path $script:CCLocal ('Context Cleaner\cache\ContextCleaner-' + $PSVersionTable.PSEdition + '-' + $hash + '.dll')
    $loaded = $false
    if (Test-Path -LiteralPath $cache) { try { Add-Type -LiteralPath $cache; $loaded = $true } catch { } }
    if (-not $loaded) {
        try {
            New-Item -ItemType Directory -Force -Path (Split-Path $cache) | Out-Null
            $temp = $cache + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
            Add-Type -TypeDefinition $CCSource -OutputAssembly $temp -OutputType Library
            Move-Item -LiteralPath $temp -Destination $cache -Force -ErrorAction SilentlyContinue
            Add-Type -LiteralPath $(if (Test-Path -LiteralPath $cache) { $cache } else { $temp })
        } catch { if (-not ('ContextCleaner.Disk' -as [type])) { Add-Type -TypeDefinition $CCSource } }
    }
}

function ConvertTo-CCUtc($Value) {
    if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
    # Anything else that isn't a date, such as an empty object an older version saved for "no date", means no date.
    if (-not ($Value -is [string]) -or -not $Value) { return $null }
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) { return $parsed.ToUniversalTime() }
    $null
}

function Join-CC([string]$Base, [string]$Child) { [IO.Path]::GetFullPath((Join-Path $Base $Child)) }

function Get-CCChildren([string]$Path, [switch]$IncludeFiles) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return @() }
    $all = Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) }
    if ($IncludeFiles) { $all } else { $all | Where-Object { $_.PSIsContainer } }
}

# True when Path is Parent itself or inside it. Plain text comparison, so brackets in names are never wildcards.
function Test-CCInside([string]$Path, [string]$Parent, [switch]$OrSame) {
    $Parent = $Parent.TrimEnd('\')
    ($OrSame -and $Path.Equals($Parent, [StringComparison]::OrdinalIgnoreCase)) -or $Path.StartsWith($Parent + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Test-CCLink([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    [bool]($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint))
}

# Settings live in %LOCALAPPDATA%\Context Cleaner\settings.json, next to scans, plans and History.
function Get-CCSettings {
    $path = Join-Path $script:CCData 'settings.json'
    $s = [ordered]@{ projectRoots = @(); tracked = @(); ignored = @(); scanningOff = @(); watched = @(); coverageOff = @(); expected = @()
        appearance = 'System'; terminal = 'wt'; untouchedDays = 1; byKind = $false; projectRootsFound = $false
        remind = @{}; notes = @{}; window = $null }
    if (Test-Path -LiteralPath $path) {
        try { $saved = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { $saved = $null }
        if ($saved) {
            # Only real text counts: an empty list saved by an older version may read back as an empty object.
            foreach ($list in 'projectRoots', 'tracked', 'ignored', 'scanningOff', 'watched', 'coverageOff', 'expected') { $s[$list] = @($saved.$list | Where-Object { $_ -is [string] -and $_.Trim() }) }
            # Path-to-text maps: when to suggest a folder again, and your note on it.
            # PowerShell 7 reads ISO dates in JSON as dates, Windows PowerShell as text; both become text here.
            foreach ($map in 'remind', 'notes') { if ($saved.$map) { foreach ($p in $saved.$map.PSObject.Properties) {
                $v = if ($p.Value -is [datetime]) { $p.Value.ToUniversalTime().ToString('o') } else { $p.Value }
                if ($v -is [string] -and $v) { $s[$map][$p.Name] = $v } } } }
            if ($saved.window -and $saved.window.Width) { $s.window = $saved.window }
            foreach ($value in 'appearance', 'terminal') { if ($saved.$value) { $s[$value] = [string]$saved.$value } }
            if ($null -ne $saved.untouchedDays) { $s.untouchedDays = [int]$saved.untouchedDays }
            if ($null -ne $saved.byKind) { $s.byKind = [bool]$saved.byKind }
        }
    }
    if (-not $s.projectRoots) {
        # Any folder on the drive, in your home folder or in Documents that holds a git repository.
        # Looking for them takes a moment, so it happens once per run.
        $s.projectRootsFound = $true
        if ($null -eq $script:CCFoundRoots) { $script:CCFoundRoots = @(Find-CCProjectRoots) }
        $s.projectRoots = $script:CCFoundRoots
    }
    [pscustomobject]$s
}

function Find-CCProjectRoots {
    $system = @('Windows', 'Program Files', 'Program Files (x86)', 'ProgramData', 'Users', 'AppData', '$Recycle.Bin', 'System Volume Information', 'Recovery')
    $codexTasks = Join-Path $script:CCHome 'Documents\Codex'
    $parents = @(Get-CCChildren $script:CCDrive) + @(Get-CCChildren $script:CCHome) + @(Get-CCChildren (Join-Path $script:CCHome 'Documents')) + @(Get-CCChildren (Join-Path $script:CCHome 'source'))
    @($parents | Where-Object { $system -notcontains $_.Name -and $_.Name -notlike '.*' -and $_.FullName -ne $codexTasks } | Where-Object {
        $folder = $_.FullName
        @(Get-CCChildren $folder | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.git') }).Count -gt 0
    } | ForEach-Object { $_.FullName })
}

function Save-CCSettings($Settings) {
    New-Item -ItemType Directory -Force -Path $script:CCData | Out-Null
    $path = Join-Path $script:CCData 'settings.json'
    # Project folders found on their own are found again next time, so new ones show up; only ones you set are saved.
    # string[] keeps an empty list as [] in Windows PowerShell's JSON.
    $saved = [ordered]@{ projectRoots = [string[]]@($(if ($Settings.projectRootsFound) { } else { $Settings.projectRoots | Where-Object { $_ } })) }
    foreach ($key in 'tracked', 'ignored', 'scanningOff', 'watched', 'coverageOff', 'expected') { $saved[$key] = [string[]]@($Settings.$key | Where-Object { $_ }) }
    foreach ($key in 'appearance', 'terminal', 'untouchedDays', 'byKind') { $saved[$key] = $Settings.$key }
    # Reminders that have passed are dropped.
    $remind = [ordered]@{}; if ($Settings.remind) { foreach ($k in @($Settings.remind.Keys)) { $at = ConvertTo-CCUtc $Settings.remind[$k]; if ($at -and $at -gt [datetime]::UtcNow) { $remind[$k] = $Settings.remind[$k] } } }
    $notes = [ordered]@{}; if ($Settings.notes) { foreach ($k in @($Settings.notes.Keys)) { if ($Settings.notes[$k]) { $notes[$k] = $Settings.notes[$k] } } }
    $saved.remind = [pscustomobject]$remind; $saved.notes = [pscustomobject]$notes
    if ($Settings.window) { $saved.window = $Settings.window }
    $text = ConvertTo-Json -InputObject $saved -Depth 3
    [IO.File]::WriteAllText($path + '.tmp', $text, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath ($path + '.tmp') -Destination $path -Force
}

# Names builds, package managers and frameworks recreate. Ported from the Mac app's rebuildableName list.
$script:BuildNames = @('build', 'dist', 'out', 'target', 'node_modules', '.next', '.nuxt', '.turbo', '.parcel-cache', '.svelte-kit',
    'obj', '.gradle', '.cxx', '.venv', 'venv', '__pycache__', '.pytest_cache', '.mypy_cache', '.ruff_cache', '.tox', '.dart_tool', '.expo', 'DerivedData')
$script:ItemizedBuildNames = @('build', 'dist', 'out', 'target')

# Package caches: folder, name, tool. Each belongs to its tool, so one may sit directly in AppData\Local.
$script:CacheEntries = @(
    @('npm-cache', 'npm download cache', 'npm', $script:CCLocal), @('pip\cache', 'pip download cache', 'pip', $script:CCLocal),
    @('uv\cache', 'uv package cache', 'uv', $script:CCLocal), @('Yarn\Cache', 'Yarn download cache', 'Yarn', $script:CCLocal), @('pnpm\store', 'pnpm store', 'pnpm', $script:CCLocal),
    @('pnpm-cache', 'pnpm cache', 'pnpm', $script:CCLocal), @('.bun\install\cache', 'Bun package cache', 'Bun', $script:CCHome), @('.nuget\packages', 'NuGet packages', 'NuGet', $script:CCHome),
    @('NuGet\v3-cache', 'NuGet HTTP cache', 'NuGet', $script:CCLocal), @('.gradle\caches', 'Gradle cache', 'Gradle', $script:CCHome), @('.cargo\registry', 'Cargo registry', 'Cargo', $script:CCHome),
    @('go-build', 'Go build cache', 'Go', $script:CCLocal), @('ms-playwright', 'Playwright browsers', 'Playwright', $script:CCLocal), @('electron\Cache', 'Electron downloads', 'Electron', $script:CCLocal),
    @('electron-builder\Cache', 'electron-builder downloads', 'electron-builder', $script:CCLocal), @('.cache\pip', 'pip download cache', 'pip', $script:CCHome), @('.cache\uv', 'uv package cache', 'uv', $script:CCHome)
) | ForEach-Object { [pscustomobject]@{ Path = [IO.Path]::GetFullPath((Join-Path $_[3] $_[0])); Name = $_[1]; App = $_[2] } }
# Shader caches: the graphics driver or DirectX rebuilds them.
$script:ShaderEntries = @(
    @('D3DSCache', 'DirectX shader cache', 'DirectX'), @('NVIDIA\DXCache', 'NVIDIA DirectX shader cache', 'NVIDIA'), @('NVIDIA\GLCache', 'NVIDIA OpenGL shader cache', 'NVIDIA'),
    @('NVIDIA Corporation\NV_Cache', 'NVIDIA shader cache', 'NVIDIA'), @('AMD\DxCache', 'AMD DirectX shader cache', 'AMD'), @('AMD\DxcCache', 'AMD shader cache', 'AMD'),
    @('AMD\GLCache', 'AMD OpenGL shader cache', 'AMD'), @('AMD\VkCache', 'AMD Vulkan shader cache', 'AMD'), @('Intel\ShaderCache', 'Intel shader cache', 'Intel')
) | ForEach-Object { [pscustomobject]@{ Path = [IO.Path]::GetFullPath((Join-Path $script:CCLocal $_[0])); Name = $_[1]; App = $_[2] } }

function New-CCPlace($Path, $Name, $App, $Coverage, $Group, $Category, $Rule, $Extra = @{}) {
    $place = [ordered]@{ Path = $Path; Name = $Name; App = $App; Coverage = $Coverage; Group = $Group; Category = $Category; Rule = $Rule
        Repo = $null; Siblings = $null; LookInside = $null; MinBytes = 1MB }
    foreach ($key in $Extra.Keys) { $place[$key] = $Extra[$key] }
    [pscustomobject]$place
}

# Fixed drives, for advice on moving games and WSL off a full drive.
function Get-CCDrives {
    @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object {
        [pscustomobject]@{ Name = $_.Name.TrimEnd('\'); Label = $_.VolumeLabel; Total = $_.TotalSize; Free = $_.AvailableFreeSpace; System = ($_.Name -ieq $script:CCDrive) }
    })
}
function Get-CCRoomyDrive {
    Get-CCDrives | Where-Object { -not $_.System -and $_.Free -ge 50GB } | Sort-Object Free -Descending | Select-Object -First 1
}

# Every place Context Cleaner knows on Windows, before measuring.
function Get-CCPlaces($Settings) {
    $h = $script:CCHome; $l = $script:CCLocal; $r = $script:CCRoaming
    $places = New-Object 'Collections.Generic.List[object]'
    $add = { param($p) if ($p -and (Test-Path -LiteralPath $p.Path)) { $places.Add($p) } }

    # Codex
    & $add (New-CCPlace (Join-CC $h '.codex') 'Codex home (.codex)' 'Codex' codex 'AI tools' 'App data' 'appdata')
    & $add (New-CCPlace (Join-CC $h '.codex\sessions') 'Codex conversations' 'Codex' codex 'AI tools' 'Chat history' 'history')
    & $add (New-CCPlace (Join-CC $h '.codex\archived_sessions') 'Codex archived conversations' 'Codex' codex 'AI tools' 'Chat history' 'history')
    & $add (New-CCPlace (Join-CC $h '.codex\generated_images') 'Codex generated images' 'Codex' codex 'AI tools' 'Codex images' 'codex-output')
    foreach ($worktree in Get-CCChildren (Join-CC $h '.codex\worktrees')) {
        $repos = if (Test-Path -LiteralPath (Join-Path $worktree.FullName '.git')) { @($worktree) } else { @(Get-CCChildren $worktree.FullName | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.git') }) }
        foreach ($repo in $repos) { & $add (New-CCPlace $repo.FullName ('Codex worktree ' + $worktree.Name) 'Codex' codex 'AI tools' 'Worktrees' 'worktree') }
    }
    foreach ($task in Get-CCChildren (Join-CC $h 'Documents\Codex')) { & $add (New-CCPlace $task.FullName ('Codex task folder ' + $task.Name) 'Codex' codex 'AI tools' 'Codex task folders' 'codex-task') }
    foreach ($runtime in Get-CCChildren (Join-CC $h '.cache\codex-runtimes')) {
        if ($runtime.Name -eq 'codex-primary-runtime') { & $add (New-CCPlace $runtime.FullName 'Codex runtime (current)' 'Codex' codex 'AI tools' 'App data' 'runtime-current') }
        else { & $add (New-CCPlace $runtime.FullName ('Codex runtime ' + ($runtime.Name -replace '^codex-primary-runtime\.', '')) 'Codex' codex 'AI tools' 'Old Codex runtimes' 'runtime-old') }
    }
    $codexApps = @(Get-CCChildren (Join-CC $l 'Packages') | Where-Object { $_.Name -like 'OpenAI.Codex_*' }) + @(Get-CCChildren $l | Where-Object { 'Codex', 'OpenAI', 'OpenCodex' -contains $_.Name }) + @(Get-CCChildren $r | Where-Object { $_.Name -eq 'Codex' })
    foreach ($app in $codexApps) { & $add (New-CCPlace $app.FullName ('Codex app data · ' + $app.Name) 'Codex' codex 'AI tools' 'App data' 'appdata') }
    # Claude
    $claudeApps = @(Get-CCChildren (Join-CC $l 'Packages') | Where-Object { $_.Name -like 'Claude_*' }) + @(Get-CCChildren $l | Where-Object { $_.Name -like 'Claude*' }) + @(Get-CCChildren $r | Where-Object { $_.Name -like 'Claude*' })
    foreach ($app in $claudeApps) { & $add (New-CCPlace $app.FullName ('Claude app data · ' + $app.Name) 'Claude' claude 'AI tools' 'App data' 'appdata') }
    & $add (New-CCPlace (Join-CC $h '.claude') 'Claude Code history and settings' 'Claude Code' claude 'AI tools' 'Chat history' 'history')
    # Models
    & $add (New-CCPlace (Join-CC $h '.cache\huggingface') 'Hugging Face models & datasets' 'Hugging Face' models 'AI tools' 'AI models' 'model')
    & $add (New-CCPlace (Join-CC $h '.ollama\models') 'Ollama models' 'Ollama' models 'AI tools' 'AI models' 'model')
    & $add (New-CCPlace (Join-CC $h '.lmstudio\models') 'LM Studio models' 'LM Studio' models 'AI tools' 'AI models' 'model')
    # Package caches and shader caches
    foreach ($c in $script:CacheEntries) { & $add (New-CCPlace $c.Path $c.Name $c.App caches 'Developer tools' 'Package downloads' 'cache') }
    foreach ($c in $script:ShaderEntries) { & $add (New-CCPlace $c.Path $c.Name $c.App gpu 'Windows' 'Shader caches' 'shader') }
    # Android
    foreach ($kind in 'system-images', 'ndk') {
        foreach ($sdk in Get-CCChildren (Join-CC $l ('Android\Sdk\' + $kind))) { & $add (New-CCPlace $sdk.FullName ('Android ' + $kind + ' ' + $sdk.Name) 'Android Studio' android 'Developer tools' 'Package downloads' 'cache') }
    }
    foreach ($avd in Get-CCChildren (Join-CC $h '.android\avd')) { & $add (New-CCPlace $avd.FullName ($avd.BaseName + ' emulator') 'Android Emulator' android 'Virtual machines' 'Virtual machines' 'vm-android') }
    # Temporary files: each top-level item, kept only when big.
    foreach ($tmp in Get-CCChildren $script:CCTemp -IncludeFiles) { & $add (New-CCPlace $tmp.FullName ('Temp · ' + $tmp.Name) 'Apps and tools' temp 'Developer tools' 'Temporary files' 'temp' @{ MinBytes = 50MB }) }
    # Crash dumps and error reports
    foreach ($dump in Get-CCChildren (Join-CC $l 'CrashDumps') -IncludeFiles) { & $add (New-CCPlace $dump.FullName ('Crash dump · ' + $dump.Name) 'Windows Error Reporting' crash 'Windows' 'Crash dumps' 'crash' @{ MinBytes = 20MB }) }
    foreach ($wer in 'ReportArchive', 'ReportQueue') { & $add (New-CCPlace (Join-CC $l ('Microsoft\Windows\WER\' + $wer)) ('Error reports · ' + $wer) 'Windows Error Reporting' crash 'Windows' 'Crash dumps' 'crash' @{ MinBytes = 20MB }) }

    # Projects: build folders inside each repository, item by item when a build folder holds several builds.
    foreach ($root in $Settings.projectRoots) {
        foreach ($project in Get-CCChildren $root) {
            $git = Join-Path $project.FullName '.git'
            if (Test-Path -LiteralPath $git -PathType Leaf) { & $add (New-CCPlace $project.FullName ('Worktree ' + $project.Name) 'git' projects 'Projects' 'Worktrees' 'worktree'); continue }
            $repo = if (Test-Path -LiteralPath $git) { $project.FullName } else { $null }
            $level1 = @(Get-CCChildren $project.FullName)
            $candidates = @($level1 | Where-Object { $script:BuildNames -contains $_.Name })
            foreach ($dir in $level1 | Where-Object { $script:BuildNames -notcontains $_.Name -and '.git', 'ref', 'refs' -notcontains $_.Name }) {
                $candidates += @(Get-CCChildren $dir.FullName | Where-Object { $script:BuildNames -contains $_.Name })
            }
            foreach ($build in $candidates) {
                $relative = $build.FullName.Substring($project.FullName.Length + 1)
                $subfolders = @(Get-CCChildren $build.FullName)
                if ($script:ItemizedBuildNames -contains $build.Name -and $subfolders.Count -ge 2) {
                    foreach ($sub in $subfolders) { & $add (New-CCPlace $sub.FullName ($project.Name + ' · ' + $relative + '\' + $sub.Name) 'Your projects' projects 'Projects' 'Build output' 'build' @{ Repo = $repo; Siblings = $build.FullName; MinBytes = 100MB }) }
                } else {
                    & $add (New-CCPlace $build.FullName ($project.Name + ' · ' + $relative) 'Your projects' projects 'Projects' 'Build output' 'build' @{ Repo = $repo; MinBytes = 100MB })
                }
            }
            # Not in git, as on the Mac: a big folder the repository ignores that isn't build output exists only on this PC.
            if ($repo) {
                $ignoredDirs = Invoke-CCGit $repo @('-c', 'core.quotePath=false', 'ls-files', '--others', '--ignored', '--exclude-standard', '--directory', '--no-empty-directory')
                foreach ($rel in @($ignoredDirs -split '\r?\n' | Where-Object { $_ -like '*/' })) {
                    $full = Join-Path $repo ($rel.TrimEnd('/') -replace '/', '\')
                    if ($script:BuildNames -contains (Split-Path $full -Leaf) -or -not (Test-Path -LiteralPath $full -PathType Container)) { continue }
                    & $add (New-CCPlace $full ($project.Name + ' · ' + $rel.TrimEnd('/').Replace('/', '\')) 'Your projects' projects 'Projects' 'Not in git' 'notingit' @{ Repo = $repo; MinBytes = 500MB })
                }
            }
        }
    }
    # Downloads, item by item.
    foreach ($download in Get-CCChildren (Join-CC $h 'Downloads') -IncludeFiles) { & $add (New-CCPlace $download.FullName ('Downloads · ' + $download.Name) 'You' downloads 'Downloads' 'Downloads' 'download' @{ MinBytes = 100MB }) }

    # Virtual machines: WSL distributions (Docker Desktop's included) keep everything in one disk file.
    foreach ($key in Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction SilentlyContinue) {
        $distro = Get-ItemProperty $key.PSPath
        if (-not $distro.BasePath) { continue }
        $file = if ($distro.VhdFileName) { $distro.VhdFileName } else { 'ext4.vhdx' }
        $vhd = Join-Path ($distro.BasePath -replace '^\\\\\?\\', '') $file
        if ($distro.DistributionName -like 'docker-desktop*') { & $add (New-CCPlace $vhd ('Docker Desktop disk · ' + $distro.DistributionName) 'Docker Desktop' vms 'Virtual machines' 'Virtual machines' 'vm-docker') }
        else { & $add (New-CCPlace $vhd ('WSL disk · ' + $distro.DistributionName) 'WSL' vms 'Virtual machines' 'Virtual machines' 'vm-wsl' @{ LookInside = $distro.DistributionName }) }
    }
    foreach ($disk in Get-ChildItem (Join-CC $l 'Docker\wsl') -Recurse -Filter '*.vhdx' -Force -ErrorAction SilentlyContinue) {
        if (-not ($places | Where-Object { $_.Path -ieq $disk.FullName })) { & $add (New-CCPlace $disk.FullName ('Docker Desktop disk · ' + $disk.Directory.Name) 'Docker Desktop' vms 'Virtual machines' 'Virtual machines' 'vm-docker') }
    }

    # Games: each Steam game in every Steam library.
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if (-not $steam) { $steam = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Steam' }
    $libraries = @($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) { $libraries += Select-String -LiteralPath $vdf -Pattern '"path"\s+"([^"]+)"' | ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' } }
    foreach ($library in $libraries | ForEach-Object { [IO.Path]::GetFullPath($_) } | Sort-Object -Unique) {
        foreach ($game in Get-CCChildren (Join-Path $library 'steamapps\common')) { & $add (New-CCPlace $game.FullName $game.Name 'Steam' games 'Games' 'Games' 'game') }
    }

    # Windows itself.
    foreach ($name in 'pagefile.sys', 'hiberfil.sys', 'swapfile.sys') { & $add (New-CCPlace (Join-Path $script:CCDrive $name) $name 'Windows' windows 'Windows' 'System files' 'system') }
    & $add (New-CCPlace (Join-Path $script:CCDrive 'Windows.old') 'Previous Windows installation' 'Windows' windows 'Windows' 'System files' 'windows-old')
    & $add (New-CCPlace (Join-Path $script:CCDrive 'Windows\SoftwareDistribution\Download') 'Windows Update downloads' 'Windows Update' windows 'Windows' 'System files' 'windows-temp')
    & $add (New-CCPlace (Join-Path $script:CCDrive 'Windows\Temp') 'Windows temporary files' 'Windows' windows 'Windows' 'System files' 'windows-temp')
    & $add (New-CCPlace (Join-Path $script:CCDrive 'ProgramData\Microsoft\Windows\WER') 'Error reports for all users' 'Windows Error Reporting' windows 'Windows' 'System files' 'windows-temp')

    # Folders you track: every item inside, so what sits untouched there can be offered too.
    foreach ($folder in $Settings.tracked) {
        foreach ($child in Get-CCChildren $folder -IncludeFiles) { & $add (New-CCPlace $child.FullName ((Split-Path $folder -Leaf) + ' · ' + $child.Name) 'You' tracked 'Your folders' 'Your folders' 'tracked' @{ MinBytes = 50MB }) }
    }

    $off = @($Settings.coverageOff)
    @($places | Where-Object { $off -notcontains $_.Coverage -and -not (Test-CCScanningOff $_.Path $Settings) })
}

function Test-CCScanningOff([string]$Path, $Settings) {
    foreach ($off in @($Settings.scanningOff)) { if ($off -and (Test-CCInside $Path $off -OrSame)) { return $true } }
    $false
}

# Folders that together cover the drive, sized without the places above, so every byte counts once.
function Get-CCElsewhere($Covered, $Settings) {
    $h = $script:CCHome
    # Windows itself is left out: its hardlinks would count the same files many times. It shows as system space.
    $skipTop = @('Windows', 'Users', '$Recycle.Bin', 'System Volume Information', 'Recovery', 'Config.Msi', '$WinREAgent', '$SysReset', 'Documents and Settings')
    $rows = @(Get-CCChildren $script:CCDrive | Where-Object { $skipTop -notcontains $_.Name })
    $rows += @(Get-CCChildren (Join-Path $script:CCDrive 'Users') | Where-Object { $_.FullName -ne $h })
    $rows += @(Get-CCChildren $h | Where-Object { $_.Name -ne 'AppData' })
    $rows += @('Local', 'Roaming', 'LocalLow' | ForEach-Object { Get-CCChildren (Join-Path $h ('AppData\' + $_)) })
    $coveredSet = New-Object 'Collections.Generic.HashSet[string]' ([string[]]@($Covered), [StringComparer]::OrdinalIgnoreCase)
    $rows | Where-Object { -not $coveredSet.Contains($_.FullName) -and -not (Test-CCScanningOff $_.FullName $Settings) } | ForEach-Object {
        New-CCPlace $_.FullName $_.Name 'Everything else' other 'Everything else' (Get-CCShortPath (Split-Path $_.FullName -Parent)) 'other' @{ MinBytes = 500MB }
    }
}

# A path as you'd say it: your home folder as ~.
function Get-CCShortPath([string]$Path) {
    if (Test-CCInside $Path $script:CCHome -OrSame) { '~' + $Path.Substring($script:CCHome.Length) } else { $Path }
}

# Read-only git: no fetch, no hooks, no prompts, no optional locks, and no program a repository's config names
# (fsmonitor, or a clean or smudge filter such as Git LFS) is run.
function Invoke-CCGit([string]$Path, [string[]]$Arguments) {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    # Windows PowerShell turns a native program's stderr into an error when errors stop the script, even when it is
    # redirected. Git warns on stderr (for example about a folder another user owns), so errors only continue here.
    $ErrorActionPreference = 'Continue'
    $env:GIT_OPTIONAL_LOCKS = '0'; $env:GIT_TERMINAL_PROMPT = '0'
    $safety = @('-c', 'core.fsmonitor=false', '-c', 'core.untrackedCache=false', '-c', 'core.hooksPath=NUL', '-c', 'credential.helper=')
    $filters = & git -C $Path config --name-only --get-regexp '^filter\..*\.(clean|smudge|process)$' 2>$null
    foreach ($name in @($filters | Where-Object { $_ })) { $safety += @('-c', ($name + '=')) }
    $output = & git -C $Path @safety @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    ($output -join $script:NL).Trim()
}

function Get-CCGitBackup([string]$Path) {
    $remotes = Invoke-CCGit $Path @('remote')
    $unpushed = Invoke-CCGit $Path @('rev-list', '--count', 'HEAD', '--not', '--remotes')
    $status = Invoke-CCGit $Path @('status', '--porcelain', '--untracked-files=normal')
    [pscustomobject]@{
        Readable = $null -ne $status
        HasRemote = [bool]$remotes
        Unpushed = if ($unpushed) { [int]$unpushed } else { $null }
        Changes = if ($null -ne $status) { @($status -split '\r?\n' | Where-Object { $_ }).Count } else { $null }
    }
}

# Whether git vouches for everything in a worktree: a remote, nothing unpushed, nothing uncommitted.
function Test-CCBackedUp($Backup) { $Backup.Readable -and $Backup.HasRemote -and $Backup.Unpushed -eq 0 -and $Backup.Changes -eq 0 }

# Paths a command may ever move: inside your home folder, your temporary folder or a project folder; never those
# folders themselves, nothing directly in home or AppData except a known cache, never a whole project, history or link.
function Test-CCAllowed([string]$Path, $Settings) {
    if (-not $Path -or $Path -match '[\x00-\x1f]') { return $false }
    $full = [ContextCleaner.Disk]::LongPath([IO.Path]::GetFullPath($Path)).TrimEnd('\')
    # A link or junction anywhere along the path could lead outside these rules, so such paths are never moved.
    if ([ContextCleaner.Disk]::ThroughLink($full)) { return $false }
    $h = $script:CCHome
    $never = @($h, (Join-CC $h 'AppData'), $script:CCLocal, $script:CCRoaming, (Join-CC $h 'AppData\LocalLow'), (Join-CC $h 'Documents'), (Join-CC $h 'Downloads'), (Join-CC $h 'Desktop'),
        (Join-CC $h '.codex'), (Join-CC $h 'Documents\Codex'), $script:CCTemp, $script:CCData)
    foreach ($n in $never) { if ($full -ieq $n) { return $false } }
    foreach ($tree in (Join-CC $h 'OneDrive'), (Join-CC $h '.ssh'), (Join-CC $h '.gnupg'), (Join-CC $h '.codex\sessions'), (Join-CC $h '.codex\archived_sessions'), (Join-CC $h '.claude'), $script:CCData) {
        if (Test-CCInside $full $tree -OrSame) { return $false }
    }
    if ($full.IndexOf('\$Recycle.Bin', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $false }
    # Never Context Cleaner itself or its own data, or a folder holding them.
    foreach ($own in $script:CCApp, $script:CCData) { if ($own -and (Test-CCInside $own $full -OrSame)) { return $false } }
    $parent = Split-Path $full -Parent
    $direct = [bool](@($script:CacheEntries) + @($script:ShaderEntries) | Where-Object { $_.Path -ieq $full })
    if (-not $direct -and ($parent -ieq $h -or $parent -ieq $script:CCLocal -or $parent -ieq $script:CCRoaming)) { return $false }
    $roots = @($h, $script:CCTemp) + @($Settings.projectRoots | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') })
    # Folders you track count only inside your home folder, so tracking never opens Program Files or Windows to a command.
    $roots += @($Settings.tracked | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') } | Where-Object { Test-CCInside $_ $h })
    if (-not ($roots | Where-Object { Test-CCInside $full $_ })) { return $false }
    foreach ($root in $Settings.projectRoots) {
        $root = [IO.Path]::GetFullPath($root).TrimEnd('\')
        # A whole project is never offered; a worktree is, after git says everything in it is pushed.
        if ($full -ieq $root) { return $false }
        if ((Split-Path $full -Parent) -ieq $root -and -not (Test-Path -LiteralPath (Join-Path $full '.git') -PathType Leaf)) { return $false }
    }
    foreach ($tracked in $Settings.tracked) { if ($full -ieq [IO.Path]::GetFullPath($tracked).TrimEnd('\')) { return $false } }
    $true
}

# Programs running from inside a folder: removing it would break them, and Windows would refuse anyway.
function Get-CCRunning {
    @(Get-CimInstance Win32_Process -Property Name, ExecutablePath -ErrorAction SilentlyContinue | Where-Object { $_.ExecutablePath } |
        ForEach-Object { [pscustomobject]@{ Name = $_.Name; Path = $_.ExecutablePath } })
}
function Get-CCInUse([string]$Path, $Running) {
    $names = @($Running | Where-Object { Test-CCInside $_.Path $Path -OrSame } | ForEach-Object { $_.Name -replace '\.exe$', '' } | Sort-Object -Unique)
    if ($names) { ($names | Select-Object -First 3) -join ', ' } else { $null }
}

function Set-CCAnswer($Item, [string]$Answer, [string]$Reason, [string]$Explanation, [string]$Consequence, [string]$HowTo = '') {
    $Item.Answer = $script:Answers[$Answer]; $Item.Reason = $Reason; $Item.Explanation = $Explanation; $Item.Consequence = $Consequence; $Item.HowTo = $HowTo
}

# One answer per folder, with its reason. Ported from the Mac Classifier and adapted to Windows places.
function Resolve-CCAnswer($Item, $Place, $Newest, $Roomy) {
    $idle = $Item.IdleDays
    $quiet = $Item.UntouchedText
    $roomyText = if ($Roomy) { $Roomy.Name + ' (' + [ContextCleaner.Format]::Bytes($Roomy.Free) + ' free)' } else { $null }
    switch ($Place.Rule) {
        'history' { Set-CCAnswer $Item Keep 'Chat history' 'Conversation records and settings this app keeps.' 'Removing them loses conversation history.' 'Manage conversations inside the app.' }
        'appdata' { Set-CCAnswer $Item Keep 'App data' 'App state, caches and local databases.' 'Removing it can break the app or lose its data.' 'Clear data from inside the app, or uninstall it in Settings > Apps.' }
        'runtime-current' { Set-CCAnswer $Item Keep 'Codex runs from it' 'The runtime Codex runs tasks with.' 'Running tasks would break, and Codex would download it again.' 'Leave it to Codex.' }
        'runtime-old' {
            if ($idle -ge 3) { Set-CCAnswer $Item Safe ('Old runtime, ' + $quiet) 'An older Codex runtime kept after an update, or an install that never finished.' 'Nothing. Codex runs from codex-primary-runtime.' }
            else { Set-CCAnswer $Item Rebuildable 'Replaced this week' 'An older Codex runtime kept after a recent update, in case it needs rolling back.' 'Nothing unless the newest runtime breaks; Codex downloads a runtime again if it needs one.' }
        }
        'codex-task' { Set-CCAnswer $Item Review $(if ($idle -lt 1) { 'Used today' } else { 'Codex task, ' + $quiet }) 'Files a Codex task made: reports, downloads, scripts and copies.' 'May hold the only copy of a task output. Look inside first.' }
        'codex-output' { Set-CCAnswer $Item Review 'Images Codex made' 'Pictures generated during Codex tasks.' 'They may be the only copies.' }
        'model' { Set-CCAnswer $Item Review 'AI models' 'Downloaded models and datasets.' 'You download them again to use them, and some may no longer be available.' 'Remove models from inside the tool (for example, ollama rm).' }
        'cache' {
            if ($idle -ge 7) { Set-CCAnswer $Item Safe ('Package cache, ' + $quiet) 'Downloads a package tool keeps so the next install is faster.' 'Nothing. The tool downloads what it needs again.' }
            else { Set-CCAnswer $Item Rebuildable 'Used this week' 'Downloads a package tool keeps so the next install is faster.' 'The next install or build downloads again and takes longer.' }
        }
        'shader' {
            if ($idle -ge 7) { Set-CCAnswer $Item Safe ('Shader cache, ' + $quiet) 'Shaders the graphics driver compiled so games and apps start faster.' 'Nothing. The driver compiles them again; the first launch of a game may stutter briefly.' }
            else { Set-CCAnswer $Item Rebuildable 'Used this week' 'Shaders the graphics driver compiled so games and apps start faster.' 'Games compile them again, so their next launch is slower.' }
        }
        'crash' {
            if ($idle -ge 14) { Set-CCAnswer $Item Safe ('Crash report, ' + $quiet) 'What a program left behind when it crashed. It only helps someone debug that crash.' 'Nothing, unless you still want to send or study that crash.' }
            else { Set-CCAnswer $Item Review ('Recent crash, ' + $quiet) 'What a program left behind when it crashed. It only helps someone debug that crash.' 'You can no longer study or send this crash.' }
        }
        'build' {
            # As on the Mac, only git says a folder is output: one the project's git ignores. "build" and ".cxx" are output
            # by name; any other build-like name (out, dist, target, venv…) that git can't vouch for is Review first.
            $folder = if ($Place.Siblings) { $Place.Siblings } else { $Item.Path }
            $byName = 'build', '.cxx' -contains (Split-Path $folder -Leaf)
            $hasGit = [bool](Get-Command git -ErrorAction SilentlyContinue)
            $ignored = $null
            if ($Place.Repo -and $hasGit) {
                $ignored = $null -ne (Invoke-CCGit $Place.Repo @('check-ignore', '--', $Item.Path.Substring($Place.Repo.Length + 1)))
                # check-ignore also fails when git can't read the repository at all; that is "unknown", not "tracked".
                if (-not $ignored -and $null -eq (Invoke-CCGit $Place.Repo @('rev-parse', '--git-dir'))) { $ignored = $null }
            }
            $unsure = 'It may hold files that exist only here.'
            if ($ignored -eq $false) { Set-CCAnswer $Item Review 'Tracked in git' 'A build-like folder that git tracks, so it may be source, not output.' 'Removing it changes the project. Check git status first.' }
            elseif ($null -eq $ignored -and -not $byName -and -not $Place.Repo) { Set-CCAnswer $Item Review 'Not in a git repository' 'A build-like folder in a project without git, so nothing confirms a tool made it.' $unsure 'Look inside first. In a git repository that ignores it, Context Cleaner can tell it is output.' }
            elseif ($null -eq $ignored -and -not $byName -and -not $hasGit) { Set-CCAnswer $Item Review 'Git isn''t installed' 'A build-like folder. Without git, Context Cleaner can''t confirm the project ignores it as output.' $unsure 'Install Git for Windows (winget install Git.Git) and scan again.' }
            elseif ($null -eq $ignored -and -not $byName) { Set-CCAnswer $Item Review 'Git can''t read it' 'A build-like folder in a repository git could not read, so whether it is output is unknown.' $unsure 'Open the project in a terminal and run git status. If git asks about safe.directory, the folder was made by another account or inside WSL.' }
            elseif ($Newest -and $Item.Path -ieq $Newest) { Set-CCAnswer $Item Rebuildable ('Newest build here, ' + $quiet) 'Output of your latest build in this folder.' 'You rebuild it from source if you need its files again.' }
            elseif ($idle -ge 7) { Set-CCAnswer $Item Safe ('Build output, ' + $quiet) 'Output a build produced. The source is in the project.' 'Nothing. A newer build exists, or the next build recreates it.' }
            else { Set-CCAnswer $Item Rebuildable 'Built this week' 'Output a build produced. The source is in the project.' 'The next build recreates it, which takes time.' }
        }
        'notingit' {
            Set-CCAnswer $Item Review 'Not in git, only on this PC' 'A folder the project''s git ignores, so it is in no commit and on no remote. Downloads, data or models a tool fetched can come back; anything you made cannot.' 'What it holds is gone for good once you empty the Recycle Bin.' 'Look inside. Keep or back up what you made; remove what a tool can fetch again.'
        }
        'worktree' {
            $b = Get-CCGitBackup $Item.Path
            if (-not $b.Readable) {
                $Item.Withheld = $true
                $Item.Evidence = 'git status failed here, for example because the folder belongs to another user or its repository is inside WSL.'
                Set-CCAnswer $Item Review 'Git can''t read it' 'A git worktree git could not read, so whether its work is backed up is unknown.' 'Uncommitted or unpushed work may exist only here.' 'Open it in a terminal and run git status. If git asks about safe.directory, the folder was made by another account or inside WSL.'
                break
            }
            $Item.Evidence = 'Remote: ' + $(if ($b.HasRemote) { 'yes' } else { 'no' }) + ' · unpushed commits: ' + $b.Unpushed + ' · uncommitted files: ' + $b.Changes
            $backed = Test-CCBackedUp $b
            $Item.Withheld = -not $backed
            if ($backed -and $idle -ge 7) { Set-CCAnswer $Item Safe ('Pushed and clean, ' + $quiet) 'A git worktree whose commits are all pushed, with nothing uncommitted.' 'Only files git ignores (build output, .env) are lost.' 'Or run git worktree remove from the main repository.' }
            elseif ($backed) { Set-CCAnswer $Item Review 'Pushed, used this week' 'A git worktree you used recently. Everything is pushed.' 'A task may still be using it.' }
            else { Set-CCAnswer $Item Review 'Not fully in git' 'A git worktree with work git has not backed up.' 'Uncommitted or unpushed work would be lost.' 'Commit and push, then remove it.' }
        }
        'temp' {
            if ($idle -ge 3) { Set-CCAnswer $Item Safe ('Temporary, ' + $quiet) 'Work files an app or tool left in your temporary folder.' 'Nothing. Nothing keeps temporary files.' }
            else { Set-CCAnswer $Item Review 'In use recently' 'Work files an app or tool left in your temporary folder.' 'Something may still be using it. Wait a few days.' }
        }
        'download' { Set-CCAnswer $Item Review ('Download, ' + $quiet) 'Something you or an app downloaded.' 'Being in Downloads does not mean another copy exists.' }
        'tracked' { Set-CCAnswer $Item Review $(if ($idle -lt 7) { 'In a tracked folder, used this week' } else { 'In a tracked folder, ' + $quiet }) 'An item in a folder you chose to track. Context Cleaner has no rule for what it is.' 'It may be the only copy. Look inside first.' }
        'vm-wsl' {
            $move = if ($roomyText) { ' To keep everything but free this drive, move it to ' + $roomyText + ': wsl --shutdown, then wsl --manage ' + $Place.LookInside + ' --move ' + $Roomy.Name + '\WSL\' + $Place.LookInside + '.' } else { '' }
            Set-CCAnswer $Item Keep 'Whole Linux system' 'The disk of a WSL Linux distribution. Everything inside Linux lives in this one file, and the file does not shrink when you delete inside Linux.' 'Removing it deletes the whole Linux system and its files.' ('Use Look Inside to see what fills it, and delete inside Linux. Then hand the space back: run wsl --shutdown, open an admin terminal, run diskpart and type select vdisk file="' + $Item.Path + '", attach vdisk readonly, compact vdisk, detach vdisk. Back up first (wsl --export).' + $move)
            $Item.Action = 'wsl'
        }
        'vm-docker' {
            $move = if ($roomyText) { ' To move it to ' + $roomyText + ', use Docker Desktop > Settings > Resources > Advanced > Disk image location.' } else { '' }
            Set-CCAnswer $Item Keep 'Docker images and containers' 'The disk that holds every Docker image, container and volume. It does not shrink when you remove images.' 'Removing it deletes all of them.' ('Remove what you no longer need in Docker Desktop (or docker system prune; add -a to remove every unused image). Then quit Docker Desktop, run wsl --shutdown, and compact the file in an admin diskpart: select vdisk file="' + $Item.Path + '", attach vdisk readonly, compact vdisk, detach vdisk.' + $move)
        }
        'vm-android' { Set-CCAnswer $Item Keep 'Virtual device' 'A virtual Android device with its apps, data and snapshots.' 'Its apps and data are lost.' 'Delete it in Android Studio''s Device Manager.' }
        'game' {
            $onSystem = Test-CCInside $Item.Path $script:CCDrive
            $move = if ($roomyText -and $onSystem) { 'To keep it but free this drive, move it to ' + $roomyText + ': Steam > Settings > Storage, add a drive, select the game and choose Move. Steam moves the files without downloading them again. ' } else { '' }
            Set-CCAnswer $Item Keep ('Installed game, ' + $quiet) 'A game installed through Steam.' 'Steam would still list it as installed, and saves kept only on this PC may be lost.' ($move + 'Or uninstall it in Steam (right-click > Manage > Uninstall); you can download it again later.')
            $Item.Action = 'steam'
        }
        'system' { Set-CCAnswer $Item Keep 'Windows uses it' 'A file Windows uses for memory or hibernation.' 'Windows needs it or recreates it.' $(if ($Item.Name -eq 'hiberfil.sys') { 'If you never hibernate, powercfg /h off in an admin terminal removes it (Fast Startup goes too).' } else { 'System > About > Advanced system settings > Performance > Advanced > Virtual memory sets its size and drive.' }) }
        'windows-old' { Set-CCAnswer $Item Keep 'Previous Windows' 'Your previous Windows installation, kept to roll back an upgrade.' 'You can no longer go back to the previous version.' 'Settings > System > Storage > Temporary files > Previous Windows installation(s).'; $Item.Action = 'storage' }
        'windows-temp' { Set-CCAnswer $Item Keep 'Windows cleans it' 'Files Windows keeps for itself: update downloads, temporary files and error reports.' 'Windows removes them safely itself; moving them by hand can break an update in progress.' 'Settings > System > Storage > Temporary files, or turn on Storage Sense to do it on a schedule.'; $Item.Action = 'storage' }
        'other' { Set-CCAnswer $Item Other 'Not a known place' 'A folder Context Cleaner has no rule for. Its size leaves out the known places inside it.' 'Unknown. Look inside.' 'Open it in Explorer to see what it holds.' }
    }
}

function Invoke-CCScan([scriptblock]$Progress = { param($text) }) {
    $settings = Get-CCSettings
    $previous = Get-CCBaselineScan
    $since = if ($previous) { Get-CCSinceText (ConvertTo-CCUtc $previous.FinishedAt) } else { $null }
    $started = Get-Date
    [ContextCleaner.Disk]::Cancel = $false
    & $Progress 'Finding places'
    $places = @(Get-CCPlaces $settings)
    $covered = @($places | ForEach-Object { $_.Path })
    $skip = $covered + @($settings.scanningOff)
    $all = $places + @(Get-CCElsewhere $covered $settings)
    & $Progress ('Measuring ' + $all.Count + ' folders')
    [ContextCleaner.Disk]::FilesRead = 0
    $measured = [ContextCleaner.Disk]::MeasureAll([string[]]@($all | ForEach-Object { $_.Path }), [string[]]$skip)
    if ([ContextCleaner.Disk]::Cancel) { throw 'The scan was stopped. Nothing was saved.' }
    & $Progress 'Reading git and choosing answers'
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $recycle = [ContextCleaner.Disk]::Measure((Join-Path $script:CCDrive ('$Recycle.Bin\' + $sid)), $null)
    $running = Get-CCRunning
    $roomy = Get-CCRoomyDrive
    $before = @{}
    if ($previous) { foreach ($p in $previous.Items) { $before[[string]$p.Path] = [long]$p.Bytes } }
    $items = New-Object 'Collections.Generic.List[ContextCleaner.Item]'
    $byPath = @{}
    for ($i = 0; $i -lt $all.Count; $i++) {
        $place = $all[$i]; $m = $measured[$i]
        if (-not $m.Exists -or $m.Link -or $m.Bytes -lt $place.MinBytes) { continue }
        $item = New-Object ContextCleaner.Item
        $item.Path = $place.Path; $item.Name = $place.Name; $item.App = $place.App; $item.Group = $place.Group; $item.Category = $place.Category
        $item.Coverage = $place.Coverage; $item.Rule = $place.Rule; $item.Bytes = $m.Bytes; $item.SharedBytes = $m.SharedBytes; $item.Files = $m.Files
        $item.Unreadable = $m.Unreadable; $item.Latest = $m.Latest; $item.LookInside = $place.LookInside
        if ($before.ContainsKey($place.Path)) { $item.Growth = $m.Bytes - $before[$place.Path] }
        $item.GrowthSince = $since
        $notes = @()
        if ($m.SharedBytes) { $notes += [ContextCleaner.Format]::Bytes($m.SharedBytes) + ' more is hardlinked files that also live elsewhere, so removing this does not free it.' }
        if ($m.CloudOnly) { $notes += [string]$m.CloudOnly + ' files kept only in the cloud are not counted.' }
        if ($m.Unreadable -eq 1) { $notes += 'One folder inside could not be read and is not counted.' } elseif ($m.Unreadable) { $notes += [string]$m.Unreadable + ' folders inside could not be read and are not counted.' }
        $item.Evidence = $notes -join ' '
        $items.Add($item); $byPath[$item.Path] = $place
    }
    # The newest build among the builds in one build folder.
    $newest = @{}
    foreach ($group in $items | Where-Object { $byPath[$_.Path].Siblings } | Group-Object { $byPath[$_.Path].Siblings }) {
        $newest[$group.Name] = ($group.Group | Sort-Object Latest -Descending | Select-Object -First 1).Path
    }
    $offerable = $script:Answers.Safe, $script:Answers.Rebuildable, $script:Answers.Review
    foreach ($item in $items) {
        $place = $byPath[$item.Path]
        $notes = $item.Evidence
        Resolve-CCAnswer $item $place $(if ($place.Siblings) { $newest[$place.Siblings] }) $roomy
        if ($notes -and $item.Evidence -ne $notes) { $item.Evidence = (@($item.Evidence, $notes) | Where-Object { $_ }) -join ' ' }
        if ($item.Rule -ne 'game' -and $item.Rule -ne 'runtime-current') { $item.InUse = Get-CCInUse $item.Path $running }
        if ($item.InUse -and ($item.Answer -eq $script:Answers.Safe -or $item.Answer -eq $script:Answers.Rebuildable)) {
            $item.Answer = $script:Answers.Review; $item.Reason = 'In use by ' + $item.InUse
            $item.Consequence = $item.InUse + ' is running from here. Quit it first; Windows will not move a folder a program is running from.'
        }
        $item.Removable = ($offerable -contains $item.Answer) -and -not $item.Withheld -and (Test-CCAllowed $item.Path $settings)
        if (-not $item.Removable -and -not $item.Withheld -and $offerable -contains $item.Answer) { $item.Evidence = (@($item.Evidence, 'Outside the places a command may reach.') | Where-Object { $_ }) -join ' ' }
        Set-CCItemSettings $item $settings
        $item.Selected = $item.Removable -and $item.Answer -eq $script:Answers.Safe -and -not $item.Ignored -and -not $item.InUse -and -not $item.IsSnoozed
    }
    $drive = New-Object IO.DriveInfo $script:CCDrive
    $scan = [pscustomobject]@{
        Version = $script:CCVersion; StartedAt = $started.ToUniversalTime().ToString('o'); FinishedAt = (Get-Date).ToUniversalTime().ToString('o')
        Seconds = [int]((Get-Date) - $started).TotalSeconds; Drive = $script:CCDrive; TotalBytes = $drive.TotalSize; FreeBytes = $drive.AvailableFreeSpace
        # Each $(if) has an else: in Windows PowerShell, an if that yields nothing is written to JSON as {} instead of null.
        RecycleBytes = $recycle.Bytes + $recycle.SharedBytes; PreviousAt = $(if ($previous) { $previous.FinishedAt } else { $null }); ProjectRoots = @($settings.projectRoots)
        Items = @($items | Sort-Object Bytes -Descending)
    }
    Save-CCScan $scan
    Add-CCReading $scan.TotalBytes $scan.FreeBytes
    $scan
}

# Saved scans are new files, written whole and then moved into place.
function Save-CCScan($Scan) {
    $dir = Join-Path $script:CCData 'scans'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $name = 'scan-' + (ConvertTo-CCUtc $Scan.FinishedAt).ToString('yyyyMMdd-HHmmss') + '.json'
    $temp = Join-Path $dir ($name + '.tmp')
    $fields = 'Path', 'Name', 'App', 'Group', 'Category', 'Coverage', 'Rule', 'Answer', 'Reason', 'Explanation', 'Consequence', 'HowTo', 'Evidence', 'LookInside', 'Action', 'InUse',
        'Bytes', 'SharedBytes', 'Files', 'Unreadable', 'Growth', 'GrowthSince', 'Removable', 'Withheld', 'Selected'
    $copy = [ordered]@{}
    foreach ($p in $Scan.PSObject.Properties) { if ($p.Name -ne 'Items') { $copy[$p.Name] = $p.Value } }
    $copy.Items = @($Scan.Items | ForEach-Object {
        $row = [ordered]@{}; foreach ($f in $fields) { $row[$f] = $_.$f }
        $row.Latest = $(if ($_.Latest) { $_.Latest.ToString('o') } else { $null }); [pscustomobject]$row })
    [IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject ([pscustomobject]$copy) -Depth 4 -Compress), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination (Join-Path $dir $name) -Force
}

function Get-CCScanFiles { @(Get-ChildItem (Join-Path $script:CCData 'scans') -Filter 'scan-*.json' -ErrorAction SilentlyContinue | Sort-Object Name) }

# When a comparison scan was taken, as a reader would say it: "9:17 AM" today, "yesterday", or "Nov 7".
function Get-CCSinceText([datetime]$Utc) {
    $at = $Utc.ToLocalTime(); $today = (Get-Date).Date
    if ($at.Date -eq $today) { $at.ToString('h:mm tt') } elseif ($at.Date -eq $today.AddDays(-1)) { 'yesterday' } else { $at.ToString('MMM d') }
}

# The scan growth is measured against: the newest one at least 6 hours old, so a quick second scan doesn't hide what
# grew today. Without one, the newest scan.
function Get-CCBaselineScan {
    $files = Get-CCScanFiles
    if (-not $files) { return $null }
    $cutoff = [datetime]::UtcNow.AddHours(-6).ToString('yyyyMMdd-HHmmss')
    $old = @($files | Where-Object { $_.BaseName.Substring(5) -le $cutoff })
    ConvertFrom-CCScanFile $(if ($old) { $old[-1] } else { $files[-1] })
}

function ConvertFrom-CCScanFile($File) {
    try { Get-Content -LiteralPath $File.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null }
}

# The latest scan. -Light skips building items, for comparing sizes.
function Get-CCLastScan([switch]$Light) {
    $file = Get-CCScanFiles | Select-Object -Last 1
    if (-not $file) { return $null }
    $saved = ConvertFrom-CCScanFile $file
    if (-not $saved -or $Light) { return $saved }
    $saved.Items = @($saved.Items | ForEach-Object {
        $i = New-Object ContextCleaner.Item
        foreach ($p in 'Path', 'Name', 'App', 'Group', 'Category', 'Coverage', 'Rule', 'Answer', 'Reason', 'Explanation', 'Consequence', 'HowTo', 'Evidence', 'LookInside', 'Action', 'InUse',
            'Bytes', 'SharedBytes', 'Files', 'Unreadable', 'Growth', 'GrowthSince', 'Removable', 'Withheld', 'Selected') {
        $v = $_.$p
        if ($null -ne $_.PSObject.Properties[$p] -and $null -ne $v -and -not ($v -is [Management.Automation.PSCustomObject])) { $i.$p = $v }
        }
        if (-not $i.Coverage) { $i.Coverage = 'other' }
        if ($_.Latest) { $i.Latest = ConvertTo-CCUtc $_.Latest }
        $i
    })
    $settings = Get-CCSettings
    foreach ($i in $saved.Items) { Set-CCItemSettings $i $settings; if ($i.Ignored -or $i.IsSnoozed) { $i.Selected = $false } }
    $saved
}

# What you chose for a folder: ignored, watched, its growth is normal, a reminder, a note.
function Set-CCItemSettings($Item, $Settings) {
    $Item.Ignored = @($Settings.ignored) -contains $Item.Path
    $Item.Watched = @($Settings.watched) -contains $Item.Path
    $Item.Expected = @($Settings.expected) -contains $Item.Path
    $Item.Snoozed = $(if ($Settings.remind.ContainsKey($Item.Path)) { ConvertTo-CCUtc $Settings.remind[$Item.Path] } else { $null })
    $Item.Note = $(if ($Settings.notes.ContainsKey($Item.Path)) { $Settings.notes[$Item.Path] } else { $null })
}

# Every saved scan, summarized, and each folder's size in each: for charts and History.
function Get-CCScanIndex {
    $scans = New-Object 'Collections.Generic.List[object]'
    $series = @{}
    foreach ($file in Get-CCScanFiles) {
        $s = ConvertFrom-CCScanFile $file
        if (-not $s) { continue }
        $at = ConvertTo-CCUtc $s.FinishedAt
        $scans.Add([pscustomobject]@{ At = $at; Free = [long]$s.FreeBytes; Total = [long]$s.TotalBytes; Count = @($s.Items).Count; Seconds = $s.Seconds; File = $file.FullName })
        foreach ($i in $s.Items) {
            $key = [string]$i.Path
            if (-not $series.ContainsKey($key)) { $series[$key] = New-Object 'Collections.Generic.List[object]' }
            $series[$key].Add([pscustomobject]@{ At = $at; Bytes = [long]$i.Bytes })
        }
    }
    [pscustomobject]@{ Scans = $scans; Series = $series }
}

# Free space readings: one per scan, one when the app opens, one from each daily scan.
function Add-CCReading([long]$Total, [long]$Free) {
    New-Item -ItemType Directory -Force -Path $script:CCData | Out-Null
    $line = ConvertTo-Json -InputObject ([pscustomobject]@{ At = (Get-Date).ToUniversalTime().ToString('o'); Total = $Total; Free = $Free }) -Compress
    Add-Content -LiteralPath (Join-Path $script:CCData 'readings.jsonl') -Value $line -Encoding UTF8
}
function Get-CCReadings {
    $file = Join-Path $script:CCData 'readings.jsonl'
    $list = @()
    if (Test-Path -LiteralPath $file) { $list = @(Get-Content -LiteralPath $file -Encoding UTF8 | Where-Object { $_ } | ForEach-Object { try { $r = $_ | ConvertFrom-Json; [pscustomobject]@{ At = ConvertTo-CCUtc $r.At; Total = [long]$r.Total; Free = [long]$r.Free } } catch { } }) }
    $list
}

# Re-check items when a command is copied: anything gone, not allowed, in use or changed since the scan is left out.
function Test-CCStillOffered($Item, $Settings, $Running) {
    if (-not (Test-Path -LiteralPath $Item.Path)) { return 'Already gone' }
    if (-not (Test-CCAllowed $Item.Path $Settings)) { return 'Not allowed in a command' }
    $inUse = Get-CCInUse $Item.Path $Running
    if ($inUse) { return 'In use by ' + $inUse }
    if ((Test-Path -LiteralPath (Join-Path $Item.Path '.git') -PathType Leaf) -and -not (Test-CCBackedUp (Get-CCGitBackup $Item.Path))) { return 'Git no longer has everything in it' }
    $now = [ContextCleaner.Disk]::Measure($Item.Path, $null)
    if (-not $Item.Latest -or ($now.Latest -and $now.Latest -gt $Item.Latest.AddSeconds(2))) { return 'Changed since the scan' }
    $null
}

# The plan a command runs: what to move, what each looked like at the scan, and when the plan expires.
function New-CCPlan([object[]]$Items, [string]$MoverPath) {
    $settings = Get-CCSettings
    $running = Get-CCRunning
    $kept = @(); $left = @()
    foreach ($item in $Items) {
        $why = Test-CCStillOffered $item $settings $running
        if ($why) { $left += [pscustomobject]@{ Path = $item.Path; Name = $item.Name; Why = $why } } else { $kept += $item }
    }
    if (-not $kept) { return [pscustomobject]@{ Command = $null; Count = 0; Bytes = 0; LeftOut = $left } }
    $id = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $dir = Join-Path $script:CCData 'plans'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $plan = [pscustomobject]@{
        Id = $id; Created = (Get-Date).ToUniversalTime().ToString('o'); Expires = (Get-Date).AddHours(1).ToUniversalTime().ToString('o')
        Items = @($kept | ForEach-Object { [pscustomobject]@{ Path = $_.Path; Name = $_.Name; Answer = $_.Answer; Bytes = $_.Bytes; SharedBytes = $_.SharedBytes; Latest = $(if ($_.Latest) { $_.Latest.ToString('o') } else { $null }) } })
    }
    $file = Join-Path $dir ('plan-' + $id + '.json')
    [IO.File]::WriteAllText($file, (ConvertTo-Json -InputObject $plan -Depth 4), [Text.UTF8Encoding]::new($false))
    [pscustomobject]@{
        # Windows PowerShell is on every Windows, and this line works pasted into PowerShell or Command Prompt.
        Command = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $MoverPath + '" -Plan "' + $file + '"'
        Count = $kept.Count; Bytes = [long]($kept | Measure-Object Bytes -Sum).Sum; LeftOut = $left; PlanPath = $file
    }
}

function Get-CCHistory {
    $file = Join-Path $script:CCData 'history.jsonl'
    if (-not (Test-Path -LiteralPath $file)) { return @() }
    @(Get-Content -LiteralPath $file -Encoding UTF8 | Where-Object { $_ } | ForEach-Object { try { $_ | ConvertFrom-Json } catch { } })
}

# Look inside a WSL distribution, read-only: the biggest folders on its disk.
function Get-CCWslInside([string]$Distribution) {
    $ErrorActionPreference = 'Continue'
    $output = & wsl.exe -d $Distribution -u root -- sh -c 'df -h / | tail -1; echo; du -xh -d3 / 2>/dev/null | sort -rh | head -25' 2>&1
    (($output | Out-String) -replace [string][char]0, '').Trim()
}

function Export-CCReport($Scan, [string]$Path) {
    $tick = [string][char]96
    $free = [ContextCleaner.Format]::Bytes($Scan.FreeBytes) + ' free of ' + [ContextCleaner.Format]::Bytes($Scan.TotalBytes) + '. Scanned ' + (ConvertTo-CCUtc $Scan.FinishedAt).ToLocalTime().ToString('yyyy-MM-dd HH:mm') + '.'
    $lines = @(('# Context Cleaner report · ' + $Scan.Drive), '', $free)
    if ($Scan.RecycleBytes) { $lines += ('The Recycle Bin holds ' + [ContextCleaner.Format]::Bytes($Scan.RecycleBytes) + '; emptying it frees that.') }
    $lines += @('', '| Answer | Size |', '|---|---:|')
    foreach ($a in $script:AnswerOrder) { $lines += '| ' + $a + ' | ' + [ContextCleaner.Format]::Bytes([long]($Scan.Items | Where-Object { $_.Answer -eq $a } | Measure-Object Bytes -Sum).Sum) + ' |' }
    foreach ($a in $script:AnswerOrder) {
        $rows = @($Scan.Items | Where-Object { $_.Answer -eq $a } | Sort-Object Bytes -Descending)
        if (-not $rows) { continue }
        $lines += '', ('## ' + $a), '', '| Size | Folder | Why | Last changed | Path |', '|---:|---|---|---|---|'
        foreach ($i in $rows | Select-Object -First 40) { $lines += '| ' + $i.SizeText + ' | ' + $i.Name + ' | ' + $i.Reason + ' | ' + $i.LatestText + ' | ' + $tick + $i.Path + $tick + ' |' }
    }
    [IO.File]::WriteAllText($Path, ($lines -join $script:NL), [Text.UTF8Encoding]::new($false))
}

# Windows PowerShell, for the daily scan and the Start menu shortcut. It ships with every Windows 10 and 11.
function Get-CCPowerShell { Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell\v1.0\powershell.exe' }

# The daily scan: a Task Scheduler task in your account that reads sizes only, so charts have a reading every day.
$script:TaskName = 'Context Cleaner daily scan'
function Get-CCSchedule {
    $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
    if (-not $task) { return $null }
    $info = $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
    [pscustomobject]@{ Next = $info.NextRunTime; Last = $(if ($info.LastRunTime -and $info.LastRunTime.Year -gt 2000) { $info.LastRunTime }) }
}
function Set-CCSchedule([bool]$On) {
    if (-not $On) { Unregister-ScheduledTask -TaskName $script:TaskName -Confirm:$false -ErrorAction SilentlyContinue; return }
    $arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $script:CCApp 'ContextCleaner.ps1') + '" -Scan'
    $action = New-ScheduledTaskAction -Execute (Get-CCPowerShell) -Argument $arguments -WorkingDirectory $script:CCApp
    $trigger = New-ScheduledTaskTrigger -Daily -At '12:30'
    $options = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -Priority 7
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $script:TaskName -Action $action -Trigger $trigger -Settings $options -Principal $principal -Description 'Context Cleaner reads folder sizes and dates. It never deletes files.' -Force | Out-Null
}

# A Start menu shortcut with the app's icon, opening without a console window.
function Get-CCShortcutPath { Join-Path ([Environment]::GetFolderPath('Programs')) 'Context Cleaner.lnk' }
function Set-CCShortcut([bool]$On) {
    $path = Get-CCShortcutPath
    if (-not $On) { Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue; return }
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($path)
    $link.TargetPath = Get-CCPowerShell
    $link.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $script:CCApp 'ContextCleaner.ps1') + '"'
    $link.WorkingDirectory = $script:CCApp
    $link.IconLocation = (Join-Path $script:CCApp 'icon.ico') + ',0'
    $link.WindowStyle = 7
    $link.Description = 'See what fills your drive. Never deletes a thing.'
    $link.Save()
}

