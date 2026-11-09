# Writes made-up scans, History and readings for screenshots, into a folder you name. Nothing real is read.
#   powershell -NoProfile -ExecutionPolicy Bypass -File windows\Tools\New-DemoData.ps1 -Out C:\temp\cc-demo
#   then: $env:CONTEXT_CLEANER_DATA = 'C:\temp\cc-demo'; $env:CONTEXT_CLEANER_DEMO = '1'; powershell -STA -File windows\ContextCleaner.ps1
param([Parameter(Mandatory = $true)][string]$Out)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\ContextCleaner.Core.ps1')
if (Test-Path -LiteralPath $Out) { throw ('Choose a folder that does not exist yet: ' + $Out) }
New-Item -ItemType Directory -Path (Join-Path $Out 'scans') | Out-Null
$GB = 1073741824; $MB = 1048576
$userHome = 'C:\Users\you'
# Name, path, app, group, category, rule, answer, reason, GB, idle days, growth GB, explanation, consequence, how to
$rows = @(
    @('harbor · build\windows-0.7', 'C:\src\harbor\build\windows-0.7', 'Your projects', 'Projects', 'Build output', 'build', 'Safe to remove', 'Build output, untouched 21 days', 19.8, 21, 0, 'Output a build produced. The source is in the project.', 'Nothing. A newer build exists, or the next build recreates it.', ''),
    @('harbor · build\windows-0.8', 'C:\src\harbor\build\windows-0.8', 'Your projects', 'Projects', 'Build output', 'build', 'Safe to remove', 'Build output, untouched 12 days', 20.4, 12, 0, 'Output a build produced. The source is in the project.', 'Nothing. A newer build exists, or the next build recreates it.', ''),
    @('harbor · build\windows-0.9', 'C:\src\harbor\build\windows-0.9', 'Your projects', 'Projects', 'Build output', 'build', 'Rebuildable', 'Newest build here, changed today', 21.1, 0.2, 6.3, 'Output of your latest build in this folder.', 'You rebuild it from source if you need its files again.', ''),
    @('tidepool · node_modules', 'C:\src\tidepool\node_modules', 'Your projects', 'Projects', 'Build output', 'build', 'Safe to remove', 'Build output, untouched 34 days', 2.4, 34, 0, 'Packages npm installed for this project.', 'Nothing. npm install puts them back.', ''),
    @('Codex runtime previous-4f1c', ($userHome + '\.cache\codex-runtimes\codex-primary-runtime.previous-4f1c'), 'Codex', 'AI tools', 'Old Codex runtimes', 'runtime-old', 'Safe to remove', 'Old runtime, untouched 9 days', 1.3, 9, 0, 'An older Codex runtime kept after an update.', 'Nothing. Codex runs from codex-primary-runtime.', ''),
    @('npm download cache', ($userHome + '\AppData\Local\npm-cache'), 'npm', 'Developer tools', 'Package downloads', 'cache', 'Safe to remove', 'Package cache, untouched 11 days', 3.2, 11, 0, 'Downloads a package tool keeps so the next install is faster.', 'Nothing. The tool downloads what it needs again.', ''),
    @('Gradle cache', ($userHome + '\.gradle\caches'), 'Gradle', 'Developer tools', 'Package downloads', 'cache', 'Rebuildable', 'Used this week', 6.1, 2, 0.4, 'Downloads a package tool keeps so the next install is faster.', 'The next build downloads again and takes longer.', ''),
    @('DirectX shader cache', ($userHome + '\AppData\Local\D3DSCache'), 'DirectX', 'Windows', 'Shader caches', 'shader', 'Safe to remove', 'Shader cache, untouched 15 days', 1.1, 15, 0, 'Shaders the graphics driver compiled so games start faster.', 'Nothing. The driver compiles them again.', ''),
    @('Codex task folder 2026-10-30', ($userHome + '\Documents\Codex\2026-10-30'), 'Codex', 'AI tools', 'Codex task folders', 'codex-task', 'Review first', 'Codex task, untouched 9 days', 4.6, 9, 0, 'Files a Codex task made: reports, downloads, scripts and copies.', 'May hold the only copy of a task output. Look inside first.', ''),
    @('Codex task folder 2026-11-02', ($userHome + '\Documents\Codex\2026-11-02'), 'Codex', 'AI tools', 'Codex task folders', 'codex-task', 'Review first', 'Codex task, untouched 6 days', 2.9, 6, 0, 'Files a Codex task made: reports, downloads, scripts and copies.', 'May hold the only copy of a task output. Look inside first.', ''),
    @('Crash dump · renderer.exe.4120.dmp', ($userHome + '\AppData\Local\CrashDumps\renderer.exe.4120.dmp'), 'Windows Error Reporting', 'Windows', 'Crash dumps', 'crash', 'Review first', 'Recent crash, untouched 4 days', 0.6, 4, 0, 'What a program left behind when it crashed.', 'You can no longer study or send this crash.', ''),
    @('Temp · playwright-run-81', ($userHome + '\AppData\Local\Temp\playwright-run-81'), 'Apps and tools', 'Developer tools', 'Temporary files', 'temp', 'Safe to remove', 'Temporary, untouched 8 days', 3.7, 8, 0, 'Work files an app or tool left in your temporary folder.', 'Nothing. Nothing keeps temporary files.', ''),
    @('WSL disk · Ubuntu', ($userHome + '\AppData\Local\wsl\{demo}\ext4.vhdx'), 'WSL', 'Virtual machines', 'Virtual machines', 'vm-wsl', 'Not for the Recycle Bin', 'Whole Linux system', 96.2, 0, 18.5, 'The disk of a WSL Linux distribution. Everything inside Linux lives in this one file.', 'Removing it deletes the whole Linux system and its files.', 'Use Look Inside to see what fills it. To keep everything but free this drive, move it to D: (3.1 TB free): wsl --shutdown, then wsl --manage Ubuntu --move D:\WSL\Ubuntu.'),
    @('Docker Desktop disk · disk', ($userHome + '\AppData\Local\Docker\wsl\disk\docker_data.vhdx'), 'Docker Desktop', 'Virtual machines', 'Virtual machines', 'vm-docker', 'Not for the Recycle Bin', 'Docker images and containers', 31.4, 1, 2.2, 'The disk that holds every Docker image, container and volume.', 'Removing it deletes all of them.', 'Remove what you no longer need in Docker Desktop, then compact the disk.'),
    @('Starfall Tactics', 'C:\Program Files (x86)\Steam\steamapps\common\Starfall Tactics', 'Steam', 'Games', 'Games', 'game', 'Not for the Recycle Bin', 'Installed game, untouched 412 days', 58.7, 412, 0, 'A game installed through Steam.', 'Steam would still list it as installed.', 'To keep it but free this drive, move it to D: with Steam > Settings > Storage > Move.'),
    @('Lantern Road', 'C:\Program Files (x86)\Steam\steamapps\common\Lantern Road', 'Steam', 'Games', 'Games', 'game', 'Not for the Recycle Bin', 'Installed game, untouched 37 days', 24.9, 37, 0, 'A game installed through Steam.', 'Steam would still list it as installed.', 'To keep it but free this drive, move it to D: with Steam > Settings > Storage > Move.'),
    @('Codex conversations', ($userHome + '\.codex\sessions'), 'Codex', 'AI tools', 'Chat history', 'history', 'Not for the Recycle Bin', 'Chat history', 2.3, 0, 0.1, 'Conversation records this app keeps.', 'Removing them loses conversation history.', 'Manage conversations inside the app.'),
    @('Windows Update downloads', 'C:\Windows\SoftwareDistribution\Download', 'Windows Update', 'Windows', 'System files', 'windows-temp', 'Not for the Recycle Bin', 'Windows cleans it', 4.8, 3, 0, 'Files Windows keeps for itself.', 'Windows removes them safely itself.', 'Settings > System > Storage > Temporary files.'),
    @('Media Library', ($userHome + '\AppData\Local\Media Library'), 'Everything else', 'Everything else', '~\AppData\Local', 'other', 'Everything else', 'Not a known place', 14.2, 0, 0, 'A folder Context Cleaner has no rule for.', 'Unknown. Look inside.', 'Open it in Explorer to see what it holds.')
)
function Sum($list) { $t = [long]0; foreach ($i in $list) { $t += $i.Bytes }; $t }
$now = [datetime]::UtcNow
$drive = New-Object IO.DriveInfo 'C:\'; $total = $drive.TotalSize
$scansAt = @($now.AddDays(-6), $now.AddDays(-3), $now.AddHours(-8), $now.AddMinutes(-5))
for ($s = 0; $s -lt $scansAt.Count; $s++) {
    $at = $scansAt[$s]; $last = $s -eq $scansAt.Count - 1
    $shrink = ($scansAt.Count - 1 - $s) / [double]($scansAt.Count - 1)
    $items = foreach ($r in $rows) {
        $bytes = [long](($r[8] - $r[10] * $shrink) * $GB)
        $removable = 'Safe to remove', 'Rebuildable', 'Review first' -contains $r[6]
        [pscustomobject]@{ Path = $r[1]; Name = $r[0]; App = $r[2]; Group = $r[3]; Category = $r[4]; Coverage = 'demo'; Rule = $r[5]; Answer = $r[6]; Reason = $r[7]
            Explanation = $r[11]; Consequence = $r[12]; HowTo = $r[13]; Evidence = ''; LookInside = $(if ($r[5] -eq 'vm-wsl') { 'Ubuntu' } else { $null }); Action = $null; InUse = $null
            Bytes = $bytes; SharedBytes = 0; Files = 1000; Unreadable = 0; Growth = $(if ($last -and $r[10]) { [long]($r[10] * 0.7 * $GB) } else { $null }); GrowthSince = $(if ($last) { Get-CCSinceText $scansAt[2] } else { $null })
            Removable = $removable; Withheld = $false; Selected = ($r[6] -eq 'Safe to remove'); Latest = $at.AddDays(-$r[9]).ToString('o') }
    }
    $used = $total - $drive.AvailableFreeSpace - [long](30 * $GB * $shrink)
    $scan = [pscustomobject]@{ Version = '0.1.0'; StartedAt = $at.AddSeconds(-30).ToString('o'); FinishedAt = $at.ToString('o'); Seconds = 31; Drive = 'C:\'; TotalBytes = $total
        FreeBytes = $total - $used; RecycleBytes = [long](8.4 * $GB); PreviousAt = $(if ($last) { $scansAt[2].ToString('o') } else { $null }); ProjectRoots = @('C:\src'); Items = @($items) }
    [IO.File]::WriteAllText((Join-Path $Out ('scans\scan-' + $at.ToString('yyyyMMdd-HHmmss') + '.json')), (ConvertTo-Json -InputObject $scan -Depth 4 -Compress))
}
$history = @(
    [pscustomobject]@{ Plan = 'demo1'; At = $now.AddDays(-5).ToString('o'); Bytes = [long](38.6 * $GB); Count = 3; Moved = @('C:\src\harbor\build\windows-0.4', 'C:\src\harbor\build\windows-0.5', 'C:\src\harbor\build\windows-0.6'); NotMoved = @(); Gone = @() },
    [pscustomobject]@{ Plan = 'demo2'; At = $now.AddDays(-2).ToString('o'); Bytes = [long](9.3 * $GB); Count = 3; Moved = @(($userHome + '\AppData\Local\Temp\playwright-run-77'), ($userHome + '\.cache\codex-runtimes\codex-primary-runtime.previous-1a2b')); NotMoved = @([pscustomobject]@{ Path = ($userHome + '\Documents\Codex\2026-10-21'); Why = 'changed since the scan; scan again' }); Gone = @() }
)
[IO.File]::WriteAllLines((Join-Path $Out 'history.jsonl'), [string[]]@($history | ForEach-Object { ConvertTo-Json -InputObject $_ -Compress -Depth 4 }))
$settings = [pscustomobject]@{ projectRoots = [string[]]@('C:\src'); tracked = [string[]]@(); ignored = [string[]]@(); scanningOff = [string[]]@(); watched = [string[]]@(); coverageOff = [string[]]@(); appearance = 'System'; terminal = 'wt'; untouchedDays = 1; byKind = $true }
[IO.File]::WriteAllText((Join-Path $Out 'settings.json'), (ConvertTo-Json -InputObject $settings))
'Demo data written to ' + $Out

