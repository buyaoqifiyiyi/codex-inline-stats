$ErrorActionPreference = 'Stop'
$config = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config.json') -Raw | ConvertFrom-Json
$package = Get-AppxPackage -Name OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1
$result = [ordered]@{
    pluginVersion = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()
    codexVersion = [string]$package.Version
    nodeExists = [bool]($config.node -and (Test-Path -LiteralPath $config.node))
    pythonExists = (Test-Path -LiteralPath $config.python)
    debugPort = $config.port
    debugReachable = $false
    codexPageFound = $false
    debugAddress = $null
    mode = $(if ($config.mode) { $config.mode } else { 'inline' })
}
if ($result.mode -eq 'external') {
    $externalScript = Join-Path $PSScriptRoot 'external.py'
    $result.externalWindowRunning = [bool](Get-CimInstance Win32_Process | Where-Object {
        $_.Name -in @('python.exe','pythonw.exe') -and $_.CommandLine -and $_.CommandLine.Contains($externalScript)
    })
    $result.debugRequired = $false
    $result | ConvertTo-Json -Depth 4
    return
}
. (Join-Path $PSScriptRoot 'SelectDebugPort.ps1')
$result.portBindable = Test-DebugPortFree ([int]$config.port)
if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
    $result.listeners = @(Get-NetTCPConnection -LocalPort ([int]$config.port) -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
        $listenerProcess = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        [pscustomobject]@{address=$_.LocalAddress;pid=$_.OwningProcess;processExists=[bool]$listenerProcess}
    })
}
foreach ($address in @('127.0.0.1', '[::1]')) {
    try {
        $targets = Invoke-RestMethod -Uri "http://${address}:$($config.port)/json/list" -TimeoutSec 3
        $result.debugReachable = $true
        $result.debugAddress = $address
        $result.codexPageFound = [bool]($targets | Where-Object { $_.type -eq 'page' -and $_.url -like 'app://-/index.html*' })
        if ($result.codexPageFound) { break }
    } catch {}
}
$status = Join-Path $PSScriptRoot 'status.json'
if (Test-Path -LiteralPath $status) { $result.collector = Get-Content -LiteralPath $status -Raw | ConvertFrom-Json }
$launchStatus = Join-Path $PSScriptRoot 'launch-status.json'
if (Test-Path -LiteralPath $launchStatus) { $result.launch = Get-Content -LiteralPath $launchStatus -Raw | ConvertFrom-Json }
$result | ConvertTo-Json -Depth 4
