# Builds windows\icon.ico (PNG entries from 16 to 256 px) and windows\icon.png from the same source as the Mac app icon.
#   powershell -NoProfile -ExecutionPolicy Bypass -File windows\Tools\Make-Icon.ps1
param([string]$Source = (Join-Path $PSScriptRoot '..\..\Assets\IconCandidates\LayeredC.png'))
Add-Type -AssemblyName System.Drawing
$windows = Split-Path $PSScriptRoot -Parent
$src = [Drawing.Image]::FromFile((Resolve-Path $Source).Path)
function Render([int]$Size) {
    $bmp = New-Object Drawing.Bitmap $Size, $Size
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = 'HighQualityBicubic'; $g.SmoothingMode = 'HighQuality'; $g.PixelOffsetMode = 'HighQuality'
    $g.DrawImage($src, 0, 0, $Size, $Size); $g.Dispose()
    $ms = New-Object IO.MemoryStream; $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    , $ms.ToArray()
}
$sizes = 16, 20, 24, 32, 40, 48, 64, 256
$pngs = foreach ($s in $sizes) { , (Render $s) }
$out = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter $out
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $d = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
    $w.Write([byte]$d); $w.Write([byte]$d); $w.Write([byte]0); $w.Write([byte]0); $w.Write([uint16]1); $w.Write([uint16]32)
    $w.Write([uint32]$pngs[$i].Length); $w.Write([uint32]$offset); $offset += $pngs[$i].Length
}
foreach ($p in $pngs) { $w.Write([byte[]]$p) }
$w.Flush()
[IO.File]::WriteAllBytes((Join-Path $windows 'icon.ico'), $out.ToArray())
[IO.File]::WriteAllBytes((Join-Path $windows 'icon.png'), (Render 256))
$src.Dispose()
'Wrote icon.ico and icon.png from ' + (Resolve-Path $Source).Path

