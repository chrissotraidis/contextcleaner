# Moves the items in a Context Cleaner plan to the Recycle Bin, checking each one again first.
# Prints Moved, Already gone or NOT moved for every item. Nothing is deleted: Restore works until you empty the bin.
# -WhatIf runs every check and says what would happen, without moving anything.
# Context Cleaner's Move to Recycle Bin button runs this same script with -Yes (it asked already, in its window) and -Log,
# a file it reads to show progress.
param([Parameter(Mandatory = $true)][string]$Plan, [switch]$WhatIf, [switch]$Yes, [string]$Log)

. (Join-Path $PSScriptRoot 'ContextCleaner.Core.ps1')
function Say([string]$Text) {
    Write-Host $Text
    if ($Log) { try { [IO.File]::AppendAllText($Log, $Text + [Environment]::NewLine, (New-Object Text.UTF8Encoding $false)) } catch { } }
}

$planData = $null
try { $planData = Get-Content -LiteralPath $Plan -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json } catch { }
if (-not $planData -or -not $planData.Expires) {
    Say ('Context Cleaner could not read the list of items for this command (' + $Plan + '), so nothing was moved. Use Move to Recycle Bin in Context Cleaner, or copy a fresh command.')
    exit 1
}
$items = @($planData.Items)
if ([datetime]::UtcNow -gt (ConvertTo-CCUtc $planData.Expires)) {
    Say 'This command is over an hour old, so nothing was moved. Copy a fresh one in Context Cleaner.'
    exit 1
}

# The Recycle Bin for this drive: refuse if it deletes immediately, and warn before it overflows.
$volume = (Get-CimInstance Win32_Volume -Filter ("DriveLetter='" + $script:CCDrive.Substring(0, 2) + "'") -ErrorAction SilentlyContinue).DeviceID
$guid = if ($volume -match '\{[^}]+\}') { $Matches[0] }
$bin = if ($guid) { Get-ItemProperty ('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket\Volume\' + $guid) -ErrorAction SilentlyContinue }
if ($bin -and $bin.NukeOnDelete -eq 1) {
    Say 'The Recycle Bin on this drive is set to delete files immediately, so nothing was moved.'
    Say 'Turn that off in Recycle Bin > Properties, then run the command again.'
    exit 1
}
# The bin counts hardlinked files in full, even though removing them frees nothing.
$total = [long]0; foreach ($i in $items) { $total += [long]$i.Bytes + [long]$i.SharedBytes }
if ($bin -and $bin.MaxCapacity) {
    $capacity = [long]$bin.MaxCapacity * 1MB
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $inBin = [ContextCleaner.Disk]::Measure((Join-Path $script:CCDrive ('$Recycle.Bin\' + $sid)), $null)
    $already = $inBin.Bytes + $inBin.SharedBytes
    if ($total + $already -gt $capacity) {
        Say ('These items total ' + [ContextCleaner.Format]::Bytes($total) + '. The Recycle Bin on ' + $script:CCDrive + ' holds at most ' + [ContextCleaner.Format]::Bytes($capacity) + ' and already has ' + [ContextCleaner.Format]::Bytes($already) + '.')
        Say 'To make room, Windows will permanently delete the oldest items in the bin, so Restore will not work for them.'
        Say 'To avoid that, empty the bin first, or copy fewer items at a time, or raise its size in Recycle Bin > Properties.'
        if (-not $WhatIf -and -not $Yes -and (Read-Host 'Type YES to continue anyway') -cne 'YES') { Say 'Nothing was moved.'; exit 1 }
    }
}

$settings = Get-CCSettings
$running = Get-CCRunning
$moved = @(); $notMoved = @(); $gone = @(); $movedBytes = [long]0
foreach ($entry in $items) {
    $path = [string]$entry.Path
    $item = [pscustomobject]@{ Path = $path; Latest = (ConvertTo-CCUtc $entry.Latest) }
    if (-not (Test-Path -LiteralPath $path)) { $gone += $path; Say ('Already gone: ' + $path); continue }
    $why = $null
    if (Test-CCLink $path) { $why = 'a link; left alone' }
    else {
        $reason = Test-CCStillOffered $item $settings $running
        if ($reason) { $why = $reason.Substring(0, 1).ToLower() + $reason.Substring(1) + $(if ($reason -eq 'Changed since the scan') { '; scan again' } else { '' }) }
    }
    if (-not $why) {
        $size = [ContextCleaner.Disk]::Measure($path, $null).Bytes
        if ($WhatIf) { Say ('Would move: ' + $path + ' (' + [ContextCleaner.Format]::Bytes($size) + ')'); $moved += $path; $movedBytes += $size; continue }
        $code = [ContextCleaner.RecycleBin]::Send($path)
        if (-not (Test-Path -LiteralPath $path)) { $moved += $path; $movedBytes += $size; Say ('Moved: ' + $path); continue }
        $why = if ($code -eq -1) { 'cancelled' } else { 'in use or blocked (code ' + $code + ')' }
    }
    $notMoved += [pscustomobject]@{ Path = $path; Why = $why }
    Say ('NOT moved: ' + $path + ' (' + $why + ')')
}

Say ''
if ($WhatIf) {
    Say ('Would move ' + $moved.Count + ' of ' + $items.Count + ', freeing ' + [ContextCleaner.Format]::Bytes($movedBytes) + ' once the Recycle Bin is emptied. Nothing was moved.')
    exit 0
}
Say ('Moved ' + $moved.Count + ' of ' + $items.Count + ' (' + [ContextCleaner.Format]::Bytes($movedBytes) + ') to the Recycle Bin.' + $(if ($gone) { ' ' + $gone.Count + ' already gone.' }) + $(if ($notMoved) { ' ' + $notMoved.Count + ' not moved.' }))
if ($moved) { Say 'The space comes back when you empty the Recycle Bin. Until then, Restore puts anything back.' }

New-Item -ItemType Directory -Force -Path $script:CCData | Out-Null
$record = [pscustomobject]@{ Plan = $planData.Id; At = [datetime]::UtcNow.ToString('o'); Bytes = $movedBytes; Count = $items.Count; Moved = $moved; NotMoved = $notMoved; Gone = $gone }
Add-Content -LiteralPath (Join-Path $script:CCData 'history.jsonl') -Value (ConvertTo-Json -InputObject $record -Depth 4 -Compress) -Encoding UTF8


