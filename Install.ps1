[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\CodexInlineStats'),
    [string]$NodePath,
    [string]$PythonPath,
    [ValidateRange(1024,65535)][int]$Port = 9335,
    [switch]$StartAtLogin,
    [switch]$NoShortcuts,
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
if (-not $NodePath) {
    $command = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($command) { $NodePath = $command.Source }
}
if (-not $PythonPath) {
    $command = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($command) { $PythonPath = $command.Source }
}
if (-not $NodePath -or -not (Test-Path -LiteralPath $NodePath)) { throw 'Install Node.js 22+ or pass -NodePath.' }
if (-not $PythonPath -or -not (Test-Path -LiteralPath $PythonPath)) { throw 'Install Python 3.10+ or pass -PythonPath.' }
$nodeVersion = & $NodePath --version
if ($LASTEXITCODE -ne 0 -or ([version]$nodeVersion.TrimStart('v')).Major -lt 22) { throw 'Node.js 22+ is required.' }
& $PythonPath -c 'import sys,sqlite3; sys.exit(0 if sys.version_info >= (3,10) else 1)'
if ($LASTEXITCODE -ne 0) { throw 'Python 3.10+ with sqlite3 is required.' }
$files = @('agent.mjs','renderer.js','reader.py','reader-entry.py','telemetry.py',
    'Launch.ps1','StartAgent.ps1','Uninstall.ps1','Get-Status.ps1','LICENSE','THIRD_PARTY_NOTICES.md','VERSION')
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
@{node=[IO.Path]::GetFullPath($NodePath);python=[IO.Path]::GetFullPath($PythonPath);port=$Port} |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $InstallDir 'config.json') -Encoding UTF8
if (-not $NoShortcuts) {
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Codex（内置统计）.lnk'))
    $link.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $link.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $InstallDir 'Launch.ps1') + '"'
    $link.WorkingDirectory = $InstallDir
    $package = Get-AppxPackage -Name OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1
    if ($package) { $link.IconLocation = (Join-Path $package.InstallLocation 'app\ChatGPT.exe') + ',0' }
    $link.Save()
    if ($StartAtLogin) {
        $startup = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Startup')) 'Codex 内置统计采集.lnk'))
        $startup.TargetPath = $link.TargetPath
        $startup.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $InstallDir 'StartAgent.ps1') + '"'
        $startup.WorkingDirectory = $InstallDir
        $startup.Save()
    }
}
Write-Output "Installed in $InstallDir. Fully quit Codex, then use the desktop shortcut."
