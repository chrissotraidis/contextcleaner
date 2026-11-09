# Context Cleaner for Windows: tests that need no window and never touch your own data.
# Run with Windows PowerShell (every Windows has it) and, if installed, PowerShell 7:
#   powershell -NoProfile -ExecutionPolicy Bypass -File windows\Tests\Run-Tests.ps1
#   pwsh -NoProfile -File windows\Tests\Run-Tests.ps1
# The mover test moves a folder it made into the Recycle Bin, then removes that folder from the bin.
$ErrorActionPreference = 'Stop'
$app = Split-Path $PSScriptRoot -Parent
$work = Join-Path ([IO.Path]::GetTempPath()) ('cc-tests-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
$env:CONTEXT_CLEANER_DATA = Join-Path $work 'data'
. (Join-Path $app 'ContextCleaner.Core.ps1')
$script:Failures = 0; $script:Checks = 0
function Check([string]$Name, [bool]$Condition, [string]$Detail = '') {
    $script:Checks++
    if ($Condition) { Write-Host ('ok    ' + $Name) } else { $script:Failures++; Write-Host ('FAIL  ' + $Name + $(if ($Detail) { ' (' + $Detail + ')' } else { '' })) -ForegroundColor Red }
}
Write-Host ('PowerShell ' + $PSVersionTable.PSVersion + ' · data in ' + $env:CONTEXT_CLEANER_DATA)

# Files: every script parses and is saved as UTF-8 with a byte-order mark, which Windows PowerShell 5.1 needs.
foreach ($f in Get-ChildItem $app -Recurse -Filter *.ps1) {
    $errors = $null; [void][Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors)
    Check ('parses: ' + $f.Name) (-not $errors) (($errors | Select-Object -First 1) -as [string])
    $b = [IO.File]::ReadAllBytes($f.FullName)
    Check ('UTF-8 with BOM: ' + $f.Name) ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
}
if ([Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA') {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $xaml = [IO.File]::ReadAllText((Join-Path $app 'ContextCleaner.xaml'))
    $loaded = $null; try { $loaded = [Windows.Markup.XamlReader]::Parse($xaml) } catch { $loaded = $_.Exception.Message }
    Check 'window XAML loads' ($loaded -is [Windows.Window]) ([string]$loaded)
    $names = [regex]::Matches((Get-Content (Join-Path $app 'ContextCleaner.ps1') -Raw), '\$ui\.(\w+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    $missing = @($names | Where-Object { $xaml -notmatch ('x:Name="' + $_ + '"') })
    Check 'every control the script uses exists in the XAML' (-not $missing) ($missing -join ', ')
}

# Sizes as Explorer shows them.
Check 'format 0' ([ContextCleaner.Format]::Bytes(0) -eq '0 B')
Check 'format 1.5 GB' ([ContextCleaner.Format]::Bytes(1610612736) -eq '1.5 GB')
Check 'format signed' ([ContextCleaner.Format]::Signed(-1048576) -eq ([string][char]0x2212 + '1.0 MB'))

# Measuring: sizes, hardlinks counted once, links never followed.
$m = Join-Path $work 'measure'
New-Item -ItemType Directory -Path "$m\a\b", "$m\target" -Force | Out-Null
[IO.File]::WriteAllBytes("$m\a\one.bin", (New-Object byte[] 1000))
[IO.File]::WriteAllBytes("$m\a\b\two.bin", (New-Object byte[] 2000))
[IO.File]::WriteAllBytes("$m\target\outside.bin", (New-Object byte[] 5000))
$big = "$m\a\big.bin"; $fs = [IO.File]::Create($big); $fs.SetLength(9MB); $fs.Close()
New-Item -ItemType HardLink -Path "$m\big-link.bin" -Target $big | Out-Null
New-Item -ItemType Junction -Path "$m\a\junction" -Target "$m\target" | Out-Null
$r = [ContextCleaner.Disk]::Measure("$m\a", $null)
Check 'measures files under a folder' ($r.Bytes -eq 3000 -and $r.Files -eq 3) ('bytes ' + $r.Bytes + ', files ' + $r.Files)
Check 'counts a hardlinked big file as shared' ($r.SharedBytes -eq 9MB) ('shared ' + $r.SharedBytes)
Check 'never follows a junction' ($r.Bytes -lt 5000)
Check 'reports the newest change' ($r.Latest -and ([datetime]::UtcNow - $r.Latest).TotalMinutes -lt 5)
$skipped = [ContextCleaner.Disk]::MeasureAll([string[]]@("$m\a"), [string[]]@("$m\a\b"))[0]
Check 'leaves out folders measured on their own' ($skipped.Bytes -eq 1000)
Check 'a junction itself is a link' ([ContextCleaner.Disk]::Measure("$m\a\junction", $null).Link)
New-Item -ItemType Directory -Path "$m\empty" | Out-Null
Check 'an empty folder still has a date' ([bool][ContextCleaner.Disk]::Measure("$m\empty", $null).Latest)
Check 'a saved empty object reads as no date' ($null -eq (ConvertTo-CCUtc ([pscustomobject]@{})))
Check 'an ISO date reads back in UTC' ((ConvertTo-CCUtc '2026-11-08T12:00:00.0000000Z').Hour -eq 12)

# Paths: what a command may ever move.
$settings = [pscustomobject]@{ projectRoots = @("$work\projects"); tracked = @(); ignored = @(); scanningOff = @(); watched = @(); coverageOff = @() }
New-Item -ItemType Directory -Path "$work\projects\app\build\old", "$work\br[a]ck\x", "$work\real" -Force | Out-Null
New-Item -ItemType Junction -Path "$work\to-home" -Target $script:CCHome | Out-Null
$h = $script:CCHome
$cases = [ordered]@{
    $h = $false; "$h\Documents" = $false; "$h\.ssh" = $false; "$h\.codex" = $false; "$h\.codex\sessions\x" = $false; $script:CCLocal = $false
    "$h\AppData\Local\SomeApp" = $false; "$h\AppData\Local\npm-cache" = $true; "$h\AppData\Local\D3DSCache" = $true; 'C:\Windows' = $false
    'C:\Program Files' = $false; "$work\projects" = $false; "$work\projects\app" = $false; "$work\projects\app\build\old" = $true
    "$work\real" = $true; "$work\br[a]ck\x" = $true; "$work\to-home\Documents" = $false; "$work\to-home" = $false; $script:CCTemp = $false
    "$work\projects\app\build\..\..\app" = $false; $app = $false; $script:CCData = $false
}
foreach ($k in $cases.Keys) { Check ('allowed ' + $cases[$k] + ': ' + $k) ((Test-CCAllowed $k $settings) -eq $cases[$k]) }
Check 'inside is plain text, not a wildcard' ((Test-CCInside 'C:\a[1]\b' 'C:\a[1]') -and -not (Test-CCInside 'C:\ab' 'C:\a'))
$s2 = [pscustomobject]@{ projectRoots = @(); tracked = @('C:\Program Files (x86)'); ignored = @(); scanningOff = @(); watched = @(); coverageOff = @() }
Check 'tracking never opens Program Files to a command' (-not (Test-CCAllowed 'C:\Program Files (x86)\Steam' $s2))

# Answers.
function New-TestItem([string]$Rule, [double]$IdleDays, [string]$Path = "$work\real") {
    $i = New-Object ContextCleaner.Item; $i.Path = $Path; $i.Name = 'x'; $i.Rule = $Rule; $i.Latest = [datetime]::UtcNow.AddDays(-$IdleDays); $i
}
$place = { param($rule) [pscustomobject]@{ Rule = $rule; Repo = $null; LookInside = 'Ubuntu'; Siblings = $null } }
$expect = @(@('cache', 10, 'Safe to remove'), @('cache', 2, 'Rebuildable'), @('temp', 5, 'Safe to remove'), @('temp', 1, 'Review first'),
    @('shader', 9, 'Safe to remove'), @('crash', 20, 'Safe to remove'), @('crash', 3, 'Review first'), @('runtime-old', 10, 'Safe to remove'),
    @('runtime-current', 10, 'Not for the Recycle Bin'), @('history', 99, 'Not for the Recycle Bin'), @('vm-wsl', 1, 'Not for the Recycle Bin'),
    @('game', 900, 'Not for the Recycle Bin'), @('codex-task', 60, 'Review first'), @('other', 1, 'Everything else'))
foreach ($e in $expect) { $i = New-TestItem $e[0] $e[1]; Resolve-CCAnswer $i (& $place $e[0]) $null $null; Check ('answer ' + $e[0] + ' after ' + $e[1] + ' days: ' + $e[2]) ($i.Answer -eq $e[2]) $i.Answer }
# Build folders: "build" is output by name; any other build-like name is output only when the project's git ignores it.
$builds = [pscustomobject]@{ Rule = 'build'; Repo = $null; LookInside = $null; Siblings = "$work\projects\app\build" }
$old = New-TestItem 'build' 10 "$work\projects\app\build\old"; Resolve-CCAnswer $old $builds $null $null
Check 'an old build in a build folder is Safe to remove' ($old.Answer -eq 'Safe to remove') $old.Answer
$newest = New-TestItem 'build' 30 "$work\projects\app\build\old"; Resolve-CCAnswer $newest $builds $newest.Path $null
Check 'the newest build in a folder is Rebuildable' ($newest.Answer -eq 'Rebuildable')
$dist = New-TestItem 'build' 30 "$work\projects\app\dist"; Resolve-CCAnswer $dist (& $place 'build') $null $null
Check 'a dist folder no git vouches for is Review first' ($dist.Answer -eq 'Review first' -and $dist.Reason -eq 'Not in a git repository') $dist.Reason
if (Get-Command git -ErrorAction SilentlyContinue) {
    $gp = Join-Path $work 'gitproj'; New-Item -ItemType Directory -Path "$gp\dist", "$gp\out" -Force | Out-Null
    $ErrorActionPreference = 'Continue'; & git -C $gp init -q 2>$null; $ErrorActionPreference = 'Stop'
    Set-Content -LiteralPath "$gp\.gitignore" 'dist'
    $inRepo = [pscustomobject]@{ Rule = 'build'; Repo = $gp; LookInside = $null; Siblings = $null }
    $ignoredDist = New-TestItem 'build' 30 "$gp\dist"; Resolve-CCAnswer $ignoredDist $inRepo $null $null
    Check 'a dist folder git ignores is Safe to remove' ($ignoredDist.Answer -eq 'Safe to remove') ($ignoredDist.Answer + ': ' + $ignoredDist.Reason)
    $plainOut = New-TestItem 'build' 30 "$gp\out"; Resolve-CCAnswer $plainOut $inRepo $null $null
    Check 'an out folder git does not ignore is Review first' ($plainOut.Answer -eq 'Review first' -and $plainOut.Reason -eq 'Tracked in git') $plainOut.Reason
    # Not in git: a folder a project's git ignores, other than build output, is found and is Review first.
    $dr = "$work\projects\data-repo"; New-Item -ItemType Directory -Path "$dr\datasets\raw", "$dr\node_modules\x" -Force | Out-Null
    Set-Content -LiteralPath "$dr\datasets\raw\a.bin" 'data'; Set-Content -LiteralPath "$dr\node_modules\x\i.js" 'x'
    $ErrorActionPreference = 'Continue'; & git -C $dr init -q 2>$null; $ErrorActionPreference = 'Stop'
    Set-Content -LiteralPath "$dr\.gitignore" "datasets/$([Environment]::NewLine)node_modules/"
    $found = @(Get-CCPlaces $settings | Where-Object { $_.Rule -eq 'notingit' })
    Check 'finds a folder git ignores, and leaves build output to its own rule' (@($found | Where-Object { $_.Path -eq "$dr\datasets" }).Count -eq 1 -and -not ($found | Where-Object { $_.Path -like '*node_modules*' })) (($found | ForEach-Object { $_.Path }) -join ', ')
    $ng = New-TestItem 'notingit' 90 "$dr\datasets"; Resolve-CCAnswer $ng ([pscustomobject]@{ Rule = 'notingit'; Repo = $dr; LookInside = $null; Siblings = $null }) $null $null
    Check 'a folder only on this PC is Review first however old' ($ng.Answer -eq 'Review first' -and $ng.Reason -eq 'Not in git, only on this PC') $ng.Reason
}
$wsl = New-TestItem 'vm-wsl' 1 'C:\wsl\ext4.vhdx'; Resolve-CCAnswer $wsl (& $place 'vm-wsl') $null ([pscustomobject]@{ Name = 'D:'; Free = 500GB })
Check 'WSL advice names the roomy drive and wsl --manage --move' ($wsl.HowTo -match 'wsl --manage Ubuntu --move D:')
$g = New-TestItem 'game' 900 'C:\Program Files (x86)\Steam\steamapps\common\X'; Resolve-CCAnswer $g (& $place 'game') $null ([pscustomobject]@{ Name = 'D:'; Free = 500GB })
Check 'game advice says Steam can move it' ($g.HowTo -match 'Steam > Settings > Storage')

# Settings: empty lists stay empty lists.
# Git: a repository git refuses to read (it writes to stderr) answers "unknown", even when errors stop the script.
$repo = Join-Path $work 'not-a-repo'; New-Item -ItemType Directory -Path $repo | Out-Null
$gitResult = 'threw'; try { $gitResult = Invoke-CCGit $repo @('status', '--porcelain') } catch { }
if (Get-Command git -ErrorAction SilentlyContinue) { Check 'git errors never stop a scan' ($null -eq $gitResult) ([string]$gitResult) }
Save-CCSettings ([pscustomobject]@{ projectRoots = @('C:\keep'); projectRootsFound = $false; tracked = @(); ignored = @(); scanningOff = @(); watched = @(); coverageOff = @(); appearance = 'Dark'; terminal = 'wt'; untouchedDays = 3; byKind = $true })
$back = Get-CCSettings
Check 'settings round-trip' ($back.appearance -eq 'Dark' -and $back.untouchedDays -eq 3 -and $back.byKind -and @($back.tracked).Count -eq 0 -and @($back.projectRoots) -contains 'C:\keep')
Save-CCSettings ([pscustomobject]@{ projectRoots = @(); projectRootsFound = $true; tracked = @(); ignored = @(); scanningOff = @(); watched = @(); coverageOff = @(); appearance = 'System'; terminal = 'wt'; untouchedDays = 1; byKind = $false })
$raw = Get-Content (Join-Path $script:CCData 'settings.json') -Raw
Check 'found project folders are not frozen into settings' ($raw -match '"projectRoots":\s*\[\s*\]') $raw.Substring(0, [math]::Min(80, $raw.Length))
# Reminders, notes, normal growth and window placement round-trip; a reminder that has passed is dropped.
$s = Get-CCSettings
$s.remind['C:\later'] = [datetime]::UtcNow.AddDays(1).ToString('o'); $s.remind['C:\past'] = [datetime]::UtcNow.AddDays(-1).ToString('o')
$s.notes['C:\noted'] = 'keep for the demo'; $s.expected = @('C:\grows'); $s.window = [pscustomobject]@{ Left = 10; Top = 20; Width = 1200; Height = 800; Max = $false }
Save-CCSettings $s
$back = Get-CCSettings
Check 'reminders round-trip, and passed ones drop' ($back.remind.ContainsKey('C:\later') -and -not $back.remind.ContainsKey('C:\past'))
Check 'notes, normal growth and window placement round-trip' ($back.notes['C:\noted'] -eq 'keep for the demo' -and @($back.expected) -contains 'C:\grows' -and $back.window.Width -eq 1200)
$it = New-Object ContextCleaner.Item; $it.Path = 'C:\later'; $it.Bytes = 10GB; $it.Growth = 5GB
Check 'a big change is growing' $it.Growing
Set-CCItemSettings $it $back
Check 'Remind Me Tomorrow snoozes the item' $it.IsSnoozed
$it.Path = 'C:\grows'; Set-CCItemSettings $it $back
Check 'growth you call normal is not growing' (-not $it.Growing)
$it.Path = 'C:\noted'; Set-CCItemSettings $it $back
Check 'a note is attached to its folder' ($it.Note -eq 'keep for the demo')

# The move command: rechecks each item, moves only to the Recycle Bin, and expires.
$mv = Join-Path $script:CCTemp ('cc-test-move-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Path "$mv\movable\inner", "$mv\changed", "$mv\target" -Force | Out-Null
Set-Content "$mv\movable\inner\a.txt" 'fixture'; Set-Content "$mv\changed\b.txt" 'fixture'
New-Item -ItemType Junction -Path "$mv\link" -Target "$mv\target" | Out-Null
function Entry($p) { $x = [ContextCleaner.Disk]::Measure($p, $null); [pscustomobject]@{ Path = $p; Name = (Split-Path $p -Leaf); Answer = 'Safe to remove'; Bytes = $x.Bytes; SharedBytes = 0; Latest = $(if ($x.Latest) { $x.Latest.ToString('o') } else { $null }) } }
$entries = @((Entry "$mv\movable"), (Entry "$mv\changed"), (Entry "$mv\link"), (Entry "$mv\missing"), (Entry "$h\Documents"))
Start-Sleep -Seconds 3
Set-Content "$mv\changed\c.txt" 'changed after the scan'
$planFile = Join-Path $work 'plan.json'
[IO.File]::WriteAllText($planFile, (ConvertTo-Json -Depth 4 -InputObject ([pscustomobject]@{ Id = 'test'; Expires = [datetime]::UtcNow.AddHours(1).ToString('o'); Items = $entries })))
$mover = Join-Path $app 'Move-ToRecycleBin.ps1'
$ps = Get-CCPowerShell
$preview = & $ps -NoProfile -ExecutionPolicy Bypass -File $mover -Plan $planFile -WhatIf | Out-String
Check '-WhatIf moves nothing' ((Test-Path "$mv\movable") -and $preview -match 'Would move: .*movable') $preview
$binBefore = [ContextCleaner.RecycleBin]::Bytes([IO.Path]::GetPathRoot($mv))
$output = & $ps -NoProfile -ExecutionPolicy Bypass -File $mover -Plan $planFile | Out-String
Check 'moves an unchanged item' (-not (Test-Path "$mv\movable") -and $output -match 'Moved: .*movable') $output
$binAfter = [ContextCleaner.RecycleBin]::Bytes([IO.Path]::GetPathRoot($mv))
Check 'reads the Recycle Bin size live' ($binBefore -ge 0 -and $binAfter -gt $binBefore) ([string]$binBefore + ' then ' + $binAfter)
Check 'leaves an item changed since the scan' ((Test-Path "$mv\changed") -and $output -match 'changed since the scan')
Check 'leaves a link alone' ((Test-Path "$mv\link") -and (Test-Path "$mv\target") -and $output -match 'a link; left alone')
Check 'says what is already gone' ($output -match 'Already gone: .*missing')
Check 'never moves Documents' ((Test-Path "$h\Documents") -and $output -match 'Documents \(not allowed')
$history = @(Get-Content (Join-Path $script:CCData 'history.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
Check 'records the cleanup in History' ($history.Count -eq 1 -and @($history[0].Moved).Count -eq 1)
[IO.File]::WriteAllText($planFile, (ConvertTo-Json -Depth 4 -InputObject ([pscustomobject]@{ Id = 'old'; Expires = [datetime]::UtcNow.AddHours(-1).ToString('o'); Items = @((Entry "$mv\changed")) })))
$old = & $ps -NoProfile -ExecutionPolicy Bypass -File $mover -Plan $planFile | Out-String
Check 'an hour-old command moves nothing' ((Test-Path "$mv\changed") -and $old -match 'over an hour old')

# Clean up: the fixture that went to the Recycle Bin, then everything else this run made.
$shell = New-Object -ComObject Shell.Application
foreach ($item in @($shell.Namespace(10).Items() | Where-Object { $_.ExtendedProperty('System.Recycle.DeletedFrom') -eq $mv })) {
    $p = $item.Path; Remove-Item -LiteralPath $p -Recurse -Force
    Remove-Item -LiteralPath (Join-Path (Split-Path $p -Parent) ('$I' + (Split-Path $p -Leaf).Substring(2))) -Force -ErrorAction SilentlyContinue
}
foreach ($j in "$mv\link", "$m\a\junction", "$work\to-home") { if (Test-Path -LiteralPath $j) { [IO.Directory]::Delete($j) } }
Remove-Item -LiteralPath $mv, $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host ([string]$script:Checks + ' checks, ' + $script:Failures + ' failed')
exit $(if ($script:Failures) { 1 } else { 0 })

