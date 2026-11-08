# Builds the Windows release: runs the tests, then zips the app with a SHA-256 checksum.
#   powershell -NoProfile -ExecutionPolicy Bypass -File windows\Build-Release.ps1 -Out C:\path\to\new-folder
# The output folder must not exist yet, so an earlier release is never overwritten.
param([Parameter(Mandatory = $true)][string]$Out)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $Out) { throw ('Refusing existing release destination: ' + $Out) }
. (Join-Path $PSScriptRoot 'ContextCleaner.Core.ps1')
$version = $script:CCVersion
& (Get-CCPowerShell) -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Tests\Run-Tests.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Tests failed; nothing was built.' }
New-Item -ItemType Directory -Path $Out | Out-Null
$stage = Join-Path $Out ('Context Cleaner ' + $version)
New-Item -ItemType Directory -Path $stage | Out-Null
foreach ($f in 'Context Cleaner.cmd', 'ContextCleaner.ps1', 'ContextCleaner.Core.ps1', 'ContextCleaner.xaml', 'Move-ToRecycleBin.ps1', 'icon.ico', 'icon.png', 'README.md') {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $f) -Destination $stage
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\LICENSE') -Destination $stage
$repo = Split-Path $PSScriptRoot -Parent
(& git -C $repo rev-parse HEAD) | Set-Content -LiteralPath (Join-Path $Out 'source-revision.txt')
(& git -C $repo status --porcelain) | Set-Content -LiteralPath (Join-Path $Out 'source-status.txt')
$zip = Join-Path $Out ('Context-Cleaner-' + $version + '-windows.zip')
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [IO.Compression.CompressionLevel]::Optimal, $true)
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower()
Set-Content -LiteralPath ($zip + '.sha256') -Value ($hash + '  ' + (Split-Path $zip -Leaf))
'Built ' + $zip
'SHA-256 ' + $hash

