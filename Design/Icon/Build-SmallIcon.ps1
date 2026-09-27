param([string]$ProjectRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# Keep the original 16 px artwork, including its thick lettering and palette.
# Only the background pixels at the four corners are modified.
$originalIcon = New-Object System.Drawing.Icon((Join-Path $PSScriptRoot 'icon-original.ico'),16,16)
$bitmap = $originalIcon.ToBitmap()
$originalIcon.Dispose()
$reference = $bitmap.Clone()
$background = $bitmap.GetPixel(0,0)
$corner = @( @(0,120,240), @(120,255,255), @(240,255,255) )
for ($y = 0; $y -lt 16; $y++) {
    for ($x = 0; $x -lt 16; $x++) {
        $cx = [Math]::Min($x,15 - $x)
        $cy = [Math]::Min($y,15 - $y)
        if ($cx -lt 3 -and $cy -lt 3) {
            $alpha = $corner[$cy][$cx]
            if ($alpha -ne 255) {
                $originalPixel = $reference.GetPixel($x,$y)
                if ($originalPixel.R -gt 80 -or $originalPixel.G -gt 80 -or $originalPixel.B -gt 80) {
                    throw 'Corner mask would alter original lettering.'
                }
                $bitmap.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($alpha,$originalPixel))
            }
        }
    }
}
$framePath = Join-Path $PSScriptRoot 'icon-16.png'
$bitmap.Save($framePath, [System.Drawing.Imaging.ImageFormat]::Png)
for ($y = 0; $y -lt 16; $y++) {
    for ($x = 0; $x -lt 16; $x++) {
        $pixel = $bitmap.GetPixel($x,$y)
        $originalPixel = $reference.GetPixel($x,$y)
        if (($originalPixel.R -gt 80 -or $originalPixel.G -gt 80 -or $originalPixel.B -gt 80) -and
            $pixel.ToArgb() -ne $originalPixel.ToArgb()) {
            throw 'Original lettering must remain pixel-identical.'
        }
        if ($pixel.A -notin 0,255 -and
            ($pixel.R -ne $originalPixel.R -or $pixel.G -ne $originalPixel.G -or $pixel.B -ne $originalPixel.B)) {
            throw 'Only the background contour may have partial alpha.'
        }
    }
}
$reference.Dispose()

# Replace only the 16 px entry. Preserve every other ICO payload verbatim.
$icoPath = Join-Path $ProjectRoot 'Assets\icon.ico'
$original = [System.IO.File]::ReadAllBytes($icoPath)
$count = [BitConverter]::ToUInt16($original,4)
$png = [System.IO.File]::ReadAllBytes($framePath)
$stream = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.BinaryWriter $stream
$writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$count)
$payloads = @()
$offset = 6 + 16 * $count
$replaced = 0
for ($i = 0; $i -lt $count; $i++) {
    $entry = 6 + 16 * $i
    $length = [BitConverter]::ToUInt32($original,$entry+8)
    $oldOffset = [BitConverter]::ToUInt32($original,$entry+12)
    $payload = New-Object byte[] $length
    [Array]::Copy($original,$oldOffset,$payload,0,$length)
    if ($original[$entry] -eq 16 -and $original[$entry+1] -eq 16) {
        $payload = $png; $replaced++
    }
    $writer.Write($original,$entry,8)
    $writer.Write([uint32]$payload.Length); $writer.Write([uint32]$offset)
    $payloads += ,$payload
    $offset += $payload.Length
}
if ($replaced -ne 1) { throw 'Expected exactly one 16 px ICO frame.' }
foreach ($payload in $payloads) { $writer.Write([byte[]]$payload) }
$writer.Flush()
[System.IO.File]::WriteAllBytes($icoPath,$stream.ToArray())
$writer.Dispose(); $stream.Dispose()

# Exact integer zoom for reviewing pixel geometry, on light and dark backgrounds.
$preview = New-Object System.Drawing.Bitmap 576,288
for ($y = 0; $y -lt 288; $y++) {
    for ($x = 0; $x -lt 576; $x++) {
        $color = if ($x -lt 288) { [System.Drawing.Color]::FromArgb(238,238,238) } else { [System.Drawing.Color]::FromArgb(32,32,32) }
        $localX = $x % 288
        if ($localX -ge 16 -and $localX -lt 272 -and $y -ge 16 -and $y -lt 272) {
            $pixel = $bitmap.GetPixel([int][Math]::Floor(($localX - 16) / 16),[int][Math]::Floor(($y - 16) / 16))
            $a = $pixel.A / 255.0
            $color = [System.Drawing.Color]::FromArgb(
                [int][Math]::Round($pixel.R * $a + $color.R * (1 - $a)),
                [int][Math]::Round($pixel.G * $a + $color.G * (1 - $a)),
                [int][Math]::Round($pixel.B * $a + $color.B * (1 - $a)))
        }
        $preview.SetPixel($x,$y,$color)
    }
}
$preview.Save((Join-Path $PSScriptRoot 'icon-16-preview.png'),[System.Drawing.Imaging.ImageFormat]::Png)
$preview.Dispose(); $bitmap.Dispose()
Write-Output 'PASS: original 16 px lettering and palette preserved exactly; only background corners rounded; other ICO frames preserved.'
