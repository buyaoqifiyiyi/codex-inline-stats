$ErrorActionPreference = 'Stop'
$package = Get-AppxPackage -Name OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1
if (-not $package) { return }
$destination = Join-Path $PSScriptRoot 'codex.ico'
$images = @()
foreach ($size in @(16,32,48,256)) {
    $image = Join-Path $package.InstallLocation "Assets\Square44x44Logo.targetsize-${size}_altform-unplated.png"
    if (Test-Path -LiteralPath $image) { $images += @{size=$size;bytes=[IO.File]::ReadAllBytes($image)} }
}
if ($images.Count) {
    # ICO supports PNG entries; preserve native artwork at each display size.
    $stream = New-Object IO.MemoryStream
    $writer = New-Object IO.BinaryWriter($stream)
    try {
        $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$images.Count)
        $offset = 6 + 16 * $images.Count
        foreach ($image in $images) {
            $dimension = [byte]($image.size % 256)
            $writer.Write($dimension); $writer.Write($dimension); $writer.Write([uint16]0)
            $writer.Write([uint16]1); $writer.Write([uint16]32)
            $writer.Write([uint32]$image.bytes.Length); $writer.Write([uint32]$offset)
            $offset += $image.bytes.Length
        }
        foreach ($image in $images) { $writer.Write([byte[]]$image.bytes) }
        $writer.Flush()
        [IO.File]::WriteAllBytes($destination, $stream.ToArray())
    } finally { $writer.Dispose(); $stream.Dispose() }
} else {
    Add-Type -AssemblyName System.Drawing
    $icon = [Drawing.Icon]::ExtractAssociatedIcon((Join-Path $package.InstallLocation 'app\ChatGPT.exe'))
    if ($icon) {
        $stream = [IO.File]::Create($destination)
        try { $icon.Save($stream) } finally { $stream.Dispose(); $icon.Dispose() }
    }
}
