$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'StartAgent.ps1') -StopOnly
$shell = New-Object -ComObject WScript.Shell
foreach ($entry in @(
    @{folder='Desktop';name='Codex（内置统计）.lnk';script='Launch.ps1'},
    @{folder='Startup';name='Codex 内置统计采集.lnk';script='StartAgent.ps1'}
)) {
    $path = Join-Path ([Environment]::GetFolderPath($entry.folder)) $entry.name
    if (Test-Path -LiteralPath $path) {
        $shortcut = $shell.CreateShortcut($path)
        if ($shortcut.Arguments.Contains((Join-Path $PSScriptRoot $entry.script))) {
            Remove-Item -LiteralPath $path
        }
    }
}
Write-Output 'Stopped statistics and removed its shortcuts. Fully quit Codex and use its normal launcher.'
Write-Output "Files remain in $PSScriptRoot; remove that folder manually if no longer needed. Chat data is untouched."
