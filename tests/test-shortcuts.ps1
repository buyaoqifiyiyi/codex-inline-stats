$ErrorActionPreference = 'Stop'
$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'RepairShortcuts.ps1'
$testDir = Join-Path ([IO.Path]::GetTempPath()) ('codex-shortcut-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDir | Out-Null
function Assert($condition, $label) { if (-not $condition) { throw $label } }
try {
    Copy-Item -LiteralPath $source -Destination (Join-Path $testDir 'RepairShortcuts.ps1')
    $codexExe = Join-Path $testDir 'app\ChatGPT.exe'
    $codexLink = Join-Path $testDir 'Codex.lnk'
    $otherLink = Join-Path $testDir 'Other.lnk'
    $comShell = New-Object -ComObject WScript.Shell
    $link = $comShell.CreateShortcut($codexLink); $link.TargetPath = $codexExe; $link.Save()
    $link = $comShell.CreateShortcut($otherLink); $link.TargetPath = Join-Path $testDir 'other.exe'; $link.Save()
    $original = (Get-FileHash -LiteralPath $codexLink).Hash
    $other = (Get-FileHash -LiteralPath $otherLink).Hash
    $global:shortcutTestFiles = @(Get-Item -LiteralPath $codexLink), @(Get-Item -LiteralPath $otherLink)
    function Get-AppxPackage { [pscustomobject]@{Version=[version]'1.0';InstallLocation=$testDir} }
    function Get-ChildItem { $global:shortcutTestFiles }
    & (Join-Path $testDir 'RepairShortcuts.ps1')
    $link = $comShell.CreateShortcut($codexLink)
    Assert ($link.Arguments.Contains((Join-Path $testDir 'Launch.ps1'))) 'Matching Codex link routes to statistics launcher'
    Assert ((Get-FileHash -LiteralPath $otherLink).Hash -eq $other) 'Other app shortcut untouched'
    $receipt = @(Get-Content -LiteralPath (Join-Path $testDir 'shortcut-backups.json') -Raw | ConvertFrom-Json)
    Assert ($receipt.Count -eq 1) 'Only one original backup saved'
    & (Join-Path $testDir 'RepairShortcuts.ps1')
    & (Join-Path $testDir 'RepairShortcuts.ps1') -Restore
    Assert ((Get-FileHash -LiteralPath $codexLink).Hash -eq $original) 'Original shortcut restored exactly'
    & (Join-Path $testDir 'RepairShortcuts.ps1')
    $link = $comShell.CreateShortcut($codexLink); $link.TargetPath = Join-Path $testDir 'user-changed.exe'; $link.Arguments = ''; $link.Save()
    $changed = (Get-FileHash -LiteralPath $codexLink).Hash
    & (Join-Path $testDir 'RepairShortcuts.ps1') -Restore
    Assert ((Get-FileHash -LiteralPath $codexLink).Hash -eq $changed) 'Restore preserves later user shortcut edits'
    Write-Output 'PASS: targeted shortcuts, idempotent backup, exact restore, unrelated app and later edits preserved'
} finally {
    Assert ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($testDir)) -eq [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')) 'Cleanup stays in temp'
    Remove-Item -LiteralPath $testDir -Recurse -Force
    Remove-Variable -Name shortcutTestFiles -Scope Global -ErrorAction SilentlyContinue
}
