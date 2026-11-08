# Context Cleaner for Windows. See what fills your drive, whether you still use it, and how to remove it yourself.
# It never deletes a thing: Free Up Space copies a command you run yourself, which moves what you tick to the Recycle Bin.
#   Open:        Context Cleaner.cmd, or the Start menu shortcut it can add (Settings)
#   Daily scan:  powershell -File ContextCleaner.ps1 -Scan
#   Report:      powershell -File ContextCleaner.ps1 -Report C:\path\report.md
param([string]$Report, [switch]$Scan)

$ErrorActionPreference = 'Stop'
$corePath = Join-Path $PSScriptRoot 'ContextCleaner.Core.ps1'
$moverPath = Join-Path $PSScriptRoot 'Move-ToRecycleBin.ps1'
. $corePath

if ($Scan -or $Report) {
    $result = Invoke-CCScan -Progress { param($text) Write-Host $text }
    if ($Report) { Export-CCReport $result $Report; Write-Host ('Report written to ' + $Report) }
    return
}

# WPF needs a single-threaded apartment. Windows PowerShell starts in one; PowerShell 7 needs -STA.
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Start-Process (Get-CCPowerShell) -ArgumentList @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + $PSCommandPath + '"')) -WindowStyle Hidden
    return
}

# One window at a time: a second launch brings the first one forward.
$created = $false
$script:Mutex = New-Object Threading.Mutex($true, 'Local\ContextCleaner.Window', [ref]$created)
if (-not $created) {
    $other = Get-Process -Name powershell, pwsh -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq 'Context Cleaner' } | Select-Object -First 1
    if ($other) { [ContextCleaner.Shell]::ShowWindow($other.MainWindowHandle, 9) | Out-Null; [ContextCleaner.Shell]::SetForegroundWindow($other.MainWindowHandle) | Out-Null }
    return
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
[ContextCleaner.Shell]::AppId('Sotraidis.ContextCleaner')
$xamlText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ContextCleaner.xaml'))
$window = [Windows.Markup.XamlReader]::Parse($xamlText)
$ui = @{}
foreach ($m in [regex]::Matches($xamlText, 'x:Name="([^"]+)"')) { $name = $m.Groups[1].Value; $ui[$name] = $window.FindName($name) }
# Fit the screen: at 125% or 150% scaling the default size can be taller than the screen, which hides the title bar.
$work = [Windows.SystemParameters]::WorkArea
$window.Width = [math]::Min($window.Width, $work.Width - 40); $window.Height = [math]::Min($window.Height, $work.Height - 40)
$window.MinWidth = [math]::Min($window.MinWidth, $window.Width); $window.MinHeight = [math]::Min($window.MinHeight, $window.Height)

$iconPath = Join-Path $PSScriptRoot 'icon.png'
if (Test-Path -LiteralPath $iconPath) {
    $bitmap = New-Object Windows.Media.Imaging.BitmapImage (New-Object Uri $iconPath)
    $ui.AppIcon.Source = $bitmap; $ui.AboutIcon.Source = $bitmap; $window.Icon = $bitmap
}

$script:LogPath = Join-Path $script:CCData 'errors.log'
function Write-CCLog([string]$Text) {
    try { New-Item -ItemType Directory -Force -Path $script:CCData | Out-Null; Add-Content -LiteralPath $script:LogPath -Value ((Get-Date).ToString('s') + ' ' + $Text) -Encoding UTF8 } catch { }
}
# Handlers are plain script blocks, so they see this script's functions. Any failure in one is caught by the
# dispatcher handler below, logged, and shown in the status line instead of closing the window.
function On($Control, [string]$EventName, [scriptblock]$Handler) { $Control.('add_' + $EventName)($Handler) }

# ---------- Theme: Windows' light or dark mode, accent color, Mica and title bar ----------
function New-Brush([string]$Hex) { $b = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($Hex)); $b.Freeze(); $b }
function New-ColorBrush([Windows.Media.Color]$Color, [byte]$Alpha = 255) { $b = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb($Alpha, $Color.R, $Color.G, $Color.B)); $b.Freeze(); $b }
function Get-CCAccent {
    # Windows keeps its accent in seven shades, lightest first: light 3, 2, 1, the accent, dark 1, 2, 3.
    $bytes = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' -ErrorAction SilentlyContinue).AccentPalette
    if ($bytes -and $bytes.Length -ge 28) { return @(0..6 | ForEach-Object { [Windows.Media.Color]::FromRgb($bytes[$_ * 4], $bytes[$_ * 4 + 1], $bytes[$_ * 4 + 2]) }) }
    $c = [Windows.Media.Color]::FromRgb(0, 103, 192)
    @([Windows.Media.Color]::FromRgb(153, 235, 255), [Windows.Media.Color]::FromRgb(118, 185, 237), [Windows.Media.Color]::FromRgb(66, 156, 227), $c, [Windows.Media.Color]::FromRgb(0, 95, 184), [Windows.Media.Color]::FromRgb(0, 62, 146), [Windows.Media.Color]::FromRgb(0, 26, 104))
}
function Test-CCDarkMode {
    $value = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction SilentlyContinue).AppsUseLightTheme
    $value -eq 0
}
$script:Mica = $false
function Set-Theme {
    $mode = $script:Settings.appearance
    $dark = if ($mode -eq 'Dark') { $true } elseif ($mode -eq 'Light') { $false } else { Test-CCDarkMode }
    $script:Dark = $dark
    $accent = Get-CCAccent
    # PowerShell wraps values it returns; the resource dictionary must hold the brush itself.
    $r = @{}
    if ($dark) {
        $p = @{ Base = '#FF202020'; Layer = '#4C3A3A3A'; LayerStroke = '#19000000'; Card = '#0DFFFFFF'; CardHover = '#15FFFFFF'; CardStroke = '#1AFFFFFF'
            Text1 = '#FFFFFFFF'; Text2 = '#C5FFFFFF'; Text3 = '#87FFFFFF'; Divider = '#15FFFFFF'; ControlFill = '#0FFFFFFF'; ControlHover = '#15FFFFFF'; ControlPressed = '#08FFFFFF'
            ControlStroke = '#12FFFFFF'; CheckStroke = '#8BFFFFFF'; InputFill = '#0FFFFFFF'; InputFocus = '#B31E1E1E'; Subtle = '#0FFFFFFF'; Selected = '#15FFFFFF'; SegOn = '#26FFFFFF'
            Thumb = '#8BFFFFFF'; Menu = '#FF2C2C2C'; MenuStroke = '#33000000'
            Safe = '#FF6CCB5F'; Rebuild = '#FF4CC2FF'; Review = '#FFFFA94D'; Keep = '#FFB4B4B4'; Other = '#FF8A8A8A'; Growing = '#FFFF9F43' }
        $p.Bin = '#FFB79CFF'
        $fill = $accent[1]; $link = $accent[0]; $hover = $accent[2]; $onAccent = '#FF000000'
    } else {
        $p = @{ Base = '#FFF3F3F3'; Layer = '#80FFFFFF'; LayerStroke = '#0F000000'; Card = '#B3FFFFFF'; CardHover = '#FFFBFBFB'; CardStroke = '#0F000000'
            Text1 = '#E4000000'; Text2 = '#9E000000'; Text3 = '#72000000'; Divider = '#14000000'; ControlFill = '#B3FFFFFF'; ControlHover = '#80F9F9F9'; ControlPressed = '#4DF9F9F9'
            ControlStroke = '#16000000'; CheckStroke = '#72000000'; InputFill = '#B3FFFFFF'; InputFocus = '#FFFFFFFF'; Subtle = '#09000000'; Selected = '#0D000000'; SegOn = '#FFFFFFFF'
            Thumb = '#72000000'; Menu = '#FFF9F9F9'; MenuStroke = '#1F000000'
            Safe = '#FF0F7B0F'; Rebuild = '#FF005FB8'; Review = '#FFB35900'; Keep = '#FF7A7A7A'; Other = '#FFA8A8A8'; Growing = '#FFC25E00' }
        $p.Bin = '#FF7A5AC8'
        $fill = $accent[4]; $link = $accent[5]; $hover = $accent[3]; $onAccent = '#FFFFFFFF'
    }
    foreach ($key in $p.Keys) { $r[$key] = New-Brush $p[$key] }
    if (-not $script:Mica) { $r['Layer'] = New-Brush $(if ($dark) { '#FF272727' } else { '#FFF9F9F9' }) }
    foreach ($answer in 'Safe', 'Rebuild', 'Review', 'Keep', 'Other') { $c = $r[$answer].Color; $r[$answer + 'Soft'] = New-ColorBrush $c $(if ($dark) { 38 } else { 28 }) }
    $r['Accent'] = New-ColorBrush $fill; $r['AccentHover'] = New-ColorBrush $hover; $r['AccentStroke'] = New-ColorBrush $fill
    $r['AccentLink'] = New-ColorBrush $link; $r['AccentText'] = New-Brush $onAccent; $r['AccentSoft'] = New-ColorBrush $fill 40
    foreach ($key in $r.Keys) { $window.Resources[$key] = $r[$key].psobject.BaseObject }
    $script:AccentColor = $fill
    if ($script:Hwnd) { [ContextCleaner.Shell]::DarkTitle($script:Hwnd, $dark) | Out-Null }
    Update-Charts
}

# ---------- State and small helpers ----------
$script:Settings = Get-CCSettings
$script:ScanData = $null
$script:Items = @()
$script:Index = $null
$script:Page = 'overview'
$script:Tile = 'all'
$script:Sort = 'size'
$script:Chip = 'all'
$script:Charts = @{}
$script:Confirm = $null
function Size([long]$Bytes) { [ContextCleaner.Format]::Bytes($Bytes) }
function Sum($Items) { $t = [long]0; foreach ($i in @($Items)) { if ($i) { $t += [long]$i.Bytes } }; $t }
function Typed($Rows) { $list = New-Object 'Collections.Generic.List[ContextCleaner.Item]'; foreach ($row in @($Rows)) { if ($row) { $list.Add($row) } }; , $list }
function Plural([int]$N, [string]$One, [string]$Many) { if ($N -eq 1) { '1 ' + $One } else { [string]$N + ' ' + $Many } }
function Set-Message([string]$Text, [switch]$Terminal) {
    $ui.Message.Text = $Text; $ui.Message.ToolTip = $Text
    $ui.MessageTerminal.Visibility = $(if ($Terminal) { 'Visible' } else { 'Collapsed' })
}
function Save-Settings { Save-CCSettings $script:Settings; $script:Settings = Get-CCSettings }
function Open-Bin { Start-Process 'explorer.exe' -ArgumentList 'shell:RecycleBinFolder' }
function Show-InExplorer([string]$Path) { if (Test-Path -LiteralPath $Path) { Start-Process 'explorer.exe' -ArgumentList ('/select,"' + $Path + '"') } else { Set-Message 'That folder is gone now. Scan again to update the list.' } }
function Get-Terminals {
    $list = @()
    if (Get-Command wt.exe -ErrorAction SilentlyContinue) { $list += [pscustomobject]@{ Id = 'wt'; Name = 'Windows Terminal'; Exe = 'wt.exe' } }
    $pwsh = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    if (Test-Path -LiteralPath $pwsh) { $list += [pscustomobject]@{ Id = 'pwsh'; Name = 'PowerShell 7'; Exe = $pwsh } }
    $list += [pscustomobject]@{ Id = 'powershell'; Name = 'Windows PowerShell'; Exe = (Get-CCPowerShell) }
    $list
}
function Open-Terminal {
    $all = Get-Terminals
    $t = $all | Where-Object { $_.Id -eq $script:Settings.terminal } | Select-Object -First 1
    if (-not $t) { $t = $all | Select-Object -First 1 }
    Start-Process $t.Exe -WorkingDirectory $script:CCHome
}
function Format-When([datetime]$Utc) {
    $local = $Utc.ToLocalTime(); $today = (Get-Date).Date
    if ($local.Date -eq $today) { 'Today' } elseif ($local.Date -eq $today.AddDays(-1)) { 'Yesterday' } else { $local.ToString('dddd, MMMM d') }
}

# ---------- Charts: drawn on a Canvas from saved readings ----------
function Add-Shape($Canvas, $Shape) { $Canvas.Children.Add($Shape) | Out-Null }
function New-Text([string]$Text, [double]$X, [double]$Y, [string]$Align = 'Left') {
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $Text; $t.FontSize = 11; $t.Foreground = $window.Resources['Text3']
    $t.Measure((New-Object Windows.Size ([double]::PositiveInfinity), ([double]::PositiveInfinity)))
    $left = if ($Align -eq 'Right') { $X - $t.DesiredSize.Width } elseif ($Align -eq 'Center') { $X - $t.DesiredSize.Width / 2 } else { $X }
    [Windows.Controls.Canvas]::SetLeft($t, [math]::Max([double]0, $left)); [Windows.Controls.Canvas]::SetTop($t, $Y); $t
}
function New-Line([double]$X1, [double]$Y1, [double]$X2, [double]$Y2, $Brush, [double]$Thickness = 1, [switch]$Dashed) {
    $l = New-Object Windows.Shapes.Line
    $l.X1 = $X1; $l.Y1 = $Y1; $l.X2 = $X2; $l.Y2 = $Y2; $l.Stroke = $Brush; $l.StrokeThickness = $Thickness
    if ($Dashed) { $l.StrokeDashArray = New-Object Windows.Media.DoubleCollection (,[double[]]@(4, 3)) }
    $l
}
# An area chart of values over time. Points: objects with At (UTC) and Value. Ceiling draws a dashed limit, such as capacity.
function Show-AreaChart($Canvas, $Points, [datetime]$From, [datetime]$To, [double]$Ceiling = 0, [string]$Empty = 'No readings yet') {
    $script:Charts[$Canvas.Name] = @{ Kind = 'area'; Points = $Points; From = $From; To = $To; Ceiling = $Ceiling; Empty = $Empty }
    $Canvas.Children.Clear()
    $w = $Canvas.ActualWidth; $h = $Canvas.ActualHeight
    if ($w -lt 60 -or $h -lt 40) { return }
    $pts = @($Points | Where-Object { $_.At -ge $From -and $_.At -le $To } | Sort-Object At)
    if ($pts.Count -eq 0) { Add-Shape $Canvas (New-Text $Empty ($w / 2) ($h / 2 - 8) 'Center'); return }
    $left = 58.0; $top = 8.0; $bottom = 20.0; $right = 10.0
    $values = @($pts | ForEach-Object { [double]$_.Value })
    $max = ($values | Measure-Object -Maximum).Maximum; $min = ($values | Measure-Object -Minimum).Minimum
    if ($Ceiling -gt 0) { $max = [math]::Max($max, $Ceiling) }
    $span = $max - $min; if ($span -le 0) { $span = [math]::Max($max * 0.1, 1) }
    $lower = [math]::Max([double]0, $min - $span * 0.25); $upper = $max + $(if ($Ceiling -gt 0) { 0 } else { $span * 0.1 })
    $ticks = [double]($To - $From).Ticks
    $x = { param($t) $left + ([double]($t - $From).Ticks / $ticks) * ($w - $left - $right) }
    $y = { param($v) $top + (1 - ($v - $lower) / ($upper - $lower)) * ($h - $top - $bottom) }
    foreach ($g in 0, 0.5, 1) {
        $v = $lower + ($upper - $lower) * $g; $gy = & $y $v
        Add-Shape $Canvas (New-Line $left $gy ($w - $right) $gy $window.Resources['Divider'])
        Add-Shape $Canvas (New-Text (Size ([long]$v)) ($left - 8) ($gy - 8) 'Right')
    }
    if ($Ceiling -gt 0) { $cy = & $y $Ceiling; Add-Shape $Canvas (New-Line $left $cy ($w - $right) $cy $window.Resources['Text3'] 1 -Dashed) }
    $span = ($To - $From)
    $format = if ($span.TotalDays -le 1.5) { 'h tt' } elseif ($span.TotalDays -le 10) { 'ddd' } else { 'MMM d' }
    foreach ($g in 0, 0.25, 0.5, 0.75, 1) {
        $t = $From.AddTicks([long]($span.Ticks * $g))
        Add-Shape $Canvas (New-Text $t.ToLocalTime().ToString($format) (& $x $t) ($h - 16) $(if ($g -eq 0) { 'Left' } elseif ($g -eq 1) { 'Right' } else { 'Center' }))
    }
    $line = New-Object Windows.Shapes.Polyline
    $area = New-Object Windows.Shapes.Polygon
    $baseline = $h - $bottom
    $area.Points.Add((New-Object Windows.Point ((& $x $pts[0].At), $baseline)))
    foreach ($p in $pts) { $pt = New-Object Windows.Point ((& $x $p.At), (& $y ([double]$p.Value))); $line.Points.Add($pt); $area.Points.Add($pt) }
    $area.Points.Add((New-Object Windows.Point ((& $x $pts[-1].At), $baseline)))
    $area.Fill = New-ColorBrush $script:AccentColor 46
    $line.Stroke = New-ColorBrush $script:AccentColor; $line.StrokeThickness = 2; $line.StrokeLineJoin = 'Round'
    Add-Shape $Canvas $area; Add-Shape $Canvas $line
    $last = $pts[-1]; $dot = New-Object Windows.Shapes.Ellipse
    $dot.Width = 8; $dot.Height = 8; $dot.Fill = New-ColorBrush $script:AccentColor
    [Windows.Controls.Canvas]::SetLeft($dot, (& $x $last.At) - 4); [Windows.Controls.Canvas]::SetTop($dot, (& $y ([double]$last.Value)) - 4)
    $dot.ToolTip = (Size ([long]$last.Value)) + ' · ' + $last.At.ToLocalTime().ToString('MMM d, h:mm tt')
    Add-Shape $Canvas $dot
}
# Bars per day. Days: objects with Date (local date) and Bytes.
function Show-BarChart($Canvas, $Days) {
    $script:Charts[$Canvas.Name] = @{ Kind = 'bars'; Days = $Days }
    $Canvas.Children.Clear()
    $w = $Canvas.ActualWidth; $h = $Canvas.ActualHeight
    if ($w -lt 60 -or $h -lt 40) { return }
    $left = 52.0; $bottom = 20.0; $top = 6.0
    $max = [double](($Days | Measure-Object Bytes -Maximum).Maximum); if ($max -le 0) { $max = 1GB }
    foreach ($g in 0, 0.5, 1) {
        $gy = $top + (1 - $g) * ($h - $top - $bottom)
        Add-Shape $Canvas (New-Line $left $gy $w $gy $window.Resources['Divider'])
        Add-Shape $Canvas (New-Text (Size ([long]($max * $g))) ($left - 8) ($gy - 8) 'Right')
    }
    $n = @($Days).Count; $slot = ($w - $left) / [math]::Max([double]1, $n)
    for ($i = 0; $i -lt $n; $i++) {
        $d = $Days[$i]
        if ($d.Bytes -gt 0) {
            $bh = [math]::Max([double]2, ($d.Bytes / $max) * ($h - $top - $bottom))
            $bar = New-Object Windows.Shapes.Rectangle
            $bar.Width = [math]::Max([double]3, $slot * 0.6); $bar.Height = $bh; $bar.RadiusX = 2; $bar.RadiusY = 2; $bar.Fill = $window.Resources['Safe']
            $bar.ToolTip = $d.Date.ToString('MMM d') + ': ' + (Size $d.Bytes)
            [Windows.Controls.Canvas]::SetLeft($bar, $left + $i * $slot + $slot * 0.2); [Windows.Controls.Canvas]::SetTop($bar, $h - $bottom - $bh)
            Add-Shape $Canvas $bar
        }
        if ($i % 7 -eq 0 -and $i -lt $n - 3) { Add-Shape $Canvas (New-Text $d.Date.ToString('MMM d') ($left + $i * $slot + $slot / 2) ($h - 16) 'Center') }
        elseif ($i -eq $n - 1) { Add-Shape $Canvas (New-Text 'Today' $w ($h - 16) 'Right') }
    }
}
function Update-Charts {
    foreach ($name in @($script:Charts.Keys)) {
        $c = $script:Charts[$name]; $canvas = $ui[$name]
        if (-not $canvas) { continue }
        if ($c.Kind -eq 'area') { Show-AreaChart $canvas $c.Points $c.From $c.To $c.Ceiling $c.Empty } else { Show-BarChart $canvas $c.Days }
    }
}

# ---------- Overview ----------
function Get-UsedSeries {
    $points = @()
    foreach ($r in Get-CCReadings) { $points += [pscustomobject]@{ At = $r.At; Value = [double]($r.Total - $r.Free) } }
    if ($script:Index) { foreach ($s in $script:Index.Scans) { $points += [pscustomobject]@{ At = $s.At; Value = [double]($s.Total - $s.Free) } } }
    $drive = New-Object IO.DriveInfo $script:CCDrive
    $points += [pscustomobject]@{ At = [datetime]::UtcNow; Value = [double]($drive.TotalSize - $drive.AvailableFreeSpace) }
    @($points | Sort-Object At)
}
function Get-RangeDays { if ($ui.Range1.IsChecked) { 1 } elseif ($ui.Range30.IsChecked) { 30 } else { 7 } }
function New-Tile([string]$Key, [string]$Title, [string]$Glyph, [string]$Brush, [string]$Value, [string]$Sub) {
    $b = New-Object Windows.Controls.Button
    $b.Tag = $Key; $b.Margin = '0,0,10,0'; $b.Padding = '16,12'; $b.HorizontalContentAlignment = 'Left'
    $b.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'Card'); $b.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty, 'CardStroke')
    $panel = New-Object Windows.Controls.StackPanel
    $head = New-Object Windows.Controls.StackPanel; $head.Orientation = 'Horizontal'
    $g = New-Object Windows.Controls.TextBlock; $g.Text = $Glyph; $g.FontFamily = $window.Resources['Icons']; $g.FontSize = 14; $g.Margin = '0,0,8,0'; $g.VerticalAlignment = 'Center'
    $g.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $Brush)
    $t = New-Object Windows.Controls.TextBlock; $t.Text = $Title; $t.FontWeight = 'SemiBold'; $t.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $Brush)
    $head.Children.Add($g) | Out-Null; $head.Children.Add($t) | Out-Null
    $v = New-Object Windows.Controls.TextBlock; $v.Text = $Value; $v.FontSize = 24; $v.FontWeight = 'SemiBold'; $v.FontFamily = $window.Resources['Display']; $v.Margin = '0,4,0,0'
    $s = New-Object Windows.Controls.TextBlock; $s.Text = $Sub; $s.FontSize = 12; $s.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Text2')
    $panel.Children.Add($head) | Out-Null; $panel.Children.Add($v) | Out-Null; $panel.Children.Add($s) | Out-Null
    $b.Content = $panel
    $b.add_Click({ param($sender, $e) $script:Tile = $sender.Tag; Show-Page 'folders' })
    $b
}
$script:AnswerInfo = [ordered]@{
    'Safe to remove' = @('safe', 'Safe', '&#xE73E;', 'not needed again'); 'Rebuildable' = @('rebuild', 'Rebuild', '&#xE72C;', 'rebuilds itself')
    'Review first' = @('review', 'Review', '&#xE7BA;', 'look inside first'); 'Not for the Recycle Bin' = @('keep', 'Keep', '&#xE72E;', 'manage in its app')
}
function Show-Overview {
    $drive = New-Object IO.DriveInfo $script:CCDrive
    $ui.OvFree.Text = Size $drive.AvailableFreeSpace
    $ui.OvFreeOf.Text = 'free of ' + (Size $drive.TotalSize) + ' on ' + $script:CCDrive.TrimEnd('\')
    $days = Get-RangeDays
    $series = Get-UsedSeries
    $from = [datetime]::UtcNow.AddDays(-$days)
    $earlier = $series | Where-Object { $_.At -ge $from } | Select-Object -First 1
    $rangeName = if ($days -eq 1) { 'in the last 24 hours' } else { 'in the last ' + $days + ' days' }
    if ($earlier -and @($series | Where-Object { $_.At -ge $from }).Count -gt 1) {
        $delta = [long]($series[-1].Value - $earlier.Value)
        if ([math]::Abs($delta) -lt 100MB) { $ui.OvChange.Text = 'About the same ' + $rangeName; $ui.OvChange.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Text1') }
        elseif ($delta -gt 0) { $ui.OvChange.Text = (Size $delta) + ' more used ' + $rangeName; $ui.OvChange.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Growing') }
        else { $ui.OvChange.Text = (Size (-$delta)) + ' freed ' + $rangeName; $ui.OvChange.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Safe') }
        $ui.OvChangeSub.Text = 'Used space, from ' + (Plural @($series | Where-Object { $_.At -ge $from }).Count 'reading' 'readings') + '. The dashed line is the drive''s capacity.'
    } else {
        $ui.OvChange.Text = 'Not enough readings yet'
        $ui.OvChange.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Text1')
        $ui.OvChangeSub.Text = 'Each scan adds a reading. Turn on the daily scan in Settings to add one every day.'
    }
    Show-AreaChart $ui.OvChart $series $from ([datetime]::UtcNow) ([double]$drive.TotalSize)

    $ui.OvBar.Children.Clear(); $ui.OvBar.ColumnDefinitions.Clear(); $ui.OvLegend.Children.Clear(); $ui.OvTiles.Children.Clear()
    $items = @($script:Items)
    $recycle = if ($script:ScanData) { [long]$script:ScanData.RecycleBytes } else { 0 }
    $segments = New-Object Collections.Specialized.OrderedDictionary
    $brushes = @{ 'Safe to remove' = 'Safe'; 'Rebuildable' = 'Rebuild'; 'Review first' = 'Review'; 'Not for the Recycle Bin' = 'Keep'; 'Everything else' = 'Other' }
    foreach ($a in $script:AnswerOrder) { $segments[$a] = Sum ($items | Where-Object { $_.Answer -eq $a }) }
    $segments['Recycle Bin'] = $recycle
    $used = $drive.TotalSize - $drive.AvailableFreeSpace
    $segments['Windows, system and shared files'] = [math]::Max([long]0, $used - (Sum $items) - $recycle)
    $segments['Free'] = $drive.AvailableFreeSpace
    $brushes['Recycle Bin'] = 'Bin'; $brushes['Windows, system and shared files'] = 'Text3'; $brushes['Free'] = 'Divider'
    $column = 0
    foreach ($key in $segments.Keys) {
        $bytes = [long]$segments[$key]
        if ($bytes -le 0 -or -not $items) { continue }
        $def = New-Object Windows.Controls.ColumnDefinition; $def.Width = New-Object Windows.GridLength ([double]$bytes), 'Star'
        $ui.OvBar.ColumnDefinitions.Add($def)
        $part = New-Object Windows.Controls.Border; $part.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, $brushes[$key]); $part.ToolTip = $key + ': ' + (Size $bytes)
        if ($key -ne 'Free') { $part.Margin = '0,0,1,0' }
        [Windows.Controls.Grid]::SetColumn($part, $column); $ui.OvBar.Children.Add($part) | Out-Null; $column++
        $legend = New-Object Windows.Controls.StackPanel; $legend.Orientation = 'Horizontal'; $legend.Margin = '0,0,20,6'
        $dot = New-Object Windows.Shapes.Ellipse; $dot.Width = 8; $dot.Height = 8; $dot.Margin = '0,0,7,0'; $dot.SetResourceReference([Windows.Shapes.Shape]::FillProperty, $brushes[$key])
        if ($key -eq 'Free') { $dot.SetResourceReference([Windows.Shapes.Shape]::StrokeProperty, 'Text3'); $dot.StrokeThickness = 1 }
        $label = New-Object Windows.Controls.TextBlock; $label.FontSize = 12
        $label.Inlines.Add((New-Object Windows.Documents.Run ($key + '  '))); $r = New-Object Windows.Documents.Run (Size $bytes); $r.FontWeight = 'SemiBold'; $label.Inlines.Add($r)
        $legend.Children.Add($dot) | Out-Null; $legend.Children.Add($label) | Out-Null; $ui.OvLegend.Children.Add($legend) | Out-Null
    }
    $ui.OvMapTotal.Text = $(if ($items) { (Plural $items.Count 'folder' 'folders') + ' measured · ' + (Size $used) + ' used' } else { 'Scan to see what fills it' })
    foreach ($a in $script:AnswerInfo.Keys) {
        $info = $script:AnswerInfo[$a]; $x = @($items | Where-Object { $_.Answer -eq $a -and -not $_.Ignored })
        $ui.OvTiles.Children.Add((New-Tile $info[0] $a ([Net.WebUtility]::HtmlDecode($info[2])) $info[1] (Size (Sum $x)) ((Plural $x.Count 'folder' 'folders') + ' · ' + $info[3]))) | Out-Null
    }
    $back = @($items | Where-Object { $_.Removable -and -not $_.Ignored -and ($_.Answer -eq 'Safe to remove' -or $_.Answer -eq 'Rebuildable') })
    $review = @($items | Where-Object { $_.Removable -and -not $_.Ignored -and $_.Answer -eq 'Review first' })
    if ($items) {
        $ui.OvBack.Text = (Size (Sum $back)) + ' you could get back, nothing lost'
        $ui.OvBackSub.Text = (Plural $back.Count 'folder is' 'folders are') + ' safe to remove or rebuildable. ' + (Size (Sum $review)) + ' more is Review first: look inside before removing it.'
    } else { $ui.OvBack.Text = 'Scan to see what you can get back'; $ui.OvBackSub.Text = 'A scan reads folder sizes and dates for about a minute. It changes nothing.' }
    $ui.OvBin.Text = $(if ($recycle -gt 0) { (Size $recycle) + ' in the Recycle Bin' } else { 'The Recycle Bin is empty' })
    $ui.OvBinSub.Text = $(if ($recycle -gt 0) { 'Emptying it frees this space. Until then, Restore puts anything back.' } else { 'Things you move there wait until you empty it.' })
    $growing = @($items | Where-Object { $_.Growing } | Sort-Object Growth -Descending | Select-Object -First 5)
    $ui.OvGrowCard.Visibility = $(if ($growing) { 'Visible' } else { 'Collapsed' })
    if ($growing -and $script:ScanData.PreviousAt) { $ui.OvGrowSub.Text = 'Compared with the scan from ' + (ConvertTo-CCUtc $script:ScanData.PreviousAt).ToLocalTime().ToString('MMM d, h:mm tt') + ', the newest one at least 6 hours old. Watch a folder to keep it on your Watchlist.' }
    $ui.OvGrow.ItemsSource = Typed $growing
    $ui.OvDrives.Children.Clear()
    $drives = @(Get-CCDrives)
    $ui.OvDrivesCard.Visibility = $(if ($drives.Count -gt 1) { 'Visible' } else { 'Collapsed' })
    foreach ($d in $drives) {
        $card = New-Object Windows.Controls.StackPanel; $card.Margin = '0,0,24,0'
        $name = New-Object Windows.Controls.TextBlock; $name.Text = $d.Name + $(if ($d.Label) { '  ' + $d.Label } else { '' }) + $(if ($d.System) { '  (Windows)' } else { '' }); $name.FontWeight = 'SemiBold'
        $bar = New-Object Windows.Controls.Border; $bar.Height = 6; $bar.CornerRadius = 3; $bar.Margin = '0,6,0,4'; $bar.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Divider')
        $grid = New-Object Windows.Controls.Grid
        $c1 = New-Object Windows.Controls.ColumnDefinition; $c1.Width = New-Object Windows.GridLength ([double]($d.Total - $d.Free)), 'Star'
        $c2 = New-Object Windows.Controls.ColumnDefinition; $c2.Width = New-Object Windows.GridLength ([double]$d.Free), 'Star'
        $grid.ColumnDefinitions.Add($c1); $grid.ColumnDefinitions.Add($c2)
        $fill = New-Object Windows.Controls.Border; $fill.CornerRadius = 3; $fill.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, $(if ($d.Free / [double]$d.Total -lt 0.1) { 'Growing' } else { 'Accent' }))
        $grid.Children.Add($fill) | Out-Null; $bar.Child = $grid
        $sub = New-Object Windows.Controls.TextBlock; $sub.Text = (Size $d.Free) + ' free of ' + (Size $d.Total); $sub.FontSize = 12; $sub.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Text2')
        $card.Children.Add($name) | Out-Null; $card.Children.Add($bar) | Out-Null; $card.Children.Add($sub) | Out-Null
        $ui.OvDrives.Children.Add($card) | Out-Null
    }
    $roomy = Get-CCRoomyDrive
    $movable = Sum ($items | Where-Object { $_.Rule -eq 'game' -or $_.Rule -eq 'vm-wsl' -or $_.Rule -eq 'vm-docker' })
    $ui.OvDrivesSub.Text = $(if ($roomy -and $movable -gt 10GB) { (Size $movable) + ' of games, WSL and Docker on ' + $script:CCDrive.TrimEnd('\') + ' could move to ' + $roomy.Name + ' instead of being deleted. Their cards in Folders say how.' } else { 'Free space on each of your drives.' })
    $ui.OvTop.ItemsSource = Typed ($items | Where-Object { -not $_.Ignored } | Sort-Object Bytes -Descending | Select-Object -First 8)
}

# ---------- Free Up Space ----------
function Get-AgeDays { [int]$script:Settings.untouchedDays }
function Get-FreeCandidates {
    $days = Get-AgeDays
    @($script:Items | Where-Object { $_.Removable -and -not $_.Ignored -and ($days -eq 0 -or $_.IdleDays -ge $days) })
}
function Get-FreeShown {
    $all = Get-FreeCandidates
    if ($script:Chip -eq 'lossless') { @($all | Where-Object { $_.Answer -ne 'Review first' }) }
    elseif ($script:Chip -eq 'review') { @($all | Where-Object { $_.Answer -eq 'Review first' }) }
    else { $all }
}
function Show-Free {
    $all = Get-FreeCandidates
    $lossless = @($all | Where-Object { $_.Answer -ne 'Review first' }); $review = @($all | Where-Object { $_.Answer -eq 'Review first' })
    $ui.ChipAll.Content = 'All  ' + $all.Count + ' · ' + (Size (Sum $all))
    $ui.ChipLossless.Content = 'Nothing lost  ' + $lossless.Count + ' · ' + (Size (Sum $lossless))
    $ui.ChipReview.Content = 'Review first  ' + $review.Count + ' · ' + (Size (Sum $review))
    $days = Get-AgeDays
    $ui.FreeHead.Text = (Size (Sum $all)) + ' you could get back'
    $ui.FreeHeadSub.Text = (Plural $all.Count 'item' 'items') + $(if ($days -eq 0) { ', however recently used' } elseif ($days -eq 1) { ' untouched for a day or longer' } else { ' untouched for ' + $days + ' days or longer' })
    $recycle = if ($script:ScanData) { [long]$script:ScanData.RecycleBytes } else { 0 }
    $ui.FreeBinNote.Text = 'Space comes back when you empty the Recycle Bin' + $(if ($recycle -gt 0) { ' (' + (Size $recycle) + ' there now)' } else { '' })
    $shown = Get-FreeShown | Sort-Object Bytes -Descending
    $groups = New-Object 'Collections.Generic.List[ContextCleaner.Group]'
    if ($script:Settings.byKind) {
        foreach ($g in $shown | Group-Object Category | Sort-Object { -(Sum $_.Group) }) { $groups.Add((New-Object ContextCleaner.Group ($g.Name, [ContextCleaner.Item[]]@($g.Group), $true))) }
    } elseif ($shown) { $groups.Add((New-Object ContextCleaner.Group ('', [ContextCleaner.Item[]]@($shown), $false))) }
    $ui.FreeGroups.ItemsSource = $groups
    $ui.FreeEmpty.Visibility = $(if ($shown) { 'Collapsed' } else { 'Visible' })
    $ui.FreeEmptyText.Text = $(if (-not $script:Items) { 'Scan to see what you can remove. A scan reads sizes and dates for about a minute and changes nothing.' }
        elseif ($days -gt 0) { 'Nothing here has sat untouched that long. Choose a shorter time above, or look in Folders.' }
        else { 'Nothing to remove here right now. Folders lists everything else, with how to get space back from it.' })
    Update-FreeTotal
}
function Get-FreeTicked { @(Get-FreeShown | Where-Object { $_.Selected }) }
function Update-FreeTotal {
    $shown = @(Get-FreeShown); $ticked = @($shown | Where-Object { $_.Selected })
    $ui.FreeTicked.Text = $(if ($ticked) { [string]$ticked.Count + ' ticked · ' + (Size (Sum $ticked)) } else { 'Nothing ticked' })
    $ui.FreeCopy.IsEnabled = [bool]$ticked; $ui.FreeClear.IsEnabled = [bool]$ticked
    $ui.FreeAllText.Text = 'Select all ' + $shown.Count + ' shown'
    $ui.FreeAll.IsChecked = $(if ($shown -and $ticked.Count -eq $shown.Count) { $true } elseif ($ticked) { $null } else { $false })
    $script:Confirm = $null
}
function Invoke-Copy {
    $ticked = Get-FreeTicked
    if (-not $ticked) { return }
    $review = @($ticked | Where-Object { $_.Answer -eq 'Review first' })
    $total = Sum $ticked; $shared = [long]0; foreach ($t in $ticked) { $shared += $t.SharedBytes }
    $capacity = Get-BinCapacity
    $key = (@($ticked | ForEach-Object { $_.Path }) -join '|')
    # Ask in place, never in a pop-up: a second click on Copy Command confirms.
    if ($script:Confirm -ne $key) {
        $asks = @()
        if ($review) { $asks += (Plural $review.Count 'item is' 'items are') + ' Review first and may hold something that exists only there' }
        if ($capacity -gt 0 -and ($total + $shared) -gt $capacity) { $asks += 'together they are more than the Recycle Bin holds (' + (Size $capacity) + '), so Windows would permanently delete the oldest things in it; empty the bin first or tick fewer' }
        if ($asks) { $script:Confirm = $key; Set-Message (($asks -join '; ') + '. Click Copy Command again to copy anyway.'); return }
    }
    $script:Confirm = $null
    $window.Cursor = [Windows.Input.Cursors]::Wait
    try { $plan = New-CCPlan $ticked $moverPath } finally { $window.Cursor = $null }
    $left = $(if ($plan.LeftOut) { ' Left out ' + $plan.LeftOut.Count + ': ' + (($plan.LeftOut | Select-Object -First 3 | ForEach-Object { $_.Name + ' (' + $_.Why.ToLower() + ')' }) -join ', ') + '.' } else { '' })
    if (-not $plan.Command) { Set-Message ('Nothing to copy.' + $left); return }
    [Windows.Clipboard]::SetText($plan.Command)
    Set-Message ('Copied a command for ' + (Plural $plan.Count 'item' 'items') + ' (' + (Size $plan.Bytes) + '). Paste it in your terminal and press Enter; it prints a line for each and stops working in an hour.' + $left) -Terminal
}
function Get-BinCapacity {
    try {
        $volume = (Get-CimInstance Win32_Volume -Filter ("DriveLetter='" + $script:CCDrive.Substring(0, 2) + "'")).DeviceID
        if ($volume -match '\{[^}]+\}') { $bin = Get-ItemProperty ('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket\Volume\' + $Matches[0]) -ErrorAction SilentlyContinue; if ($bin.MaxCapacity) { return [long]$bin.MaxCapacity * 1MB } }
    } catch { }
    0
}

# ---------- Folders, Watchlist, Ignored, Couldn't Scan ----------
function Get-OffItems {
    @($script:Settings.scanningOff | ForEach-Object {
        $i = New-Object ContextCleaner.Item
        $i.Path = $_; $i.Name = $_; $i.App = 'Scanning off'; $i.Category = 'Not read'; $i.Rule = 'off'; $i.Answer = 'Everything else'; $i.Reason = 'Scanning off'
        $i.Explanation = 'You stopped scanning this folder. Context Cleaner does not read it, and its size is the last one seen.'; $i.Consequence = 'Unknown.'
        if ($script:Index -and $script:Index.Series.ContainsKey($_)) { $i.Bytes = $script:Index.Series[$_][-1].Bytes }
        $i
    })
}
function Get-FolderRows {
    $q = $ui.SearchBox.Text.Trim()
    $rows = switch ($script:Page) {
        'watch' { @($script:Items | Where-Object { $_.Watched -or $_.Growing }) }
        'ignored' { @($script:Items | Where-Object { $_.Ignored }) + @(Get-OffItems) }
        'unread' { @($script:Items | Where-Object { $_.Unreadable -gt 0 }) }
        default {
            $base = @($script:Items | Where-Object { -not $_.Ignored })
            switch ($script:Tile) { 'safe' { @($base | Where-Object { $_.Answer -eq 'Safe to remove' }) } 'rebuild' { @($base | Where-Object { $_.Answer -eq 'Rebuildable' }) }
                'review' { @($base | Where-Object { $_.Answer -eq 'Review first' }) } 'keep' { @($base | Where-Object { $_.Answer -eq 'Not for the Recycle Bin' }) } default { $base } }
        }
    }
    if ($q) { $rows = @($rows | Where-Object { $_.Name.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or $_.Path.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or ($_.App -and $_.App.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0) -or ($_.Category -and $_.Category.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0) }) }
    switch ($script:Sort) {
        'growth' { @($rows | Sort-Object @{ Expression = { if ($_.Growth) { $_.Growth } else { 0 } }; Descending = $true }, @{ Expression = 'Bytes'; Descending = $true }) }
        'idle' { @($rows | Sort-Object @{ Expression = { $_.IdleDays }; Descending = $true }) }
        'name' { @($rows | Sort-Object Name) }
        default { @($rows | Sort-Object Bytes -Descending) }
    }
}
function Set-TileContent($Tile, [string]$Brush, [string]$Title, [string]$Value, [string]$Sub) {
    $panel = New-Object Windows.Controls.StackPanel
    $t = New-Object Windows.Controls.TextBlock; $t.Text = $Title; $t.FontWeight = 'SemiBold'; $t.FontSize = 13; $t.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $Brush)
    $v = New-Object Windows.Controls.TextBlock; $v.Text = $Value; $v.FontSize = 20; $v.FontWeight = 'SemiBold'; $v.FontFamily = $window.Resources['Display']
    $s = New-Object Windows.Controls.TextBlock; $s.Text = $Sub; $s.FontSize = 12; $s.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Text2')
    $panel.Children.Add($t) | Out-Null; $panel.Children.Add($v) | Out-Null; $panel.Children.Add($s) | Out-Null
    $Tile.Content = $panel
}
function Show-Folders {
    $base = @($script:Items | Where-Object { -not $_.Ignored })
    Set-TileContent $ui.TileAll 'Text1' 'All folders' ([string]$base.Count + ' measured') 'not counting ignored'
    $map = @{ TileSafe = 'Safe to remove'; TileRebuild = 'Rebuildable'; TileReview = 'Review first'; TileKeep = 'Not for the Recycle Bin' }
    foreach ($name in 'TileSafe', 'TileRebuild', 'TileReview', 'TileKeep') {
        $a = $map[$name]; $info = $script:AnswerInfo[$a]; $x = @($base | Where-Object { $_.Answer -eq $a })
        Set-TileContent $ui[$name] $info[1] $a (Size (Sum $x)) ([string]$x.Count + ' · ' + $info[3])
    }
    $ui.TileAll.IsChecked = $script:Tile -eq 'all'; $ui.TileSafe.IsChecked = $script:Tile -eq 'safe'; $ui.TileRebuild.IsChecked = $script:Tile -eq 'rebuild'
    $ui.TileReview.IsChecked = $script:Tile -eq 'review'; $ui.TileKeep.IsChecked = $script:Tile -eq 'keep'
    $ui.FolderTiles.Visibility = $(if ($script:Page -eq 'folders') { 'Visible' } else { 'Collapsed' })
    $previous = $ui.FolderList.SelectedItem
    $rows = Get-FolderRows
    $ui.FolderList.ItemsSource = Typed $rows
    $ui.FolderCount.Text = (Plural $rows.Count 'folder' 'folders') + ' · ' + (Size (Sum $rows)) + $(if ($ui.SearchBox.Text) { ' matching "' + $ui.SearchBox.Text.Trim() + '"' } else { '' })
    $ui.FolderEmpty.Visibility = $(if ($rows) { 'Collapsed' } else { 'Visible' })
    $ui.FolderEmpty.Text = switch ($script:Page) {
        'watch' { 'Nothing on your watchlist. Watch a folder from its card, and any folder that grows between scans shows here too.' }
        'ignored' { 'Nothing ignored. Ignore a folder from its card or right-click it: it''s still scanned, but never suggested.' }
        'unread' { 'Nothing to fix. Every folder was read in full.' }
        default { $(if ($script:Items) { 'No folders match.' } else { 'Scan to see every folder Context Cleaner knows.' }) }
    }
    $keep = $null
    if ($previous) { $keep = $rows | Where-Object { $_.Path -eq $previous.Path } | Select-Object -First 1 }
    if ($keep) { $ui.FolderList.SelectedItem = $keep } elseif ($rows) { $ui.FolderList.SelectedIndex = 0 } else { Show-Inspector $null }
}
function Show-Inspector($Item) {
    $ui.InInside.Visibility = 'Collapsed'
    if (-not $Item) { $ui.Inspector.Visibility = 'Collapsed'; return }
    $ui.Inspector.Visibility = 'Visible'
    $ui.InName.Text = $Item.Name
    $ui.InSub.Text = $Item.SubLine + $(if ($Item.Group -and $Item.Group -ne $Item.Category -and $Item.Group -ne $Item.App) { ' · ' + $Item.Group } else { '' })
    $ui.InPath.Text = $Item.Path
    $ui.InSize.Text = $Item.SizeText
    $ui.InGrowth.Text = $(if ($Item.GrowthText) { $Item.GrowthText } else { 'Last changed ' + $Item.LatestText.ToLower() })
    $ui.InGrowth.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($Item.Growing) { 'Growing' } else { 'Text2' }))
    $ui.InWatchText.Text = $(if ($Item.Watched) { 'Stop Watching' } else { 'Watch' })
    $ui.InIgnoreText.Text = $(if ($Item.Ignored) { 'Stop Ignoring' } else { 'Ignore' })
    $off = $Item.Rule -eq 'off'
    $ui.InWatch.Visibility = $(if ($off) { 'Collapsed' } else { 'Visible' }); $ui.InIgnore.Visibility = $ui.InWatch.Visibility
    $brush = switch ($Item.AnswerKey) { 'safe' { 'Safe' } 'rebuild' { 'Rebuild' } 'review' { 'Review' } 'keep' { 'Keep' } default { 'Other' } }
    $ui.InAnswerBox.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, $brush)
    $ui.InAnswer.Text = $Item.Answer; $ui.InAnswer.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $brush)
    $ui.InReason.Text = $Item.Reason + $(if ($Item.Ignored) { ' · ignored, so never suggested' } else { '' })
    $ui.InWhat.Text = $Item.Explanation
    $ui.InCost.Text = $Item.Consequence
    $ui.InHow.Text = $Item.HowTo; $ui.InHowBox.Visibility = $(if ($Item.HowTo) { 'Visible' } else { 'Collapsed' })
    $notes = @($Item.Evidence)
    if ($Item.InUse) { $notes += 'Running from here: ' + $Item.InUse + '.' }
    $ui.InEvidence.Text = ($notes | Where-Object { $_ }) -join ' '
    $ui.InEvidence.Visibility = $(if ($ui.InEvidence.Text) { 'Visible' } else { 'Collapsed' })
    $ui.InAction.Visibility = 'Visible'
    switch ($Item.Action) {
        'storage' { $ui.InAction.Content = 'Open Storage Settings' }
        'steam' { $ui.InAction.Content = 'Open Steam' }
        default { $ui.InAction.Visibility = 'Collapsed' }
    }
    $ui.InLook.Visibility = $(if ($Item.LookInside) { 'Visible' } else { 'Collapsed' })
    $tracked = @($script:Settings.tracked) -contains $Item.Path
    $trackable = ($Item.Rule -eq 'other' -and (Test-CCInside $Item.Path $script:CCHome) -and (Test-Path -LiteralPath $Item.Path -PathType Container)) -or $tracked
    $ui.InTrack.Visibility = $(if ($trackable) { 'Visible' } else { 'Collapsed' })
    $ui.InTrackText.Text = $(if ($tracked) { 'Stop Tracking' } else { 'Track This Folder' })
    $series = @()
    if ($script:Index -and $script:Index.Series.ContainsKey($Item.Path)) { $series = @($script:Index.Series[$Item.Path] | ForEach-Object { [pscustomobject]@{ At = $_.At; Value = [double]$_.Bytes } }) }
    if ($series.Count -ge 1) {
        $from = $series[0].At; $to = [datetime]::UtcNow
        if (($to - $from).TotalHours -lt 2) { $from = $to.AddHours(-2) }
        Show-AreaChart $ui.InChart $series $from $to 0 'One reading so far'
        $change = [long]($series[-1].Value - $series[0].Value)
        $span = $to - $series[0].At
        $ui.InChartChange.Text = $(if ($series.Count -gt 1 -and $change -ne 0) { [ContextCleaner.Format]::Signed($change) + ' in ' + $(if ($span.TotalDays -ge 1) { [string][int]$span.TotalDays + ' days' } else { [string][int][math]::Max([double]1, $span.TotalHours) + ' hours' }) } else { '' })
        $ui.InChartSub.Text = (Plural $series.Count 'scan' 'scans') + ' since ' + $series[0].At.ToLocalTime().ToString('MMM d, h:mm tt') + '. Point at the last dot for its reading.'
    } else { Show-AreaChart $ui.InChart @() ([datetime]::UtcNow.AddDays(-1)) ([datetime]::UtcNow) 0 'Not measured yet'; $ui.InChartChange.Text = ''; $ui.InChartSub.Text = '' }
}

# Watch, Ignore, Stop Scanning and Track: each one is a setting, saved at once.
function Set-ListSetting([string]$Name, [string]$Path, [bool]$On) {
    $list = @($script:Settings.$Name | Where-Object { $_ -and $_ -ne $Path })
    if ($On) { $list += $Path }
    $script:Settings.$Name = $list
    Save-CCSettings $script:Settings
}
function Switch-Watch($Item) { $Item.Watched = -not $Item.Watched; Set-ListSetting 'watched' $Item.Path $Item.Watched; Set-Message $(if ($Item.Watched) { 'Watching ' + $Item.Name + '. It stays on your Watchlist.' } else { 'Stopped watching ' + $Item.Name + '.' }); Update-Views }
function Switch-Ignore($Item) {
    $Item.Ignored = -not $Item.Ignored; if ($Item.Ignored) { $Item.Selected = $false }
    Set-ListSetting 'ignored' $Item.Path $Item.Ignored
    Set-Message $(if ($Item.Ignored) { 'Ignoring ' + $Item.Name + ': still scanned, never suggested. It''s under Ignored.' } else { $Item.Name + ' can be suggested again.' })
    Update-Views
}
function Switch-Scanning($Item) {
    $off = @($script:Settings.scanningOff) -contains $Item.Path
    Set-ListSetting 'scanningOff' $Item.Path (-not $off)
    if (-not $off) { $script:Items = @($script:Items | Where-Object { $_.Path -ne $Item.Path }); Set-Message ('Stopped scanning ' + $Item.Name + '. It''s under Ignored; Scan This Folder Again there undoes it.') }
    else { Set-Message ($Item.Name + ' will be scanned again from the next scan.') }
    Update-Views
}
function Switch-Track($Item) {
    $on = -not (@($script:Settings.tracked) -contains $Item.Path)
    Set-ListSetting 'tracked' $Item.Path $on
    Set-Message $(if ($on) { 'Tracking ' + $Item.Path + '. Scan again to see what''s inside it.' } else { 'Stopped tracking ' + $Item.Path + '.' })
    Update-Views
}
function New-MenuItem([string]$Header, [string]$Glyph, [scriptblock]$Action, $Item) {
    $m = New-Object Windows.Controls.MenuItem
    $m.Header = $Header; $m.Tag = [Net.WebUtility]::HtmlDecode($Glyph); $m.DataContext = @{ Item = $Item; Action = $Action }
    $m.add_Click({ param($sender, $e) $ctx = $sender.DataContext; & $ctx.Action $ctx.Item })
    $m
}
function New-ItemMenu($Item) {
    $menu = New-Object Windows.Controls.ContextMenu
    $noun = if (Test-Path -LiteralPath $Item.Path -PathType Leaf) { 'File' } else { 'Folder' }
    $menu.Items.Add((New-MenuItem 'Show in Explorer' '&#xE838;' { param($i) Show-InExplorer $i.Path } $Item)) | Out-Null
    $menu.Items.Add((New-MenuItem 'Copy Path' '&#xE8C8;' { param($i) [Windows.Clipboard]::SetText($i.Path); Set-Message ('Copied ' + $i.Path) } $Item)) | Out-Null
    if ($Item.Rule -ne 'off') {
        $menu.Items.Add((New-Object Windows.Controls.Separator)) | Out-Null
        $menu.Items.Add((New-MenuItem $(if ($Item.Watched) { 'Stop Watching' } else { 'Watch for Growth' }) '&#xE890;' { param($i) Switch-Watch $i } $Item)) | Out-Null
        $menu.Items.Add((New-MenuItem $(if ($Item.Ignored) { 'Stop Ignoring' } else { 'Ignore This ' + $noun }) '&#xED1A;' { param($i) Switch-Ignore $i } $Item)) | Out-Null
    }
    if ($Item.Rule -eq 'other' -and (Test-CCInside $Item.Path $script:CCHome)) { $menu.Items.Add((New-MenuItem $(if (@($script:Settings.tracked) -contains $Item.Path) { 'Stop Tracking' } else { 'Track This Folder' }) '&#xE710;' { param($i) Switch-Track $i } $Item)) | Out-Null }
    $menu.Items.Add((New-Object Windows.Controls.Separator)) | Out-Null
    $menu.Items.Add((New-MenuItem $(if ($Item.Rule -eq 'off') { 'Scan This Again' } else { 'Stop Scanning This ' + $noun }) '&#xE8D8;' { param($i) Switch-Scanning $i } $Item)) | Out-Null
    $menu
}
# The item under the mouse, from whatever element was clicked inside a row.
function Find-Item($Source) {
    $node = $Source
    while ($node) {
        if ($node.DataContext -is [ContextCleaner.Item]) { return $node.DataContext }
        if ($node -is [Windows.Media.Visual]) { $node = [Windows.Media.VisualTreeHelper]::GetParent($node) } else { $node = $node.Parent }
    }
    $null
}
function Open-ItemMenu($Sender, $E) {
    $item = Find-Item $E.OriginalSource
    if (-not $item) { return }
    $menu = New-ItemMenu $item
    $menu.PlacementTarget = $Sender; $menu.IsOpen = $true; $E.Handled = $true
}

# ---------- History ----------
function Show-History {
    $records = @(Get-CCHistory | ForEach-Object { $_ | Add-Member -NotePropertyName AtUtc -NotePropertyValue (ConvertTo-CCUtc $_.At) -PassThru -Force } | Sort-Object AtUtc -Descending)
    $week = @($records | Where-Object { $_.AtUtc -ge [datetime]::UtcNow.AddDays(-7) })
    $sumOf = { param($list) $t = [long]0; foreach ($r in @($list)) { $t += [long]$r.Bytes }; $t }
    $countMoved = { param($list) $n = 0; foreach ($r in @($list)) { $n += @($r.Moved).Count }; $n }
    $ui.HiWeek.Text = Size (& $sumOf $week); $ui.HiWeekSub.Text = Plural (& $countMoved $week) 'item' 'items'
    $scans = if ($script:Index) { $script:Index.Scans.Count } else { 0 }
    $ui.HiAll.Text = Size (& $sumOf $records); $ui.HiAllSub.Text = (Plural $records.Count 'cleanup' 'cleanups') + ' · ' + (Plural $scans 'scan' 'scans')
    $days = @(0..29 | ForEach-Object { $d = (Get-Date).Date.AddDays($_ - 29); [pscustomobject]@{ Date = $d; Bytes = (& $sumOf ($records | Where-Object { $_.AtUtc.ToLocalTime().Date -eq $d })) } })
    $ui.HiChartTitle.Text = 'Moved to the Recycle Bin each day · ' + (Size (& $sumOf ($records | Where-Object { $_.AtUtc -ge [datetime]::UtcNow.AddDays(-30) }))) + ' in 30 days'
    Show-BarChart $ui.HiChart $days
    $rows = @()
    if ($ui.HiTabCleanups.IsChecked) {
        foreach ($r in $records) {
            $moved = @($r.Moved).Count; $not = @($r.NotMoved).Count; $gone = @($r.Gone).Count; $count = $moved + $not + $gone
            $title = if ($count -eq 1 -and $moved -eq 1) { 'Moved 1 item to the Recycle Bin' } elseif ($moved -eq $count) { 'Moved all ' + $count + ' to the Recycle Bin' } else { 'Moved ' + $moved + ' of ' + $count + ' to the Recycle Bin' }
            $names = @($r.Moved | ForEach-Object { Split-Path $_ -Leaf })
            $detail = @(); if ($names) { $detail += (($names | Select-Object -First 3) -join ', ') + $(if ($names.Count -gt 3) { ' and ' + ($names.Count - 3) + ' more' } else { '' }) }
            if ($not) { $detail += [string]$not + ' not moved' }; if ($gone) { $detail += [string]$gone + ' already gone' }
            $lines = @($r.Moved | ForEach-Object { 'Moved: ' + $_ }) + @($r.NotMoved | ForEach-Object { 'NOT moved: ' + $_.Path + ' (' + $_.Why + ')' }) + @($r.Gone | ForEach-Object { 'Already gone: ' + $_ })
            $rows += [pscustomobject]@{ At = $r.AtUtc; Icon = $(if ($not) { [string][char]0xE7BA } else { [string][char]0xE73E }); IconBrush = $window.Resources[$(if ($not) { 'Review' } else { 'Safe' })]
                Title = $title; Detail = ($detail -join ' · '); Size = $(if ($r.Bytes) { Size ([long]$r.Bytes) } else { '' }); Time = $r.AtUtc.ToLocalTime().ToString('h:mm tt'); Lines = ($lines -join [Environment]::NewLine) }
        }
        $ui.HiEmpty.Text = 'No cleanups yet. When you run a copied command, each one is listed here with what it moved and what it left alone.'
    } elseif ($script:Index) {
        $previous = $null
        foreach ($s in $script:Index.Scans) {
            $rows += [pscustomobject]@{ At = $s.At; Icon = [string][char]0xE72C; IconBrush = $window.Resources['AccentLink']; Title = 'Scanned ' + (Plural $s.Count 'folder' 'folders')
                Detail = (Size $s.Free) + ' free of ' + (Size $s.Total) + $(if ($s.Seconds) { ' · took ' + $s.Seconds + ' s' } else { '' }) + $(if ($previous) { ' · ' + [ContextCleaner.Format]::Signed($previous.Free - $s.Free) + ' used since the scan before' } else { '' })
                Size = ''; Time = $s.At.ToLocalTime().ToString('h:mm tt'); Lines = 'Saved as ' + $s.File }
            $previous = $s
        }
        $rows = @($rows | Sort-Object At -Descending)
        $ui.HiEmpty.Text = 'No scans yet.'
    }
    $ui.HiList.ItemsSource = @($rows | Group-Object { Format-When $_.At } | ForEach-Object { [pscustomobject]@{ Day = $_.Name; Rows = @($_.Group) } })
    $ui.HiEmpty.Visibility = $(if ($rows) { 'Collapsed' } else { 'Visible' })
}

# ---------- Settings ----------
function New-PathRow([string]$Path, [string]$Button, [string]$Note = '') {
    $border = New-Object Windows.Controls.Border; $border.Padding = '20,10'; $border.BorderThickness = '0,0,0,1'; $border.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Divider')
    $dock = New-Object Windows.Controls.DockPanel
    $b = New-Object Windows.Controls.Button; $b.Content = $Button; $b.Tag = $Path; [Windows.Controls.DockPanel]::SetDock($b, 'Right')
    $t = New-Object Windows.Controls.TextBlock; $t.Text = $Path; $t.VerticalAlignment = 'Center'; $t.TextTrimming = 'CharacterEllipsis'
    if ($Note) { $n = New-Object Windows.Controls.TextBlock; $n.Text = $Note; $n.FontSize = 12; $n.Margin = '0,0,16,0'; $n.VerticalAlignment = 'Center'; $n.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Text2'); [Windows.Controls.DockPanel]::SetDock($n, 'Right') }
    $dock.Children.Add($b) | Out-Null; if ($Note) { $dock.Children.Add($n) | Out-Null }; $dock.Children.Add($t) | Out-Null
    $border.Child = $dock; $border
}
function New-EmptyRow([string]$Text) {
    $t = New-Object Windows.Controls.TextBlock; $t.Text = $Text; $t.Margin = '20,12'; $t.FontSize = 12; $t.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Text2'); $t
}
function Show-Settings {
    $s = $script:Settings
    foreach ($rb in $ui.SetTheme.Children) { $rb.IsChecked = $rb.Tag -eq $s.appearance }
    $ui.SetTerminal.Children.Clear()
    foreach ($t in Get-Terminals) {
        $rb = New-Object Windows.Controls.RadioButton; $rb.Style = $window.Resources['Seg']; $rb.Content = $t.Name; $rb.Tag = $t.Id; $rb.GroupName = 'terminal'
        $rb.IsChecked = $t.Id -eq $s.terminal
        $rb.add_Checked({ param($sender, $e) $script:Settings.terminal = $sender.Tag; Save-Settings })
        $ui.SetTerminal.Children.Add($rb) | Out-Null
    }
    if (-not ($ui.SetTerminal.Children | Where-Object { $_.IsChecked })) { $ui.SetTerminal.Children[0].IsChecked = $true }
    $schedule = Get-CCSchedule
    $script:Quiet = $true
    $ui.SetDaily.IsChecked = [bool]$schedule
    $ui.SetShortcut.IsChecked = Test-Path -LiteralPath (Get-CCShortcutPath)
    $script:Quiet = $false
    $ui.SetDailySub.Text = 'Reads sizes in the background at 12:30 PM, or when your PC is next on, so charts and growth have a reading every day. Uses Task Scheduler in your account.' + $(if ($schedule -and $schedule.Next) { ' Next: ' + $schedule.Next.ToString('ddd h:mm tt') + '.' } else { '' })
    $sizes = @{}; foreach ($i in $script:Items) { $sizes[$i.Coverage] += [long]$i.Bytes }
    $ui.SetCoverage.ItemsSource = @($script:Coverage.Keys | ForEach-Object { [pscustomobject]@{ Key = $_; Title = $script:Coverage[$_][0]; Description = $script:Coverage[$_][1]; On = -not (@($s.coverageOff) -contains $_); SizeText = $(if ($sizes[$_]) { Size $sizes[$_] } else { '' }) } })
    $ui.SetRootsSub.Text = $(if ($s.projectRootsFound) { 'Found automatically: folders on ' + $script:CCDrive.TrimEnd('\') + ', in your home folder or in Documents that hold git repositories. Build output inside them is offered.' } else { 'Folders you chose. Build output in the repositories inside them is offered.' })
    $ui.SetRoots.Items.Clear()
    foreach ($p in $s.projectRoots) { $ui.SetRoots.Items.Add((New-PathRow $p 'Remove')) | Out-Null }
    if (-not $s.projectRoots) { $ui.SetRoots.Items.Add((New-EmptyRow 'No project folders. Add the folder that holds your git repositories, such as C:\src.')) | Out-Null }
    $ui.SetTracked.Items.Clear()
    foreach ($p in $s.tracked) { $ui.SetTracked.Items.Add((New-PathRow $p 'Stop Tracking')) | Out-Null }
    if (-not $s.tracked) { $ui.SetTracked.Items.Add((New-EmptyRow 'None yet. Choose Track on a folder under Everything else, or Add Folder.')) | Out-Null }
    $ui.SetOff.Items.Clear()
    foreach ($p in $s.scanningOff) { $ui.SetOff.Items.Add((New-PathRow $p 'Scan Again')) | Out-Null }
    if (-not $s.scanningOff) { $ui.SetOff.Items.Add((New-EmptyRow 'Every folder is scanned. Right-click a folder and choose Stop Scanning This Folder to skip it.')) | Out-Null }
    $ui.SetVersion.Text = 'Context Cleaner for Windows ' + $script:CCVersion
    $cleanups = @(Get-CCHistory).Count
    $ui.SetDataText.Text = (Plural $(if ($script:Index) { $script:Index.Scans.Count } else { 0 }) 'scan' 'scans') + ' and ' + (Plural $cleanups 'cleanup' 'cleanups') + ' saved in ' + $script:CCData + '. Windows PowerShell ' + $PSVersionTable.PSVersion.ToString() + '.'
}
function Add-FolderSetting([string]$Name, [string]$Title) {
    $hwnd = (New-Object Windows.Interop.WindowInteropHelper $window).Handle
    $path = [ContextCleaner.FolderPicker]::Pick($hwnd, $Title)
    if (-not $path) { return }
    $path = [IO.Path]::GetFullPath($path).TrimEnd('\')
    if ($Name -eq 'tracked' -and -not (Test-CCInside $path $script:CCHome)) { Set-Message 'Only folders inside your home folder can be tracked, so a command never reaches Program Files or Windows.'; return }
    if ($Name -eq 'projectRoots' -and $script:Settings.projectRootsFound) { $script:Settings.projectRootsFound = $false }
    Set-ListSetting $Name $path $true
    $script:Settings = Get-CCSettings
    Show-Settings
    Set-Message ('Added ' + $path + '. Scan again to see what''s inside it.')
}

# ---------- Navigation ----------
$script:Titles = @{
    overview = @('Overview', 'What fills your drive, what changed, and what you could get back.')
    free = @('Free Up Space', 'What nothing has touched for a while, biggest first. Tick it, copy one command, paste it in your terminal.')
    folders = @('Folders', 'Every folder Context Cleaner knows, with its answer and why.')
    watch = @('Watchlist', 'Folders you watch, and any that grew since an earlier scan.')
    ignored = @('Ignored', 'Folders you set aside: still scanned and never suggested, or not scanned at all.')
    unread = @('Couldn''t Scan', 'Folders with parts Windows wouldn''t let Context Cleaner read. Their sizes leave those parts out.')
    history = @('History', 'What you moved to the Recycle Bin, and what each scan found.')
    settings = @('Settings', 'How Context Cleaner looks, where it looks, and when.')
}
function Show-Page([string]$Key) {
    $script:Page = $Key
    $ui.PageTitle.Text = $script:Titles[$Key][0]; $ui.PageSubtitle.Text = $script:Titles[$Key][1]
    $panels = @{ overview = 'PageOverview'; free = 'PageFree'; folders = 'PageFolders'; watch = 'PageFolders'; ignored = 'PageFolders'; unread = 'PageFolders'; history = 'PageHistory'; settings = 'PageSettings' }
    foreach ($p in 'PageOverview', 'PageFree', 'PageFolders', 'PageHistory', 'PageSettings') { $ui[$p].Visibility = $(if ($panels[$Key] -eq $p) { 'Visible' } else { 'Collapsed' }) }
    $script:Navigating = $true
    foreach ($nav in $ui.Nav, $ui.NavFooter) { foreach ($li in $nav.Items) { $li.IsSelected = $li.Tag -eq $Key } }
    $script:Navigating = $false
    Update-Views
}
function Update-Badges {
    $w = @($script:Items | Where-Object { $_.Watched -or $_.Growing }).Count
    $ig = @($script:Items | Where-Object { $_.Ignored }).Count + @($script:Settings.scanningOff).Count
    $un = @($script:Items | Where-Object { $_.Unreadable -gt 0 }).Count
    $ui.BadgeWatch.Text = $(if ($w) { [string]$w } else { '' }); $ui.BadgeIgnored.Text = $(if ($ig) { [string]$ig } else { '' }); $ui.BadgeUnread.Text = $(if ($un) { [string]$un } else { '' })
}
function Update-Status {
    $drive = New-Object IO.DriveInfo $script:CCDrive
    $ui.FreeMiniText.Text = (Size $drive.AvailableFreeSpace) + ' free of ' + (Size $drive.TotalSize)
    $ui.FreeMiniUsed.Width = New-Object Windows.GridLength ([double]($drive.TotalSize - $drive.AvailableFreeSpace)), 'Star'
    $ui.FreeMiniFree.Width = New-Object Windows.GridLength ([double]$drive.AvailableFreeSpace), 'Star'
    if ($script:Worker) { return }
    if ($script:ScanData) {
        $growing = @($script:Items | Where-Object { $_.Growing }).Count
        $ui.Status.Text = 'Scanned ' + [ContextCleaner.Format]::Ago((ConvertTo-CCUtc $script:ScanData.FinishedAt)).ToLower() + ' · ' + (Plural $script:Items.Count 'folder' 'folders') + $(if ($growing) { ' · ' + $growing + ' growing' } else { '' })
    } else { $ui.Status.Text = 'Not scanned yet. Choose Scan; it reads sizes and dates only.' }
}
function Update-Views {
    Update-Badges; Update-Status
    switch ($script:Page) {
        'overview' { Show-Overview } 'free' { Show-Free } 'history' { Show-History } 'settings' { Show-Settings }
        default { Show-Folders }
    }
}
function Set-ScanData($Data) {
    $script:ScanData = $Data
    $script:Items = @($Data.Items)
    foreach ($item in $script:Items) { $item.add_PropertyChanged({ param($s, $e) if ($e.PropertyName -eq 'Selected' -and $script:Page -eq 'free') { Update-FreeTotal } }) }
    $script:Index = Get-CCScanIndex
}

# ---------- Scanning, on its own thread so the window stays responsive ----------
function Start-Scan {
    if ($script:Worker) { return }
    $ui.ScanButton.IsEnabled = $false; $ui.StopButton.Visibility = 'Visible'; $ui.ScanProgress.Visibility = 'Visible'
    $script:Sync = [hashtable]::Synchronized(@{ Status = 'Starting'; Result = $null; Error = $null; Done = $false })
    $runspace = [runspacefactory]::CreateRunspace(); $runspace.ApartmentState = 'STA'; $runspace.Open()
    $runspace.SessionStateProxy.SetVariable('sync', $script:Sync); $runspace.SessionStateProxy.SetVariable('corePath', $corePath)
    $script:Worker = [powershell]::Create(); $script:Worker.Runspace = $runspace
    $script:Worker.AddScript({
        try { . $corePath; $sync.Result = Invoke-CCScan -Progress { param($text) $sync.Status = $text } }
        catch { $sync.Error = $_.Exception.Message }
        finally { $sync.Done = $true }
    }) | Out-Null
    $script:WorkerHandle = $script:Worker.BeginInvoke()
    $script:Started = Get-Date
    $script:ScanTimer.Start()
}
$script:ScanTimer = New-Object Windows.Threading.DispatcherTimer
$script:ScanTimer.Interval = [TimeSpan]::FromMilliseconds(400)
$script:ScanTimer.add_Tick({
    $sync = $script:Sync
    $seconds = [int]((Get-Date) - $script:Started).TotalSeconds
    $ui.Status.Text = $sync.Status + ' · ' + ([ContextCleaner.Disk]::FilesRead).ToString('N0') + ' files · ' + $seconds + ' s'
    if (-not $sync.Done) { return }
    $script:ScanTimer.Stop()
    try { $script:Worker.EndInvoke($script:WorkerHandle) | Out-Null } catch { }
    $script:Worker.Runspace.Dispose(); $script:Worker.Dispose(); $script:Worker = $null
    $ui.ScanButton.IsEnabled = $true; $ui.StopButton.Visibility = 'Collapsed'; $ui.ScanProgress.Visibility = 'Collapsed'
    if ($sync.Error) { Set-Message $sync.Error; Update-Status; return }
    # Reload from the saved file, so the window and the saved scan always agree.
    Set-ScanData (Get-CCLastScan)
    Set-Message ('Scanned in ' + $seconds + ' s. ' + (Plural @($script:Items | Where-Object { $_.Growing }).Count 'folder grew' 'folders grew') + ' since the scan before.')
    Update-Views
})
function Stop-Scan { if ($script:Worker) { [ContextCleaner.Disk]::Cancel = $true; $ui.Status.Text = 'Stopping…' } }

# Gone means gone: a folder you moved yourself leaves every list within seconds.
$script:GoneTimer = New-Object Windows.Threading.DispatcherTimer
$script:GoneTimer.Interval = [TimeSpan]::FromSeconds(15)
$script:GoneTimer.add_Tick({ Remove-Gone })
function Remove-Gone {
    # Demo data (for screenshots) names folders that don't exist, so it is never pruned.
    if (-not $script:Items -or $script:Worker -or $env:CONTEXT_CLEANER_DEMO) { Update-Status; return }
    $left = @($script:Items | Where-Object { -not $_.Removable -or (Test-Path -LiteralPath $_.Path) })
    if ($left.Count -ne $script:Items.Count) { $script:Items = $left; Update-Views } else { Update-Status }
}

# ---------- Wiring ----------
$window.Dispatcher.add_UnhandledException({
    param($sender, $e)
    Write-CCLog ($e.Exception.ToString())
    Set-Message ('Something went wrong: ' + $e.Exception.Message + ' It''s logged in ' + $script:LogPath)
    $e.Handled = $true
})
On $ui.Nav 'SelectionChanged' { if (-not $script:Navigating -and $ui.Nav.SelectedItem) { Show-Page $ui.Nav.SelectedItem.Tag } }
On $ui.NavFooter 'SelectionChanged' { if (-not $script:Navigating -and $ui.NavFooter.SelectedItem) { Show-Page $ui.NavFooter.SelectedItem.Tag } }
On $ui.ScanButton 'Click' { Start-Scan }
On $ui.StopButton 'Click' { Stop-Scan }
On $ui.MoreButton 'Click' { $menu = $ui.MoreButton.ContextMenu; $menu.PlacementTarget = $ui.MoreButton; $menu.Placement = 'Bottom'; $menu.IsOpen = $true }
On $ui.MenuExport 'Click' { Export-Report }
On $ui.MenuBin 'Click' { Open-Bin }
On $ui.MenuStorage 'Click' { Start-Process 'ms-settings:storagesense' }
On $ui.MenuData 'Click' { New-Item -ItemType Directory -Force -Path $script:CCData | Out-Null; Start-Process 'explorer.exe' -ArgumentList ('"' + $script:CCData + '"') }
On $ui.MessageTerminal 'Click' { Open-Terminal }
On $ui.SearchBox 'TextChanged' {
    if ($ui.SearchBox.Text -and @('folders', 'watch', 'ignored', 'unread') -notcontains $script:Page) { $script:Tile = 'all'; Show-Page 'folders' } elseif ($script:Page -ne 'overview') { Show-Folders }
}
foreach ($r in $ui.Range1, $ui.Range7, $ui.Range30) { On $r 'Checked' { if ($script:Page -eq 'overview' -and $script:Ready) { Show-Overview } } }
On $ui.OvGoFree 'Click' { Show-Page 'free' }
On $ui.OvOpenBin 'Click' { Open-Bin }
foreach ($list in $ui.OvTop, $ui.OvGrow) {
    On $list 'MouseDoubleClick' { param($s, $e) $item = Find-Item $e.OriginalSource; if ($item) { $script:Tile = 'all'; Show-Page 'folders'; $ui.FolderList.SelectedItem = $item; $ui.FolderList.ScrollIntoView($item) } }
    On $list 'ContextMenuOpening' { param($s, $e) Open-ItemMenu $s $e }
}
# Free Up Space
foreach ($rb in $ui.FreeAges.Children) {
    $rb.IsChecked = [int]$rb.Tag -eq [int]$script:Settings.untouchedDays
    On $rb 'Checked' { param($s, $e) if ($script:Ready) { $script:Settings.untouchedDays = [int]$s.Tag; Save-Settings; Show-Free } }
}
$ui.ChipAll.IsChecked = $true
On $ui.ChipAll 'Checked' { $script:Chip = 'all'; if ($script:Ready) { Show-Free } }
On $ui.ChipLossless 'Checked' { $script:Chip = 'lossless'; if ($script:Ready) { Show-Free } }
On $ui.ChipReview 'Checked' { $script:Chip = 'review'; if ($script:Ready) { Show-Free } }
$ui.OrderBig.IsChecked = -not $script:Settings.byKind; $ui.OrderKind.IsChecked = [bool]$script:Settings.byKind
On $ui.OrderBig 'Checked' { if ($script:Ready) { $script:Settings.byKind = $false; Save-Settings; Show-Free } }
On $ui.OrderKind 'Checked' { if ($script:Ready) { $script:Settings.byKind = $true; Save-Settings; Show-Free } }
On $ui.FreeAll 'Click' {
    $shown = @(Get-FreeShown); $all = @($shown | Where-Object { $_.Selected }).Count -eq $shown.Count
    foreach ($i in $shown) { $i.Selected = -not $all }
    Update-FreeTotal
}
On $ui.FreeClear 'Click' { foreach ($i in $script:Items) { $i.Selected = $false }; Update-FreeTotal }
On $ui.FreeCopy 'Click' { Invoke-Copy }
On $ui.FreeTerminal 'Click' { Open-Terminal }
On $ui.FreeOpenBin 'Click' { Open-Bin }
On $ui.FreeGroups 'ContextMenuOpening' { param($s, $e) Open-ItemMenu $s $e }
On $ui.FreeGroups 'MouseDoubleClick' { param($s, $e) $item = Find-Item $e.OriginalSource; if ($item) { Show-InExplorer $item.Path } }
# Folders
foreach ($pair in @(@($ui.TileAll, 'all'), @($ui.TileSafe, 'safe'), @($ui.TileRebuild, 'rebuild'), @($ui.TileReview, 'review'), @($ui.TileKeep, 'keep'))) {
    $pair[0].Tag = $pair[1]
    On $pair[0] 'Click' { param($s, $e) $script:Tile = $s.Tag; Show-Folders }
}
foreach ($rb in $ui.FolderSorts.Children) { On $rb 'Checked' { param($s, $e) $script:Sort = $s.Tag; if ($script:Ready) { Show-Folders } } }
On $ui.FolderList 'SelectionChanged' { Show-Inspector $ui.FolderList.SelectedItem }
On $ui.FolderList 'ContextMenuOpening' { param($s, $e) Open-ItemMenu $s $e }
On $ui.FolderList 'MouseDoubleClick' { param($s, $e) $item = Find-Item $e.OriginalSource; if ($item) { Show-InExplorer $item.Path } }
On $ui.InWatch 'Click' { $i = $ui.FolderList.SelectedItem; if ($i) { Switch-Watch $i } }
On $ui.InIgnore 'Click' { $i = $ui.FolderList.SelectedItem; if ($i) { Switch-Ignore $i } }
On $ui.InReveal 'Click' { $i = $ui.FolderList.SelectedItem; if ($i) { Show-InExplorer $i.Path } }
On $ui.InMore 'Click' { $i = $ui.FolderList.SelectedItem; if ($i) { $m = New-ItemMenu $i; $m.PlacementTarget = $ui.InMore; $m.Placement = 'Bottom'; $m.IsOpen = $true } }
On $ui.InTrack 'Click' { $i = $ui.FolderList.SelectedItem; if ($i) { Switch-Track $i } }
On $ui.InAction 'Click' {
    $i = $ui.FolderList.SelectedItem
    if (-not $i) { return }
    switch ($i.Action) { 'storage' { Start-Process 'ms-settings:storagesense' } 'steam' { Start-Process 'steam://open/main' } }
}
On $ui.InLook 'Click' {
    $i = $ui.FolderList.SelectedItem
    if (-not $i -or -not $i.LookInside -or $script:Look) { return }
    $ui.InInside.Visibility = 'Visible'; $ui.InInside.Text = 'Reading sizes inside ' + $i.LookInside + '. This starts Linux if it isn''t running, and takes up to a minute…'
    $ui.InLook.IsEnabled = $false
    $script:Look = [powershell]::Create()
    $script:Look.AddScript({ param($core, $name) . $core; Get-CCWslInside $name }).AddArgument($corePath).AddArgument($i.LookInside) | Out-Null
    $script:LookHandle = $script:Look.BeginInvoke()
    $script:LookTimer.Start()
}
$script:LookTimer = New-Object Windows.Threading.DispatcherTimer
$script:LookTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$script:LookTimer.add_Tick({
    if (-not $script:LookHandle.IsCompleted) { return }
    $script:LookTimer.Stop()
    try { $ui.InInside.Text = (($script:Look.EndInvoke($script:LookHandle) | Out-String).Trim()) } catch { $ui.InInside.Text = 'Couldn''t look inside: ' + $_.Exception.Message }
    $script:Look.Dispose(); $script:Look = $null; $ui.InLook.IsEnabled = $true
})
# History
On $ui.HiTabCleanups 'Checked' { if ($script:Ready) { Show-History } }
On $ui.HiTabScans 'Checked' { if ($script:Ready) { Show-History } }
On $ui.HiOpenBin 'Click' { Open-Bin }
# Settings
foreach ($rb in $ui.SetTheme.Children) { On $rb 'Checked' { param($s, $e) if ($script:Ready -and $script:Settings.appearance -ne $s.Tag) { $script:Settings.appearance = $s.Tag; Save-Settings; Set-Theme; Update-Views } } }
On $ui.SetDaily 'Click' {
    try { Set-CCSchedule ([bool]$ui.SetDaily.IsChecked); Set-Message $(if ($ui.SetDaily.IsChecked) { 'Context Cleaner will scan once a day. It reads sizes only.' } else { 'Daily scan turned off.' }) }
    catch { Set-Message ('Windows didn''t let Context Cleaner change the daily scan: ' + $_.Exception.Message) }
    Show-Settings
}
On $ui.SetShortcut 'Click' { Set-CCShortcut ([bool]$ui.SetShortcut.IsChecked); Set-Message $(if ($ui.SetShortcut.IsChecked) { 'Added Context Cleaner to the Start menu.' } else { 'Removed the Start menu shortcut.' }); Show-Settings }
$ui.SetCoverage.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
    param($s, $e)
    $box = $e.OriginalSource
    if (-not ($box -is [Windows.Controls.CheckBox])) { return }
    Set-ListSetting 'coverageOff' $box.Tag (-not $box.IsChecked)
    $script:Settings = Get-CCSettings
    Set-Message ($script:Coverage[$box.Tag][0] + $(if ($box.IsChecked) { ' will be scanned' } else { ' won''t be scanned' }) + ' from the next scan.')
})
foreach ($pair in @(@($ui.SetRoots, 'projectRoots'), @($ui.SetTracked, 'tracked'), @($ui.SetOff, 'scanningOff'))) {
    $pair[0].Tag = $pair[1]
    $pair[0].AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
        param($s, $e)
        $b = $e.OriginalSource
        if (-not ($b -is [Windows.Controls.Button]) -or -not $b.Tag) { return }
        if ($s.Tag -eq 'projectRoots' -and $script:Settings.projectRootsFound) { $script:Settings.projectRootsFound = $false }
        Set-ListSetting $s.Tag $b.Tag $false
        $script:Settings = Get-CCSettings
        Show-Settings
        Set-Message ('Changed. Scan again to update the lists.')
    })
}
On $ui.SetRootsAdd 'Click' { Add-FolderSetting 'projectRoots' 'Choose a folder that holds your git repositories' }
On $ui.SetRootsAuto 'Click' { $script:Settings.projectRoots = @(); $script:Settings.projectRootsFound = $true; Save-Settings; Show-Settings; Set-Message 'Project folders are found automatically again.' }
On $ui.SetTrackAdd 'Click' { Add-FolderSetting 'tracked' 'Choose a folder in your home folder to track item by item' }
On $ui.SetOpenData 'Click' { New-Item -ItemType Directory -Force -Path $script:CCData | Out-Null; Start-Process 'explorer.exe' -ArgumentList ('"' + $script:CCData + '"') }
On $ui.SetGitHub 'Click' { Start-Process 'https://github.com/chrissotraidis/contextcleaner' }

function Export-Report {
    if (-not $script:ScanData) { Set-Message 'Scan first; the cleanup list comes from a scan.'; return }
    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.FileName = 'Context Cleaner ' + (Get-Date).ToString('yyyy-MM-dd') + '.md'; $dialog.Filter = 'Markdown (*.md)|*.md|Text (*.txt)|*.txt'
    if ($dialog.ShowDialog($window)) { Export-CCReport $script:ScanData $dialog.FileName; Set-Message ('Saved the cleanup list to ' + $dialog.FileName) }
}

# Keyboard: Ctrl+R or F5 scans, Esc stops, Ctrl+F searches, Ctrl+Shift+C copies, Ctrl+E exports, Ctrl+1 to 7 switch pages.
On $window 'PreviewKeyDown' {
    param($s, $e)
    $ctrl = [Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control
    $shift = [Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Shift
    $pages = @('overview', 'free', 'folders', 'watch', 'ignored', 'unread', 'history')
    if ($e.Key -eq 'F5' -or ($ctrl -and $e.Key -eq 'R')) { Start-Scan; $e.Handled = $true }
    elseif ($e.Key -eq 'Escape') { if ($script:Worker) { Stop-Scan } elseif ($ui.SearchBox.Text) { $ui.SearchBox.Text = '' }; $e.Handled = $true }
    elseif ($ctrl -and $e.Key -eq 'F') { $ui.SearchBox.Focus() | Out-Null; $ui.SearchBox.SelectAll(); $e.Handled = $true }
    elseif ($ctrl -and $shift -and $e.Key -eq 'C') { if ($script:Page -eq 'free') { Invoke-Copy }; $e.Handled = $true }
    elseif ($ctrl -and $e.Key -eq 'E') { Export-Report; $e.Handled = $true }
    elseif ($ctrl -and $e.Key -eq 'OemComma') { Show-Page 'settings'; $e.Handled = $true }
    elseif ($ctrl -and $e.Key -ge 'D1' -and $e.Key -le 'D7') { Show-Page $pages[[int]$e.Key - [int][Windows.Input.Key]::D1]; $e.Handled = $true }
}
foreach ($c in 'OvChart', 'InChart', 'HiChart') { On $ui[$c] 'SizeChanged' { param($s, $e) $c = $script:Charts[$s.Name]; if ($c) { if ($c.Kind -eq 'area') { Show-AreaChart $s $c.Points $c.From $c.To $c.Ceiling $c.Empty } else { Show-BarChart $s $c.Days } } } }
On $window 'Activated' { if ($script:Ready) { Remove-Gone } }

# Follow Windows when its light or dark mode or accent changes while the app is open.
$script:LastSystemTheme = (Test-CCDarkMode).ToString() + (Get-CCAccent)[3].ToString()
$script:ThemeTimer = New-Object Windows.Threading.DispatcherTimer
$script:ThemeTimer.Interval = [TimeSpan]::FromSeconds(3)
$script:ThemeTimer.add_Tick({
    $now = (Test-CCDarkMode).ToString() + (Get-CCAccent)[3].ToString()
    if ($now -ne $script:LastSystemTheme) { $script:LastSystemTheme = $now; Set-Theme; Update-Views }
})

On $window 'SourceInitialized' {
    $script:Hwnd = (New-Object Windows.Interop.WindowInteropHelper $window).Handle
    # Mica on Windows 11: the window and its sidebar show the desktop's tint, like Settings and File Explorer.
    try {
        if ([Environment]::OSVersion.Version.Build -ge 22621 -and [Windows.Media.RenderCapability]::Tier -ge 0x20000) {
            $source = [Windows.Interop.HwndSource]::FromHwnd($script:Hwnd)
            $source.CompositionTarget.BackgroundColor = [Windows.Media.Colors]::Transparent
            if ([ContextCleaner.Shell]::Mica($script:Hwnd)) { $script:Mica = $true; $window.Background = [Windows.Media.Brushes]::Transparent }
        }
    } catch { $script:Mica = $false }
    Set-Theme
}
On $window 'Closed' { $script:ScanTimer.Stop(); $script:GoneTimer.Stop(); $script:ThemeTimer.Stop(); if ($script:Worker) { [ContextCleaner.Disk]::Cancel = $true } }

# ---------- Start ----------
Set-Theme
$last = Get-CCLastScan
if ($last) { Set-ScanData $last } else { $script:Index = Get-CCScanIndex }
$drive = New-Object IO.DriveInfo $script:CCDrive
$lastReading = Get-CCReadings | Select-Object -Last 1
if (-not $lastReading -or ([datetime]::UtcNow - $lastReading.At).TotalHours -ge 1) { Add-CCReading $drive.TotalSize $drive.AvailableFreeSpace }
$script:Ready = $true
Show-Page 'overview'
$script:GoneTimer.Start(); $script:ThemeTimer.Start()
if (-not $last) { Set-Message 'Welcome. Choose Scan to see what fills your drive; it reads folder sizes and dates and changes nothing.' }
$window.ShowDialog() | Out-Null
$script:Mutex.ReleaseMutex()

