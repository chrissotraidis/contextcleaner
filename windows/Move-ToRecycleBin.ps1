# Moves the items in a Context Cleaner plan to the Recycle Bin, checking each one again first.
# Prints Moved, Already gone or NOT moved for every item. Nothing is deleted: Restore works until you empty the bin.
# -WhatIf runs every check and says what would happen, without moving anything.
param([Parameter(Mandatory = $true)][string]$Plan, [switch]$WhatIf)

. (Join-Path $PSScriptRoot 'ContextCleaner.Core.ps1')

$planData = Get-Content -LiteralPath $Plan -Raw -Encoding UTF8 | ConvertFrom-Json
$items = @($planData.Items)
if ([datetime]::UtcNow -gt (ConvertTo-CCUtc $planData.Expires)) {
    Write-Host 'This command is over an hour old, so nothing was moved. Copy a fresh one in Context Cleaner.'
    exit 1
}

# The Recycle Bin for this drive: refuse if it deletes immediately, and warn before it overflows.
$volume = (Get-CimInstance Win32_Volume -Filter ("DriveLetter='" + $script:CCDrive.Substring(0, 2) + "'") -ErrorAction SilentlyContinue).DeviceID
$guid = if ($volume -match '\{[^}]+\}') { $Matches[0] }
$bin = if ($guid) { Get-ItemProperty ('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket\Volume\' + $guid) -ErrorAction SilentlyContinue }
if ($bin -and $bin.NukeOnDelete -eq 1) {
    Write-Host 'The Recycle Bin on this drive is set to delete files immediately, so nothing was moved.'
    Write-Host 'Turn that off in Recycle Bin > Properties, then run the command again.'
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
        Write-Host ('These items total ' + [ContextCleaner.Format]::Bytes($total) + '. The Recycle Bin on ' + $script:CCDrive + ' holds at most ' + [ContextCleaner.Format]::Bytes($capacity) + ' and already has ' + [ContextCleaner.Format]::Bytes($already) + '.')
        Write-Host 'To make room, Windows will permanently delete the oldest items in the bin, so Restore will not work for them.'
        Write-Host 'To avoid that, empty the bin first, or copy fewer items at a time, or raise its size in Recycle Bin > Properties.'
        if (-not $WhatIf -and (Read-Host 'Type YES to continue anyway') -cne 'YES') { Write-Host 'Nothing was moved.'; exit 1 }
    }
}

$settings = Get-CCSettings
$running = Get-CCRunning
$moved = @(); $notMoved = @(); $gone = @(); $movedBytes = [long]0
foreach ($entry in $items) {
    $path = [string]$entry.Path
    $item = [pscustomobject]@{ Path = $path; Latest = (ConvertTo-CCUtc $entry.Latest) }
    if (-not (Test-Path -LiteralPath $path)) { $gone += $path; Write-Host ('Already gone: ' + $path); continue }
    $why = $null
    if (Test-CCLink $path) { $why = 'a link; left alone' }
    else {
        $reason = Test-CCStillOffered $item $settings $running
        if ($reason) { $why = $reason.Substring(0, 1).ToLower() + $reason.Substring(1) + $(if ($reason -eq 'Changed since the scan') { '; scan again' } else { '' }) }
    }
    if (-not $why) {
        $size = [ContextCleaner.Disk]::Measure($path, $null).Bytes
        if ($WhatIf) { Write-Host ('Would move: ' + $path + ' (' + [ContextCleaner.Format]::Bytes($size) + ')'); $moved += $path; $movedBytes += $size; continue }
        $code = [ContextCleaner.RecycleBin]::Send($path)
        if (-not (Test-Path -LiteralPath $path)) { $moved += $path; $movedBytes += $size; Write-Host ('Moved: ' + $path); continue }
        $why = if ($code -eq -1) { 'cancelled' } else { 'in use or blocked (code ' + $code + ')' }
    }
    $notMoved += [pscustomobject]@{ Path = $path; Why = $why }
    Write-Host ('NOT moved: ' + $path + ' (' + $why + ')')
}

Write-Host ''
if ($WhatIf) {
    Write-Host ('Would move ' + $moved.Count + ' of ' + $items.Count + ', freeing ' + [ContextCleaner.Format]::Bytes($movedBytes) + ' once the Recycle Bin is emptied. Nothing was moved.')
    exit 0
}
Write-Host ('Moved ' + $moved.Count + ' of ' + $items.Count + ' (' + [ContextCleaner.Format]::Bytes($movedBytes) + ') to the Recycle Bin.' + $(if ($gone) { ' ' + $gone.Count + ' already gone.' }) + $(if ($notMoved) { ' ' + $notMoved.Count + ' not moved.' }))
if ($moved) { Write-Host 'The space comes back when you empty the Recycle Bin. Until then, Restore puts anything back.' }

New-Item -ItemType Directory -Force -Path $script:CCData | Out-Null
$record = [pscustomobject]@{ Plan = $planData.Id; At = [datetime]::UtcNow.ToString('o'); Bytes = $movedBytes; Count = $items.Count; Moved = $moved; NotMoved = $notMoved; Gone = $gone }
Add-Content -LiteralPath (Join-Path $script:CCData 'history.jsonl') -Value (ConvertTo-Json -InputObject $record -Depth 4 -Compress) -Encoding UTF8

