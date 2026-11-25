# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# Makes a Windows .ico from a macOS .icns: takes the largest PNG inside the .icns and
# writes it at 16, 24, 32, 48, 64, 128 and 256 pixels (PNG entries, Windows Vista or later).
#
# Usage: powershell -File apps\scripts\make-ico.ps1 [name]      (default VLCNDI)
# Reads apps\resources\icons\<name>.icns, writes apps\resources\icons\<name>.ico

param([string]$Name = 'VLCNDI')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$icons = Join-Path $PSScriptRoot '..\resources\icons'
$icns = [IO.File]::ReadAllBytes((Join-Path $icons "$Name.icns"))

# .icns: "icns", total size, then chunks of (4-char type, big-endian size, data).
function Read-UInt32BE([byte[]]$b, [int]$o) { ([uint32]$b[$o] -shl 24) -bor ([uint32]$b[$o+1] -shl 16) -bor ([uint32]$b[$o+2] -shl 8) -bor $b[$o+3] }
$best = $null
$pos = 8
while ($pos + 8 -le $icns.Length) {
    $size = [int](Read-UInt32BE $icns ($pos + 4))
    if ($size -lt 8) { break }
    $data = $pos + 8
    $isPng = $icns[$data] -eq 0x89 -and $icns[$data+1] -eq 0x50 -and $icns[$data+2] -eq 0x4E -and $icns[$data+3] -eq 0x47
    if ($isPng) {
        $bytes = New-Object byte[] ($size - 8)
        [Array]::Copy($icns, $data, $bytes, 0, $size - 8)
        $img = [Drawing.Image]::FromStream((New-Object IO.MemoryStream (,$bytes)))
        if (-not $best -or $img.Width -gt $best.Width) { $best = $img }
    }
    $pos += $size
}
if (-not $best) { throw "No PNG image found in $Name.icns" }

$sizes = 16, 24, 32, 48, 64, 128, 256
$pngs = foreach ($s in $sizes) {
    $bmp = New-Object Drawing.Bitmap $s, $s, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.DrawImage($best, 0, 0, $s, $s)
    $g.Dispose()
    $ms = New-Object IO.MemoryStream
    $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    ,$ms.ToArray()
}

$out = New-Object IO.MemoryStream
$w = New-Object IO.BinaryWriter $out
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $w.Write([byte]($sizes[$i] % 256)); $w.Write([byte]($sizes[$i] % 256))   # 256 is stored as 0
    $w.Write([byte]0); $w.Write([byte]0); $w.Write([uint16]1); $w.Write([uint16]32)
    $w.Write([uint32]$pngs[$i].Length); $w.Write([uint32]$offset)
    $offset += $pngs[$i].Length
}
foreach ($p in $pngs) { $w.Write($p) }
$w.Flush()
$ico = Join-Path $icons "$Name.ico"
[IO.File]::WriteAllBytes($ico, $out.ToArray())
"Wrote $ico ($($best.Width) px source, sizes: $($sizes -join ', '))"
