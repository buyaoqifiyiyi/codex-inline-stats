[CmdletBinding()]
param([switch]$Restart, [switch]$StopOnly, [string]$ApplicationDir = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$agent = Join-Path $ApplicationDir 'agent.mjs'
$reader = Join-Path $ApplicationDir 'reader-entry.py'
$processes = Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -and (($_.Name -eq 'node.exe' -and $_.CommandLine.Contains($agent)) -or
    ($_.Name -eq 'python.exe' -and $_.CommandLine.Contains($reader)))
}
if ($Restart -or $StopOnly) {
    $processes | ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
    $processes = @()
}
if ($StopOnly) { return }
if (-not ($processes | Where-Object Name -eq 'node.exe')) {
    $config = Get-Content -LiteralPath (Join-Path $ApplicationDir 'config.json') -Raw | ConvertFrom-Json
    Start-Process -FilePath $config.node -ArgumentList @('"' + $agent + '"') -WorkingDirectory $ApplicationDir -WindowStyle Hidden
}
