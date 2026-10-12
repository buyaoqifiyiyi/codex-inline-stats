[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\CodexInlineStats'),
    [string]$NodePath,
    [string]$PythonPath,
    [ValidateRange(1024,65535)][int]$Port = 9335,
    [switch]$StartAtLogin,
    [switch]$External,
    [switch]$RepairShortcuts,
    [switch]$NoShortcuts,
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
if ($External -and $StartAtLogin) { throw 'External mode is manually launched; do not use -StartAtLogin.' }
if ($External -and $RepairShortcuts) { throw 'Shortcut repair is for inline mode only.' }
if (-not $NodePath) {
    $command = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($command) { $NodePath = $command.Source }
}
if (-not $PythonPath) {
    $command = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($command) { $PythonPath = $command.Source }
}
if (-not $External -and (-not $NodePath -or -not (Test-Path -LiteralPath $NodePath))) { throw 'Install Node.js 22+ or pass -NodePath.' }
if (-not $PythonPath -or -not (Test-Path -LiteralPath $PythonPath)) { throw 'Install Python 3.10+ or pass -PythonPath.' }
if (-not $External) {
    $nodeVersion = & $NodePath --version
    if ($LASTEXITCODE -ne 0 -or ([version]$nodeVersion.TrimStart('v')).Major -lt 22) { throw 'Node.js 22+ is required.' }
}
& $PythonPath -c 'import sys,sqlite3; sys.exit(0 if sys.version_info >= (3,10) else 1)'
if ($LASTEXITCODE -ne 0) { throw 'Python 3.10+ with sqlite3 is required.' }
if ($External) {
    & $PythonPath -I -c 'import tkinter'
    if ($LASTEXITCODE -ne 0) { throw 'External mode requires Python with tkinter.' }
}
$files = @('agent.mjs','debug-endpoint.mjs','reader-client.mjs','renderer.js','reader.py','reader-entry.py','telemetry.py',
    'Launch.ps1','SelectDebugPort.ps1','StartAgent.ps1','RepairShortcuts.ps1','UpdateIcon.ps1','external.py','StartExternal.ps1','Uninstall.ps1','Get-Status.ps1','LICENSE','THIRD_PARTY_NOTICES.md','VERSION')
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $file))) { throw "Missing source file: $file" }
}
if ($CheckOnly) { Write-Output 'PASS: runtimes and source files'; return }
$InstallDir = [IO.Path]::GetFullPath($InstallDir)
if ($InstallDir -eq [IO.Path]::GetFullPath($PSScriptRoot)) { throw 'InstallDir must differ from the source checkout.' }
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
if (Test-Path -LiteralPath (Join-Path $InstallDir 'StartAgent.ps1')) {
    & (Join-Path $PSScriptRoot 'StartAgent.ps1') -ApplicationDir $InstallDir -StopOnly
}
foreach ($file in $files) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $InstallDir $file) -Force }
@{node=$(if ($NodePath) { [IO.Path]::GetFullPath($NodePath) } else { $null });python=[IO.Path]::GetFullPath($PythonPath);port=$Port;mode=$(if ($External) { 'external' } else { 'inline' })} |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $InstallDir 'config.json') -Encoding UTF8
if (-not $NoShortcuts) {
    & (Join-Path $InstallDir 'UpdateIcon.ps1')
    $shell = New-Object -ComObject WScript.Shell
    if ($External) {
        & (Join-Path $InstallDir 'RepairShortcuts.ps1') -Restore
        foreach ($entry in @(
            @{folder='Desktop';name='Codex（内置统计）.lnk';script='Launch.ps1'},
            @{folder='Programs';name='Codex（内置统计）.lnk';script='Launch.ps1'},
            @{folder='Startup';name='Codex 内置统计采集.lnk';script='StartAgent.ps1'}
        )) {
            $oldPath = Join-Path ([Environment]::GetFolderPath($entry.folder)) $entry.name
            if (Test-Path -LiteralPath $oldPath) {
                $oldLink = $shell.CreateShortcut($oldPath)
                if ($oldLink.Arguments.Contains((Join-Path $InstallDir $entry.script))) { Remove-Item -LiteralPath $oldPath }
            }
        }
        $link = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Codex 外置统计.lnk'))
        $link.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $link.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $InstallDir 'StartExternal.ps1') + '"'
        $link.WorkingDirectory = $InstallDir
        $link.Save()
        Write-Output "External window installed in $InstallDir. Use Codex normally and launch Codex External Stats separately."
        return
    }
    $externalScript = Join-Path $InstallDir 'external.py'
    Get-CimInstance Win32_Process | Where-Object {
        $_.Name -in @('python.exe','pythonw.exe') -and $_.CommandLine -and $_.CommandLine.Contains($externalScript)
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
    $externalShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Codex 外置统计.lnk'
    if (Test-Path -LiteralPath $externalShortcut) {
        $oldLink = $shell.CreateShortcut($externalShortcut)
        if ($oldLink.Arguments.Contains((Join-Path $InstallDir 'StartExternal.ps1'))) { Remove-Item -LiteralPath $externalShortcut }
    }
    $link = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Codex（内置统计）.lnk'))
    $link.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $link.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $InstallDir 'Launch.ps1') + '"'
    $link.WorkingDirectory = $InstallDir
    $package = Get-AppxPackage -Name OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1
    if (Test-Path -LiteralPath (Join-Path $InstallDir 'codex.ico')) { $link.IconLocation = (Join-Path $InstallDir 'codex.ico') + ',0' }
    elseif ($package) { $link.IconLocation = (Join-Path $package.InstallLocation 'app\ChatGPT.exe') + ',0' }
    $link.Save()
    $menuLink = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Programs')) 'Codex（内置统计）.lnk'))
    $menuLink.TargetPath = $link.TargetPath
    $menuLink.Arguments = $link.Arguments
    $menuLink.WorkingDirectory = $link.WorkingDirectory
    $menuLink.IconLocation = $link.IconLocation
    $menuLink.Save()
    if ($StartAtLogin) {
        $startup = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Startup')) 'Codex 内置统计采集.lnk'))
        $startup.TargetPath = $link.TargetPath
        $startup.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $InstallDir 'StartAgent.ps1') + '"'
        $startup.WorkingDirectory = $InstallDir
        $startup.Save()
    }
}
if ($RepairShortcuts) { & (Join-Path $InstallDir 'RepairShortcuts.ps1') }
Write-Output "Installed in $InstallDir. Fully quit Codex, then use the desktop shortcut."
